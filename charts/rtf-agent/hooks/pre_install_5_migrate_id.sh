#!/bin/bash

# pre-install task: migrate id labels

TYPES=(deployment daemonset configmap secret job ingress service)
NAMESPACES=$(kubectl get ns -l rtf.mulesoft.com/role -ojsonpath='{range .items[*]}{.metadata.name} {end}')

for NS in ${NAMESPACES[*]}
do
  for TYPE in ${TYPES[*]}
  do
    TO_MIGRATE=$(kubectl get ${TYPE} -n${NS} -l 'id,!rtf.mulesoft.com/id' -ojsonpath='{range .items[*]}{.metadata.name}:{.metadata.labels.id} {end}')

    for TARGET in ${TO_MIGRATE[*]}
    do
      NAME=$(echo -n ${TARGET} | cut -d: -f 1)
      ID=$(echo -n ${TARGET} | cut -d: -f 2)

      kubectl -n${NS} label ${TYPE} ${NAME} "rtf.mulesoft.com/id=${ID}"
    done
  done
done
