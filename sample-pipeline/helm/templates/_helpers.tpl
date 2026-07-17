{{- define "sheep-counting.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "sheep-counting.fullname" -}}
{{- if .Release.Name | eq .Chart.Name -}}
{{- .Chart.Name -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "sheep-counting.labels" -}}
app.kubernetes.io/name: {{ include "sheep-counting.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "sheep-counting.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sheep-counting.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
