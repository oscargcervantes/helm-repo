#!/bin/bash

# pre-install task: add certificate chain to pem file

AGENT_KEYSTORE="agent-keystore.p12"
PEM_CERTIFICATE="signed-cert.pem"
NAMESPACE=rtf
BASE64_DECODE_OPTS="-d"
BASE64_OPTS="-w0"

set +o errexit
kubectl -n${NAMESPACE} get secret agent-keystore
EXISTING_AGENT_KEYSTORE=$?
set -o errexit

if [[ "$EXISTING_AGENT_KEYSTORE" -eq "0" ]]; then

  # Check if PEM certificate contains chain
  kubectl get secret agent-keystore -n $NAMESPACE -o json | jq -r '.data["signed-cert.pem"]' | base64 $BASE64_DECODE_OPTS > $PEM_CERTIFICATE
  CERTIFICATE_COUNT=$(cat $PEM_CERTIFICATE | grep "BEGIN CERTIFICATE" | wc -l)

  if [[ "$CERTIFICATE_COUNT" -eq "1" ]]; then

    echo "Proceeding with replacing certificate from P12 keystore"
    kubectl get secret agent-keystore -n $NAMESPACE -o json | jq -r '.data["agent-keystore.p12"]' | base64 $BASE64_DECODE_OPTS > $AGENT_KEYSTORE

    KEYSTORE_PASSWORD=$(kubectl -n $NAMESPACE get secret agent-keystore -o json | jq -r '.data["keystore-password"]' | base64 $BASE64_DECODE_OPTS)

    # extract cert chain to signed.crt
    openssl pkcs12 -in $AGENT_KEYSTORE -nokeys -out signed.crt -nodes -password pass:$KEYSTORE_PASSWORD

    # Update agent keystore
    UPDATED_SIGNED_CERT=$(cat signed.crt | base64 $BASE64_OPTS)

    kubectl -n $NAMESPACE get secret agent-keystore -o json | \
      jq --arg cert "$UPDATED_SIGNED_CERT" '.data["signed-cert.pem"] = $cert' | \
      kubectl apply -f -
  fi
fi
