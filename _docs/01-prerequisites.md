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
beyond Docker Engine if you don't already have it — the install of
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
(the node image, container layers, persistent volume data) lives under `~/.minikube/` and Docker's data root
(`/var/lib/docker`), and grows over time as you pull
images and create resources.

## Operating system

This tutorial is written and tested against **Fedora 44**, on a
host or in a Fedora VM. **RHEL 9+**, on a host or in a RHEL VM, uses
the same commands; the one difference is the Docker repo URL below.
Package names occasionally differ, so verify with `dnf info
<package>` before installing.

Confirm your release:

```bash
cat /etc/fedora-release      # Fedora
cat /etc/redhat-release      # RHEL
```

On Fedora you should see `Fedora release 44 (Forty)` or newer.
Earlier Fedora versions almost certainly still work, but you may
encounter package naming differences in §2.

## Container engine

minikube isn't a container engine itself. It uses an existing
engine on your host as its **driver**. This tutorial uses the
**docker driver** with **Docker Engine** (`docker-ce`) and runs
Kubernetes with **containerd** and **runc** inside the node. Docker
Engine only; no desktop app is required or used. Why the tutorial
moved off rootless Podman is in [LESSONS-LEARNED, Part
4](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/onboarding/LESSONS-LEARNED.md).

### Docker Engine

Check whether you already have it:

```bash
docker --version && docker context show
```

If `docker` isn't installed, add Docker's repo and install the
engine packages. On Fedora:

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
```

On RHEL, use Docker's RHEL repo instead:

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/rhel/docker-ce.repo
```

Then install and start the engine:

```bash
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Log out and back in so the new `docker` group applies to your
shell, then make sure the CLI uses the local engine:

```bash
docker context use default
```

Verified with `docker-ce 29.8.2-1.fc44`, `containerd.io 2.3.6`, and
`docker-buildx-plugin 0.37.1` on the maintainer's Fedora 44 host.

> **Install only Docker's packages.** Do not install Fedora's
> `moby-engine` or `podman-docker` alongside `docker-ce`. They
> provide a second `docker` CLI and daemon socket, and the demos'
> `require_docker_engine` check fails if `podman-docker` is present.
>
> **`docker` group membership is root-equivalent.** Anyone in the
> group can start a privileged container and read or write any file
> on the host. Add only accounts you would give `sudo`.

Two host effects to know about:

- **Firewall rules.** `dockerd` manages iptables itself and may set
  the `FORWARD` chain policy to `DROP`. That can break traffic for
  libvirt VMs on the same host. If your VMs lose connectivity after
  Docker starts, check `sudo iptables -S FORWARD` and add an
  accept rule for the libvirt bridge. This is host-specific;
  verify on yours
- **SELinux.** Docker Engine's SELinux support is off by default.
  If you are unsure how your daemon is configured, check:

{% raw %}
```bash
docker info --format '{{.SecurityOptions}}'
```
{% endraw %}

  `name=selinux` in the output means the daemon enforces SELinux
  labels on containers. This tutorial's manifests need no host
  labelling either way

### What this tutorial does NOT require

- **No KVM or qemu.** The docker driver runs
  Kubernetes nodes as containers on your host, not as VMs. No
  virtualization extensions needed
- **No Red Hat subscription registration.** All container images
  pulled by this tutorial's examples come from public registries
  (`registry.access.redhat.com/ubi10/...`, `quay.io/...`,
  `ghcr.io/...`) and do not require `subscription-manager`
- **No host volume mounts.** Where this tutorial mounts data into
  pods (e.g., §8 persistent volumes), the manifests use `hostPath`
  paths that live *inside* the minikube container, not on your host
  filesystem

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

## Kernel limits for multi-cluster (needed for §11)

The §3 minikube profile is a containerized Linux that runs systemd
as PID 1. Systemd uses **inotify** watches to manage cgroups — and
the Fedora 44 defaults for `fs.inotify.max_user_instances` and
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
docker --version && docker context show && \
docker run --rm registry.access.redhat.com/ubi10/ubi-minimal:10.2-1791444377 echo OK
```

The final `OK` printed from inside the container confirms that
Docker Engine works for your user without `sudo`, can pull from
Red Hat's public registry, and can run UBI 10 images — which is the
floor everything in this tutorial builds on. On RHEL, replace the
first `cat` with `cat /etc/redhat-release`.

The repo also ships an audit that reports all of this at once,
including the Docker Engine, group, and context checks:

```bash
./scripts/audit-fedora-prereqs.sh
```

If your hardware is short of the comfortable target and you only
want to go through §1–§10, that's fine — just plan to skip §11
and §12 (or revisit them once you have more resources to spare).

Ready? [On to §2: Installation →]({{ "/docs/02-installation/" | relative_url }})
