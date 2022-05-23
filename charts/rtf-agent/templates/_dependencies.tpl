{{- define "CORE_ACTION_IMAGE" -}}
mulesoft/rtf-core-actions:v1.0.16
{{- end -}}

{{- define "CONTAINER_MONITORING_IMAGE" -}}
mulesoft/dias-anypoint-monitoring-sidecar:v1.3.18
{{- end -}}

{{- define "CLUSTEROPS_IMAGE" -}}
mulesoft/rtf-cluster-ops:v1.1.43
{{- end -}}

{{- define "CONTAINER_RTF_DAEMON_IMAGE" -}}
mulesoft/rtf-daemon:v1.0.23
{{- end -}}

{{- define "EXTERNAL_LOG_FORWARDER_IMAGE" -}}
mulesoft/rtf-pkg-fluentbit:v1.2.60
{{- end -}}

{{- define "MULE_CLUSTER_IP_IMAGE" -}}
mulesoft/rtf-mule-clusterip-service:v1.2.40
{{- end -}}

{{- define "CONTAINER_INIT_IMAGE" -}}
mulesoft/rtf-app-init:v1.0.45
{{- end -}}

{{- define "CONTAINER_PERSISTENCE_GATEWAY_IMAGE" -}}
mulesoft/rtf-object-store:v1.0.51
{{- end -}}

{{- define "EDGE_IMAGE" -}}
mulesoft/securityfabric-edge:v1.1.359
{{- end -}}

{{- define "NGINX_IMAGE" -}}
mulesoft/base-image-nginx-1.21.1:v1.1.17
{{- end -}}

{{- define "RESOURCE_FETCHER_IMAGE" -}}
mulesoft/rtf-resource-fetcher:v1.0.53
{{- end -}}
