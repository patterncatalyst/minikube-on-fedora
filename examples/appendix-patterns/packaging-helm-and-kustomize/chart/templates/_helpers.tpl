{{/* Fixed fullname: nameOverride if set, else the usual release-chart pattern */}}
{{- define "shipping-chart.fullname" -}}
{{- .Values.nameOverride | default (printf "%s-%s" .Release.Name .Chart.Name) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels */}}
{{- define "shipping-chart.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "shipping-chart.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels */}}
{{- define "shipping-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shipping-chart.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
