#!/bin/bash
set -o errtrace
set -o errexit
set -o pipefail

export NAMESPACE=rtf
export VERBOSE=${VERBOSE:-0}

AGENT_TYPE="MC"
WORKING_DIR=rtf-agent
SCRIPT_VERSION="1.0.0"
HELM_RELEASE_NAME=runtime-fabric
HELM_LIST_OPTS="--date --reverse --max 1"
LAST_ERROR_FILE=${TERMINATION_LOG:-/dev/termination-log}
CURL_RESPONSE_FILE=/tmp/curl-response
CURL_OPTS="-s --max-time 20 -w %{http_code} -o $CURL_RESPONSE_FILE"
AWS_OPTS=""
INSTALL_TIMEOUT=600
EXIT_CODE_HELM_STATUS_NOT_DEPLOYED=100
TRANSACTION_ID=$(head /dev/urandom | LC_ALL=C tr -dc a-z0-9 | head -c 5)
SECURE_QUEUE_CONNECTION=${SECURE_QUEUE_CONNECTION:-true}
PULL_SECRET_NAME=${PULL_SECRET_NAME:-awsecr-cred}
LOCAL_REGISTRY_ENDPOINT=${LOCAL_REGISTRY_ENDPOINT:-leader.telekube.local:5000}
SKIP_REGISTRATION=${SKIP_REGISTRATION:-}
SKIP_CREATE_PULL_SECRET=${SKIP_CREATE_PULL_SECRET:-}
ACTIVATION_TOKEN=${ACTIVATION_TOKEN:-}
INFLUX_NS="monitoring"
INFLUXDB_SERVICE_NAME=${INFLUXDB_SERVICE_NAME:-influxdb}

export AGENT_KEYSTORE="agent-keystore.p12"
export KEYSTORE_PASSWORD=$(head /dev/urandom | LC_ALL=C tr -dc a-z0-9 | head -c 8)
export ANYPOINT_TRUSTSTORE=${WORKING_DIR}/anypoint-truststore.p12
export TRUSTSTORE_PASSWORD="password"

export RTF_HTTP_PROXY=${HTTP_PROXY:-}
export RTF_NO_PROXY=${NO_PROXY:-}

if [[ -z ${RTF_HTTP_PROXY} ]]; then
    CURL_WITH_PROXY="curl"
    AWS_WITH_PROXY="aws"
else
    CURL_WITH_PROXY="curl --proxy $RTF_HTTP_PROXY"
    AWS_WITH_PROXY="HTTP_PROXY=$RTF_HTTP_PROXY HTTPS_PROXY=$RTF_HTTP_PROXY NO_PROXY=$RTF_NO_PROXY aws"
fi

# remove global proxy settings
export NO_PROXY=
export HTTP_PROXY=
export HTTPS_PROXY=
export http_proxy=


# detect OS
unameOut="$(uname -s)"
case "${unameOut}" in
    Darwin*)
      export BASE64_OPTS="-b0"
      export BASE64_DECODE_OPTS="-D"
      ;;
    *)
      export BASE64_OPTS="-w0"
      export BASE64_DECODE_OPTS="-d"
esac

function subsh () {
  subsh_cmd=$1
  eval $subsh_cmd
  exitCode=$?
  if [ $exitCode != "0" ]; then
    lastError=$(cat $LAST_ERROR_FILE)
    echo "Error executing command \"${subsh_cmd:0:20}...\"($exitCode): $lastError" > $LAST_ERROR_FILE
  fi
  return $exitCode
}

function on_exit {
  local trap_code=$?

  if [ $trap_code -ne 0 ] ; then
    echo
    echo
    echo "============ Registration Error ============"
    printf "Exit code: $trap_code\nLine: $TRAP_LINE"
    if [ -f $LAST_ERROR_FILE ]; then
      printf "\nContext: "
      cat $LAST_ERROR_FILE
    fi
    echo
  fi
}

function on_error {
    TRAP_LINE=$1
}

trap 'on_error $LINENO' ERR
trap on_exit EXIT

function parseJSONStringProperty() {
  local jsonString=$1
  local jqString=$2
  local extractedVar=$(echo $jsonString | jq "$jqString")

  if [ "$extractedVar" == "null" ] || [ -z "$extractedVar" ]; then
    echo "Failed to execute 'parseJSONStringProperty'. jq: $jqString" > $LAST_ERROR_FILE
    exit 1
  fi
  echo ${extractedVar//\"/}
}

function parseJSONResponse() {
  local jqString=$1
  local extractedVar=$(jq "$jqString" $CURL_RESPONSE_FILE)
  if [ "$extractedVar" == "null" ] || [ -z "$extractedVar" ]; then
    echo "Failed to execute 'parseJSONResponse'. jq: $jqString" > $LAST_ERROR_FILE
    exit 1
  fi
  echo ${extractedVar//\"/}
}

function parseJSONResponseCaChain() {
  jq ".caChain" $CURL_RESPONSE_FILE | jq -r '.[]' > ca-chain.crt
}

function registerAgent() {
  local csr=$1

  $CURL_WITH_PROXY -X POST $CURL_OPTS \
    "$REGISTRATION_ENDPOINT/organizations/$ORG_ID/agents" \
    -A "AgentRegistrationScript/$SCRIPT_VERSION" \
    -H "Authorization: $ACTIVATION_TOKEN" \
    -H "Content-Type: application/json" \
    -H "X-ANYPNT-TRX-ID: $TRANSACTION_ID" \
    -d "{
        \"region\": \"$REGION\",
        \"csr\": \"$csr\",
        \"type\": \"$AGENT_TYPE\",
        \"agentInfo\": {
            \"activationToken\": \"$ACTIVATION_TOKEN\"
        }
    }"
}

function generateKeyAndCSR() {
  openssl req -out agent.csr -new \
    -newkey rsa:2048 -nodes -keyout agent.key \
    -subj "/C=US/ST=/L=/O=/OU=/CN=*.$AGENT_TYPE.$REGION.$CSR_SUFFIX"
  local cert=$(cat agent.csr)
  echo ${cert//$'\n'/'\n'}
}


function stepOK() {
  echo "[OK]"
  echo > $LAST_ERROR_FILE
}

function stepSkipped() {
  echo "[Skipped]"
  echo > $LAST_ERROR_FILE
}
function createInitialImagePullSecrets() {
  ecrResponse=$(subsh "$AWS_WITH_PROXY $AWS_OPTS --region $REGION ecr get-authorization-token")
  ecrEndpoint=$(parseJSONStringProperty "$ecrResponse" ".authorizationData[0].proxyEndpoint")
  ecrToken=$(parseJSONStringProperty "$ecrResponse" ".authorizationData[0].authorizationToken")

  if [[ "$EXPECTED_AGENT_VERSION" =~ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    dockerOrg="mulesoft"
  else
    dockerOrg="mulesoft-ci"
  fi

  printf "Validating ECR credentials... "
  statusCode=$($CURL_WITH_PROXY --head $CURL_OPTS \
    $ecrEndpoint/v2/$dockerOrg/rtf-agent/templates/v$EXPECTED_AGENT_VERSION \
    -H "Authorization: Basic $ecrToken")

  if [ $statusCode != "200" ]; then
    echo "ERROR: Failed to validate docker registry credentials, status code: $statusCode" > $LAST_ERROR_FILE
    exit 1
  fi

  printf '{"auths":{"%s":{"auth":"%s","email":"none"}}}' $ecrEndpoint $ecrToken > /tmp/dockerconfigjson

  stepOK
}

function getAgentDeploymentVersion() {
  CURRENT_AGENT_VERSION=$(subsh "kubectl get deployment deployer -n$NAMESPACE -o jsonpath=\"{.spec.template.spec.containers[0].image}\" | cut -d: -f 2 | cut -dv -f 2")
}

function rollbackHelmRevision() {
  echo "Rolling back to the previous revision... "
  set +o errexit
  helm rollback --force --wait --timeout $INSTALL_TIMEOUT $HELM_RELEASE_NAME 0
  HELM_EXIT_CODE=$?
  set -o errexit

  if [ "$HELM_EXIT_CODE" -ne "0" ] ; then
    echo "FATAL: helm tried to perform a rollback but failed "
    echo "State:"
    helm history $HELM_RELEASE_NAME --max 4
    kubectl get deployments -n$NAMESPACE
    kubectl get events -n$NAMESPACE | grep Warning
  fi
  exit $EXIT_CODE_HELM_STATUS_NOT_DEPLOYED
}

############################# BEGINNING OF REGISTRATION ########################################
echo "============  Runtime Fabric Agent Installation ============ "

if [ "$VERBOSE" -eq "0" ] ; then
  exec 2>$LAST_ERROR_FILE
else
  if [ "$VERBOSE" -gt "0" ] ; then
    CURL_OPTS="$CURL_OPTS -v"  # add verboseness
  fi
  if [ "$VERBOSE" -gt "1" ] ; then
    set -x
  fi
  if [ "$VERBOSE" -gt "2" ] ; then
    echo "Warning: use only for debugging - this will fail the deployment"
    AWS_OPTS="$AWS_OPTS --debug"
  fi
fi

printf "Checking for cluster-admin authorization... "
HAS_AUTH=$(subsh "kubectl get nodes")
stepOK

printf "Checking for controller node labels... "
HAS_CONTROLLER=$(subsh "kubectl get nodes -o name -l node-role.kubernetes.io/master=true --ignore-not-found")
if [ -z $HAS_CONTROLLER ]; then
  FIRST_NODE=$(subsh "kubectl get nodes -o name | head -n1")
  kubectl label $FIRST_NODE node-role.kubernetes.io/master- > /dev/null
  kubectl label $FIRST_NODE node-role.kubernetes.io/master=true
  echo "Marked $FIRST_NODE as controller."
fi
stepOK

printf "Checking for existing registration... "
set +o errexit

INSTALLED_PSDN=$(helm status poseidon-agent)
HELM_EXIT_CODE=$?
if [ "$HELM_EXIT_CODE" -eq "0" ] ; then
  echo "This is a pre-release version of RTF and is not able to be upgraded" > $LAST_ERROR_FILE
  exit 1
fi

INSTALLED=$(helm status $HELM_RELEASE_NAME)
HELM_EXIT_CODE=$?
set -o errexit

if [ "$HELM_EXIT_CODE" -eq "0" ] ; then
    echo "[Registered]"
    UPGRADE=1
    echo "Upgrade an existing installation... "
    getAgentDeploymentVersion
    printf "Checking version of the current agent... $CURRENT_AGENT_VERSION "
    stepOK
else
    echo
    echo
    echo
    echo
    echo "[ERROR] A newer version of the install scripts are required to install this version of Runtime Fabric."
    echo "Please resume installation using the latest version of the install scripts which can be found in the Downloads page in Anypoint Runtime Manager:"
    echo "https://anypoint.mulesoft.com/cloudhub/#/console/home/runtimefabrics/downloads"
    exit 1
fi

if [ -n "$CUSTOM_OVERRIDES" ] ; then
    echo "Warning: using custom override parameters: $CUSTOM_OVERRIDES"
fi

if [ -n "$DRY_RUN" ] ; then
    echo "==> Dry run"
    UPGRADE_OPTS="--dry-run"
fi


# get the expected agent version from the chart
EXPECTED_AGENT_VERSION=$(subsh 'cat ./rtf-agent/Chart.yaml | grep version | awk "{print \$2}"')
echo "Preparing to install agent version: $EXPECTED_AGENT_VERSION"

if [ -n "$UPGRADE" ]; then
    # retrieve agent information
    printf "Obtaining registration ID and region... "
    AGENT_ID=$(subsh 'kubectl -n $NAMESPACE get configmap app-config -o jsonpath="{.data.QUEUE_NODEID}"')
    REGION=$(subsh 'kubectl -n $NAMESPACE get configmap app-config -o jsonpath="{.data.QUEUE_ZONE}"')

    if [ -z "$AGENT_ID" ]; then
      AGENT_ID=$(subsh 'kubectl -n $NAMESPACE get configmap app-config -o jsonpath="{.data.*}" | grep "queue.nodeId" | cut -d"=" -f 2')
    fi
    if [ -z "$REGION" ]; then
      REGION=$(subsh 'kubectl -n $NAMESPACE get configmap app-config -o jsonpath="{.data.*}" | grep "queue.zone" | cut -d"=" -f 2')
    fi
    if [ -z "$AGENT_ID" ] || [ -z "$REGION" ] ; then
        echo "ERROR: Failed to obtain registration Id or region" > $LAST_ERROR_FILE
        exit 1
    fi
    printf "$AGENT_ID - $REGION "
fi
stepOK

printf "Exporting CA certs... "
openssl pkcs12 -in $ANYPOINT_TRUSTSTORE -nokeys -out ca.pem -nodes -password pass:$TRUSTSTORE_PASSWORD ;
stepOK

printf "Discovering InfluxDB service..."
kubectl create ns $INFLUX_NS || true
INFLUXDB_URI=http://$INFLUXDB_SERVICE_NAME.$INFLUX_NS.svc.cluster.local:8086
if [ "$VERBOSE" -gt "0" ] ; then
  printf "$INFLUXDB_URI"
fi
stepOK

printf "Initializing helm... "
helm init --client-only --skip-refresh > /dev/null
stepOK

if [ -n "$SKIP_CREATE_PULL_SECRET" ]; then
  echo "Warning: skipping image pull secret creation"
else
  echo "Creating image pull secret... "
  createInitialImagePullSecrets
  IMAGE_PULL_SECRET=$(subsh 'cat /tmp/dockerconfigjson | base64 $BASE64_OPTS')

  # update image pull secret
  cat <<EOF | kubectl apply -f -
apiVersion: v1
type: kubernetes.io/dockerconfigjson
kind: Secret
metadata:
  name: $PULL_SECRET_NAME
  namespace: $NAMESPACE
data:
  .dockerconfigjson: "$IMAGE_PULL_SECRET"
EOF

  stepOK
fi

##### Pre-install hooks ######
hooks=$(ls ${WORKING_DIR}/hooks/pre_install*.sh)
for hook in ${hooks[*]}
do
  echo "Running ${hook}..."
  eval ${hook}
  echo -n "Done hook."
  stepOK
done

##### Inherited values #######
if [ -n "$UPGRADE" ]; then
    helm get values $HELM_RELEASE_NAME > inheritedValues.yaml
fi

##### New values #######
if [ -n "$UPGRADE" ]; then
    ##### upgrade values. #######
    echo "
    queue:
      broker: '$QUEUE_BROKER'
      ssl:
        keystore: null
        keystorePassword: null
        truststore: null
        truststorePassword: null
        keyPem: null
        signedCertPem: null
        caPem: null
    agent:
      masterOrgId: '$RTF_MASTER_ORG_ID'
    global:
      certRenewalUrl: '$CERT_RENEWAL_URL'
      pullCredentials:
        region: '$REGION'
        key: '$IMAGE_REGISTRY_KEY'
        secret: '$IMAGE_REGISTRY_SECRET'
      image:
        registry: '$IMAGE_REGISTRY_ENDPOINT'
      localRegistry:
        endpoint: '$LOCAL_REGISTRY_ENDPOINT'
      influxdb:
        uri: '$INFLUXDB_URI'
        namespace: '$INFLUX_NS'
      anypointMonitoring:
        ingestUrl: '$AM_INGEST_URL'
        ingestUrlLegacy: $AM_INGEST_URL_LEGACY'
    " > newValues.yaml
    echo "Upgrading Runtime Fabric Agent. This may take several minutes... "
fi

# delete original grafana-dashboards configmap
UNMANAGED_GRAFANA_COUNT=$(kubectl get configmaps -n ${INFLUX_NS} -l rtf!=grafana-dashboards --field-selector="metadata.name==grafana-dashboards" -o json | jq '.items | length')
if [ "$UNMANAGED_GRAFANA_COUNT" -gt "0" ] ; then
  kubectl delete configmap grafana-dashboards -n ${INFLUX_NS}
fi

# manage kapacitor alerts
UNMANAGED_KAPACITOR_COUNT=$(kubectl get configmaps -n ${INFLUX_NS} -l rtf!=kapacitor-alerts --field-selector="metadata.name==kapacitor-alerts" -o json | jq '.items | length')
if [ "$UNMANAGED_KAPACITOR_COUNT" -gt "0" ] ; then
  kubectl delete configmap kapacitor-alerts -n ${INFLUX_NS}
fi

# add rtf-restricted service account to all worker namespaces if it does not exist
NAMESPACES=$(kubectl get namespaces -l rtf.mulesoft.com/role=workers -o=jsonpath='{range .items[*]}{.metadata.name} {end}')
for NS in ${NAMESPACES[*]}
do
  SA_EXISTS=$(kubectl get serviceaccount rtf-restricted -n${NS} --ignore-not-found)
  if [[ -z "$SA_EXISTS" ]]; then
    echo "Updating namespace "$NS""
    kubectl create serviceaccount rtf-restricted -n${NS}
    kubectl create rolebinding rtf-restricted --clusterrole=rtf-restricted --serviceaccount=${NS}:rtf-restricted -n${NS}
  fi
done

set +o errexit
oldRevision=$(helm list -a $HELM_LIST_OPTS $HELM_RELEASE_NAME | grep NAME -A 1 | grep $HELM_RELEASE_NAME | awk -F '\t' '{ print $2 }')

echo "Helm revision history:"
helm history $HELM_RELEASE_NAME --max 4

helm upgrade --install $HELM_RELEASE_NAME ./rtf-agent --namespace $NAMESPACE --wait \
    --timeout $INSTALL_TIMEOUT \
    --force $UPGRADE_OPTS \
    -f inheritedValues.yaml \
    -f newValues.yaml \
    $CUSTOM_OVERRIDES

HELM_EXIT_CODE=$?

newRevision=$(helm list -a $HELM_LIST_OPTS $HELM_RELEASE_NAME | grep NAME -A 1 | grep $HELM_RELEASE_NAME | awk -F '\t' '{ print $2 }')
status=$(helm status $HELM_RELEASE_NAME | grep 'STATUS:' | cut -d' ' -f 2)

if [ "$VERBOSE" -gt "0" ] ; then
    echo "=========>"
    echo "Pre-upgrade revision: $oldRevision"
    echo "Post-upgrade revision: $newRevision"
    echo "Release status: $status"
    echo
fi

set -o errexit

if [ "$HELM_EXIT_CODE" -ne "0" ] || [ "$status" != "DEPLOYED" ]; then

  set +o errexit
  deployments=$(kubectl -n$NAMESPACE get deploy -o=jsonpath="{.items[*].metadata.name}")
  readyDeployments=$(kubectl -n$NAMESPACE get deploy -o=jsonpath="{.items[?(@.status.availableReplicas > 0)].metadata.name}")

  if [ "$(echo $deployments | wc -w)" != "$(echo $readyDeployments | wc -w)" ]; then
    echo "The following deployments failed to become ready within the time limit:"

    for deployment in ${deployments[*]}
    do
      echo $readyDeployments | grep $deployment > /dev/null
      if [ "$?" -gt "0" ]; then
        echo "$deployment ---"

        pod=$(kubectl -n$NAMESPACE get pods | grep $deployment | awk '{print $1}')
        kubectl -n$NAMESPACE describe pod $pod
        echo "Logs: "
        kubectl -n$NAMESPACE logs $pod | tail -n 200
      fi
    done
  fi
  set -o errexit

  if [ -n "$UPGRADE" ] ; then
    echo "Upgrade failed ($HELM_EXIT_CODE, $status)."

    helm history $HELM_RELEASE_NAME --max 4
    rollbackHelmRevision
  else
    set +o errexit
    echo "State:"
    helm history $HELM_RELEASE_NAME --max 4
    kubectl get deployments -n$NAMESPACE
    kubectl get events -n$NAMESPACE | grep Warning
    echo "WARNING: Unexpected upgrade. Old revision: "$oldRevision", new: $newRevision"
    set -o errexit
    exit $EXIT_CODE_HELM_STATUS_NOT_DEPLOYED
  fi
fi

# Sanity check: version of agent pods is matching version of the helm chart
getAgentDeploymentVersion
if [[ "$CURRENT_AGENT_VERSION" -ne "$EXPECTED_AGENT_VERSION" ]] ; then
  echo "Current helm chart version $EXPECTED_AGENT_VERSION is not matching agent pods version $CURRENT_AGENT_VERSION."
  rollbackHelmRevision
fi

# Post-install task: restart kapacitor pod
KAPACITOR_POD=$(kubectl -n${INFLUX_NS} get pod -l component=kapacitor -o json | jq -r ".items[0].metadata.name")
if [[ "$KAPACITOR_POD" != "null" ]]; then
  echo "Restarting Kapacitor..."
  kubectl -n${INFLUX_NS} delete pod $KAPACITOR_POD
fi
stepOK

exit $HELM_EXIT_CODE
