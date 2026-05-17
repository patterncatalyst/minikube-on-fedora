---
title: Helm
order: 9
description: Helm 4 as a Kubernetes package manager; authoring a small chart that deploys the same UBI nginx via templated manifests and a ConfigMap.
duration: 25 minutes
---

§6 through §8 wrote Kubernetes manifests by hand: Deployment,
Service, PVC. Each kept some constants (image name, replica count,
service port) hardcoded. For a single example that's fine. For
deploying the same application across dev / staging / prod with
small differences, or for distributing an application that other
people will install, you want **parameterized** manifests.

That's what **helm** provides. A helm *chart* is a directory of
templated manifests plus a `values.yaml` file. `helm install`
renders the templates with the values, applies the result to your
cluster, and tracks the deployment as a **release**. Later you can
`helm upgrade` with different values, `helm history` to see what
changed, `helm rollback` to revert, or `helm uninstall` to remove
everything cleanly.

This section walks through building a small chart that deploys
`nginx-custom:v1` (the same image from §6/§7/§8) with content
parameterized via `values.yaml`. By the end you'll have authored
a working chart and exercised the install/upgrade/history/uninstall
loop.

## helm 3 vs helm 4

§2 installed helm via `dnf install helm`, which on Fedora 44 gives
**helm 4** (4.1.x at time of writing). The chart format used here
is `apiVersion: v2`, which is the format helm 3 introduced and
helm 4 continues to use. **Charts written for helm 3 generally
work unchanged with helm 4.** The helm 4 changes are mostly under
the hood (improved OCI registry handling, plugin system updates,
better dependency resolution). Day-to-day chart authoring and the
install/upgrade workflow are unchanged.

If you're following along on a system with helm 3, the example
chart and demo should still work.

## Chart anatomy

A chart is a directory with a specific structure:

```
chart/
├── Chart.yaml            # metadata: name, version, description
├── values.yaml           # default values for templating
└── templates/
    ├── _helpers.tpl      # reusable template definitions
    ├── configmap.yaml    # templated manifests…
    ├── deployment.yaml
    └── service.yaml
```

Each file in `templates/` is a Go template that produces a
Kubernetes manifest when rendered. The template syntax is
**Go templating + Sprig functions** — `{{ .Values.foo }}` inserts
a value, `{{ if .Values.bar }}` conditionally renders a block,
`{{ include "..." . | nindent N }}` interpolates a reusable
template defined in `_helpers.tpl`.

`values.yaml` provides the default values. The user (or a CI
pipeline) can override any of them at install time with
`--values custom-values.yaml` or `--set key=value`.

`Chart.yaml` is the chart's metadata:

```yaml
apiVersion: v2
name: nginx-helm
description: Deploys the §6 UBI nginx via a small helm chart with templated content
type: application
version: 0.1.0
appVersion: "1.20.1"
```

- `apiVersion: v2` — chart API v2, the helm 3+/4 format
- `version: 0.1.0` — the **chart's** version (changes when the
  chart itself changes)
- `appVersion: "1.20.1"` — the **application's** version (the
  nginx in the image). String, not numeric

## Our chart's design

`examples/09-deploy-nginx-helm/chart/values.yaml`:

```yaml
replicaCount: 1

image:
  repository: nginx-custom
  tag: v1
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

content:
  title: "Test Page from helm chart"
  message: "Content served from a templated ConfigMap"
  customLine: "Override this with --set content.customLine=..."
```

These are the defaults. Each becomes accessible inside templates
as `.Values.replicaCount`, `.Values.image.repository`, etc.

The chart has three manifests in `templates/`:

### ConfigMap

`templates/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "nginx-helm.fullname" . }}-content
  labels:
    {{- include "nginx-helm.labels" . | nindent 4 }}
data:
  index.html: |
    <h1>{{ .Values.content.title }}</h1>
    <p>{{ .Values.content.message }}</p>
    <p><strong>Custom line:</strong> {{ .Values.content.customLine }}</p>
    <p>Replicas: {{ .Values.replicaCount }} · Service port:
       {{ .Values.service.port }}</p>
```

The ConfigMap stores `index.html` as a key. The values from
`values.yaml` get interpolated at install time. Override
`content.title` at install with `--set content.title="My title"`
and the rendered ConfigMap reflects that.

### Deployment

`templates/deployment.yaml` (abbreviated):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nginx-helm.fullname" . }}
  labels:
    {{- include "nginx-helm.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "nginx-helm.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "nginx-helm.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: nginx
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: content
        configMap:
          name: {{ include "nginx-helm.fullname" . }}-content
```

The ConfigMap is mounted at `/usr/share/nginx/html`. Same overlay
trick as §8 — the image's baked-in content is hidden by the mount.

### Service

`templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "nginx-helm.fullname" . }}
  labels:
    {{- include "nginx-helm.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  selector:
    {{- include "nginx-helm.selectorLabels" . | nindent 4 }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: 8080
    protocol: TCP
```

### _helpers.tpl

`templates/_helpers.tpl` defines the named templates the manifests
reference:

```
{{/* Fullname: "release-chart" pattern, truncated to 63 chars */}}
{{- define "nginx-helm.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels */}}
{{- define "nginx-helm.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "nginx-helm.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels (subset used by Service selectors) */}}
{{- define "nginx-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

Three templates. `fullname` produces a `<release>-<chart>` name
that's truncated to fit Kubernetes' 63-character DNS limit;
`labels` produces the canonical helm/Kubernetes label set;
`selectorLabels` is the subset Services use to match Pods (the
two labels that *don't* change across releases of the same chart).

## The workflow

### Install

```bash
helm install nginx-helm ./chart \
    --set content.title="First install" \
    --set content.customLine="from helm install"
```

Output:

```
NAME: nginx-helm
LAST DEPLOYED: ...
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

helm rendered the templates with the merged values
(`values.yaml` defaults + `--set` overrides), applied the
resulting manifests, and tracked the release as `nginx-helm`
revision 1.

Verify:

```bash
helm list
kubectl get deployment,svc,configmap -l app.kubernetes.io/instance=nginx-helm
```

### Dry-run rendering — `helm template`

Before `install`, render the chart to stdout and inspect:

```bash
helm template nginx-helm ./chart --set content.title="Preview"
```

This is invaluable for catching template errors or visualizing
what your overrides actually produce. It doesn't talk to the
cluster.

### Lint — `helm lint`

Quick chart sanity check:

```bash
helm lint ./chart
```

Catches missing fields in `Chart.yaml`, bad indentation,
references to undefined values, and a handful of best-practice
issues.

### Upgrade

After install, change a value and upgrade:

```bash
helm upgrade nginx-helm ./chart \
    --set content.title="Upgraded title" \
    --set content.customLine="from helm upgrade"
```

The release moves to revision 2. The Deployment rolls out the new
ConfigMap; the existing Pods get recreated (or you'd need to add
an annotation that triggers rollout on ConfigMap change — a
separate refinement worth knowing about for production charts).

### History

```bash
helm history nginx-helm
```

```
REVISION  UPDATED                  STATUS      CHART             ...  DESCRIPTION
1         ...                      superseded  nginx-helm-0.1.0  ...  Install complete
2         ...                      deployed    nginx-helm-0.1.0  ...  Upgrade complete
```

### Rollback (optional)

```bash
helm rollback nginx-helm 1
```

Reverts to revision 1's values. Useful when an upgrade misbehaves.

### Uninstall

```bash
helm uninstall nginx-helm
```

Removes the Deployment, Service, ConfigMap, and the release record.
A clean uninstall — no orphans.

## Verification: examples/09-deploy-nginx-helm/

`examples/09-deploy-nginx-helm/demo.sh` exercises the full
workflow:

1. Pre-flight: cluster up; image cached (auto-build if not);
   helm available
2. `helm lint` the chart
3. `helm template` the chart (renders without applying; verifies
   the chart parses)
4. `helm install` with `--set content.title="..."` overrides
5. Wait for Deployment Available
6. Port-forward, curl, verify the installed title appears in the
   served HTML
7. `helm upgrade` with different title
8. Wait for rollout
9. Re-establish port-forward (Pods got recreated)
10. Curl, verify the upgraded title now appears
11. `helm history nginx-helm` — show both revisions
12. `helm uninstall nginx-helm` — clean removal
13. Verify no leftover resources match the chart's label selector

```bash
cd examples/09-deploy-nginx-helm
./demo.sh
```

Expected duration: 30-60 seconds. Most of it is the rollout-after-
upgrade phase.

[On to §10: editor, shell, and terminal →]({{ "/docs/10-editor-shell-terminal/" | relative_url }})
