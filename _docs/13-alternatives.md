---
title: Alternatives to minikube
order: 13
description: A brief tour of kind, k3s, and MicroShift. When each is the right choice on a Fedora or RHEL host, and why this tutorial runs minikube on Docker Engine.
duration: 5 minutes
---

minikube isn't the only way to run Kubernetes locally. It was
the right pick for this tutorial — it has the best
multi-profile story and the broadest addon coverage, and its
docker driver runs each Kubernetes node as a container on Docker
Engine — but three alternatives are worth knowing about. Each
makes different trade-offs.

This section is short and opinionated. The honest framing
matters more than a comparison matrix that pretends everything
is roughly equivalent.

## Quick decision framework

- **Daily development on Fedora or RHEL, you want the most
  features out of the box** → minikube (you already have this)
- **CI pipelines, ephemeral clusters, fastest start/stop** → kind
- **Single-host edge or IoT, you want the cluster running
  directly on Linux without a node container** → k3s
- **You're working with Red Hat OpenShift and want local
  parity** → MicroShift (directly on RHEL, or via CRC on a
  Fedora laptop)

## kind — Kubernetes IN Docker

[kind](https://kind.sigs.k8s.io/) runs each Kubernetes "node"
as a container on Docker Engine, the same engine this tutorial
uses for minikube. The control plane and workers are sibling
containers on your host, talking to each other over a Docker
network. No VM, no virtualization overhead, and bringing up a
multi-node cluster takes about 30 seconds.

```bash
go install sigs.k8s.io/kind@v0.31.0
kind create cluster
```

The kind v0.31.0 release (December 2025) defaults to
Kubernetes 1.35.0 and has
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

**Fedora and RHEL compatibility:** good. Works against Docker
Engine with no SELinux gotchas in practice.

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

**Fedora and RHEL compatibility:** good, with a small caveat. You'll
need the `container-selinux` package and the SELinux policy
RPM that matches your k3s version. Firewalld needs a few
ports opened (typically 6443/tcp for the API server,
10250/tcp for the kubelet, and pod-network ports). All
documented in [the k3s install docs](https://docs.k3s.io/installation/requirements).

## MicroShift — Red Hat's edge OpenShift

[MicroShift](https://microshift.io/) is Red Hat's
miniaturized OpenShift, designed for edge computing and
single-node deployments. It strips OpenShift down to its
essentials (a CRI runtime, etcd, kubelet, OpenShift's HAProxy
ingress) and runs as a single systemd service. Minimum
requirements are 2 CPU / 2 GB / 10 GB — genuinely lean.

The interesting property of MicroShift is **API compatibility
with full OpenShift**. Applications written for MicroShift run
unchanged on OpenShift. If you're working in a Red Hat
ecosystem and need local development that mirrors production
OpenShift, MicroShift is the answer.

**Compatibility:** MicroShift's RPM
packages are built for RHEL 9 and RHEL 10, so on a RHEL host you
install it directly. On Fedora it is **complicated**: the
Red Hat Developer site
[explicitly recommends against](https://developers.redhat.com/articles/2025/02/20/why-developers-should-use-microshift)
trying to `dnf install microshift` on Fedora because the
interdependencies (Open Virtual Networking, specific container-runtime
versions, etc.) are tightly coupled to RHEL package
versions. The supported path for Fedora users is **CRC
(CodeReady Containers)**, which manages a RHEL VM running
MicroShift for you:

```bash
# Download CRC from https://developers.redhat.com/products/openshift-local/overview
crc setup
crc start --preset microshift
```

Where minikube's docker driver runs the node as a container on
your host, CRC runs a RHEL VM with an OpenShift-flavored
Kubernetes inside.

**When to pick it:** you specifically need OpenShift API
compatibility for development. If you don't, the overhead
isn't justified.

## Comparison at a glance

| Distribution | Architecture | Fedora and RHEL story | Best fit |
|---|---|---|---|
| **minikube** | Containers as nodes (docker driver, Docker Engine) | first-class | general development, this tutorial |
| **kind**     | Containers as nodes | first-class | CI pipelines, ephemeral clusters |
| **k3s**      | Host systemd service | good, needs SELinux RPM | single-host edge, IoT, ARM |
| **MicroShift** | RHEL systemd service | direct on RHEL; CRC (RHEL VM) on Fedora | OpenShift parity |

## Recommendation

If you've read this far in the tutorial,
**minikube remains the right choice for the things you've
just learned**. Switch to kind if you're building CI; switch
to k3s if you're deploying to an edge device; reach for CRC
if you specifically need OpenShift compatibility. There's no
strong reason to switch from minikube on a development
laptop unless one of those specific needs applies.

The underlying Kubernetes is the same in every case. The
manifests, kubectl commands, helm charts, and operator
patterns you learned in §3-§12 work unchanged across all
four distributions. That's the whole point of Kubernetes
being a standard interface: the choice of distribution is a
deployment decision, not an application-design decision.

<!-- policy-exempt:start -->
## minikube driver choice: why not rootless podman

minikube can also run on rootless Podman, and an earlier revision of
this tutorial did. It was dropped because the node's network and
storage depended on workarounds that Docker Engine does not need:
unroutable node IPs forced tunnels and port-forwards, runtime pairing
rules were easy to break, and image loading was unreliable. The
full record, one symptom at a time, is in
[Lessons learned, Part 4](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/onboarding/LESSONS-LEARNED.md).
The FAQ entry "Why did this tutorial move off rootless podman?"
gives the short version.
<!-- policy-exempt:end -->

[On to §14: FAQ →]({{ "/docs/14-faq/" | relative_url }})
