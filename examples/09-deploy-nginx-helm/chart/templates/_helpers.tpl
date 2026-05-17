{{/*
Expand the name of the chart.
*/}}
{{- define "nginx-helm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
Pattern: "<release>-<chart>", truncated to 63 chars (Kubernetes DNS limit).
If release name contains chart name, use release name alone.
*/}}
{{- define "nginx-helm.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart label string: "<name>-<version>" with "+" replaced (label values
can't contain "+").
*/}}
{{- define "nginx-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full common labels. Used on metadata.labels.
*/}}
{{- define "nginx-helm.labels" -}}
helm.sh/chart: {{ include "nginx-helm.chart" . }}
{{ include "nginx-helm.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels — the subset that doesn't change across releases of
the same chart, used by Service selectors and Deployment matchLabels.
*/}}
{{- define "nginx-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nginx-helm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
