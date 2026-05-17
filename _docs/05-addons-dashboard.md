---
title: Addons and the dashboard
order: 5
description: Enable optional cluster features via minikube addons; the metrics-server, ingress, and dashboard addons used by later sections.
duration: 10 minutes
---

minikube ships a set of optional cluster features as **addons** —
self-contained chunks of Kubernetes manifests you can enable or
disable with a single CLI command. This section covers the addons
this tutorial uses (and a handful you'll commonly want even outside
it), plus the Kubernetes Dashboard which is itself an addon.

## Listing addons

```bash
minikube addons list
```

You'll see a table of all available addons with their enable/disable
status. By default only two are enabled:

- `default-storageclass` — provides a `StorageClass` named `standard`
  marked as default, so `PersistentVolumeClaims` without an explicit
  class get bound by `storage-provisioner`
- `storage-provisioner` — the controller that actually creates
  hostPath PVs when PVCs are created

Both showed up as `Running` pods in the §3 driver-check output. The
default-disabled list is where everything else lives.

## Enabling and disabling

```bash
minikube addons enable <name>
minikube addons disable <name>
```

Both are idempotent. The addon's manifests get applied (or removed)
against the current cluster. Most addons take effect within a few
seconds; ones requiring container image pulls take a minute or two
the first time.

## Addons we'll use in this tutorial

Enable these on your default cluster — later sections assume
they're running:

```bash
minikube addons enable metrics-server
minikube addons enable ingress
minikube addons enable dashboard
```

### `metrics-server`

Provides the Kubernetes Metrics API — what `kubectl top nodes` and
`kubectl top pods` use. Without it those commands fail with "Metrics
API not available". §12's KEDA needs metrics-server for any
CPU-based scaling target.

Verify a minute after enabling:

```bash
kubectl top nodes
kubectl top pods -A
```

If `kubectl top` errors with "metrics not available yet", give
metrics-server another 30-60 seconds — it needs to collect samples
before it can serve them.

### `ingress`

Installs the NGINX Ingress controller in namespace `ingress-nginx`.
§7 covers NodePort access; ingress is what you reach for beyond
that when you want host-based or path-based routing rather than
per-service NodePort exposure. §11 Istio replaces ingress with its
own Gateway resources, but in §7-§10 the NGINX ingress is enough.

Verify:

```bash
kubectl get pods -n ingress-nginx
```

You should see an `ingress-nginx-controller-*` pod in `Running`
state and an `ingress-nginx-admission-create-*` job `Completed`.

### `dashboard`

The Kubernetes Dashboard — a web UI for browsing cluster resources.
Covered in its own subsection below since it has its own access
pattern.

## Other addons worth knowing

Not needed for this tutorial but worth knowing they exist:

| Addon                       | What it gives you                                                                          |
|-----------------------------|--------------------------------------------------------------------------------------------|
| `registry`                  | An in-cluster image registry — push images here from your host, nodes pull them locally   |
| `volcano`                   | Batch scheduling for ML/HPC workloads                                                      |
| `nvidia-gpu-device-plugin`  | GPU support (Linux only, NVIDIA only)                                                      |
| `cloud-spanner`             | Cloud Spanner emulator                                                                     |
| `csi-hostpath-driver`       | A CSI-based version of the default storage class — more flexible than the default hostPath provisioner |
| `inaccel`                   | FPGA accelerator support                                                                   |
| `headlamp`                  | An alternative dashboard, less venerable than the default but actively maintained          |
| `gvisor`                    | Run pods inside gVisor sandboxes — kernel-level isolation per pod                          |

Browse the full list with `minikube addons list` — the maintainer
column tells you who owns each chunk of YAML so you know whether
to expect kubernetes upstream support or community responsiveness.

## Configuring addons

Some addons have configurable parameters. The `registry-creds`
addon, for example, needs registry credentials passed in:

```bash
minikube addons configure registry-creds
```

This prompts for credentials interactively (or accepts them via
environment variables). For the addons we use in this tutorial
the defaults are fine — no `configure` step needed.

## The Kubernetes Dashboard

The dashboard is enabled like any other addon (we did so above):

```bash
minikube addons enable dashboard
```

But access is via a dedicated subcommand:

```bash
minikube dashboard
```

This opens your default browser at the dashboard URL, behind a
`kubectl proxy` that handles auth automatically. You'll see node
and pod status, can browse namespaces, edit manifests inline, view
logs, exec into pods.

For headless setups — working over SSH, on a remote host — get
just the URL and don't open a browser:

```bash
minikube dashboard --url
```

You can then port-forward or tunnel that URL however you need.

### Dashboard or kubectl?

The dashboard is genuinely useful for exploring an unfamiliar
cluster — like joining a project that already has Kubernetes
running. For day-to-day work in this tutorial, `kubectl` is faster
and more reproducible (and what we'll be doing throughout). We'll
mention the dashboard occasionally; we won't rely on it.

## Verifying the three addons are running

After enabling metrics-server, ingress, and dashboard, two checks:

```bash
minikube addons list | grep -E '(STATUS|metrics-server|ingress |dashboard)'
```

Should show all three as `enabled` (the regex avoids matching
`ingress-dns` which is a separate addon).

For a deeper check that the addons' workloads are actually running:

```bash
kubectl get pods -A | grep -E '(metrics-server|ingress-nginx|kubernetes-dashboard)'
```

Each should show a `Running` pod. metrics-server may take an extra
minute or two to be ready since it has to collect initial samples.

[On to §6: Deploying with kubectl →]({{ "/docs/06-deploying-with-kubectl/" | relative_url }})
