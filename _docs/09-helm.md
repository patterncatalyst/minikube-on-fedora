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

Every `helm` command here carries `--kube-context minikube`, and every
`kubectl` command assumes the `minikube` context from §4 (add
`--context minikube` if another is current). The demo pins both.

## helm 3 vs helm 4

§2 installed helm via `dnf install helm`, which on Fedora 44 gives
**helm 4**. The chart format used here
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
{% raw %}**Go templating + Sprig functions** — `{{ .Values.foo }}` inserts
a value, `{{ if .Values.bar }}` conditionally renders a block,
`{{ include "..." . | nindent N }}` interpolates a reusable
template defined in `_helpers.tpl`.{% endraw %}

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
  pullPolicy: Never       # loaded into the node in §6

service:
  type: NodePort
  port: 80
  # Published to 127.0.0.1:18080 at profile creation
  # (--ports=127.0.0.1:18080:30080). Shared slot with §6, §8, §12-http.
  # Set to null for a Kubernetes-assigned port.
  nodePort: 30080

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

{% raw %}
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
{% endraw %}

The ConfigMap stores `index.html` as a key. The values from
`values.yaml` get interpolated at install time. Override
`content.title` at install with `--set content.title="My title"`
and the rendered ConfigMap reflects that.

### Deployment

`templates/deployment.yaml` (abbreviated):

{% raw %}
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
      annotations:
        # Rotates when the rendered ConfigMap content changes, so a
        # `helm upgrade` that only changes values rolls the Pods.
        checksum/configmap: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
      - name: nginx
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: content
        configMap:
          name: {{ include "nginx-helm.fullname" . }}-content
```
{% endraw %}

The ConfigMap is mounted at `/usr/share/nginx/html`. Same overlay
trick as §8 — the image's baked-in content is hidden by the mount.

### Service

`templates/service.yaml`:

{% raw %}
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
  - name: http
    port: {{ .Values.service.port }}
    targetPort: http
    protocol: TCP
    {{- if .Values.service.nodePort }}
    nodePort: {{ .Values.service.nodePort }}
    {{- end }}
```
{% endraw %}

With `service.type: NodePort` and `service.nodePort: 30080`, the
Service lands on the slot the `minikube` profile publishes to
`127.0.0.1:18080` (§7 explains the mechanism). The `if` makes the port
optional: `--set service.nodePort=null` lets Kubernetes pick one, and
`--set service.type=ClusterIP` with `nodePort=null` gives an internal
Service. Only one Service can hold 30080 at a time, so **delete §8's
Service first** (`kubectl delete -f
examples/08-persistent-volume/manifests/`); the demo's preflight stops
with a "delete X first" message if something holds the port.

### _helpers.tpl

`templates/_helpers.tpl` defines the named templates the manifests
reference:

{% raw %}
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
{% endraw %}

Three templates. `fullname` produces a `<release>-<chart>` name
that's truncated to fit Kubernetes' 63-character DNS limit;
`labels` produces the canonical helm/Kubernetes label set;
`selectorLabels` is the subset Services use to match Pods (the
two labels that *don't* change across releases of the same chart).

## The workflow

### Install

```bash
helm --kube-context minikube install nginx-helm ./chart \
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

Verify, then reach it on the published port:

```bash
helm --kube-context minikube list
kubectl get deployment,svc,configmap -l app.kubernetes.io/instance=nginx-helm
curl http://127.0.0.1:18080/
```

The response contains the title and custom line you passed with
`--set`.

### Dry-run rendering — `helm template`

Before `install`, render the chart to stdout and inspect:

```bash
helm --kube-context minikube template nginx-helm ./chart --set content.title="Preview"
```

This is invaluable for catching template errors or visualizing
what your overrides actually produce. It doesn't talk to the
cluster.

### Lint — `helm lint`

Quick chart sanity check:

```bash
helm --kube-context minikube lint ./chart
```

Catches missing fields in `Chart.yaml`, bad indentation,
references to undefined values, and a handful of best-practice
issues.

### Upgrade

After install, change a value and upgrade:

```bash
helm --kube-context minikube upgrade nginx-helm ./chart \
    --set content.title="Upgraded title" \
    --set content.customLine="from helm upgrade"
```

The release moves to revision 2. A ConfigMap change alone does not
roll Pods, so the Deployment template carries a
`checksum/configmap` annotation: the hash of the rendered ConfigMap
changes with the values, the Pod template changes with it, and the
Pods are recreated. The published port follows them with no
re-attaching; `curl http://127.0.0.1:18080/` shows the new title once
the rollout finishes.

### History

```bash
helm --kube-context minikube history nginx-helm
```

```
REVISION  UPDATED                  STATUS      CHART             ...  DESCRIPTION
1         ...                      superseded  nginx-helm-0.1.0  ...  Install complete
2         ...                      deployed    nginx-helm-0.1.0  ...  Upgrade complete
```

### Rollback (optional)

```bash
helm --kube-context minikube rollback nginx-helm 1
```

Reverts to revision 1's values. Useful when an upgrade misbehaves.

### Uninstall

```bash
helm --kube-context minikube uninstall nginx-helm
```

Removes the Deployment, Service, ConfigMap, and the release record,
freeing nodePort 30080. A clean uninstall — no orphans.

## Verification: examples/09-deploy-nginx-helm/

`examples/09-deploy-nginx-helm/demo.sh` exercises the full
workflow:

1. Pre-flight: Docker Engine, `minikube` profile with published
   ports, pinned context; helm available; image loaded (auto-build and
   load from §6 if not); nodePort 30080 free
2. `helm lint` the chart
3. `helm template` the chart (renders without applying; verifies
   the chart parses)
4. `helm install` with `--set content.title="..."` overrides
5. Wait for Deployment Available
6. Confirm the port is published, curl `http://127.0.0.1:18080/`,
   verify the installed title appears in the served HTML
7. `helm upgrade` with different title
8. Wait for rollout
9. Poll `http://127.0.0.1:18080/` until the recreated Pods answer
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
