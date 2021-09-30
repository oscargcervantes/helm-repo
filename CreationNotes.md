# Helm chart creation

## Clone repo and create images

    git clone https://github.com/yoongti/devops
    cd devops/apps/01-first-app/

## Change port from 80 to 4043

    sed -i 's/const port =.*/const port = 4043/g' app.js

## Modify yaml

    sed -i 's|image:.*|image: quay.io/oscargcervantes/first-app:v1|g' yml/deployment.yml
    sed -i 's|containerPort:.*|containerPort: 4043|g' yml/deployment.yml
    sed -i 's/port:.*/port: 4043/g' yml/service.yml
    sed -i 's/targetPort:.*/targetPort: 4043/g' yml/service.yml
    
## Build image

    docker build -t quay.io/oscargcervantes/first-app:v1 -f Dockerfile .
    docker push quay.io/oscargcervantes/first-app:v1
    
  **NOTE:** Set quay.io/oscargcervantes/firs-tapp repository as public
    
## Test container  
    
    docker run -d --rm --name first-app -p 4043:4043 quay.io/oscargcervantes/first-app:v1
    docker ps

## Create namespace/project

    oc new-project first-app-helm
    
## Test deployment yml

    oc apply -f yml/deployment.yml
    oc apply -f yml/service.yml
    oc apply -f yml/first-app-ingress.yml 
    oc get ingress
    oc delete -f yml/deployment.yml
    oc delete -f yml/service.yml
    oc delete -f yml/first-app-ingress.yml
    
## Create helm chart

    cd ../../../
    helm create first-app
    rm -rf first-app/templates/*

## Copy yml from devops/apps/01-fisrt-app/yml directory to helm chart templates

    cp devops/apps/01-first-app/yml/* first-app/templates/

## Install helm chart
    
    // helm install [NAME] [CHART]
    helm install first-app-helm first-app
    
    * Output
    
            NAME: first-app-helm
            LAST DEPLOYED: Wed Sep 29 14:59:46 2021
            NAMESPACE: default
            STATUS: deployed
            REVISION: 1
            TEST SUITE: None

## List helm
 
     helm list
     
## Expose helm service using routes (OPTIONAL)
     
    oc get service
    oc expose service first-app-service
    oc get route
    
    #curl first-app-service-default.apps.ocp4sdev.atl.dst.ibm.com
    #curl first-app-service-default.apps.ocp4sdev.atl.dst.ibm.com/v1
    #curl first-app-service-default.apps.ocp4sdev.atl.dst.ibm.com/v2
    #curl first-app-service-default.apps.ocp4sdev.atl.dst.ibm.com/v3
    #curl first-app-service-default.apps.ocp4sdev.atl.dst.ibm.com/v4

## Delete helm

    helm uninstall first-app-helm

## Modify ymls in first-app/templates directory to use variables

### deployment.yml

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  labels:
    app: {{ .Values.name }}
spec:
  replicas: {{ .Values.deployment.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
    spec:
      containers:
        - name: {{ .Values.name }}
          image: {{ .Values.deployment.image }}:{{ .Values.deployment.tag }}
          imagePullPolicy: Always
          ports:
            - containerPort: {{ .Values.deployment.containerPort }}
```

### service.yml

```
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.service.name }}
spec:
  type: NodePort
  selector:
    app: {{ .Values.service.selector }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      nodePort: {{ .Values.service.nodePort }}
```

### first-app-ingress.yml

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Values.ingress.name}}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: {{ .Values.ingress.host}}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ .Values.service.name }}
            port:
              number: {{ .Values.ingress.port }}
```

### values.yml

```
name: first-app
deployment:
  image: quay.io/oscargcervantes/first-app
  tag: v1
  replicas: 5
  containerPort: 4043
service:
  name: first-app-service
  selector: first-app
  port: 4043
  targetPort: 4043
  nodePort: 30112
ingress:
  name: first-app-ingress
  host: "first-app-ingress.apps.ocp4sdev.atl.dst.ibm.com"
  port: 4043
```

## Check templates

    helm template first-app

## Reinstall the helm

    // helm install [NAME] [CHART]
    helm install first-app-helm first-app/
    
    * Output
    
            NAME: first-app-helm
            LAST DEPLOYED: Wed Sep 29 14:59:46 2021
            NAMESPACE: default
            STATUS: deployed
            REVISION: 1
            TEST SUITE: None

## List new helm
 
     helm list

## Upgrade helm values

Change replicas number in values.yml and upgrade helm

    helm upgrade first-app-helm first-app/
    
* Output

        Release "first-app-helm" has been upgraded. Happy Helming!
        NAME: first-app-helm
        LAST DEPLOYED: Thu Sep 30 07:29:24 2021
        NAMESPACE: default
        STATUS: deployed
        REVISION: 2
        TEST SUITE: None

## Rollback to previous helm

    // helm rollback <RELEASE> [REVISION] [flags]
    helm rollback first-app-helm

* Output

        Rollback was a success! Happy Helming!

## Check helm history

    helm history first-app-helm

## Check helm package

    helm lint first-app/

---

## Prepare github repository as helm repository

## Helm github repository url

    https://github.com/oscargcervantes/helm-repo.git

### Next check that GitHub Pages is enabled

* Click on your git repo settings in GitHub repository and check
* Github pages published at: https://pages.github.ibm.com/ocervant/helm-repo/

### Create helm package

    helm package charts/first-app #--destination deploy-files
    helm repo index . --url https://oscargcervantes.github.io/helm-repo/ #deploy-files/ --url https://pages.github.ibm.com/ocervant/helm-repo/

### Check index.yaml

    cat index.yaml 

### Commit changes

    git add -A
    git commit -a -m "change index"
    git push origin

### Check helm package file

    curl https://oscargcervantes.github.io/helm-repo

### Add helm repo

    helm repo add my-repo https://oscargcervantes.github.io/helm-repo/

### List repo

    helm repo list

### Search

    helm search repo first-app

    NAME             	CHART VERSION	APP VERSION	DESCRIPTION                
    my-repo/first-app	0.1.0        	1.16.0     	A Helm chart for Kubernetes

### Helm repo update

    helm repo update

### Install from github repo
    
    helm install first-app-helm my-repo/first-app
    oc get pod
    oc get route

### Upgrade helm using new-values.yaml

    helm upgrade first-app-helm my-repo/first-app -f new-values.yaml 
    oc get pod

### Helm uninstall

    helm uninstall first-app-helm

### Remove helm repo
    
    helm repo list
    helm repo remove my-repo