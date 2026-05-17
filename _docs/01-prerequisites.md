---
title: Prerequisites
order: 1
description: Hardware, operating system, and tooling you need before starting.
duration: 10 minutes
---

This section describes the floor for running through this tutorial.
If your machine clears the bar here, you'll have a smooth time
through §2–§10. §11 (Istio) and §12 (KEDA) raise the bar slightly;
their requirements are called out here too so you can plan ahead.

By the end of this section you'll have run a handful of checks
that confirm everything is in place. No installation happens here
beyond Podman if you don't already have it — the install of
minikube, kubectl, helm, and the supporting toolbox lives in §2.

## Hardware floor

minikube is intentionally light, but Kubernetes itself is not. The
control plane alone burns about 1 GB of RAM doing nothing useful.
Add the addons most readers will end up enabling (dashboard,
metrics-server, ingress) and the working set climbs. Add Istio
(§11) and KEDA (§12) and it climbs further.

| Resource  | Core (§1–§10) | With Istio (§11) | With KEDA (§12) | Comfortable for all |
|-----------|---------------|------------------|-----------------|---------------------|
| CPU       | 4 cores       | 6 cores          | 6 cores         | **6+ cores**        |
| Memory    | 8 GB          | 12 GB            | 12 GB           | **16 GB**           |
| Disk free | 20 GB         | 30 GB            | 30 GB           | **50 GB**           |

The **comfortable for all** column is the recommended target if you
plan to work through the entire tutorial. minikube's defaults are
2 CPU / 2 GB which is enough to start a cluster and not much more
— §3 walks through bumping those defaults.

Check your hardware on Fedora:

```bash
nproc && free -h && df -h ~ /
```

You want at least 4 CPUs, 8 GB total memory, and 20 GB free on
whichever filesystem holds your home directory. minikube's state
(the cluster's qcow images, container layers, persistent volume
data) lives under `~/.minikube/` and grows over time as you pull
images and create resources.

## Operating system

This tutorial is written and tested against **Fedora 44** as the
primary platform. Fedora derivatives (RHEL 9+, Rocky 9+, Alma 9+)
should work with the same commands; package names occasionally
differ and you should verify with `dnf info <package>` before
installing.

Confirm your Fedora version:

```bash
cat /etc/fedora-release
```

You should see `Fedora release 44 (Forty)` or newer. Earlier
Fedora versions almost certainly still work — Fedora 43 was the
target for the prior version of this tutorial — but you may
encounter package naming differences in §2.

### macOS note

If you're on macOS, the broad shape of this tutorial applies but
specific commands won't. Treat the macOS callouts in §1 and §2 as
advisory pointers, not as a tested path. Podman Desktop on macOS
bundles its own Linux VM and minikube integrates with it
differently than on Linux hosts. Use `brew install minikube
kubectl helm` as a starting point and consult the upstream
minikube docs for driver-specific guidance on the Apple Silicon
vs. Intel split.

## Container engine

minikube is a Kubernetes-running tool, but it isn't a container
engine itself. It uses an existing engine on your host as its
**driver** — `podman`, `docker`, `kvm2`, `qemu`, or others. This
tutorial uses the **podman driver** as the primary path because
that's what's actually on a typical Fedora workstation.

### Podman

Check whether you already have Podman:

{% raw %}
```bash
podman --version && podman info --format '{{.Host.OS}} {{.Host.Arch}}'
```
{% endraw %}

You want Podman 5.x or newer; 4.x will work but lacks a couple of
quality-of-life features used in §3. If `podman` isn't installed:

```bash
sudo dnf install -y podman podman-compose
```

Podman runs **rootless by default** on Fedora — none of the
commands in this tutorial require `sudo`. Confirm rootless is
working:

```bash
podman run --rm registry.access.redhat.com/ubi9/ubi-minimal:latest id
```

You should see `uid=0(root) gid=0(root)` *inside* the container,
while the process on the host is running as your unprivileged
user. That's rootless behaving correctly. If this command fails
with a permission error, your user probably needs `subuid` and
`subgid` mappings — `cat /etc/subuid /etc/subgid` should show
your username; if not, the upstream Podman troubleshooting guide
covers the fix.

### Docker CLI as an alternative

If you have the Docker CLI installed as a familiarity safety net
or for other tools, minikube works with `--driver=docker` too.
Both drivers are covered in §3. There's no need to remove or hide
your Docker CLI to follow this tutorial:

```bash
docker --version 2>&1 || echo "(Docker CLI not installed — that's fine)"
```

### What this tutorial does NOT require

- **No KVM, qemu, or VirtualBox.** The podman driver runs
  Kubernetes nodes as containers on your host, not as VMs. No
  virtualization extensions needed
- **No SELinux changes or `:Z` volume flags.** Podman handles
  SELinux labelling correctly out of the box on Fedora. Where this
  tutorial mounts data into pods (e.g., §8 persistent volumes),
  the manifests use `hostPath` paths that live *inside* the
  minikube container, not on your host filesystem — no host
  labelling concerns
- **No Red Hat subscription registration.** All container images
  pulled by this tutorial's examples come from public registries
  (`registry.access.redhat.com/ubi9/...`, `quay.io/...`,
  `ghcr.io/...`) and do not require `subscription-manager`

## Tooling installed in §2

You don't need any of the following yet — §2 installs them in one
go:

- **`minikube`** — the local-cluster tool itself
- **`kubectl`** — the Kubernetes CLI
- **`helm`** — the chart-based package manager
- **Supporting tools**: `stern` (multi-pod log tailing),
  `kubectx` + `kubens` (context/namespace switching), `yq` (YAML
  query/transform), `krew` (kubectl plugin manager), `httpie`
  (humane HTTP client), `hey` (HTTP load generator, used heavily
  in §12)

The `gh` CLI is useful for working with this repo and following
links to the published tutorial, but isn't strictly required for
following along.

## Optional but recommended

- A code editor with a Kubernetes-aware extension. §10 covers
  CLion's Kubernetes plugin specifically and walks through the
  same patterns that apply to IntelliJ and VS Code equivalents
- A terminal you're comfortable with. §10 covers `zsh` integration
  (kubectl completion, kubectx/kubens prompt segments) and
  `warp.dev` workflows specifically
- **Podman Desktop** — useful for visualizing what's running on
  the cluster. §10 covers its Kubernetes view pointed at the
  minikube context

## Kernel limits for multi-cluster (needed for §11)

The §3 minikube profile is a containerized Linux that runs systemd
as PID 1. Systemd uses **inotify** watches to manage cgroups — and
Fedora 44's defaults for `fs.inotify.max_user_instances` and
`fs.inotify.max_user_watches` are sized for **one** such container.

§3 through §10 all run on a single minikube profile, so the defaults
are fine. §11 (Istio) spins up a **second** profile alongside the
first, and the second profile's systemd cannot allocate enough
inotify resources. The container dies during start with:

```
Failed to create control group inotify object: Too many open files
Failed to allocate manager object: Too many open files
[!!!!!!] Failed to allocate manager object.
```

This is **not** the per-process file-descriptor limit (`RLIMIT_NOFILE`,
ulimit -n). It's a separate kernel-wide sysctl. Bumping ulimits or
adding `LimitNOFILE=infinity` to a unit file will not fix it. The
fix is `sysctl`-based and persists across reboots:

```bash
sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 524288
EOF
sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf
```

Verify the change took:

```bash
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
```

Should print `= 512` and `= 524288`.

**Skip this step if you don't plan to do §11.** Default Fedora 44
settings handle §3-§10's single cluster fine. The `examples/11-istio/demo.sh`
pre-flight catches insufficient limits with the same recipe printed
inline, so even if you skip ahead, the demo tells you what to do.

The same numbers come up again in `scripts/audit-fedora-prereqs.sh`,
which now reports current inotify values and a `✓ OK for §11` or
`⚠ defaults — fine for §3-§10 but not §11` verdict alongside its
other Fedora 44 environment checks.

## Verification

If the following block produces clean output (no errors, an `OK`
from the final container), you're ready for §2:

```bash
cat /etc/fedora-release && nproc && free -h && \
podman --version && \
podman run --rm registry.access.redhat.com/ubi9/ubi-minimal:latest echo OK
```

The final `OK` printed from inside the container confirms that
Podman is rootless, can pull from Red Hat's public registry, and
can run UBI 9 images — which is the floor everything in this
tutorial builds on.

If your hardware is short of the comfortable target and you only
want to go through §1–§10, that's fine — just plan to skip §11
and §12 (or revisit them once you have more resources to spare).

Ready? [On to §2: Installation →]({{ "/docs/02-installation/" | relative_url }})
