---
title: Tutorial outline
order: 0
description: What this tutorial covers, in what order, and how the sections build on each other.
duration: 2 minutes
---

This tutorial takes a developer comfortable with Fedora and Podman
from `dnf install minikube` (where available) through running real
applications on a local Kubernetes cluster with `kubectl` and
`helm`, and ends with reference material for Istio service mesh
and KEDA HTTP-driven autoscaling. Sections 11 and 12 are skippable
for readers who only want the core minikube workflow.

Estimated total reading + hands-on time is around 3½ hours. Each
section's own estimate is in its header. Sections are designed so
partial reads still leave you with something useful.

## The sections

| §  | Title                                       | What you'll learn                                                                        | Duration |
|----|---------------------------------------------|------------------------------------------------------------------------------------------|----------|
| 1  | Prerequisites                               | What hardware, OS, and tools you need before starting                                    | 10 min   |
| 2  | Installation                                | Install minikube, kubectl, helm, and the supporting toolbox (stern, kubectx, etc.)       | 20 min   |
| 3  | Starting minikube                           | Drivers (podman, docker), in-cluster runtimes, status, pause/stop, upgrade               | 15 min   |
| 4  | Custom resources, profiles, multi-node      | Tune CPU/memory, run parallel clusters via profiles, configure multi-node                | 15 min   |
| 5  | Addons and the dashboard                    | List, enable, and use addons; the Kubernetes dashboard                                   | 10 min   |
| 6  | Deploying with kubectl                      | Imperative and declarative deploys, dry-run manifest generation, idiomatic kubectl       | 20 min   |
| 7  | Services, NodePort, and minikube IP         | Service types, exposing apps, getting URLs back via `minikube service`                   | 10 min   |
| 8  | Persistent volumes                          | Static `hostPath` PVs and dynamic PVCs using the default storage class                   | 15 min   |
| 9  | Deploying with Helm                         | `helm install/upgrade/rollback`, using public charts, authoring a small chart            | 25 min   |
| 10 | Editor, shell, and terminal integration     | CLion k8s plugin, Podman Desktop, zsh + kubectx/kubens, warp.dev workflows               | 15 min   |
| 11 | Istio on minikube                           | Install via `istioctl`, sidecar-enabled demo app, Gateway + VirtualService, mTLS basics  | 30 min   |
| 12 | KEDA on minikube (optional)                 | Helm install of KEDA + HTTP add-on; HTTP-driven scaling with a `hey` load test           | 25 min   |
| 13 | Alternatives to minikube                    | Brief tour: kind, k3s, microk8s, microshift — when to pick what                          | 5 min    |
| 14 | FAQ                                         | Common pain points; cleanup recipes                                                      | 5 min    |
| 15 | Where to go next                            | Pointers to deeper resources and possible follow-on tutorials                            | 5 min    |

## How to read this tutorial

**Read §1 first, always.** The prerequisites are non-negotiable —
the most common failures in later sections trace back to a missing
or misconfigured prereq.

**§2 and §3 must run end-to-end before any of §4–§9 will work.**
You need a running minikube cluster with `kubectl` pointed at it
before you can deploy anything.

**§6 (kubectl) and §9 (helm) are deliberately parallel.** Both
deploy the same UBI nginx workload — once with `kubectl apply` and
once with a small helm chart. Reading both makes the trade-offs
between imperative and declarative deployment concrete.

**§11 (Istio) and §12 (KEDA) are optional.** They assume §1–§9 are
done. Each starts with a "resource check" that bumps minikube's
CPU and memory allocation, because both service meshes and KEDA
add real overhead on top of a basic cluster.

## Conventions in this tutorial

- All commands target **Fedora 44** with the **podman driver**
  unless explicitly noted. Where macOS differs, a "macOS note"
  callout flags it — macOS is not a tested platform here, just
  acknowledged
- All container images used by examples are **UBI-based** and
  pullable without `subscription-manager` registration:
  `registry.access.redhat.com/ubi9/...`
- The `examples/` directory holds runnable code for each hands-on
  section. Each example has a `README.md` (narrated walkthrough)
  and a `demo.sh` (strict end-to-end script that also serves as
  the maintainer's verification test)
- Diagrams are SVG with editable Excalidraw sources alongside in
  `assets/diagrams/`. Click any diagram's "Download Excalidraw
  source" link to edit it in [excalidraw.com](https://excalidraw.com)

## Prerequisite knowledge (not covered here)

You should already know, roughly:

- What a container is and how to run one with `podman run`
- What a Pod, Deployment, and Service are in Kubernetes (one
  paragraph each is enough)
- How to read YAML and edit it in a text editor
- The basics of your shell — variables, pipes, redirecting

If any of those are unfamiliar, the upstream [Kubernetes Basics
walkthrough][k8s-basics] is the right warm-up.

[k8s-basics]: https://kubernetes.io/docs/tutorials/kubernetes-basics/

## What this tutorial does **not** cover

- Production cluster operations (RBAC at depth, network policies,
  secrets at scale, multi-tenancy, hardening)
- Building container images (the examples pull pre-built UBI
  images)
- A comparison of minikube with managed Kubernetes offerings as a
  recommendation (the "alternatives" section names local-cluster
  options for navigation only)
- Knative (intentionally out of scope; possible standalone
  follow-on)
- Windows / WSL (not tested)

Ready? [Start with §1: Prerequisites →]({{ "/docs/01-prerequisites/" | relative_url }})
