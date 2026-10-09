---
title: "§7 nodeport service"
order: 7
example_dir: examples/07-nodeport-service
permalink: /examples/07-nodeport-service/
layout: tutorial
---

**Source:** [`examples/07-nodeport-service/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/07-nodeport-service) &middot; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})

Exposes the §6 nginx workload through a second **NodePort Service**,
`nginx-np`, on nodePort `30808`. The educational point is "this Service
exposes the workload outside the cluster". On the Docker driver the
minikube node is a container, so the port has to be published on the
host when that container is created. The default profile does this with
`--ports=127.0.0.1:18081:30808` (the `CORE_PORTS` map in
`scripts/lib/_helpers.sh`), so the Service answers at
`http://127.0.0.1:18081/` with no foreground process.

## What it tests

Six §7 claims:

1. The `nginx-custom:v1` image is loaded in the cluster (built with
   `docker build` from §6's Containerfile and loaded with
   `minikube image load` if missing, automatically)
2. `kubectl apply -f manifests/` ships both the Deployment and
   NodePort Service cleanly
3. The Deployment reaches `Available` within 3 minutes
4. `docker port minikube 30808/tcp` shows `127.0.0.1:18081`, so the
   nodePort is published on the host
5. `curl http://127.0.0.1:18081/` succeeds: the published port reaches
   the node, and kube-proxy routes nodePort 30808 to a ready Pod
6. The response contains the sentinel string from §6's baked-in
   index.html

## Published ports, briefly

Docker publishes container ports when the container is created, and
they cannot be added later. `minikube start` with `--ports` therefore
carries every host-facing NodePort the tutorial uses:

| Host | NodePort | Used by |
|---|---|---|
| `127.0.0.1:18080` | 30080 | §6, §8, §9 (one at a time) |
| `127.0.0.1:18081` | 30808 | §7 (this example) |
| `127.0.0.1:18090` | 30900 | §5 dashboard |

The demo calls `ensure_profile`, which creates the `minikube` profile
with that map when it is absent and otherwise checks that every mapping
is present. If the check fails, the demo prints the delete-and-recreate
command; the mapping cannot be patched onto a running profile.

<!-- policy-exempt:start -->
`minikube service` and `minikube tunnel` are not used. Both need a
foreground process that disconnects when the terminal does.
<!-- policy-exempt:end -->

## Running

```bash
./demo.sh
```

Expected duration:

- **If §6 has been run** (image loaded): about 15-30 seconds
- **First time** (image build needed): 2-4 minutes

## What you should see

`==> step` lines for each phase, ending in:

```
==> SUCCESS — NodePort Service for nginx-np reachable at http://127.0.0.1:18081

  The NodePort was published when the profile was created:
    --ports=127.0.0.1:18081:30808  (host :18081 -> node :30808)
```

## Cluster scope

Uses the **default minikube cluster** (the `minikube` profile), same
as §6, and pins every `kubectl` call to that context. The §7
Deployment and Service use distinct names (`nginx-np` instead of
`nginx`) and labels (`app: nginx-np`), and a different nodePort, so
they can coexist with §6's resources.

## Cleanup

`demo.sh` installs a `trap cleanup EXIT` that deletes the Deployment
and Service. `nginx-custom:v1` stays loaded in the cluster.

Manual cleanup if needed:

```bash
kubectl --context minikube delete -f manifests/ --ignore-not-found=true
```

## When this fails

1. **`profile 'minikube' does not publish nodePort 30808`** — the
   profile was created without `--ports`. Run the delete-and-recreate
   command the script prints
2. **`cannot publish ports for profile`** — another process holds
   host port 18080, 18081 or 18090. Free it and re-run
3. **`curl` returns no response** — the port is published but the
   Service has no ready endpoints. `kubectl --context minikube get
   endpoints nginx-np` should list Pod IPs; if empty, the selector
   isn't matching any ready Pod
4. **`curl` returns wrong content** — pods responding but content
   differs from expected. Compare `kubectl exec` into a Pod with
   what's actually being served

For any of these, paste the failing output back.
