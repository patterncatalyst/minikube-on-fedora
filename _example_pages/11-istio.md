---
title: "§11 istio"
order: 11
example_dir: examples/11-istio
permalink: /examples/11-istio/
layout: tutorial
---

**Source:** [`examples/11-istio/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/11-istio) &middot; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})

The longest single demo in the tutorial. Installs Istio on a
dedicated minikube profile, sidecar-injects our existing
`nginx-custom:v1` Deployment, deploys the **Bookinfo** sample
app, exercises traffic-routing rules (v1 pinning, 50/50 split)
and verifies that requests actually flow through the configured
versions.

## Pre-requisites

This demo assumes you've already run:

```bash
./scripts/setup-istio.sh
```

which downloads Istio 1.29.2 to `~/.local/share/istio-1.29.2/`,
installs `istioctl` to `~/.local/bin/`, and creates the
`~/.local/share/istio-current` symlink the demo references for
the Bookinfo manifests.

The demo also expects a minikube profile called `istio` —
**separate from the `minikube` profile** §6-§9 use. If it
doesn't exist, the demo creates it. The recommended sizing:

```
--memory=6g --cpus=4 --container-runtime=containerd --rootless=true
```

These match the §3 settings, just on a bigger profile.

## What it tests

Eleven §11 claims:

1. The `istio` minikube profile starts with sufficient resources
   for Istio + Bookinfo
2. `istioctl install --set profile=demo` installs the control
   plane + ingressgateway successfully
3. The `default` namespace can be labeled for sidecar injection
4. A Deployment with the `sidecar.istio.io/inject: "true"`
   annotation produces Pods with `READY 2/2` (app + Envoy
   sidecar)
5. Bookinfo's 4 microservices deploy cleanly with sidecars
6. The Bookinfo Gateway + VirtualService make productpage
   reachable through the ingress gateway
7. `istioctl analyze` returns clean (no config errors)
8. `virtual-service-all-v1.yaml` pins 100% of reviews traffic
   to v1 (the demo confirms by counting v2/v3 indicators in 10
   responses — should be 0)
9. `virtual-service-reviews-50-v3.yaml` produces roughly 50/50
   between v1 and v3 (sampled across 20 requests)
10. Per-profile minikube image cache is independent from the
    `minikube` profile (nginx-custom:v1 must be rebuilt on the
    istio profile)
11. kubectl context can be restored to `minikube` after the
    demo runs (the cleanup trap does this)

## Running

```bash
./demo.sh
```

Expected duration:

- **First run** (image build + Istio install + Bookinfo first-pull):
  8-12 minutes. Most of it is Bookinfo Pods pulling images
  (~150 MB total across 4 services × 3 reviews versions)
- **Subsequent runs** (everything cached): 4-6 minutes

If `nginx-custom:v1` isn't cached on the istio profile, add 2-4
minutes for the §6 Containerfile to build.

## What you should see

`==> step` lines for each phase. Notable checkpoints:

```
==> deploying nginx-with-sidecar
✓ nginx-istio Pod has nginx + istio-proxy (mesh injection working)

==> applying Bookinfo Gateway + VirtualService
✓ Gateway + VirtualService applied; istioctl analyze clean

==> curling productpage; expecting the Bookinfo Sample heading
✓ Bookinfo productpage served via ingress + mesh

==> curling productpage 10 times; counting v2/v3 indicators (should be 0)
  0 of 10 responses contained 'glyphicon-star' (v2/v3 ratings)
✓ 100% of reviews traffic routed to v1 (no ratings)

==> curling productpage 20 times; expecting roughly 8-12 v3 hits
  10 of 20 responses contained 'glyphicon-star' (v3 indicator)
✓ traffic split: 10/20 hit v3
```

The exact split count varies (it's a random sample of 20
requests). The demo treats 4-16 of 20 as a soft pass — anything
more skewed than that prints a warning but doesn't fail, since
routing rule propagation can lag a few seconds.

## Cluster scope

Uses the **`istio` minikube profile** (NOT the default profile
that §6-§9 use). The demo:

1. Switches `kubectl config use-context istio` at start
2. Saves your original context
3. Restores it on exit (success or failure)

So your `minikube` profile is undisturbed; §6-§9 demos continue
to work normally after §11 runs.

## Cleanup

The demo's `trap cleanup EXIT` handler:

1. Kills the background `kubectl port-forward`
2. Deletes Bookinfo's networking rules
3. Deletes Bookinfo's Deployments and Services
4. Deletes our nginx-with-sidecar
5. Restores kubectl context to the saved original

**Istio itself stays installed** on the istio profile. The demo
doesn't `istioctl uninstall` on every exit — that would mean
every re-run waits 30-60 seconds for the control plane to come
back up. To fully remove Istio:

```bash
kubectl config use-context istio
istioctl uninstall --purge -y
kubectl delete namespace istio-system
kubectl label namespace default istio-injection-
```

To stop or delete the istio profile entirely:

```bash
minikube stop -p istio       # stop, keep state
minikube delete -p istio     # delete, free disk
```

## When this fails

1. **`scripts/setup-istio.sh` not run** — the demo will tell you
   if istioctl isn't in PATH or if the Bookinfo samples aren't
   present at `~/.local/share/istio-current/samples/bookinfo/`.
   Run setup-istio.sh and try again

2. **istio profile out of resources** — Istio + Bookinfo + sidecars
   easily peak at 4-5 GB. If the profile was created with less
   than `--memory=6g`, Pods will go OOMKilled or stay Pending.
   Fix: delete and recreate the profile

       minikube delete -p istio
       minikube start -p istio --memory=6g --cpus=4 \
           --container-runtime=containerd --rootless=true

3. **Bookinfo Pods stuck pulling images** — the `docker.io/istio/*`
   images are larger than our nginx-custom image. Check
   `kubectl describe pod` for image-pull errors

4. **`istioctl analyze` reports errors** — usually a Gateway or
   VirtualService misconfiguration. The demo's failure dump
   includes the full analyze output

5. **v3-hit count is way off** — could mean the routing rule
   didn't propagate to the sidecars (rare; usually resolves
   within 10s of apply), OR the Bookinfo manifest filename
   moved in a newer Istio release. The demo falls back to
   `virtual-service-reviews-jason-v2-v3.yaml` if the canonical
   50/50 file is missing

6. **`READY 1/2` instead of `2/2`** on Bookinfo Pods — sidecar
   injection didn't happen. Verify the namespace label:
   `kubectl get namespace default -L istio-injection`

For any of these, paste the failing output back.

## Going further on your own

The demo deliberately stops short of:

- **Fault injection** — try
  `kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml`
  for a 7-second delay on ratings
- **Observability addons** — `kubectl apply -f
  ~/.local/share/istio-current/samples/addons/` installs Kiali,
  Prometheus, Grafana, Jaeger (5+ min). Then `istioctl dashboard
  kiali` opens the visual mesh
- **Production profiles** — the demo profile is for tutorials;
  real deployments use a slimmer profile or a custom
  IstioOperator

All three are covered briefly in the §11 prose.
