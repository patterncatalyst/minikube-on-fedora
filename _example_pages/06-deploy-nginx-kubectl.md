---
title: "§6 deploy nginx kubectl"
order: 6
example_dir: examples/06-deploy-nginx-kubectl
permalink: /examples/06-deploy-nginx-kubectl/
layout: docs
---

> Source: [`examples/06-deploy-nginx-kubectl/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/06-deploy-nginx-kubectl) &nbsp;|&nbsp; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})

First workload-deployment example in the tutorial. A smoke test that
builds a small nginx image with a two-stage `Containerfile` (UBI 9
builder → UBI 9 Minimal runtime), loads it into the cluster via
`minikube image build`, deploys it with a Deployment + Service,
port-forwards to the Service, validates the response content, then
scales.

This isn't a cluster-startup test (that was §3's
`examples/03-driver-check/`). The cluster needs to already be
running — the script will start it for you if not, but the focus
here is **building an image and deploying it**.

## Why we build our own image

Red Hat publishes nginx images at `registry.access.redhat.com/ubi9/nginx-124`
(and `-122`), but those are **s2i (source-to-image) builder images**
designed for OpenShift, not plain Kubernetes. Their default CMD
invokes `/usr/libexec/s2i/run` and expects content baked in via the
s2i workflow; running them as-is in Kubernetes crashloops with no
document root.

Rather than coax the s2i image into running directly (possible but
fragile), the right pattern is to build our own image from a base
UBI image. The `Containerfile` in this directory does that: a
builder stage (`ubi9/ubi`) stages content, a runtime stage
(`ubi9/ubi-minimal`) installs nginx, configures it for non-root +
port 8080, copies the staged content in, and runs nginx in the
foreground.

Both base images are **freely redistributable** — no
subscription-manager registration needed to install packages from
the public UBI repos.

## What it tests

Seven claims that span §6's scope:

1. `minikube image build -f Containerfile -t nginx-custom:v1 .`
   produces an image visible to the cluster's runtime
2. The two-stage Containerfile builds cleanly under the build
   environment minikube provides
3. `kubectl apply -f manifests/` ships both files cleanly
4. The Deployment reaches `Available` condition within 3 minutes
5. The Service's selector matches the Pod labels, so the Service
   has live endpoints
6. `kubectl port-forward` opens a tunnel from `127.0.0.1:18080` to
   the Service inside the cluster; the response contains the
   sentinel string from our baked-in `index.html`
7. `kubectl scale --replicas=3` brings the count to 3 Running
   Pods and the Deployment stays `Available` throughout

On success, the corresponding §6 reconciliation rows promote.

## Running

```bash
./demo.sh
```

Expected duration:

- **First run:** 2-4 minutes (downloads `ubi9` and `ubi9/ubi-minimal`
  base images, ~250 MB combined; runs `microdnf install nginx`;
  builds final image)
- **Subsequent runs:** 25-40 seconds (image cached in cluster's
  local image cache; rebuild skipped if Containerfile hasn't changed)

To force a rebuild from scratch:

```bash
minikube image rm nginx-custom:v1
./demo.sh
```

## What you should see

A series of `==> step` lines for each phase, with build output and
`kubectl` output inlined. The build step is the most verbose — you'll
see microdnf installing nginx and a few hundred kilobytes of
package metadata. The script finishes with
`✓ SUCCESS — image built + Deployment + Service + port-forward + scaling all working`
on a clean pass.

## Cluster scope

This demo uses your **default minikube cluster** (the `minikube`
profile), not a dedicated one. It assumes you've completed §3's
defaults block (`minikube config set driver podman`,
`rootless true`, `container-runtime containerd`, and your preferred
cpus/memory).

The built image `nginx-custom:v1` persists in the cluster's image
cache across runs. To remove it: `minikube image rm nginx-custom:v1`.

## SELinux note

This example doesn't bind-mount anything from the host. The build
context is read by `minikube image build` and the resulting image
is referenced by name, not via host path. So **no `:Z` flag is
needed here**. When §8 adds hostPath PersistentVolumes, that's
where `:Z` (and the broader SELinux story) becomes relevant.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that runs whether the
script succeeds or fails:

- Kills the backgrounded `kubectl port-forward` process
- Deletes the Deployment and Service via `kubectl delete -f`
- **Does not** delete the built image (kept for fast re-runs)
- Leaves the cluster running

If something pathological happens (script killed during cleanup),
manual recovery:

```bash
pkill -f 'kubectl port-forward service/nginx' || true
kubectl delete -f manifests/ --ignore-not-found=true
```

## Re-running

Idempotent. The pre-flight step deletes any pre-existing `nginx`
Deployment/Service and waits briefly for terminating Pods to
finish before applying fresh. The image build is skipped if
`nginx-custom:v1` already exists in the cluster's image cache.

## When this fails

The most likely failure modes, in order:

1. **`minikube image build` fails on UBI image pull** — transient
   network issue reaching `registry.access.redhat.com`. Retry
2. **`microdnf install nginx` fails inside the build** — UBI repos
   transiently unreachable. Retry
3. **Cluster not reachable** — `minikube status` errors. The script
   will try `minikube start` automatically; if that fails, work the
   failure like §3 (driver, rootless, or runtime config issue)
4. **Pods stuck in `CrashLoopBackOff`** — most likely a permissions
   issue inside the container. The demo's `kubectl wait` failure
   path automatically dumps logs from current and previous
   containers, which usually tells you exactly what nginx is
   complaining about. Common causes: misconfigured port (try
   `kubectl describe pod <name>` for the actual port), permission
   denied on a directory the non-root user can't write
5. **Image-pull failure on `nginx-custom:v1`** — minikube's image
   cache didn't pick up the build for some reason. Confirm with
   `minikube image ls | grep nginx-custom` — if absent, rerun
   `minikube image build -f Containerfile -t nginx-custom:v1 .`
   manually from this directory

For any of these, copy the failing output and share it back so the
iteration can produce an `r07b` fix-up.
