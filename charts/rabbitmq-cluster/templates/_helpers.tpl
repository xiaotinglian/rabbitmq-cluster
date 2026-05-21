{{- define "rabbitmq-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rabbitmq-cluster.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "rabbitmq-cluster.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rabbitmq-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rabbitmq-cluster.labels" -}}
helm.sh/chart: {{ include "rabbitmq-cluster.chart" . }}
app.kubernetes.io/name: {{ include "rabbitmq-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "rabbitmq-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rabbitmq-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rabbitmq-cluster.headlessServiceName" -}}
{{- printf "%s-headless" (include "rabbitmq-cluster.fullname" .) -}}
{{- end -}}

{{- define "rabbitmq-cluster.authSecretName" -}}
{{- printf "%s-auth" (include "rabbitmq-cluster.fullname" .) -}}
{{- end -}}

{{- define "rabbitmq-cluster.tlsSecretName" -}}
{{- printf "%s-tls" (include "rabbitmq-cluster.fullname" .) -}}
{{- end -}}