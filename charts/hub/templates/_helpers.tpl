{{/*
Expand the name of the chart.
*/}}
{{- define "self-healing-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "self-healing-platform.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "self-healing-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "self-healing-platform.labels" -}}
helm.sh/chart: {{ include "self-healing-platform.chart" . }}
{{ include "self-healing-platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "self-healing-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "self-healing-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "self-healing-platform.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "self-healing-platform.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get S3 endpoint URL
Auto-detects from NooBaa route if not provided in values
Defaults to: https://s3.openshift-storage.svc.cluster.local
*/}}
{{- define "self-healing-platform.s3Endpoint" -}}
{{- if .Values.objectStore.endpoint }}
{{- .Values.objectStore.endpoint }}
{{- else }}
{{- "https://s3.openshift-storage.svc.cluster.local" }}
{{- end }}
{{- end }}

{{/*
Get S3 bucket name for models
*/}}
{{- define "self-healing-platform.modelBucket" -}}
{{- .Values.objectStore.buckets.models | default "model-storage" }}
{{- end }}

{{/*
Get S3 bucket name for training data
*/}}
{{- define "self-healing-platform.trainingDataBucket" -}}
{{- .Values.objectStore.buckets.trainingData | default "training-data" }}
{{- end }}

{{/*
Get S3 bucket name for inference results
*/}}
{{- define "self-healing-platform.inferenceResultsBucket" -}}
{{- .Values.objectStore.buckets.inferenceResults | default "inference-results" }}
{{- end }}

{{/*
Get S3 region
*/}}
{{- define "self-healing-platform.s3Region" -}}
{{- .Values.objectStore.region | default "us-east-1" }}
{{- end }}

{{/*
Get SSL verification flag
*/}}
{{- define "self-healing-platform.sslVerify" -}}
{{- .Values.objectStore.sslVerify | default false }}
{{- end }}

{{/*
Get namespace for resources
*/}}
{{- define "self-healing-platform.namespace" -}}
{{- .Values.main.namespace | default "self-healing-platform" }}
{{- end }}

{{/*
Wait-for-image Job template
Creates a Job that waits for an ImageStreamTag to exist before allowing sync to continue.
Usage: {{ include "self-healing-platform.waitForImage" (dict "name" "my-image" "tag" "latest" "namespace" .Values.main.namespace "syncWave" "-3" "timeout" "3600") }}
*/}}
{{- define "self-healing-platform.waitForImage" -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: wait-for-{{ .name }}-image
  namespace: {{ .namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "{{ .syncWave | default "-3" }}"
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
  labels:
    app.kubernetes.io/name: wait-for-{{ .name }}-image
    app.kubernetes.io/component: image-wait
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app.kubernetes.io/name: wait-for-{{ .name }}-image
    spec:
      serviceAccountName: self-healing-operator
      restartPolicy: Never
      containers:
      - name: wait-for-image
        image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
        command: ["/bin/bash", "-c"]
        args:
        - |
          set -e
          echo "Waiting for ImageStreamTag {{ .name }}:{{ .tag | default "latest" }} to exist..."
          TIMEOUT={{ .timeout | default "3600" }}
          ELAPSED=0
          INTERVAL=30
          while [ $ELAPSED -lt $TIMEOUT ]; do
            if oc get imagestreamtag {{ .name }}:{{ .tag | default "latest" }} -n {{ .namespace }} 2>/dev/null; then
              echo "✅ ImageStreamTag {{ .name }}:{{ .tag | default "latest" }} exists!"
              exit 0
            fi
            echo "⏳ Waiting for image... ($ELAPSED/$TIMEOUT seconds)"
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
          done
          echo "❌ Timeout waiting for ImageStreamTag {{ .name }}:{{ .tag | default "latest" }}"
          exit 1
{{- end }}

{{/*
Git URL fallback chain helper
Returns the first non-empty git URL from: specific config > chart values > global values
Usage: {{ include "self-healing-platform.gitUrl" (dict "specific" .Values.notebooks.validation.git.url "chart" .Values.git.repoURL "global" .Values.global.git.repoURL) }}
*/}}
{{- define "self-healing-platform.gitUrl" -}}
{{- .specific | default .chart | default .global | default "" }}
{{- end }}

{{/*
Git ref fallback chain helper
Returns the first non-empty git ref from: specific config > chart values > global values > "main"
Usage: {{ include "self-healing-platform.gitRef" (dict "specific" .Values.notebooks.validation.git.ref "chart" .Values.git.revision "global" .Values.global.git.revision) }}
*/}}
{{- define "self-healing-platform.gitRef" -}}
{{- .specific | default .chart | default .global | default "main" }}
{{- end }}

{{/*
Conditional resource rendering helper
Only renders content if condition is true and required values exist
Usage: {{- include "self-healing-platform.ifEnabled" (dict "enabled" .Values.feature.enabled "required" .Values.feature.requiredValue "content" "yaml content here") }}
*/}}
{{- define "self-healing-platform.ifEnabled" -}}
{{- if and .enabled .required }}
{{ .content }}
{{- end }}
{{- end }}

{{/*
RHOAI dashboard route name
Returns the route hostname prefix based on RHOAI version:
  - RHOAI 3.x (OCP 4.20+): "data-science-gateway"
  - RHOAI 2.x (OCP 4.18):  "rhods-dashboard-redhat-ods-applications"
Can be overridden explicitly via workbench.dashboardRoute.
*/}}
{{- define "self-healing-platform.dashboardRoute" -}}
{{- if ((.Values.workbench).dashboardRoute | default "") }}
{{- .Values.workbench.dashboardRoute }}
{{- else }}
{{- $version := .Values.cluster.version | default "4.18" }}
{{- if semverCompare ">=4.20" $version }}
{{- "data-science-gateway" }}
{{- else }}
{{- "rhods-dashboard-redhat-ods-applications" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
RHOAI dashboard host (FQDN)
Combines the dashboard route name with the cluster apps domain.
global.clusterDomain is the OpenShift baseDomain (e.g. "ocp.example.com"),
auto-populated by the Validated Patterns operator. Routes use "apps.<baseDomain>".
*/}}
{{- define "self-healing-platform.dashboardHost" -}}
{{- $route := include "self-healing-platform.dashboardRoute" . }}
{{- $domain := .Values.global.clusterDomain | default "" }}
{{- if $domain }}
{{- printf "%s.apps.%s" $route $domain }}
{{- else }}
{{- $route }}
{{- end }}
{{- end }}
