{{- define "sample-backend.name" -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "sample-backend.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "sample-backend.selector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "sample-backend.image" -}}
{{- $digest := required "image.digest is required, tags are not accepted" .Values.image.digest -}}
{{- if not (hasPrefix "sha256:" $digest) -}}
{{- fail (printf "image.digest must start with sha256:, got %q" $digest) -}}
{{- end -}}
{{ .Values.image.repository }}@{{ $digest }}
{{- end -}}

{{- define "sample-backend.database" -}}
{{ include "sample-backend.name" . }}-db
{{- end -}}

{{/*
CloudNativePG writes the application credentials into <cluster>-app, including
a ready to use connection URI. The app and the migration job both read it.
*/}}
{{- define "sample-backend.databaseEnv" -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "sample-backend.database" . }}-app
      key: uri
{{- end -}}

{{- define "sample-backend.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
fsGroup: 65532
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "sample-backend.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
{{- end -}}
