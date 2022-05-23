#!/bin/bash

# pre-install task: label the secrets that needs to be synchronized to worker namespaces

SECRETS_TO_SYNC=(custom-properties rtf-monitoring-certificate rtf-muleruntime-license)

for TARGET in ${SECRETS_TO_SYNC[*]}
  do
    set +o errexit
    kubectl -n${NAMESPACE} patch secret ${TARGET} -p '{"metadata":{"labels":{"rtf.mulesoft.com/synchronized": "true"}}}'
    set -o errexit
done
