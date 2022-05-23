{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "name" -}}
  {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
Credit: @technosophos
https://github.com/technosophos/common-chart/
chartref prints a chart name and version.
It does minimal escaping for use in Kubernetes labels.
Example output:
  zookeeper-1.2.3
  wordpress-3.2.1_20170219
*/ -}}
{{- define "chartref" -}}
  {{- replace "+" "_" .Chart.Version | printf "%s-%s" .Chart.Name -}}
{{- end -}}

{{- define "image.registryEndpoint" -}}
{{ .Values.global.image.rtfRegistry }}
{{- end -}}

{{- define "labels.rtfComponent" -}}
rtf.mulesoft.com/component: agent
{{- end -}}

{{- define "labels.standard" -}}
app.kubernetes.io/instance: {{ .Release.Name  }}
{{- end -}}

{{- define "labels.enableComponentClusterHealth" -}}
rtf.mulesoft.com/report-status: "true"
{{- end -}}

{{- define "annotations.componentTag" -}}
rtf.mulesoft.com/tags: {{ . }}
{{- end -}}

{{- define "isBYOK" -}}
{{- if and (ne .Values.global.cluster.flavor "gravitational") (ne .Values.global.cluster.flavor "rtfc") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "isRTFC" -}}
{{- if and (ne .Values.global.cluster.flavor "gravitational") (ne .Values.global.cluster.flavor "byok") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "isGravity" -}}
{{- if and (ne .Values.global.cluster.flavor "byok") (ne .Values.global.cluster.flavor "rtfc") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "linux_node_selector_labels" -}}
{{- if or (gt .Capabilities.KubeVersion.Major "1") (and (eq .Capabilities.KubeVersion.Major "1") (ge .Capabilities.KubeVersion.Minor "14")) -}}
kubernetes.io/os: linux
kubernetes.io/arch: amd64
{{- else -}}
beta.kubernetes.io/os: linux
beta.kubernetes.io/arch: amd64
{{- end -}}
{{- end -}}

{{- define "image.name" -}}
{{- $tag := (printf "v%s" .Chart.Version) -}}
{{ template "image.registryEndpoint" . }}/mulesoft/rtf-agent:{{ $tag }}
{{- end -}}


{{- define "CUSTOM_RESOURCES_DEFINITIONS" -}}
'[{"resourceDefinition":"persistencegateways.rtf.mulesoft.com","namespaces":["rtf"]}]'
{{- end -}}

