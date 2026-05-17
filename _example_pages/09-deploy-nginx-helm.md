---
title: "09-deploy-nginx-helm"
order: 9
example_dir: examples/09-deploy-nginx-helm
permalink: /examples/09-deploy-nginx-helm/
layout: docs
---

> Source: [`examples/09-deploy-nginx-helm/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/09-deploy-nginx-helm)
> &nbsp;&nbsp;|&nbsp;&nbsp; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})

Authors a small helm chart that deploys the same `nginx-custom:v1`
image as §6/§7/§8, but with content templated through helm's
`values.yaml` mechanism and injected via a ConfigMap. The demo
exercises the full helm lifecycle: lint, dry-run render, install,
upgrade, history, uninstall.

## What's in the chart

```
chart/
├── Chart.yaml            # nginx-helm 0.1.0, app nginx 1.20.1
├── values.yaml           # defaults: 1 replica, ClusterIP:80,
│                         # placeholder content title/message
└── templates/
    ├── _helpers.tpl      # fullname/labels/selectorLabels templates
    ├── configmap.yaml    # index.html populated from values.content.*
    ├── deployment.yaml   # mounts the ConfigMap at /usr/share/nginx/html
    │                     # with a checksum annotation that rotates
    │                     # when ConfigMap content changes (triggers
    │                     # Pod rollout on `helm upgrade` even when
    │                     # only values changed)
    └── service.yaml      # ClusterIP, port-forward target
```

## What it tests

Eight §9 claims:

1. helm 4.x can lint a chart with `apiVersion: v2` cleanly
2. `helm template` renders all three resource kinds (ConfigMap,
   Deployment, Service) from the templates
3. `helm install --set key=value` overrides default values
4. The installed Deployment serves the **install-time** title in
   its HTML response (templating worked end-to-end)
5. `helm upgrade --set ...` updates the release to revision 2
6. The `checksum/configmap` annotation in the Deployment template
   triggers a Pod rollout when only the ConfigMap changes
   (otherwise upgrading only `content.*` values wouldn't roll the
   Pods — the Deployment spec itself would be unchanged)
7. After upgrade rollout, the served HTML contains the
   **upgrade-time** title — old content gone
8. `helm uninstall` removes Deployment + Service + ConfigMap with
   no leftovers

## Running

```bash
./demo.sh
```

Expected duration: 30-60 seconds. Most of it is the rollout-after-
upgrade phase.

If `nginx-custom:v1` isn't cached, add 2-4 minutes for the first
build (auto-built from §6's Containerfile).

## What you should see

`==> step` lines for each phase, ending in:

```
==> SUCCESS — helm install + upgrade + history + uninstall all green
```

Notable mid-flow checkpoints:

```
==> verifying installed title appears in served HTML
✓ served HTML contains 'First install via helm'

==> verifying upgraded title appears in served HTML
✓ served HTML contains 'Upgraded title via helm'

==> running 'helm history nginx-helm'
    REVISION  UPDATED  STATUS      CHART             ...  DESCRIPTION
    1                  superseded  nginx-helm-0.1.0  ...  Install complete
    2                  deployed    nginx-helm-0.1.0  ...  Upgrade complete

==> verifying no chart resources remain
✓ no leftover resources — helm uninstall cleaned everything
```

## Cluster scope

Uses the **default minikube cluster** with the release name
`nginx-helm`. Chart-generated resources are named `nginx-helm`
(via the `fullname` helper) and labeled
`app.kubernetes.io/instance=nginx-helm`, distinct from §6/§7/§8.

The cleanup label selector relies on the
`app.kubernetes.io/instance=nginx-helm` label that the chart
applies to all resources — that's how the post-uninstall
leftover check works.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that:

1. Kills the background `kubectl port-forward` process
2. Runs `helm uninstall nginx-helm` (idempotent — succeeds even
   if no release exists)

`nginx-custom:v1` stays in the cluster's image cache.

Manual cleanup if needed:

```bash
helm uninstall nginx-helm
# verify:
kubectl get all,configmap -l app.kubernetes.io/instance=nginx-helm
# should return nothing
```

## When this fails

1. **`helm lint` fails** — likely a Chart.yaml field missing or a
   template syntax error. The lint output points at the offending
   file and line
2. **`helm template` fails** — usually a `{{ ... }}` syntax error
   or a value reference that doesn't resolve. The template output
   is full Go-template error messages with file:line markers
3. **`helm install` succeeds but Deployment never goes Available**
   — typically image not cached (the pre-flight should have
   built it; check `minikube image ls`)
4. **First curl returns wrong content** — values weren't
   templated as expected. `helm get values nginx-helm` shows
   what helm thought your values were
5. **Upgrade rollout doesn't happen / served HTML still shows
   old title** — likely the `checksum/configmap` annotation isn't
   working. `kubectl get deployment nginx-helm -o yaml | grep
   checksum` to confirm the annotation is present and changing
   across revisions
6. **`helm uninstall` leaves resources behind** — check the chart
   for any resource that doesn't have the standard labels (every
   resource the chart creates should include the
   `nginx-helm.labels` block from `_helpers.tpl`)

For any of these, paste the failing output back.
