---
title: Alternatives to minikube
order: 13
description: A brief tour of kind, k3s, microk8s, and MicroShift. When each is the right choice — and which ones are genuinely awkward to run on Fedora.
duration: 5 minutes
---

minikube isn't the only way to run Kubernetes locally. It was
the right pick for this tutorial — it has the best
multi-profile story, the broadest addon coverage, and rootless
Podman support on Fedora 44 works out of the box — but four
alternatives are worth knowing about. Each makes different
trade-offs.

This section is short and opinionated. The honest framing
matters more than a comparison matrix that pretends everything
is roughly equivalent: from a Fedora user's perspective some
of these are first-class options and some have meaningful
friction.

## Quick decision framework

- **Daily development on Fedora, you want the most features
  out of the box** → minikube (you already have this)
- **CI pipelines, ephemeral clusters, fastest start/stop** → kind
- **Single-host edge or IoT, you want the cluster running
  directly on Linux without a VM layer** → k3s
- **You're working with Red Hat OpenShift and want local
  parity** → MicroShift (via CRC on a Fedora laptop)
- **You're on Ubuntu and want the most opinionated setup** →
  microk8s. (On Fedora, see the honest note below — this
  one's awkward enough to be worth flagging up front)

## kind — Kubernetes IN Docker

[kind](https://kind.sigs.k8s.io/) runs each Kubernetes "node"
as a container (Docker or Podman). The control plane and
workers are sibling containers on your host, talking to each
other over a Docker/Podman network. No VM, no virtualization
overhead, and bringing up a multi-node cluster takes about 30
seconds.

```bash
go install sigs.k8s.io/kind@v0.31.0
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster
```

The kind v0.31.0 release (December 2025) defaults to
Kubernetes 1.35.0, supports Podman auto-detection, and has
first-class multi-node clusters via a small YAML config file.
It's the tool most CI pipelines reach for because the
start-test-tear-down cycle is so fast.

**Where it's strong:** CI, ephemeral testing, "let me try
this manifest against three different K8s versions in
parallel" workflows. Designed originally for testing
Kubernetes itself, which shows in the polish.

**Where it's weaker:** loading images is awkward — `kind load
docker-image myapp:v1` is required to get a locally-built
image into the cluster, since kind's nodes run their own
containerd that isn't your host's. Persistent state across
restarts works but isn't the design center. The default
single-node story is fine; the multi-node story requires
config files.

**Fedora compatibility:** good. Works rootful, podman support
is mature, no SELinux gotchas in practice.

## k3s — lightweight upstream Kubernetes

[k3s](https://k3s.io/) is Rancher Labs' (now SUSE Rancher's)
take on a smaller, faster Kubernetes. It's CNCF-sandbox and
ships as a single ~50 MB binary. The latest release as of mid-
2026 is v1.36.1+k3s1, which tracks upstream Kubernetes 1.36.1
closely.

```bash
curl -sfL https://get.k3s.io | sh -
sudo systemctl status k3s
```

The single-command install brings up a complete cluster as a
systemd service on the host — no VM, no containers wrapping
the control plane, just `kubelet` and `containerd` and the
API server running natively. The default datastore is SQLite,
which means HA requires switching to embedded etcd. k3s ships
with sensible defaults: Traefik for ingress, Klipper (a
service load balancer), local-path-provisioner for storage.

**Where it's strong:** edge devices (Raspberry Pi, ARM boxes,
small VPSes), IoT scenarios, anything where you want
Kubernetes running directly on Linux with minimum overhead.
Also good for single-host production workloads where a VM
layer is unwelcome.

**Where it's weaker:** the bundled components (Traefik,
Klipper) want to be different from the production-K8s
defaults you might be used to. Multi-node setup involves
joining nodes via a shared token, which is straightforward but
not as instant as minikube's `--nodes=N`.

**Fedora compatibility:** good, with a small caveat. You'll
need the `container-selinux` package and the SELinux policy
RPM that matches your k3s version. Firewalld needs a few
ports opened (typically 6443/tcp for the API server,
10250/tcp for the kubelet, and pod-network ports). All
documented in [the k3s install docs](https://docs.k3s.io/installation/requirements).

## microk8s — Canonical's snap-based Kubernetes

[microk8s](https://microk8s.io/) is Canonical's take. It
installs as a snap on Ubuntu, comes with a rich addon system
(`microk8s enable dns`, `microk8s enable ingress`, etc.), and
has strict-confinement options for security-sensitive
environments. Current stable channel is 1.33/stable.

```bash
# On Ubuntu — works great
sudo snap install microk8s --classic --channel=1.33/stable
```

On Ubuntu, microk8s is genuinely well-engineered: the addons
work, the upgrade story is smooth, the documentation is
thorough.

**Fedora compatibility:** **rough.** snap on Fedora has had
ongoing issues — squashfs mount errors on classic snaps,
AppArmor not being available in stock Fedora kernels
(microk8s relies on it for confinement), and a general
ecosystem mismatch between Canonical's snap tooling and the
RPM/Flatpak world Fedora lives in. A practitioner blog post
from late 2024 working through a microk8s-on-Fedora install
[concluded](https://blog.hardill.me.uk/2024/12/06/microk8s-on-fedora-41/)
that the only realistic recommendation was *"to not try and
run microk8s on Fedora at this time."* The situation may
improve, but if you're on Fedora and considering microk8s,
the friction is real and you'll likely fight it. minikube,
kind, or k3s give you everything microk8s would on a Fedora
host without the snap ecosystem mismatch.

This honest assessment isn't a knock on microk8s as a project
— on Ubuntu, where Canonical maintains the full stack, it's
excellent. It's just not the right fit for this audience.

## MicroShift — Red Hat's edge OpenShift

[MicroShift](https://microshift.io/) is Red Hat's
miniaturized OpenShift, designed for edge computing and
single-node deployments. It strips OpenShift down to its
essentials (CRI-O, etcd, kubelet, OpenShift's HAProxy
ingress) and runs as a single systemd service. Minimum
requirements are 2 CPU / 2 GB / 10 GB — genuinely lean.

The interesting property of MicroShift is **API compatibility
with full OpenShift**. Applications written for MicroShift run
unchanged on OpenShift. If you're working in a Red Hat
ecosystem and need local development that mirrors production
OpenShift, MicroShift is the answer.

**Fedora compatibility:** **complicated.** MicroShift's RPM
packages are built for RHEL 9 and RHEL 10, not Fedora. The
Red Hat Developer site
[explicitly recommends against](https://developers.redhat.com/articles/2025/02/20/why-developers-should-use-microshift)
trying to `dnf install microshift` on Fedora — the
interdependencies (Open Virtual Networking, specific CRI-O
versions, etc.) are tightly coupled to RHEL package
versions. The supported path for Fedora users is **CRC
(CodeReady Containers)**, which manages a RHEL VM running
MicroShift for you:

```bash
# Download CRC from https://developers.redhat.com/products/openshift-local/overview
crc setup
crc start --preset microshift
```

This is functionally similar to what minikube does — a VM
managed for you with a Kubernetes-shaped thing running
inside — except the VM runs RHEL and the Kubernetes is
OpenShift-flavored.

**When to pick it:** you specifically need OpenShift API
compatibility for development. If you don't, the overhead
isn't justified.

## Comparison at a glance

| Distribution | Architecture | Fedora story | Best fit |
|---|---|---|---|
| **minikube** | VM (via Podman driver) | first-class, rootless | general development, this tutorial |
| **kind**     | Containers as nodes | first-class | CI pipelines, ephemeral clusters |
| **k3s**      | Host systemd service | good, needs SELinux RPM | single-host edge, IoT, ARM |
| **microk8s** | Snap | rough (snapd+AppArmor mismatch) | Ubuntu, not Fedora |
| **MicroShift** | RHEL systemd service | requires CRC (RHEL VM) | OpenShift parity |

## Recommendation

If you're a Fedora user who's read this far in the tutorial,
**minikube remains the right choice for the things you've
just learned**. Switch to kind if you're building CI; switch
to k3s if you're deploying to an edge device; reach for CRC
if you specifically need OpenShift compatibility. There's no
strong reason to switch from minikube on a development
laptop unless one of those specific needs applies.

The underlying Kubernetes is the same in every case. The
manifests, kubectl commands, helm charts, and operator
patterns you learned in §3-§12 work unchanged across all
five distributions. That's the whole point of Kubernetes
being a standard interface: the choice of distribution is a
deployment decision, not an application-design decision.

[On to §14: FAQ →]({{ "/docs/14-faq/" | relative_url }})
