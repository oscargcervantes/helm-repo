#!/bin/bash

# pre-install task: create agent-keystore secret

set +o errexit
kubectl -n${NAMESPACE} get secret agent-keystore
MIGRATED_KEYSTORE_EXIT_CODE=$?
set -o errexit

if [[ "$MIGRATED_KEYSTORE_EXIT_CODE" -gt "0" ]]; then

  set +o errexit
  kubectl -n${NAMESPACE} get secret agent-keystore-secret
  EXISTING_KEYSTORE_EXIT_CODE=$?
  set -o errexit

  if [[ "$EXISTING_KEYSTORE_EXIT_CODE" -gt "0" ]]; then
      # case 1: secret doesn't exist
      echo "Creating agent-keystore secret..."

      kubectl create secret generic agent-keystore \
        --from-file=agent-keystore.p12=$(pwd)/$AGENT_KEYSTORE \
        --from-file=agent-truststore.p12=$(pwd)/$ANYPOINT_TRUSTSTORE \
        --from-file=key.pem=$(pwd)/agent.key \
        --from-file=signed-cert.pem=$(pwd)/signed.crt \
        --from-file=ca.pem=$(pwd)/ca.pem \
        --from-literal=keystore-password="$KEYSTORE_PASSWORD" \
        --from-literal=truststore-password="$TRUSTSTORE_PASSWORD" \
        --dry-run -o yaml > keystore-secret.yml

      kubectl apply -n${NAMESPACE} -f keystore-secret.yml

  else
      # case 2: secret needs migration from helm
      echo "Migrating agent-keystore secret..."

      kubectl -n${NAMESPACE} get secret agent-keystore-secret -o json | \
        jq '.metadata.name = "agent-keystore"' | \
        kubectl apply -f -
  fi
fi
