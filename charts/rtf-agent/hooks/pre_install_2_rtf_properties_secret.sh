#!/bin/bash

# pre-install task: create custom properties secret

set +o errexit
kubectl -n${NAMESPACE} get secret custom-properties -ojsonpath="{.data}" | grep HTTP_PROXY
SECRET_MIGRATED=$?
set -o errexit

if [[ "$SECRET_MIGRATED" == "0" ]]; then
  echo "Secret already migrated. No changes to apply..."
  exit 0
fi

__http_proxy=$(kubectl get cm custom-properties -n${NAMESPACE} -ojsonpath='{.data.proxy\.http}')
if [[ -z "$__http_proxy" ]]; then
  __http_proxy=${RTF_HTTP_PROXY}
fi

if [[ -z "$__http_proxy" ]]; then
  echo "No changes to apply. Ensuring secret exists..."
  kubectl -n${NAMESPACE} create secret generic custom-properties || true
  exit 0
fi

rm -rf custom-secrets
mkdir custom-secrets

if [[ -n "$RTF_MONITORING_PROXY" ]]; then
  echo -n "${RTF_MONITORING_PROXY}" > custom-secrets/proxy.monitoring
fi

echo -n "${__http_proxy}" > custom-secrets/proxy.http

kubectl create secret generic custom-properties \
  --from-file=$(pwd)/custom-secrets \
  --dry-run -o yaml > secret.yml

NAMESPACES=$(kubectl get namespaces -l rtf.mulesoft.com/role=workers -ojsonpath='{range .items[*]}{.metadata.name} {end}')
NAMESPACES+=($NAMESPACE)

for NS in ${NAMESPACES[*]}
do
  echo "Applying custom properties to namespace $NS..."
  kubectl apply -n${NS} -f secret.yml
done
