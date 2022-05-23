#!/bin/bash

# pre-install task: migrate proxy.http to custom-properties secret
set +o errexit
kubectl -n${NAMESPACE} get secrets custom-properties -ojsonpath='{.data}' | grep "proxy.http"
PROXY_MIGRATED_EXIT_CODE=$?
set -o errexit

if [[ "$PROXY_MIGRATED_EXIT_CODE" -gt "0" ]]; then
  echo "Migrating http proxy configuration..."

  __http_proxy=$(kubectl get cm custom-properties -nrtf -ojsonpath='{.data.proxy\.http}')

  NAMESPACES=$(kubectl get namespaces -l rtf.mulesoft.com/role=workers -o=jsonpath='{range .items[*]}{.metadata.name} {end}')
  NAMESPACES+=($NAMESPACE)

  for NS in ${NAMESPACES[*]}
  do
    echo "Updating namespace $NS"
    kubectl -n${NS} patch secret custom-properties -p "{\"data\":{\"proxy.http\":\"`echo -n $__http_proxy | base64 ${BASE64_OPTS}`\"}}"
  done
fi
