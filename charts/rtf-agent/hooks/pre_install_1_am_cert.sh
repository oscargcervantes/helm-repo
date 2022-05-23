#!/bin/bash

if [ -n "$AM_TIER" ]; then
  echo "Upserting rtf-monitoring-certificate secret..."
  rm -rf certs
  mkdir certs
  echo -n $AM_TIER > certs/tier
  echo -e "$AM_KEY" > certs/mule-agent.key
  echo -e "$AM_CERT" > certs/mule-agent-chain.crt
  echo -e "$AM_CA" > certs/registration-agent-ca.crt
  kubectl create secret generic rtf-monitoring-certificate \
    --from-file=$(pwd)/certs \
    --dry-run -o yaml > secret.yml
  NAMESPACES=$(kubectl get namespaces -l rtf.mulesoft.com/role=workers -o=jsonpath='{range .items[*]}{.metadata.name} {end}')
  NAMESPACES+=($NAMESPACE)

  for NS in ${NAMESPACES[*]}
  do
    echo "Updating namespace "$NS""
    kubectl apply -n${NS} -f secret.yml
  done
fi
