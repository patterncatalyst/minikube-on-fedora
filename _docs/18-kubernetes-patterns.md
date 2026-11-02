---
title: "Appendix: Kubernetes patterns & CKAD"
order: 18
description: "A pattern-per-chapter reference to cloud-native Kubernetes design patterns, worked with the tutorial's shipping services and reconciled against the CKAD exam. Organized as its own set."
duration: reference
---

The tutorial up to here is a path: install minikube, deploy with kubectl and
helm, add Istio and KEDA, and converge everything into the §17 data-mesh
capstone. This appendix is the other half of the picture. Rather than *how to
operate the cluster*, it names the **design patterns** that the deployments,
services, jobs, and operators in this tutorial are instances of, and works each
one on its own.

Like the capstone, it's large enough to be its own set with its own reading
order, so it lives on its own pages rather than stretching this chapter.

## What's in it

One chapter per pattern, across the six families the literature uses:
foundational, structural, behavioral, configuration, advanced, and security. Each
chapter works the pattern against the tutorial's own shipping services (the same
order, inventory, payment, shipping, and notification services the capstone runs),
so the pattern is grounded in a system you can place an order against rather
than a throwaway demo.

The advanced family includes a real **operator**, written in Go with a custom
resource for the shipping domain, in place of the shell-script controllers most
pattern catalogs use to sketch the idea.

## Two lenses on every chapter

Each pattern chapter carries two recurring call-outs:

- **🎓 CKAD exam lens**: maps the pattern to its Certified Kubernetes
  Application Developer exam domain and weight, names the competency it
  exercises, and gives a short `kubectl` drill. A closing crosswalk chapter maps
  the whole appendix back to the exam's five domains, with a self-test task list,
  so the set doubles as CKAD revision.
- **🤖 Explore with your agent**: a ready-to-run prompt for taking the pattern
  further with Claude.

A few **gap chapters** cover the parts of the CKAD curriculum the patterns don't
reach on their own: observability and debugging, packaging with Helm and
Kustomize, and namespace governance.

## Where it runs

The appendix examples run on a dedicated `mof-patterns` minikube profile,
separate from the capstone's `mof-capstone`, with the same host prerequisites as
[§1]({{ '/docs/01-prerequisites/' | relative_url }}). It stays on plain
Kubernetes; the OpenShift Local (CRC) equivalent is a separate corollary.

<p><a class="btn btn--primary" href="{{ '/appendix/k8s-patterns/' | relative_url }}">Open the Kubernetes patterns &amp; CKAD appendix →</a></p>
