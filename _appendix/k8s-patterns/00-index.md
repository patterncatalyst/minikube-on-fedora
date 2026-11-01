---
title: "Kubernetes patterns & CKAD: start here"
order: 0
part: "Start here"
description: "The map: the six pattern families, how each chapter is built, the two call-outs, and how the set reconciles against the CKAD exam."
duration: 6 min
---

This appendix is a reference to the design patterns of cloud-native Kubernetes,
worked one pattern at a time against the tutorial's own shipping services. Where
most pattern material leans on a throwaway demo app, every chapter here uses the
same order / inventory / payment / shipping / notification services the
[§17 data mesh]({{ '/capstone/data-mesh/' | relative_url }}) already runs, so a
pattern lands on a system you can actually place an order against.

It is also a CKAD companion. Each pattern is tagged to where it sits on the
Certified Kubernetes Application Developer exam, and a closing crosswalk maps the
whole set back to the exam's five domains so you can use the appendix as revision.

## How a chapter is built

Every pattern chapter follows the same spine:

- **Learning objectives**: what you can do by the end.
- **Why this matters**: the problem the pattern solves, in the shipping domain.
- **The pattern, worked**: the manifests and, where needed, the code, applied to
  a shipping service.
- **🎓 CKAD exam lens**: the exam domain and weight this pattern touches, the
  competency it exercises, and a short `kubectl` drill to rehearse it.
- **🤖 Explore with your agent**: a ready-to-run prompt to take the pattern
  further with Claude.
- **Cleanup** and a pointer to the runnable **example** under
  `examples/appendix-patterns/`.

Each chapter carries at least one diagram, and holds to a pattern-language
register: tighter than the tutorial chapters, long enough to be complete.

## The six families

The patterns are grouped the way the literature groups them. Read a family at a
time; within a family the chapters stand alone.

- **Foundational**: the contracts every container must honor to be a good
  Kubernetes citizen: predictable resource demands, declarative deployment,
  health probes, a managed lifecycle, and letting the scheduler place the pod.
- **Structural**: how containers are composed inside a Pod: init containers,
  sidecars, adapters, and ambassadors.
- **Behavioral**: how workloads behave over time: batch and periodic jobs,
  daemons, singletons, stateless and stateful services, discovery, and
  self-awareness.
- **Configuration**: how configuration reaches the application: ConfigMaps and
  Secrets, templates, and immutable configuration.
- **Advanced**: extending the platform itself: controllers, a real operator and
  CRD, elastic scaling, and in-cluster image builds.
- **Security**: running safely: access control, network segmentation, process
  containment, and secure configuration.

The full, always-current list is the card grid on the
[appendix landing page]({{ '/appendix/k8s-patterns/' | relative_url }}).

## The CKAD reconciliation

The pattern families cover most of the CKAD curriculum, but not all of it. A
short set of **gap chapters** fills what the patterns leave out: observability
and debugging, packaging with Helm and Kustomize, and namespace governance
(ResourceQuota and LimitRange). A **crosswalk** closes the set by mapping
every pattern to its exam domain with a self-test task list.

## What this appendix leaves out

This appendix stays on plain Kubernetes, running on a dedicated `mof-patterns`
minikube profile. The OpenShift Local (CRC) equivalent (Security Context
Constraints, Routes, OperatorHub installs, in-cluster S2I builds) is a separate
corollary and is not covered here.

Start with the first family: **foundational patterns**.
