---
title: "§7 nodeport service"
order: 7
example_dir: examples/07-nodeport-service
permalink: /examples/07-nodeport-service/
layout: tutorial
---

**Source:** [`examples/07-nodeport-service/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/07-nodeport-service) &middot; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})

Exposes the §6 nginx workload through a **NodePort Service** instead
of ClusterIP. The educational point is "this Service exposes the
workload externally"; the operational reality under rootless podman
is that minikube auto-tunnels the NodePort to a localhost URL,
because the cluster container's IP lives in a user network
namespace that isn't host-routable.

## What it tests

Six §7 claims:

1. The `nginx-custom:v1` image is available in the cluster's image
   cache (built from §6's Containerfile if missing — automatic)
2. `kubectl apply -f manifests/` ships both the Deployment and
   NodePort Service cleanly
3. The Deployment reaches `Available` within 3 minutes
4. `minikube service nginx-np --url` returns a host-reachable URL
   (a `127.0.0.1:<random-port>` auto-tunnel URL under rootless
   podman; would be `http://<minikube ip>:30808` directly under
   rootful podman or kvm2)
5. Curling that URL from the host shell succeeds — kube-proxy is
   wired to the NodePort, the tunnel reaches kube-proxy
6. The response contains the sentinel string from §6's baked-in
   index.html

## The tunnel, briefly

`minikube service <name> --url` works in two modes depending on
whether the cluster IP is host-routable:

- **Routable** (rootful podman, kvm2 with bridge networking):
  returns `http://<node IP>:<NodePort>` instantly, no tunnel
- **Not routable** (rootless podman — our default — plus macOS,
  qemu, Podman Desktop's VM): starts a tunnel, prints
  `http://127.0.0.1:<random-port>` once the tunnel is up, holds
  the process open until SIGINT

The demo runs `minikube service --url` in the background and
watches its output for the URL line. Cleanup kills the tunnel
process on exit. This is the same pattern §6's demo uses for
`kubectl port-forward`.

## Running

```bash
./demo.sh
```

Expected duration:

- **If §6 has been run** (image cached) and rootless podman:
  ~25-50 seconds (most of it tunnel setup)
- **First time** (image build needed): 2-4 minutes
- **Rootful podman / kvm2** (no tunnel): ~10 seconds total

## What you should see

`==> step` lines for each phase, ending in something like:

```
==> SUCCESS — NodePort Service for nginx-np reachable at http://127.0.0.1:42367

  Under rootless podman, minikube auto-tunneled the NodePort to
  a localhost port (the cluster IP isn't host-routable from the
  user network namespace). With rootful podman or kvm2 the URL
  would be http://<minikube ip>:30808 directly — no tunnel.
```

The exact tunnel port (`42367` above) is randomly assigned by the
auto-tunnel; the NodePort `30808` on the cluster side is pinned in
the manifest.

## Cluster scope

Uses the **default minikube cluster** (the `minikube` profile),
same as §6. The §7 Deployment and Service use distinct names
(`nginx-np` instead of `nginx`) and labels (`app: nginx-np`) so
they can coexist with §6's resources without selector confusion.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that:

1. Kills the background `minikube service` tunnel process
2. Sweeps any lingering `minikube service nginx-np` children with
   `pkill` (defensive — some minikube builds spawn helper processes)
3. Deletes the Deployment and Service
4. Removes the tunnel log temp file

`nginx-custom:v1` stays in the cluster's cache.

Manual cleanup if needed:

```bash
pkill -f 'minikube service nginx-np' 2>/dev/null || true
kubectl delete -f manifests/ --ignore-not-found=true
```

## When this fails

1. **`minikube service` exits before printing a URL** — the tunnel
   couldn't be established. Most likely cause: the Service has no
   ready endpoints (Pods aren't actually responding on `:8080`).
   `kubectl get endpoints nginx-np` should show the Pod IPs; if
   empty, the Service selector isn't matching any ready Pod
2. **Tunnel doesn't establish within 90s** — first-time tunnel
   setup can be slow if kube-proxy is still wiring things up.
   `kubectl get pods -n kube-system -l k8s-app=kube-proxy` shows
   kube-proxy state. If that's healthy, the demo's
   `TUNNEL_WAIT_SECONDS=90` constant can be bumped
3. **`curl` returns no response from the tunnel URL** — tunnel is
   up but isn't reaching the Service. Often a kube-proxy mode
   issue (iptables vs ipvs); rare on a fresh minikube
4. **`curl` returns wrong content** — pods responding but content
   differs from expected. Compare `kubectl exec` into a Pod with
   what's actually being served

For any of these, paste the failing output back.
