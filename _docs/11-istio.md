---
title: Istio
order: 11
description: Service mesh on minikube — install Istio, sidecar-inject an existing Deployment, deploy Bookinfo, and exercise traffic routing and fault injection.
duration: 40 minutes
---

Everything in §6 through §10 has been about getting workloads
onto Kubernetes and keeping them running. **Istio** is about what
happens *between* them: how Pods talk to each other, how that
traffic gets observed, how it gets shaped, and how it gets
secured — all without changing application code.

This is a reference section. It's the longest one in the tutorial,
covers two distinct examples (a minimal sidecar injection of our
existing nginx, then the full Istio Bookinfo sample with routing
and fault injection), and uses a dedicated minikube profile to
avoid stepping on §6-§9 work. By the end you'll have:

1. Istio installed on a separate `istio` minikube profile
2. Our `nginx-custom:v1` Deployment running with an Envoy sidecar
3. Bookinfo (4 microservices) deployed and reachable through
   the Istio ingress gateway
4. Traffic-routing rules pinning reviews to a single version,
   then splitting 50/50 between two
5. Fault injection slowing the ratings service
6. Optional: Kiali / Prometheus / Grafana / Jaeger for visualizing
   the mesh

## What's a service mesh

In §6-§9, when one Pod talked to another (e.g., a Deployment of
nginx serving a request that *would* have made an upstream call
to a database, if we had one), the networking happened through
kube-proxy and the Service abstraction. The application code knew
nothing about retries, timeouts, mutual TLS, load-balancing
strategy, or which version of an upstream it was talking to —
because those concerns lived inside the application.

A **service mesh** moves application-level networking concerns
out of the application and into a layer of infrastructure. Each
Pod gets a small proxy injected as a *sidecar* container; the
application Pod's traffic is transparently redirected through
the sidecar; and the sidecar handles mTLS, retries, routing
rules, traffic splitting, observability — driven by configuration
from a central control plane.

Istio is the most widely deployed service mesh. The data plane
is **Envoy** — a high-performance proxy that runs as the sidecar
in every meshed Pod. The control plane is **istiod** — a single
binary that configures every Envoy in the mesh.

## Istio architecture

```
   ┌─────────────────────────┐
   │      istiod             │   ← control plane: serves config
   │  (control plane)        │     to every sidecar via xDS
   └────────────┬────────────┘
                │ xDS
   ┌────────────┴─────────────────────────────────────┐
   │                                                   │
   ▼                                                   ▼
┌──────────────────┐                       ┌──────────────────┐
│  Pod: nginx      │                       │  Pod: bookinfo   │
│  ┌────────────┐  │   mTLS, traffic       │  ┌────────────┐  │
│  │ nginx app  │  │   shaping happen      │  │ productpage│  │
│  └─────┬──────┘  │   in the sidecars,    │  └─────┬──────┘  │
│        │         │   not in the apps     │        │         │
│  ┌─────▼──────┐  │                       │  ┌─────▼──────┐  │
│  │ envoy      │◄─┼───────────────────────┼─►│ envoy      │  │
│  │ (sidecar)  │  │                       │  │ (sidecar)  │  │
│  └────────────┘  │                       │  └────────────┘  │
└──────────────────┘                       └──────────────────┘
```

The mechanism: at Pod creation, Istio's admission webhook injects
a second container (`istio-proxy`, running Envoy) and an init
container (`istio-init`, which uses iptables to redirect the
Pod's traffic through Envoy). Both containers are added to the
Pod spec by the cluster, not by you. The application container
sees a regular network — but every packet in or out goes through
the sidecar.

Sidecar injection is **opt-in per namespace**. We'll label the
`default` namespace to enable injection, and any Pod created
there will get the sidecar automatically.

## Profile setup

Istio is heavier than anything in §6-§9. The control plane needs
~512 MB just to start; each sidecar adds another ~100 MB; the
Bookinfo sample is 12 Pods (so 12 sidecars). The default
`minikube` profile sized for §3 is too small.

Rather than resize the existing profile (which would force
re-deploying §6-§9 demos), §11 uses a **dedicated `istio`
profile**. Start it once:

```bash
minikube start -p istio \
    --memory=6g \
    --cpus=4 \
    --container-runtime=containerd \
    --rootless=true \
    --container-runtime=containerd
```

(The same flags as §3, just on a fresh profile and with more
resources.)

After it starts, your kubectl context points at the `istio`
cluster. You can confirm:

```bash
kubectl config current-context  # → istio
minikube profile list
```

When you're done with §11 and want to go back to the §6-§9
profile:

```bash
kubectl config use-context minikube
```

(Or use `kubectx` from §10.) `minikube stop -p istio` stops the
istio cluster; `minikube delete -p istio` removes it entirely.

## Installing Istio

Istio is installed by **istioctl**, a CLI that ships with the
Istio release tarball. The one-time setup script downloads both:

```bash
./scripts/setup-istio.sh
```

The script:

1. Downloads `istio-1.29.2-linux-amd64.tar.gz` from istio.io
2. Extracts to `~/.local/share/istio-1.29.2/`
3. Installs `istioctl` to `~/.local/bin/istioctl`
4. Sets up a `~/.local/share/istio-current` symlink for
   `examples/11-istio/demo.sh` to find samples

If `~/.local/bin` isn't already in your PATH, the script prints
the line to add to `~/.zshrc` or `~/.bashrc`.

Verify istioctl is reachable:

```bash
istioctl version --remote=false
```

Should print `client version: 1.29.2`.

### Install the control plane

```bash
istioctl install --set profile=demo -y
```

The `demo` profile is what Istio's own tutorials use — it
enables the ingressgateway and adds resources appropriate for
local experimentation. Production deployments would use a
slimmer profile (e.g., `default` or a custom IstioOperator).

After ~30-60 seconds:

```bash
kubectl get pods -n istio-system
```

```
NAME                                    READY   STATUS    RESTARTS   AGE
istio-egressgateway-...                 1/1     Running   0          ...
istio-ingressgateway-...                1/1     Running   0          ...
istiod-...                              1/1     Running   0          ...
```

Three Pods total: control plane (`istiod`), an ingress gateway,
and an egress gateway.

## Sidecar injection

Two ways to opt a Pod into the mesh:

### Namespace label (the usual way)

```bash
kubectl label namespace default istio-injection=enabled
```

Every Pod created in `default` from now on gets the
`istio-proxy` sidecar automatically. Existing Pods don't — you'd
need to recreate them (e.g., `kubectl rollout restart deployment/nginx`).

### Per-Pod annotation (override)

```yaml
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "true"   # force inject (or "false" to opt out)
```

The annotation overrides the namespace label. Useful when you
want injection only for a specific Deployment, or want to
exclude a Pod from injection in an otherwise meshed namespace.

## Sidecar in action — our nginx, now with Envoy

`examples/11-istio/manifests/nginx-with-sidecar.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-istio
  labels:
    app: nginx-istio
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-istio
  template:
    metadata:
      labels:
        app: nginx-istio
      annotations:
        sidecar.istio.io/inject: "true"
    spec:
      containers:
      - name: nginx
        image: nginx-custom:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 2
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-istio
spec:
  type: ClusterIP
  selector:
    app: nginx-istio
  ports:
  - port: 80
    targetPort: 8080
```

Same image as §6 (we'll need to rebuild it on this profile —
images don't cross profiles), same Deployment shape with the
mesh-injection annotation added. The Service is plain ClusterIP
— Istio's sidecars provide mTLS between meshed Pods regardless
of Service type.

Apply:

```bash
kubectl apply -f examples/11-istio/manifests/nginx-with-sidecar.yaml
```

Watch:

```bash
kubectl get pods -l app=nginx-istio
```

```
NAME                          READY   STATUS    RESTARTS   AGE
nginx-istio-xxxxxxx-aaaaa     2/2     Running   0          12s
nginx-istio-xxxxxxx-bbbbb     2/2     Running   0          12s
```

**`READY 2/2`** — that's the key difference. Each Pod has two
containers now: the nginx application (one) and the
`istio-proxy` Envoy sidecar (two).

`kubectl describe pod` confirms:

```
Init Containers:
  istio-init:
    Image:  docker.io/istio/proxyv2:1.29.2
    ...
Containers:
  nginx:
    Image:  nginx-custom:v1
    ...
  istio-proxy:
    Image:  docker.io/istio/proxyv2:1.29.2
    ...
```

The `istio-init` init container runs once (sets up iptables to
redirect traffic through Envoy), exits. `istio-proxy` runs as
the sidecar for the Pod's lifetime.

### Inspecting the sidecar

Useful istioctl commands:

```bash
# What Envoy clusters does this Pod know about?
istioctl proxy-config clusters $(kubectl get pod -l app=nginx-istio -o jsonpath='{.items[0].metadata.name}')

# What listeners?
istioctl proxy-config listeners $(kubectl get pod -l app=nginx-istio -o jsonpath='{.items[0].metadata.name}')

# What route rules?
istioctl proxy-config routes $(kubectl get pod -l app=nginx-istio -o jsonpath='{.items[0].metadata.name}')

# Cluster-wide sanity check
istioctl analyze
```

These get more interesting once Bookinfo's routing rules are in
place. For now, just knowing the commands exist is enough.

## Bookinfo

Bookinfo is Istio's canonical sample application: a four-service
microservices app written in four languages, designed to
exercise the interesting parts of a service mesh.

Architecture:

```
┌─────────────┐
│ productpage │   Python — the frontend
│  (port 9080)│
└──┬───────┬──┘
   │       │
   │       └────────────┐
   ▼                    ▼
┌─────────┐    ┌─────────────────────┐
│ details │    │ reviews             │
│  (Ruby) │    │  (Java; v1, v2, v3) │
└─────────┘    └──────────┬──────────┘
                          │
                          ▼ (v2 + v3 only)
                   ┌─────────────┐
                   │ ratings     │
                   │ (Node.js)   │
                   └─────────────┘
```

Three versions of `reviews` give Istio something to route
between:

- **v1** — no ratings stars
- **v2** — black ratings stars (calls `ratings`)
- **v3** — red ratings stars (calls `ratings`)

By default, traffic round-robins across all three; we'll add
rules that pin or split.

### Deploy

```bash
kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/platform/kube/bookinfo.yaml
```

(`istio-current` is the symlink the setup script created.)

About 12 Pods come up — productpage, details, ratings, and
three reviews versions, each with 2 containers (app + sidecar).
Give it 1-2 minutes.

```bash
kubectl get pods
kubectl get svc
```

### Expose via the ingress gateway

`bookinfo-gateway.yaml` creates a `Gateway` (which configures
the ingress gateway to listen on a host/port) and a
`VirtualService` (which routes traffic from the Gateway to the
productpage Service):

```bash
kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/networking/bookinfo-gateway.yaml
```

Verify config is clean:

```bash
istioctl analyze
```

### Reaching Bookinfo

Under rootless podman (same situation as §7), the ingress
gateway's IP isn't host-routable. Two ways to reach it:

**Option A: kubectl port-forward** (consistent with §6/§9):

```bash
kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80
```

Then in another terminal:

```bash
curl http://127.0.0.1:8080/productpage
```

**Option B: minikube tunnel** (Istio's documented approach):

```bash
minikube tunnel -p istio   # leave running in another terminal
# Then look up the ingress gateway's external IP
INGRESS_HOST=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://${INGRESS_HOST}/productpage
```

The demo uses Option A — simpler, doesn't need a second
terminal. For interactive exploration, Option B + a browser
gives the cleaner experience.

Either way, refresh the page a few times. The reviews section
cycles through three versions (no ratings, black stars, red
stars) because the default routing is round-robin.

## Traffic management

This is where Istio earns its keep. The `samples/bookinfo/networking/`
directory has manifests for the common patterns.

### Pin everything to v1

First, define `DestinationRule`s that name the three subsets of
the reviews Service:

```bash
kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/networking/destination-rule-all.yaml
```

Then a `VirtualService` that sends 100% of reviews traffic to
v1:

```bash
kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/networking/virtual-service-all-v1.yaml
```

Refresh the productpage a few times. The reviews section is now
**always no-ratings** (v1). The other versions are still running
— they're just not getting traffic.

### 50/50 between v1 and v3

```bash
kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
```

Refresh a dozen times. Roughly half show no ratings (v1), half
show red stars (v3). This is the **canary release** pattern:
deploy v3 alongside v1, route a fraction of traffic to it, watch
the metrics, gradually shift more traffic.

### Fault injection

Istio can synthesize problems for testing — useful for verifying
that your app handles upstream failures gracefully.

Add a 7-second delay to all calls hitting ratings:

```bash
kubectl apply -f ~/.local/share/istio-current/samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml
```

Refresh the productpage. The ratings panel takes 7 seconds to
appear (or times out and shows an error, depending on the
productpage's timeout). The slowness is **synthetic, configured
in Istio**, not actually slow code.

Other patterns the same directory has manifests for (worth
exploring on your own):

- HTTP 500 abort injection
- Header-based routing (route different users to different
  versions)
- Timeouts and retries

## Observability: the addons

Istio doesn't include Kiali / Prometheus / Grafana / Jaeger
by default, but ships sample manifests for them:

```bash
kubectl apply -f ~/.local/share/istio-current/samples/addons/
```

~5 minutes to come up. Then:

```bash
istioctl dashboard kiali
```

Opens Kiali in your browser. The most useful view is the
**service graph** — visualize the entire mesh as a directed
graph of Services, with live traffic rates and golden signals on
each edge. The current routing rules show up as colored edges
(green for healthy, red for errors). Apply the 50/50 split rule
and you'll see the traffic visibly diverge in real time.

Other dashboards:

- `istioctl dashboard prometheus` — raw metrics
- `istioctl dashboard grafana` — pre-built Istio dashboards
- `istioctl dashboard jaeger` — distributed traces

The addons are **not part of the §11 demo** because they take 5+
minutes to come up and aren't critical for the routing exercises.
Install them when you want the visual feedback; uninstall with
`kubectl delete -f ~/.local/share/istio-current/samples/addons/`.

## Cleanup

The §11 demo's trap cleans up Bookinfo, our nginx, and the
routing rules. To uninstall Istio itself:

```bash
istioctl uninstall --purge -y
kubectl delete namespace istio-system
kubectl label namespace default istio-injection-
```

To stop the istio profile:

```bash
minikube stop -p istio
```

Or delete it entirely:

```bash
minikube delete -p istio
```

## Verification: examples/11-istio/

`examples/11-istio/demo.sh` runs the §11 happy path:

1. Pre-flight: istio profile up; kubectl context is `istio`;
   istioctl in PATH; ISTIO_DIR symlink exists
2. Build `nginx-custom:v1` in the istio profile (image cache
   doesn't carry across profiles)
3. Install Istio if not already installed (`istioctl install`)
4. Label `default` namespace for injection
5. Deploy our nginx-with-sidecar; verify 2/2 containers
6. Deploy Bookinfo; wait for all Pods to be Ready
7. Apply the Gateway + VirtualService
8. Port-forward the ingress gateway; curl `/productpage`;
   verify the response contains expected markers (e.g. the
   "Bookinfo Sample" heading)
9. Apply destination rules + all-v1 routing; curl productpage
   N times; verify no v2/v3 stars appear
10. Apply 50/50 split; curl productpage 20 times; count how
    many responses contain `glyphicon-star` (v3) — should be
    roughly 8-12 of 20 if split is working
11. Cleanup all bookinfo and nginx resources on exit (trap)

Restoring kubectl context to `minikube` (the §6-§9 profile)
happens in the trap too.

```bash
cd examples/11-istio
./demo.sh
```

Expected duration: **5-10 minutes** for the full run. Most of it
is Bookinfo Pod startup and waiting for sidecars to be ready.
First run after `setup-istio.sh` adds 2-4 minutes for the
nginx-custom image build on the new profile.

This is the longest single demo in the tutorial. The phases are
idempotent — re-running picks up where the cluster state left
off.

[On to §12: KEDA →]({{ "/docs/12-keda/" | relative_url }})
