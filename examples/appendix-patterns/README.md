# Kubernetes patterns appendix: runnable examples

The runnable code for the [Kubernetes patterns & CKAD
appendix](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/).
One directory per pattern, each self-contained, each worked against the
tutorial's shipping services rather than a throwaway demo app.

This tree is excluded from the Jekyll build (like all of `examples/`): it is
runnable code, not site content.

## The profile

Every example runs on a dedicated **`mof-patterns`** minikube profile, separate
from §3's `minikube` profile and the capstone's `mof-capstone`. Create it once:

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
```

It is sized for the heaviest appendix needs (Istio + KEDA + metrics-server
together), lighter than the full capstone mesh. A few chapters need extras set at
creation time; the NetworkSegmentation chapter needs the Calico CNI:

```bash
./scripts/setup-patterns-profile.sh --replace --calico
```

Prerequisites (Docker Engine, kernel tweaks) are the same as
[§1](https://patterncatalyst.github.io/minikube-on-fedora/docs/01-prerequisites/).

## Layout

```
examples/appendix-patterns/
  scripts/
    lib/env.sh                 # PROFILE=mof-patterns, NS=patterns, context pinning
    setup-patterns-profile.sh  # create/replace the profile
    build-service.sh           # build+load one capstone service image onto mof-patterns
  <pattern>/                   # one directory per pattern chapter
    README.md                  # how to run this pattern's example
    *.yaml                     # the manifests, worked against a shipping service
  operator/                    # Go operator + Shipping CRD (Controller/Operator chapters)
```

## Building a service image

Four of the Foundational examples run a real shipping service. There's no
registry: `build-service.sh` builds the service's Containerfile with Docker
Engine and loads the image straight into the `mof-patterns` profile's
containerd store, the same `imagePullPolicy: Never` approach the capstone
uses.

```bash
./scripts/build-service.sh shipping-service v1
./scripts/build-service.sh inventory-service v1
```

The capstone's service source under `examples/17-capstone/services/` is read,
never modified.

Each `<pattern>/` directory is referenced from its chapter's
`## Verification: examples/appendix-patterns/<pattern>/` section. Most examples
reach a service with `kubectl port-forward`, so no fixed NodePort map is needed.

## Shipping services

The examples reuse the capstone's services (order, inventory, payment, shipping,
notification, review, graphql-gateway). The Python reference architecture
(`datamesh-reference-arch-python`) is the source of truth for that service code;
these examples apply manifests and, where a pattern needs net-new code (batch
jobs, daemons, immutable config), add small apps built with `uv` + FastAPI.

## Cleanup

Each pattern README documents its own cleanup. To remove the whole profile:

```bash
minikube delete -p mof-patterns
```
