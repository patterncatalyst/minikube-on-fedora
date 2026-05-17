---
title: Custom resources, profiles, multi-node
order: 4
description: Override CPU/memory per cluster, run multiple clusters side by side with profiles, and run single clusters with multiple nodes.
duration: 15 minutes
---

After §3 you have a single minikube cluster running on its default
profile. This section covers three related capabilities: overriding
resources for a specific cluster beyond the §3 defaults, running
multiple clusters side by side via **profiles**, and running a single
cluster with multiple **nodes** via `--nodes`.

None of these need a separate demo — they're CLI patterns you'll use
when the work demands them. By the end you'll know which lever to
reach for: a bigger cluster, a parallel cluster, or a multi-node
cluster.

## Custom CPU and memory per cluster

§3's defaults block set `cpus 6` and `memory 16384` via
`minikube config set`. That handled the "all my clusters use these
values" case. Sometimes you want a one-off cluster with different
sizing — a smaller cluster to test a low-resource deployment, or a
bigger one for Istio + KEDA stress. Override with flags on `minikube
start`:

```bash
minikube start -p small \
    --cpus=2 --memory=2048 \
    --driver=podman --rootless --container-runtime=containerd
```

The flags override the defaults for *this* cluster only. Your
default-profile cluster (still 6 CPU / 16 GB) is untouched.

For an existing cluster, a resize requires stop/reconfigure/start:

```bash
minikube stop -p small
minikube -p small config set memory 4096
minikube start -p small
```

Note the profile-scoped syntax: `minikube -p PROFILE config set KEY
VALUE` writes to that profile's config rather than the global
defaults. Without `-p PROFILE`, `config set` writes to defaults
(which apply to all profiles that don't override).

> A caveat about drivers that require recreate: VirtualBox and some
> KVM configurations need `minikube delete -p PROFILE` before a
> CPU/memory increase takes effect, because they baked the resource
> limits into the VM definition. The podman driver re-reads the
> values on start, so stop/start is enough.

## Profiles

A **profile** is a named minikube cluster. Each profile has its own
state: its own podman container(s), its own kubeconfig context, its
own configuration. Profiles let you have multiple clusters running
side by side or stored as named experiments.

You've already used profiles without thinking about it. `minikube
start` without `-p` operates on the profile named `minikube` (the
default). `examples/03-driver-check/demo.sh` used `-p driver-check`.

### Creating profiles

```bash
minikube start -p sandbox-1.34 --kubernetes-version=v1.34.0
minikube start -p sandbox-1.35 --kubernetes-version=v1.35.1
```

These create two independent clusters running different Kubernetes
minor versions. The `--driver`, `--rootless`, and
`--container-runtime` flags inherit from your defaults block, so
they don't need to be repeated.

### Listing profiles

```bash
minikube profile list
```

You'll see all profiles with their driver, in-cluster runtime, IP,
status, and Kubernetes version. Useful for quickly seeing what's
running.

### Switching the active profile

The "active" profile is what `minikube` commands target when you
don't pass `-p`. To switch:

```bash
minikube profile sandbox-1.34
```

After this, `minikube status` reports on `sandbox-1.34`, and
`kubectl`'s active context follows along. To check which profile is
currently active:

```bash
minikube profile
```

This prints the active profile name and exits.

### Profile-scoped commands

Anything you'd run against the default cluster works against a
specific profile by adding `-p NAME`:

```bash
minikube -p sandbox-1.35 status
minikube -p sandbox-1.35 stop
minikube -p sandbox-1.35 addons enable metrics-server
```

This is often clearer than switching the active profile and back —
you stay anchored at your default cluster for the rest of your
work.

### Deleting profiles

```bash
minikube delete -p sandbox-1.34
```

Removes the cluster, its podman container(s), its volumes, its
network, and its kubeconfig context. Idempotent — re-running is safe.

### When to reach for profiles

- **Run multiple Kubernetes versions side by side.** Compatibility
  testing, or trying an upgrade against a copy of your real cluster
- **Isolate experiments.** A `scratch` profile for trying something
  potentially destructive
- **Different resource shapes for different work.** A small profile
  for hello-world testing, a bigger one for Istio + KEDA
- **Multiple instances of the same app under different config.** Two
  Helm rollouts of the same chart with conflicting values, side by
  side rather than uninstall-reinstall

## Multi-node clusters

By default `minikube start` creates a **single-node** cluster — one
node running both the control plane and your workloads. For testing
things that exercise multi-node behavior (DaemonSets across nodes,
scheduling with `nodeAffinity`, `PodDisruptionBudget`, taints and
tolerations, multi-AZ-shaped tests), use `--nodes`:

```bash
minikube start -p multi --nodes=3
```

This creates one control-plane node and two worker nodes, each as
its own podman container on your host. Confirm:

```bash
minikube node list -p multi
kubectl --context multi get nodes
```

You should see three nodes; one will be the control plane and two
will show `<none>` for role (worker nodes).

### Adding and removing nodes after start

```bash
minikube node add -p multi               # adds a worker
minikube node delete multi-m04 -p multi  # remove (use names from `node list`)
```

### High availability (multiple control planes)

For testing how an app handles a control plane that itself moves:

```bash
minikube start -p ha --ha --nodes=3
```

This starts three control-plane nodes with stacked etcd. Resource
cost is meaningfully higher than `--nodes=3` without `--ha`; the
control plane components run on every CP node.

### When you don't need multi-node

Most of the rest of this tutorial works on single-node. §6 onwards
deploys workloads — pods, services, persistent volumes, ingress, a
helm chart, an Istio mesh. The Kubernetes scheduler doesn't care
about node count for these examples; a single-node cluster runs
them identically to a three-node one. Reach for multi-node when the
thing you're testing is *specifically* about multi-node behavior.

## A recommended profile layout

A reasonable starting layout for working through this tutorial plus
side projects:

| Profile name | Resources       | Purpose                                            |
|--------------|-----------------|----------------------------------------------------|
| `minikube`   | 6 CPU / 16 GB   | The default; everyday work                          |
| `scratch`    | 2 CPU / 4 GB    | Disposable sandbox for trying something potentially destructive |
| `mesh`       | 6 CPU / 16 GB   | §11 Istio work — kept warm with charts loaded       |
| `keda-test`  | 4 CPU / 8 GB    | §12 KEDA testing                                    |

`mesh` and `keda-test` are optional — only create them when you
reach §11 and §12. `scratch` is worth creating now; you'll be
glad of it when an experiment goes sideways and you'd rather not
trash your default cluster.

[On to §5: Addons and the dashboard →]({{ "/docs/05-addons-dashboard/" | relative_url }})
