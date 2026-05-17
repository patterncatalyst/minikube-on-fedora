---
title: Starting minikube
order: 3
description: Start a minikube cluster with the podman driver, verify it's healthy, manage its lifecycle.
duration: 15 minutes
---

This section starts your first minikube cluster, walks through
the layers involved (driver, in-cluster runtime, the cluster
itself), and covers the lifecycle commands you'll use day to
day: status, pause, stop, delete, upgrade.

At the end of the section, `examples/03-driver-check/demo.sh`
runs the whole thing as a strict end-to-end script — same
commands the prose walks through, packaged as a smoke test.

This section assumes §2 is complete (minikube, kubectl, and the
supporting tools are on `PATH`).

## Set sensible defaults

Before the first `minikube start`, set defaults so you don't have
to remember flags every time. Use the values from the §1 hardware
table that match your plan — these are good "comfortable for
most of the tutorial" picks:

```bash
minikube config set cpus 6
minikube config set memory 16384
minikube config set driver podman
minikube config set rootless true
minikube config set container-runtime containerd
```

These get written to `~/.minikube/config/config.json` and are
applied by every future `minikube start` that doesn't override
them via flags. Inspect with:

```bash
minikube config view
```

If you set values you later regret, `minikube config unset <key>`
clears them, or just rerun `set` with a new value.

### Why `rootless true`

minikube's podman driver defaults to **rootful** mode — it shells
out to `sudo podman ...` to talk to the system podman. That's the
historical mainstream and works fine if you've configured passwordless
sudo for podman. Fedora 44 ships rootless podman as default
(verified in §1: `podman info` showed `rootless=true`), and the
tutorial assumes that posture. Without `rootless true`, your first
`minikube start` will fail with:

```
💣  Exiting due to PROVIDER_PODMAN_NOT_RUNNING:
    "sudo -n -k podman version ..." exit status 1: sudo: a password is required
```

The fix is what we just set: `minikube config set rootless true`
makes minikube use rootless podman directly — no `sudo`, no
passwordless-sudo plumbing needed. Functionally equivalent
clusters, the rootless one just has slightly different network
plumbing under the hood. For everything in this tutorial, it
doesn't matter which mode you use; the rootless choice avoids
the password prompt.

## Start the cluster

Now actually launch it:

```bash
minikube start
```

The first run downloads minikube's "kicbase" image (a UBI-style
base with kubeadm preinstalled) and starts a podman container
named `minikube`, then bootstraps a single-node Kubernetes 1.35.x
cluster inside it. Expect 60–90 seconds for the first run; 15–30
seconds for restarts thereafter.

You'll see output like:

```
😄  minikube v1.38.x on Fedora 44
✨  Using the podman driver based on user configuration
🌟  Selected podman driver. Recommended: ...
🔥  Creating podman container (CPUs=6, Memory=16384MB) ...
🐳  Preparing Kubernetes v1.35.x on containerd ...
🔎  Verifying Kubernetes components...
🌟  Enabled addons: storage-provisioner, default-storageclass
🏄  Done! kubectl is now configured to use "minikube" cluster
```

The last line is the important one — minikube has updated your
`~/.kube/config` so `kubectl` points at the cluster you just
started.

### What just happened

Three layers stacked up:

| Layer                      | Implementation                              | Inspect with                              |
|----------------------------|---------------------------------------------|-------------------------------------------|
| Host container engine      | Podman (rootless, on Fedora 44)             | `podman ps` (shows the `minikube` container) |
| In-cluster container runtime | containerd (set explicitly in defaults; see below) | `minikube ssh -- crictl info` |
| Kubernetes itself          | One node running kubelet + control plane    | `kubectl get nodes`                       |

Most readers don't need to think about the bottom two layers
much — they're the implementation. What matters day to day is
that `kubectl` talks to a working Kubernetes cluster.

## Verify the cluster

Three sanity checks:

```bash
minikube status
```

You should see all four components `Running`:

```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

Then via `kubectl`:

```bash
kubectl get nodes
```

```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   30s   v1.35.x
```

And the system pods that make the cluster work:

```bash
kubectl get pods -A
```

You should see pods in the `kube-system` namespace (`etcd`,
`kube-apiserver`, `kube-scheduler`, `kube-controller-manager`,
`coredns`, `storage-provisioner`, `kube-proxy`) all in
`Running` state.

If anything's not `Running`, give it 30 seconds and retry —
control-plane pods sometimes take a moment to settle after the
node first reports Ready.

## Drivers (briefly)

You set `driver=podman` in the defaults above; here's what other
options exist and when you'd reach for them.

| Driver     | When                                                                                       |
|------------|--------------------------------------------------------------------------------------------|
| **podman** | Default for this tutorial. Rootless on Fedora; no virtualization required                  |
| `docker`   | Same shape as podman, runs the kicbase under Docker Engine. Fine if Docker is your daily   |
| `kvm2`     | Runs a full VM via libvirt/KVM. Slower start, full isolation. Needs `libvirtd` configured  |
| `qemu`     | Like `kvm2` but without KVM acceleration. Mainly for ARM hosts or unusual configurations   |

To try a different driver without changing the default, pass
`--driver=<name>` to one-off `minikube start` invocations, or use
a separate profile (covered in §4):

```bash
minikube start -p docker-profile --driver=docker
```

## In-cluster container runtime

Separate from the driver above is the container runtime *inside*
the cluster — what the kubelet uses to run Pods.

The defaults block above sets `container-runtime=containerd`
explicitly. This is worth a small detour to explain, because
minikube v1.38.x's default behavior here surprises people.

### What minikube picks if you don't choose

minikube v1.38.x picks the in-cluster runtime based on the driver
and other factors, and for the podman driver it historically
defaults to **docker as the in-cluster runtime**. minikube's own
v1.38 release notes flag that this is about to change:

> Starting v1.39.0, minikube will default to "containerd"
> container runtime.

We're getting ahead of that — and avoiding a real failure mode in
the meantime.

### Why docker-as-in-cluster-runtime fails under rootless podman

Inside the kicbase container, minikube has to start `dockerd` as a
systemd service if you've selected the docker runtime. systemd
expects to manage cgroup delegation, network namespaces, and a
few other things in a way that **doesn't work cleanly inside a
rootless container** (the kicbase container is rootless because
the host's podman is rootless). The symptom is a failure during
`minikube start` along the lines of:

```
Job for docker.service failed because the control process exited
with error code.
```

`containerd` is simpler — no systemd-managed daemon to bring up,
no cgroup-delegation dance — so it initializes cleanly in
rootless mode.

### Putting the layers together

Three independent runtime choices, easy to conflate:

| Layer                            | What we use here                         | Why                                                              |
|----------------------------------|------------------------------------------|------------------------------------------------------------------|
| Host container engine            | **Podman, rootless**                     | Default on Fedora 44; no `sudo` needed                            |
| minikube driver                  | **`--driver=podman --rootless`**         | Talks to the host podman in rootless mode                         |
| In-cluster container runtime     | **`--container-runtime=containerd`**     | Initializes cleanly in rootless; matches minikube's v1.39 default |

The first two are about the host's relationship with minikube.
The third is what the kubelet uses inside the cluster to run
Pods — *independent* of the first two.

### Alternative in-cluster runtime: cri-o

If you have a specific reason to run cri-o instead (matching a
production environment that uses it, for example):

```bash
minikube start --container-runtime=cri-o
```

You'll rarely need this. Stick with containerd.

### A note on docker-as-runtime in modern Kubernetes

Docker as the in-cluster runtime has been deprecated since
Kubernetes 1.24 (2022) — that release removed the dockershim that
had bridged the kubelet's CRI interface to Docker's non-CRI
socket. minikube's `--container-runtime=docker` still works, but
it routes through `cri-dockerd`, an external shim that adds
moving parts without buying you anything for tutorial-scale work.
There's no reason to prefer docker over containerd as an
in-cluster runtime today.

## Cluster lifecycle

You'll use these constantly.

### Pause and unpause

Suspend the cluster without shutting it down:

```bash
minikube pause
minikube unpause
```

`pause` keeps your workloads loaded but freezes their processes.
Useful when you want to free CPU/memory temporarily without
losing state. Unpausing resumes everything from the same place.

### Stop and start

A heavier suspend; cleanly shuts down the cluster:

```bash
minikube stop
minikube start
```

`stop` terminates the cluster's container; `start` (without
re-creating anything) brings it back. Persistent volumes and
loaded workloads survive `stop`/`start`.

### Delete

A full reset — removes the cluster, the container, and the
persistent state:

```bash
minikube delete
```

You'll want this after experiments, or when an upgrade is in
order, or if the cluster gets wedged. Recovery is fast: just
`minikube start` again and you have a fresh cluster.

### Upgrading minikube

Since §2 installed minikube via dnf (from the upstream RPM), the
upgrade is the standard dnf path:

```bash
sudo dnf upgrade -y minikube
minikube version
```

Check for new versions without applying:

```bash
minikube update-check
```

If you've been running an older cluster across an upgrade,
`minikube delete && minikube start` is usually the cleanest way
to migrate to the new minikube version's defaults.

## A note about NodePort access

A small driver-specific gotcha to know about ahead of §7:

On Linux with `--driver=podman` (or `docker`), the cluster's
node IP is reachable from your host — `curl minikube-ip:nodeport`
works directly. On macOS or under Podman Desktop's VM, the
cluster lives inside a VM and you need `minikube tunnel` or
`minikube service <name>` to get a host-reachable URL. §7 covers
both paths.

This isn't something to act on now — it's just context for why
§7 introduces `minikube service` as the canonical NodePort
access pattern even though raw `minikube ip` is simpler.

## Smoke test: examples/03-driver-check/

The `examples/03-driver-check/demo.sh` script runs the whole
sequence above as one end-to-end test:

1. Starts a minikube cluster on a `driver-check` profile (so it
   doesn't disturb your default cluster)
2. Verifies status is fully `Running`
3. Verifies `kubectl` can list nodes and system pods
4. Tears down the profile on exit (even on failure, via `trap`)

Run it:

```bash
cd examples/03-driver-check
./demo.sh
```

Expected duration: 60–90 seconds first run, 30–45 seconds after.
You should see a `✓ SUCCESS` line at the end.

If anything fails, the script leaves the profile around for
inspection — `minikube logs -p driver-check` and
`kubectl --context driver-check get events -A --sort-by='.lastTimestamp'`
are the first two things to look at.

[On to §4: Custom resources, profiles, multi-node →]({{ "/docs/04-profiles-multi-node/" | relative_url }})
