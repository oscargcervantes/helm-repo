#!/bin/bash

BACKUP_DIR=/var/lib/gravity/backup
alias kubectl=/usr/local/bin/kubectl

echo "Backing up cluster-wide resources..."
touch $BACKUP_DIR/__cluster.yaml
kubectl get ns rtf -oyaml > $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl get ns -l rtf.mulesoft.com/role=workers -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl get psp -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl get clusterrole -l "app.kubernetes.io/instance==runtime-fabric" -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl get clusterrolebinding -l "app.kubernetes.io/instance==runtime-fabric" -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl get priorityclass -l "app.kubernetes.io/instance==runtime-fabric" -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl get crd persistencegateways.rtf.mulesoft.com  -oyaml --ignore-not-found >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl -nkube-system get cm -l NAME=runtime-fabric,OWNER=TILLER -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl -nkube-system get cm -l OWNER=rtf.mulesoft.com -oyaml >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl -nkube-system get cm -l "app.kubernetes.io/instance==runtime-fabric" -oyaml >> $BACKUP_DIR/__cluster.yaml

# back up rtf-tiller stuff
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl -nkube-system get clusterrolebinding tiller -oyaml --ignore-not-found >> $BACKUP_DIR/__cluster.yaml
echo --- >> $BACKUP_DIR/__cluster.yaml
kubectl -nkube-system get sa rtf-tiller -oyaml --ignore-not-found >> $BACKUP_DIR/__cluster.yaml

# create restore data
echo --- >> $BACKUP_DIR/__cluster.yaml
NODES=$(kubectl get node -ojson | jq -c '[.items[] | {kind, metadata}]')
kubectl -nrtf create configmap restore-data --dry-run -oyaml \
 --from-literal=RESTORE_STARTUP_RUN=true \
 --from-literal=RESTORE_DATA_NODES=$NODES \
 >> $BACKUP_DIR/__cluster.yaml


# backup resources per namespace
NAMESPACES=$(kubectl get ns -l rtf.mulesoft.com/role -o=jsonpath="{range .items[*]}{.metadata.name} {end}")

for NS in ${NAMESPACES[*]}
do
  echo "Backing up namespace $NS..."
  touch $BACKUP_DIR/$NS.yaml
  kubectl get secret -n$NS --field-selector="type!=kubernetes.io/service-account-token" -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get serviceaccount -n$NS --field-selector="metadata.name!=default" -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get configmap -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get service -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get cronjob -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get daemonset -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get deployment -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get ingress -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get role -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get rolebinding -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
  echo --- >> $BACKUP_DIR/$NS.yaml
  kubectl get persistencegateways.rtf.mulesoft.com -n$NS  >/dev/null 2>&1
  if [ "$?" == "0" ]; then
    kubectl get persistencegateways.rtf.mulesoft.com -n$NS -oyaml >> $BACKUP_DIR/$NS.yaml
    echo --- >> $BACKUP_DIR/$NS.yaml
  fi
done

echo "Post-processing..."
BACKUP_FILES=$(find $BACKUP_DIR/*.yaml)

for FILE in ${BACKUP_FILES[*]}
do
  basename $FILE

  yq --yaml-output "del(.. | .ownerReferences?) | del(.. | .status?) | del(.. | .creationTimestamp?)" $FILE > $FILE.tmp
  mv $FILE.tmp $FILE
done

echo "Done."
