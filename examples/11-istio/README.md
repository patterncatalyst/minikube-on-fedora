# 11-istio

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

which downloads Istio 1.31.1 to `~/.local/share/istio-1.31.1/`,
installs `istioctl` to `~/.local/bin/`, and creates the
`~/.local/share/istio-current` symlink the demo references for
the Bookinfo manifests.

The demo also expects a minikube profile called `istio` —
**separate from the `minikube` profile** §6-§9 use. If it
doesn't exist, the demo creates it. The recommended sizing:

```
minikube start -p istio --driver=docker --container-runtime=containerd \
    --kubernetes-version=v1.36.5 --cpus=4 --memory=6144 \
    --ports=127.0.0.1:8080:30880,127.0.0.1:20001:30201,127.0.0.1:3000:30300,127.0.0.1:9090:30990,127.0.0.1:16686:31686
```

These match the §3 settings (Docker Engine, containerd), just on a
bigger profile. The demo creates it with this command through
`ensure_profile`; the `--ports` map is `ISTIO_PORTS` in
`scripts/lib/_helpers.sh`. Published ports are fixed at profile
creation: if the profile already exists without them, the demo
prints the delete-and-recreate command and stops.

## What it tests

Eleven §11 claims:

1. The `istio` minikube profile starts with sufficient resources
   for Istio + Bookinfo and publishes its five NodePorts on
   `127.0.0.1`
2. `istioctl install --set profile=demo` installs the control
   plane + ingressgateway successfully
3. The `default` namespace can be labeled for sidecar injection
4. A Deployment with the `sidecar.istio.io/inject: "true"`
   annotation produces Pods with `READY 2/2` (app + Envoy
   sidecar)
5. Bookinfo's 4 microservices deploy cleanly with sidecars
6. The Bookinfo Gateway + VirtualService make productpage
   reachable through the ingress gateway at
   `http://127.0.0.1:8080/productpage` (companion Service
   `ingressgateway-host`, nodePort 30880)
7. `istioctl analyze` returns clean (no config errors)
8. `virtual-service-all-v1.yaml` pins 100% of reviews traffic
   to v1 (the demo confirms by counting v2/v3 indicators in 10
   responses — should be 0)
9. `virtual-service-reviews-50-v3.yaml` produces roughly 50/50
   between v1 and v3 (sampled across 20 requests)
10. Per-profile minikube image cache is independent from the
    `minikube` profile (nginx-custom:v1 must be rebuilt on the
    istio profile)
11. Every call is pinned to the `istio` context, so your current
    kubectl context is never changed

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
minutes for the §6 Containerfile to build (`docker build`, then
`minikube image load`).

## What you should see

`==> step` lines for each phase. Notable checkpoints:

```
==> deploying nginx-with-sidecar
✓ nginx-istio Pod has nginx + istio-proxy (mesh injection working)

==> applying Bookinfo Gateway + VirtualService
✓ Gateway + VirtualService applied; istioctl analyze clean

==> waiting for productpage on http://127.0.0.1:8080/ (nodePort 30880)
✓ ingress gateway reachable at http://127.0.0.1:8080/

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
that §6-§9 use). Every `kubectl`, `istioctl` and `minikube` call
in the demo targets the `istio` context or profile explicitly, so
your current kubectl context stays as it was and your `minikube`
profile is undisturbed; §6-§9 demos continue to work normally
after §11 runs.

## Host access

Services this demo needs from the host are NodePorts published at
profile creation, reached on `127.0.0.1`. The upstream Services
(`istio-ingressgateway`, and the Kiali, Grafana, Prometheus and
Jaeger addons) are never patched, since `istioctl install` or an
addon re-apply would revert the change. Instead
`host-access/` holds one companion NodePort Service per
destination, owned by this repo and selecting the same Pods. It
sits outside `manifests/` so the demo's cleanup of the workload
does not remove it.

| Companion (istio-system) | Target | nodePort | Host URL |
|---|---|---|---|
| `ingressgateway-host` | 80 -> 8080 | 30880 | `http://127.0.0.1:8080/productpage` |
| `kiali-host` | 20001 | 30201 | `http://127.0.0.1:20001/kiali` |
| `grafana-host` | 3000 | 30300 | `http://127.0.0.1:3000/` |
| `prometheus-host` | 9090 | 30990 | `http://127.0.0.1:9090/` |
| `tracing-host` | 80 -> 16686 | 31686 | `http://127.0.0.1:16686/` |

The demo applies `ingressgateway-host` after the Istio install.
The addon companions are applied together with the addons (see
"Going further"). Selectors were read from the Istio 1.31.1
release's addon manifests; confirm any of them on a live cluster
with `kubectl --context istio get svc -n istio-system <svc> -o
jsonpath='{.spec.selector}'`.

## Cleanup

The demo's `trap cleanup EXIT` handler:

1. Deletes Bookinfo's networking rules
2. Deletes Bookinfo's Deployments and Services
3. Deletes our nginx-with-sidecar

**Istio itself stays installed** on the istio profile, along with
the `ingressgateway-host` companion Service. The demo
doesn't `istioctl uninstall` on every exit — that would mean
every re-run waits 30-60 seconds for the control plane to come
back up. To fully remove Istio:

```bash
kubectl --context istio delete -f host-access/ --ignore-not-found
istioctl --context istio uninstall --purge -y
kubectl --context istio delete namespace istio-system
kubectl --context istio label namespace default istio-injection-

# or all of it, including the addons, with:
./cleanup.sh --remove-istio
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
       minikube start -p istio --driver=docker \
           --container-runtime=containerd \
           --kubernetes-version=v1.36.5 --cpus=4 --memory=6144 \
           --ports=127.0.0.1:8080:30880,127.0.0.1:20001:30201,127.0.0.1:3000:30300,127.0.0.1:9090:30990,127.0.0.1:16686:31686

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

6. **Port 8080, 20001, 3000, 9090 or 16686 already in use on the
   host** — `ensure_profile` lists the conflicting host port and
   stops before creating the profile. Free the port (a stray
   local server is the usual cause) and re-run

7. **Demo says the profile does not publish a nodePort** — the
   `istio` profile was created without `--ports`. Published ports
   cannot be added to an existing profile; run the printed
   `minikube delete` / `minikube start` command

8. **`curl 127.0.0.1:8080` fails but the gateway is Ready** — the
   companion selector matched no Pod. The demo prints the
   Service's endpoints and the gateway Service's real selector;
   fix `host-access/ingressgateway-host.yaml` to match

9. **`READY 1/2` instead of `2/2`** on Bookinfo Pods — sidecar
   injection didn't happen. Verify the namespace label:
   `kubectl get namespace default -L istio-injection`

For any of these, paste the failing output back.

## Going further on your own

The demo deliberately stops short of:

- **Fault injection** — try
  `kubectl --context istio apply -f ~/.local/share/istio-current/samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml`
  for a 7-second delay on ratings
- **Observability addons** — `kubectl --context istio apply -f
  ~/.local/share/istio-current/samples/addons/` installs Kiali,
  Prometheus, Grafana, Jaeger (5+ min), then
  `kubectl --context istio apply -f host-access/` adds their
  NodePort companions. Kiali is then at
  `http://127.0.0.1:20001/kiali`
- **Production profiles** — the demo profile is for tutorials;
  real deployments use a slimmer profile or a custom
  IstioOperator

All three are covered briefly in the §11 prose.
