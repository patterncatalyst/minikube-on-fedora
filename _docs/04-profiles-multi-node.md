---
title: Custom resources, profiles, multi-node
order: 4
description: Override CPU/memory per cluster, run multiple clusters side by side with profiles, and run single clusters with multiple nodes.
duration: 15 minutes
---

After §3 you have a single minikube cluster running on its default
profile. This section covers three related capabilities: overriding
resources for a specific cluster beyond the §3 sizing, running
multiple clusters side by side via **profiles**, and running a single
cluster with multiple **nodes** via `--nodes`.

None of these need a separate demo — they're CLI patterns you'll use
when the work demands them. By the end you'll know which lever to
reach for: a bigger cluster, a parallel cluster, or a multi-node
cluster.

## Custom CPU and memory per cluster

§3's start command passed `--cpus=6 --memory=16384` on the command
line, so there is no shared default to inherit: every profile
states its own sizing and its own published ports. Sometimes you
want a one-off cluster with different sizing — a smaller cluster to
test a low-resource deployment, or a bigger one for Istio + KEDA
stress:

```bash
minikube start -p small \
    --driver=docker --container-runtime=containerd \
    --kubernetes-version=v1.36.5 \
    --cpus=2 --memory=2048
```

This profile publishes no ports, so it suits experiments you reach
with `kubectl` only. Add a `--ports` list for anything that needs a
host address (see "Profiles and published ports" below).

Resizing the CPU or memory of an existing docker-driver profile
isn't supported. The documented approach is to delete the profile
and recreate it with the new values, repeating the same `--ports`
list:

```bash
minikube delete -p small
minikube start -p small \
    --driver=docker --container-runtime=containerd \
    --kubernetes-version=v1.36.5 \
    --cpus=2 --memory=4096
```

Deleting removes everything in the cluster, so redeploy your
workloads afterwards.

## Profiles

A **profile** is a named minikube cluster. Each profile has its own
state: its own Docker container(s), its own kubeconfig context, its
own configuration. Profiles let you have multiple clusters running
side by side or stored as named experiments.

You've already used profiles without thinking about it. `minikube
start` without `-p` operates on the profile named `minikube` (the
default). `examples/03-driver-check/demo.sh` used `-p driver-check`.

The profiles this repo uses by name:

| Profile        | Used by                                            |
|----------------|----------------------------------------------------|
| `minikube`     | §3 and §5–§10, §12 (default cluster)               |
| `driver-check` | §3 smoke test (`examples/03-driver-check`)         |
| `istio`        | §11 Istio                                          |
| `mof-capstone` | §17 capstone                                       |

### Creating profiles

```bash
minikube start -p sandbox-1.35 --driver=docker --container-runtime=containerd \
    --kubernetes-version=v1.35.9
minikube start -p sandbox-1.36 --driver=docker --container-runtime=containerd \
    --kubernetes-version=v1.36.5
```

These create two independent clusters running different Kubernetes
minor versions. Neither passes `--ports`, so neither publishes a
host port.

### Profiles and published ports

A host port can be bound by only one running profile. If a second
profile asks for `127.0.0.1:18080` while `minikube` is running,
the start fails because the port is already in use. Either stop the
first profile, or give the second profile different host ports.
That is why the example profiles use distinct maps: `minikube`
publishes 18080, 18081, and 18090; `driver-check` publishes 18079;
`istio` publishes 8080, 20001, 3000, 9090, and 16686. Stopping a
profile releases its host ports; starting it takes them back.

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
minikube profile sandbox-1.35
```

After this, `minikube status` reports on `sandbox-1.35`, and
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
minikube -p sandbox-1.36 status
minikube -p sandbox-1.36 stop
minikube -p sandbox-1.36 addons enable metrics-server
```

This is often clearer than switching the active profile and back —
you stay anchored at your default cluster for the rest of your
work.

### Deleting profiles

```bash
minikube delete -p sandbox-1.35
```

Removes the cluster, its Docker container(s), its volumes, its
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
minikube start -p multi --nodes=3 \
    --driver=docker --container-runtime=containerd --kubernetes-version=v1.36.5
```

This creates one control-plane node and two worker nodes, each as
its own Docker container on your host. Confirm:

```bash
minikube node list -p multi
kubectl --context multi get nodes
```

You should see three nodes; one will be the control plane and two
will show no role (worker nodes).

### Adding and removing nodes after start

```bash
minikube node add -p multi               # adds a worker
minikube node delete multi-m04 -p multi  # remove (use names from `node list`)
```

### High availability (multiple control planes)

For testing how an app handles a control plane that itself moves:

```bash
minikube start -p ha --ha --nodes=3 \
    --driver=docker --container-runtime=containerd --kubernetes-version=v1.36.5
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

| Profile name   | Resources       | Purpose                                            |
|----------------|-----------------|----------------------------------------------------|
| `minikube`     | 6 CPU / 16 GB   | The default; everyday work, §5–§10 and §12          |
| `istio`        | 6 CPU / 16 GB   | §11 Istio work, created by the example's setup      |
| `mof-capstone` | see §17         | The capstone; created by its setup script           |
| `scratch`      | 2 CPU / 4 GB    | Disposable sandbox, no published ports              |

Run one workshop profile at a time: each node container reserves
its full memory allocation, and the published host ports must not
overlap. Stop the others with `minikube stop -p NAME` before you
start another. `scratch` is worth creating now; you'll be glad of
it when an experiment goes sideways and you'd rather not trash
your default cluster.

[On to §5: Addons and the dashboard →]({{ "/docs/05-addons-dashboard/" | relative_url }})
