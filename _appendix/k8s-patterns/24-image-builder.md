---
title: "Image Builder"
order: 24
part: "Advanced"
description: "Build a container image without Docker Engine on the host: minikube image build runs the build on the node itself, and a Kaniko Job builds inside a Pod and pushes to an in-cluster registry, the way a real CI pipeline would."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Build a container image on the node itself with `minikube image build`, with no Docker Engine on the host at all
- Run a Kaniko `Job` that builds a container image inside a Pod, with no privileged container and no Docker daemon anywhere in the cluster
- Explain why a Pod pushes to an in-cluster registry using a different address than the one a Deployment later pulls from
- State what each build path actually produces: a local image in the node's runtime, versus a real Kubernetes object a CI pipeline could trigger

## Why this matters

Every other chapter in this appendix builds `shipping-service` the same way: `scripts/build-service.sh` runs `docker build` on the host, using whatever container engine happens to be installed there, then loads the resulting image straight into the `mof-patterns` profile's containerd store with `minikube image load`. That workflow is fast and simple for a local tutorial profile, and it's also not how a real deployment pipeline usually works: a CI runner building an image for a production cluster rarely has (or should have) a privileged Docker daemon sitting next to it, and the whole point of **in-cluster** image building is removing that dependency, building the image using only the compute the cluster itself provides.

This chapter covers two ways to do that, chosen specifically because they differ in how real they are as Kubernetes objects. `minikube image build` is the lighter of the two: it builds the image on the node itself, through minikube's own tooling, bypassing the Kubernetes API entirely in the process. Kaniko is the heavier, more complete answer: a `Job`, created and scheduled through the normal Kubernetes API exactly like any other workload, that builds a Containerfile inside its own Pod with no privileged container and no Docker daemon anywhere in the cluster, then pushes the result to a registry. Per the appendix's own reconciliation plan, this chapter also drops the Knative build lane the underlying pattern literature covers: Knative's build pipeline wraps the same in-cluster-build problem inside a heavier serving-and-build framework this appendix doesn't otherwise adopt, and Kaniko alone covers the "build inside the cluster" half of that story without requiring it.

## Part 1: minikube image build, the quickest path

```bash
minikube -p mof-patterns image build \
  -f ../17-capstone/services/shipping-service/Containerfile \
  -t shipping-service:v1 \
  ../17-capstone/services/shipping-service
```

No `docker build` runs on the host at all here. `minikube image build` ships the named build context (a directory, same as any `docker build` invocation's final positional argument) to the node, and runs the build there using the node's own container runtime, containerd on this profile, the identical runtime that's already running every Pod. The result lands directly in that runtime's local image store, which is exactly where `imagePullPolicy: Never` looks when the kubelet tries to start a container: `minikube -p mof-patterns image ls` shows `shipping-service:v1` present immediately afterward, with no separate load step, because there was never a separate host-side image to load from.

This is the fastest route to something that behaves like an in-cluster build, and for a single-node development profile, it's often the right tool: one command, no registry, no extra YAML, and the result is immediately usable by any Deployment on that same node. It comes with a real limitation, stated precisely: there's no Kubernetes object behind it anywhere. `kubectl get pods` during the build shows nothing related to it; `kubectl get jobs` shows nothing; nothing about this build is schedulable, observable through the API, or triggerable by anything that only knows how to talk to the Kubernetes API rather than shell out to the `minikube` CLI directly. It's a convenience minikube's own tooling provides on top of the cluster, not a capability the cluster itself exposes.

## Part 2: Kaniko, a build that's actually a Pod

Kaniko closes that gap. The build happens entirely inside a Pod, submitted as an ordinary `Job`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shipping-service-kaniko-build
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:v1.24.0
          args:
            - --context=git://github.com/patterncatalyst/minikube-on-fedora.git#refs/heads/main
            - --context-sub-path=examples/17-capstone/services/shipping-service
            - --dockerfile=Containerfile
            - --destination=registry.kube-system.svc.cluster.local/shipping-service:kaniko
            - --insecure
            - --insecure-pull
            - --skip-tls-verify
```

The Kaniko executor reimplements the parts of a container build (reading a Dockerfile-syntax file, executing each instruction, assembling layers, writing an OCI-compliant image) entirely in user space, with no Docker daemon, no `/var/run/docker.sock`, and critically, no privileged container: every other mechanism for building an image inside a Pod historically meant mounting the host's own Docker socket into the build Pod, handing that Pod root-equivalent control over the entire node, a real and well-known security hole this appendix's own Process Containment pattern would flag immediately. Kaniko exists specifically to make that mount unnecessary.

`--context` and `--context-sub-path` tell Kaniko where to find the build context: a git reference rather than a local directory, since the Pod running the build has no access to this host's filesystem at all. This matters more than it might first appear. The host-build workflow every other chapter uses relies on `docker build`'s context being whatever's on the local disk at build time; a Kaniko Job running from a git context instead builds from a specific, named, reproducible reference, the same discipline a real CI pipeline enforces by construction: the artifact a build Job produces is traceable back to an exact commit, not whatever happened to be sitting uncommitted on someone's laptop.

`--destination` names where the built image gets pushed, and this is where the chapter's registry story turns interesting.

## Two addresses, one registry

There's no registry anywhere else in this appendix; every other chapter sidesteps needing one with `imagePullPolicy: Never`. This chapter enables minikube's own `registry` addon specifically because Kaniko needs somewhere real to push to, and that addon's own design surfaces a distinction worth understanding precisely: a Pod and a node do not share a network namespace, and the registry addon is reachable at a different address depending on which one is doing the asking.

The Kaniko Job pushes from inside a Pod, using ordinary cluster networking, the same mechanism every Service-to-Service call in this appendix already relies on (the Service Discovery pattern covers exactly this). From a Pod's perspective, the registry is just another in-cluster Service, reached by its cluster-DNS name:

```
--destination=registry.kube-system.svc.cluster.local/shipping-service:kaniko
```

The Deployment that later *runs* this image does something categorically different: it doesn't push or pull from inside a Pod's own network namespace at all. Pulling an image happens at the kubelet/containerd layer, on the node itself, before any Pod network namespace for the new container even exists yet. The registry addon accounts for this by running a small `registry-proxy` DaemonSet, one Pod per node, that listens on that node's own loopback at port 5000 and forwards whatever it receives to the registry Service. Because the kubelet's pull request originates from the node's network namespace, not a Pod's, `localhost:5000` from that vantage point really does reach the proxy sitting on the very same node:

```yaml
containers:
  - name: shipping-service
    image: localhost:5000/shipping-service:kaniko
    imagePullPolicy: Always
```

Pushing a Kaniko image from inside a Pod and pulling that same image into a Deployment's container therefore use two different addresses for the identical registry, not because the registry has two endpoints, but because the two operations happen from two distinct vantage points on the cluster's network: one from inside a Pod's own namespace, one from the node's. Getting this backwards (using `localhost:5000` from inside the Kaniko Pod, say) fails with a connection refused that has nothing to do with the registry being down, and everything to do with asking the wrong network namespace for something that only exists in the other one. `imagePullPolicy: Always` here is itself a direct contrast with every other chapter's `imagePullPolicy: Never`: there's a real registry behind this image now, something for the kubelet to actually contact, verify, and pull fresh from, rather than a bare name whose only valid resolution is whatever's already sitting in the node's local image store.

![minikube image build runs on the node itself with no Kubernetes object behind it, while a Kaniko Job is a real Pod that builds and pushes to an in-cluster registry a Deployment later pulls from through a second, different address]({{ "/assets/diagrams/appendix-24-image-builder.svg" | relative_url }})
*The build mechanism differs in how visible it is to the Kubernetes API; the registry addresses differ because a Pod's network namespace and a node's are never the same thing.*

## Confirming what actually ran

`kubectl get job shipping-service-kaniko-build -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'` is the single-line answer to "did the build finish," but a Job completing successfully only proves Kaniko's own process exited zero; it doesn't by itself prove the Deployment that references the built image is actually running it. `kubectl describe pod` on the Deployment's Pod answers that second question directly, in its `Events` section: a line reading `Pulling image "localhost:5000/shipping-service:kaniko"` followed by `Successfully pulled image` confirms the kubelet actually contacted the registry-proxy and fetched fresh content, rather than reusing whatever happened to already be sitting in the node's local containerd store under that same tag from an earlier run. That distinction matters more here than in most of this appendix's other chapters, specifically because `imagePullPolicy: Always` is in play: a stale local image under the same tag, left over from a previous Kaniko run that pushed to the same destination, would otherwise be indistinguishable from a freshly pulled one without checking the pull event directly.

Kaniko itself supports layer caching (`--cache=true`, plus a `--cache-repo` naming where to store cached layers), which matters for anything beyond a tutorial-sized image: without it, every Job run rebuilds every layer in the Containerfile from scratch, including the dependency-installation layers that rarely change between builds. This chapter's own manifest leaves caching off, to keep the example's moving parts limited to the ones actually being taught (a git context, an in-cluster push, a node-local pull), but a real pipeline building the same image dozens of times a day would almost certainly want it enabled, trading a small amount of extra configuration (somewhere for the cache layers to live, typically the same registry) for meaningfully faster builds once the dependency layers stop changing.

## Choosing between them

Neither path is strictly better than the other; they trade off exactly the properties their designs suggest. `minikube image build` is faster to run and needs nothing beyond minikube itself, which makes it the right default for iterating on a single-node development profile where "did my latest code change actually get built" is the whole question, and nobody needs to trigger that build from outside a terminal session. Kaniko is slower to set up (a registry, a Job manifest, a git-reachable source) and slower to run (a real Pod scheduling, pulling the Kaniko executor image, and doing the actual build work), but it's the one that answers to the Kubernetes API: a CI system that can create a `Job` object can trigger this build, watch its `status.conditions` for completion, read its logs through the same `kubectl logs` mechanism used everywhere else in this appendix, and know unambiguously when the build finished and whether it succeeded, none of which `minikube image build`'s host-to-node shortcut can offer, because there's no object in the cluster for anything external to watch.

That's the real reason production image-building pipelines reach for something closer to Kaniko's shape (or a managed equivalent: OpenShift's own S2I and Docker-strategy builds work on the identical principle, a build expressed as a Kubernetes-native object rather than a privileged host-side process) rather than a developer convenience tool: the moment a build needs to be triggered by something other than a person at a terminal, running by hand on a specific developer's machine, it needs to be a first-class object the API itself can create, schedule, and report status on.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design and Build (20%)
> **Competency:** Build and reference a container image produced in-cluster
> **Drill:** `kubectl get job shipping-service-kaniko-build -n patterns -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'`

> **🤖 Explore with your agent**
>
> "Change the Kaniko Job's --context-sub-path to build inventory-service instead of shipping-service, apply it, and show me the exact log line where Kaniko reports the build finished and the destination it pushed to."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f image-builder/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f image-builder/01-kaniko-job.yaml
kubectl --context mof-patterns delete -n patterns -f image-builder/00-postgres.yaml
minikube -p mof-patterns addons disable registry
minikube -p mof-patterns image rm shipping-service:v1
```

## Verification: examples/appendix-patterns/image-builder/

The runnable example builds `shipping-service` once with `minikube image build` directly on the node, then a second time with a Kaniko `Job` that builds from a git context and pushes to the minikube registry addon, pulling that second image back into a Deployment through the node-local `localhost:5000` address the registry addon's per-node proxy exposes. Full walkthrough in `examples/appendix-patterns/image-builder/README.md`.
