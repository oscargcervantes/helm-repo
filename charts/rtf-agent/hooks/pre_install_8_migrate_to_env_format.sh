#!/bin/bash

# pre-install task: migrate custom properties into secrets

# migrate NO_PROXY
set +o errexit
kubectl -n${NAMESPACE} get secret custom-properties -oyaml | grep HTTP_NO_PROXY
SHOULD_MIGRATE=$?
set -o errexit

if [[ "$SHOULD_MIGRATE" -gt "0" ]]; then
  TO_MIGRATE=$(kubectl -n${NAMESPACE} get cm custom-properties -ojsonpath="{.data['proxy\.noproxy']}" | base64 ${BASE64_OPTS})
  kubectl -n${NAMESPACE} patch secret custom-properties -p "{\"data\":{\"HTTP_NO_PROXY\":\"${TO_MIGRATE}\"}}"
fi

# migrate proxy.http
set +o errexit
kubectl -n${NAMESPACE} get secret custom-properties -oyaml | grep HTTP_PROXY
SHOULD_MIGRATE=$?
set -o errexit

if [[ "$SHOULD_MIGRATE" -gt "0" ]]; then
  TO_MIGRATE=$(kubectl -n${NAMESPACE} get secret custom-properties -ojsonpath="{.data['proxy\.http']}")

  if [[ "$TO_MIGRATE" == "<nil>" ]]; then
    TO_MIGRATE=""
  fi

  kubectl -n${NAMESPACE} patch secret custom-properties -p "{\"data\":{\"HTTP_PROXY\":\"${TO_MIGRATE}\"}}"
fi

# migrate proxy.monitoring
set +o errexit
kubectl -n${NAMESPACE} get secret custom-properties -oyaml | grep MONITORING_PROXY
SHOULD_MIGRATE=$?
set -o errexit

if [[ "$SHOULD_MIGRATE" -gt "0" ]]; then
  TO_MIGRATE=$(kubectl -n${NAMESPACE} get secret custom-properties -ojsonpath="{.data['proxy\.monitoring']}")

  if [[ "$TO_MIGRATE" == "<nil>" ]]; then
    TO_MIGRATE=""
  fi

  kubectl -n${NAMESPACE} patch secret custom-properties -p "{\"data\":{\"MONITORING_PROXY\":\"${TO_MIGRATE}\"}}"
fi

# migrate AM_ENABLED
TO_MIGRATE=$(kubectl -n${NAMESPACE} get cm custom-properties -ojsonpath="{.data['anypointMonitoring\.enabled']}")
if [[ -n "$AM_ENABLED" ]]; then
  kubectl -n${NAMESPACE} patch cm app-config -p "{\"data\":{\"ANYPOINTMONITORING_ENABLED\":\"${TO_MIGRATE}\"}}"
fi
