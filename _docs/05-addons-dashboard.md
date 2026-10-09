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

## Addons used in this tutorial

Enable these on your default cluster. Later sections assume
`metrics-server` and `dashboard` are running; `ingress` is optional:

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
kubectl --context minikube top nodes
kubectl --context minikube top pods -A
```

If `kubectl top` errors with "metrics not available yet", give
metrics-server another 30-60 seconds — it needs to collect samples
before it can serve them.

### `ingress`

Installs the NGINX Ingress controller in namespace `ingress-nginx`.
This tutorial does **not** use it to reach workloads: every
host-facing Service is a NodePort published to `127.0.0.1` (§3, §7).
Ingress is what you reach for beyond that when you want host-based
or path-based routing rather than per-service NodePort exposure,
and §11 Istio replaces it with its own Gateway resources. Enable
it to see how it works; nothing later depends on it.

Verify:

```bash
kubectl --context minikube get pods -n ingress-nginx
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
| `volcano`                   | Batch scheduling for ML/HPC workloads                                                      |
| `nvidia-gpu-device-plugin`  | GPU support (NVIDIA only)                                                      |
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
environment variables). For the addons used in this tutorial
the defaults are fine — no `configure` step needed.

## The Kubernetes Dashboard

The dashboard is enabled like any other addon (done above):

```bash
minikube addons enable dashboard
```

The addon's Service is a `ClusterIP`, which your host can't reach,
and this tutorial doesn't use proxies or tunnels. Instead you add a
small **companion** NodePort Service that selects the same pods.
The profile already publishes nodePort 30900 on `127.0.0.1:18090`
(§3), so the Service only has to claim it:

```bash
kubectl --context minikube apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: dashboard-host
  namespace: kubernetes-dashboard
spec:
  type: NodePort
  selector:
    k8s-app: kubernetes-dashboard
  ports:
    - name: http
      port: 80
      targetPort: 9090
      nodePort: 30900
YAML
```

Open the dashboard at <http://127.0.0.1:18090/>. You'll see node
and pod status, can browse namespaces, edit manifests inline, view
logs, exec into pods.

Notes:

- **Loopback only.** The port is published on `127.0.0.1`, so only
  this machine reaches the dashboard. The dashboard addon runs
  without a login, which is why it must not be exposed on a LAN
  address
- **The companion survives addon changes.** The Service is owned
  by you, not by the addon. minikube re-applies the addon's own
  manifests on `minikube start`, and that doesn't touch
  `dashboard-host`
- **Nothing to keep running.** There is no proxy process; the
  mapping lives in the Docker container's port bindings
- **No answer on 18090?** Run `docker port minikube 30900/tcp`. If
  it prints nothing, the profile was created without the mapping
  and has to be recreated (§3)

To remove the companion later:

```bash
kubectl --context minikube delete service dashboard-host -n kubernetes-dashboard
```

### Dashboard or kubectl?

The dashboard is genuinely useful for exploring an unfamiliar
cluster — like joining a project that already has Kubernetes
running. For day-to-day work in this tutorial, `kubectl` is faster
and more reproducible, and it is what the tutorial uses throughout.
The dashboard comes up occasionally; nothing relies on it.

## Verifying the three addons are running

After enabling metrics-server, ingress, and dashboard, two checks:

```bash
minikube addons list | grep -E '(STATUS|metrics-server|ingress |dashboard)'
```

Should show all three as `enabled` (the regex avoids matching
`ingress-dns` which is a separate addon).

For a deeper check that the addons' workloads are actually running:

```bash
kubectl --context minikube get pods -A | grep -E '(metrics-server|ingress-nginx|kubernetes-dashboard)'
```

Each should show a `Running` pod. metrics-server may take an extra
minute or two to be ready since it has to collect initial samples.

[On to §6: Deploying with kubectl →]({{ "/docs/06-deploying-with-kubectl/" | relative_url }})
