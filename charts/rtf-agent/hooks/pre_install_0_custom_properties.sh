#!/bin/bash

# pre-install task: create/migrate custom properties
set +o errexit
kubectl -n${NAMESPACE} get cm custom-properties
CUSTOM_CONFIG_CM_EXIT_CODE=$?
set -o errexit

if [[ "$CUSTOM_CONFIG_CM_EXIT_CODE" -eq "0" ]]; then
  echo "Nothing to do. Skipping."
  exit
fi

echo "Creating custom-properties config map..."

if [[ "$VERBOSE" -gt 0 ]]; then
  echo "User supplied NO_PROXY=${RTF_NO_PROXY}"
fi

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-properties
  namespace: ${NAMESPACE}
data:
  proxy.noproxy: "${RTF_NO_PROXY}"
EOF
