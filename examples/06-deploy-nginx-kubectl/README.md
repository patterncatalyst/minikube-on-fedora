# 06-deploy-nginx-kubectl

First workload-deployment example in the tutorial. A smoke test that
exercises §6's happy path end-to-end: apply Deployment + Service
manifests, wait for Pods to be ready, port-forward to the Service,
curl it, scale the Deployment, then clean up.

This isn't a cluster-startup test (that was §3's
`examples/03-driver-check/`). The cluster needs to already be
running — the script will start it for you if not, but the
emphasis here is on **what happens inside the cluster** once it's
up.

## What it tests

Six §6 claims:

1. `kubectl apply -f manifests/` ships both files cleanly
2. The Deployment reaches `Available` condition within 3 minutes
3. The Service's selector matches the Pod labels, so the Service
   has live endpoints
4. `kubectl port-forward` opens a tunnel from `127.0.0.1:18080`
   to the Service inside the cluster
5. The UBI nginx-124 image serves its default page
6. `kubectl scale --replicas=3` brings the count to 3 Running
   Pods and the Deployment stays `Available` throughout

On success, multiple §6 Section B claims promote, along with the
testing-matrix Section C row for this example.

## Running

```bash
./demo.sh
```

Expected duration:

- **First run:** 60-120 seconds (pulls `ubi9/nginx-124`, ~150 MB)
- **Subsequent runs:** 20-30 seconds (image cached on the kicbase
  node)

## What you should see

A series of `==> step` lines for each phase, with `kubectl` output
inlined. The script finishes with `✓ SUCCESS — nginx Deployment +
Service + port-forward + scaling all working` if everything
passes, or `✗ FAILED` and the failing step's name otherwise.

## Cluster scope

This demo uses your **default minikube cluster** (the `minikube`
profile), not a dedicated one. It assumes you've completed the §3
defaults block (`minikube config set driver podman`,
`rootless true`, `container-runtime containerd`, plus your
preferred cpus/memory) and that `examples/03-driver-check/` has
already shown the cluster is healthy.

If you'd rather isolate this demo from your default cluster
work, run it under a dedicated profile by setting the
`MINIKUBE_PROFILE` env var (not currently supported, but a
reasonable future enhancement — file an issue if you'd find this
useful).

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that runs whether the
script succeeds or fails:

- Kills the backgrounded `kubectl port-forward` process
- Deletes the Deployment and Service via `kubectl delete -f`
- Leaves the cluster running

If the script is killed mid-run via Ctrl-C, the trap still runs.
If something pathological happens (Ctrl-C during cleanup itself),
manual cleanup:

```bash
pkill -f 'kubectl port-forward service/nginx' || true
kubectl delete -f manifests/ --ignore-not-found=true
```

## Re-running

Idempotent — re-running from any state does the right thing. The
pre-flight step deletes any pre-existing `nginx` Deployment/Service
and waits briefly for terminating Pods to actually go away before
applying fresh.

## When this fails

The most likely failure modes, in order:

1. **`minikube: command not found`** or **`kubectl: command not
   found`** — §2 install didn't complete. Fix per the §2
   instructions
2. **Cluster not reachable** — `minikube status` errors. The
   script will try `minikube start` automatically; if that fails,
   work the failure like §3 (probably a driver, rootless, or
   runtime config issue)
3. **Image pull timeout** — `registry.access.redhat.com` is
   transiently unreachable. Re-run; the partial download will
   resume
4. **Pods stuck in `Pending`** — node lacks resources. `kubectl
   describe pod <name>` shows the scheduler's reason. Common
   cause: cluster memory/CPU too small relative to the Deployment's
   `resources.requests`. Increase cluster size or decrease the
   manifest's resource requests
5. **`kubectl wait` times out** — Pods are starting but never
   becoming Ready. Usually the readiness probe is failing.
   `kubectl describe pod <name>` shows probe failures; `kubectl
   logs <pod-name>` shows what's actually happening inside

For any of these, copy the failing output and share it back so
the iteration can produce an `r07a` fix-up if the prose or
manifests need adjustment.
