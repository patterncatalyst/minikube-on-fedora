---
title: Services and NodePort
order: 7
description: Service types compared, NodePort mechanics, and how to reach the cluster from your host without port-forwarding.
duration: 20 minutes
---

§6 exposed nginx through a `ClusterIP` Service — reachable from
inside the cluster, requiring `kubectl port-forward` to hit from
your host. This section is the next step up: **NodePort**, a Service
type that opens a port on every node and makes the workload
reachable from outside the cluster directly, no tunneling.

By the end you'll know when to reach for NodePort vs ClusterIP vs
LoadBalancer, how minikube specifically returns a URL you can hit,
and which gotchas are worth knowing before NodePort touches a real
network.

## Service types: a tour

Kubernetes Services come in several types. The chart of what each
provides:

| Type             | Reachable from                                    | Typical use                                                  |
|------------------|---------------------------------------------------|--------------------------------------------------------------|
| **ClusterIP**    | Inside the cluster only                            | Internal service-to-service communication                    |
| **NodePort**     | Inside the cluster + `<nodeIP>:<nodePort>`         | Quick external access for testing, internal admin endpoints  |
| **LoadBalancer** | Same as NodePort + an external load-balancer IP    | Production external access (cloud-provided LB)              |
| **ExternalName** | A DNS `CNAME` — no real service                    | Map a Kubernetes name to an external DNS                     |
| (Headless)       | DNS-resolves directly to Pod IPs, no virtual IP    | StatefulSets, direct Pod addressing                          |

The default is `ClusterIP`. We covered ClusterIP in §6; this
section is NodePort. LoadBalancer requires cloud integration that
minikube partly emulates via `minikube tunnel` (briefly noted
below). Ingress is a different resource type — separate from
Services — and gets attention via the `ingress` addon you enabled
in §5; §9 helm work uses it.

## NodePort mechanics

A NodePort Service:

- Has a ClusterIP (just like a ClusterIP Service) — internal access
  still works
- **Additionally** opens a TCP port on every node in the cluster
- Forwards traffic from `<any node's IP>:<nodePort>` to the
  Service's endpoints, which are the matching Pods

The default port range is **30000-32767**. You can let Kubernetes
assign one for you, or pin a specific port — the manifest below
shows the pin pattern.

In a multi-node cluster, the NodePort works on *every* node — you
can hit it via any node's IP, not just the node a Pod happens to
be running on. `kube-proxy` handles routing. For our single-node
minikube cluster, "every node" means the one minikube node;
`minikube ip` returns its IP (typically `192.168.49.2` under the
podman driver).

## Writing a NodePort Service

`examples/07-nodeport-service/manifests/service-nodeport.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-np
  labels:
    app: nginx-np
spec:
  type: NodePort
  selector:
    app: nginx-np
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30808
    protocol: TCP
```

Two new fields compared to §6's ClusterIP Service:

- **`type: NodePort`** — selects the NodePort behavior
- **`nodePort: 30808`** — pins the cluster-side port. If omitted,
  Kubernetes picks one in the 30000-32767 range. Pinning is useful
  for documentation and predictability; auto-allocation is useful
  for avoiding conflicts in a busy cluster

The Deployment in this example uses the name and label `nginx-np`
(not the `nginx` from §6) so the two examples can coexist without
either selector accidentally matching the wrong Pods. Otherwise
the Deployment is identical to §6 — same multi-stage Containerfile,
same `nginx-custom:v1` image, same probes and resources.

Apply both manifests:

```bash
kubectl apply -f examples/07-nodeport-service/manifests/
```

## Reaching the NodePort

Three patterns, listed in order of preference for minikube on Linux:

### 1. `minikube service <name> --url`

The cleanest path. minikube knows about its own node IPs and
assembles the URL:

```bash
minikube service nginx-np --url
```

On Linux with the podman driver, you'll see something like:

```
http://192.168.49.2:30808
```

Hit it:

```bash
curl http://192.168.49.2:30808/
```

You should see the same baked-in nginx page from §6 — same image,
just a different way of reaching it.

### 2. `minikube ip` + the nodePort

If you'd rather construct the URL yourself:

```bash
curl "http://$(minikube ip):30808/"
```

Same result, slightly more explicit about what's happening.

### 3. `minikube service <name>` (without `--url`)

Opens the URL in your default browser. Convenient for interactive
debugging; less useful for scripts.

### A note about macOS and Podman Desktop's VM

On macOS — or on Linux with the qemu driver — the minikube node
lives inside a VM whose IP isn't directly routable from your host.
In that case:

- `minikube service <name> --url` still returns a working URL, but
  it's `127.0.0.1:<random-port>` from a tunnel minikube auto-starts
- The tunnel persists until you Ctrl-C `minikube service`
- For scripts, the URL from stdout still works; you just need to
  keep the parent `minikube service` process alive

The §1 hardware section called out Fedora-on-Linux as the primary
tested platform; the macOS path is conceptually identical but the
URL is a tunnel, not a direct IP.

## NodePort gotchas

Three things worth knowing.

### 1. The 30000-32767 range is enforced

Try to pin `nodePort: 80` or `nodePort: 8080` and Kubernetes
rejects the manifest:

```
Invalid value: 80: provided port is not in the valid range. The
range of valid ports is 30000-32767.
```

This is a deliberate guardrail — privileged ports below 1024
require special handling, and ports 1024-29999 commonly clash
with applications running on your nodes (or your dev host).

To shift the range (rarely needed): the kube-apiserver flag
`--service-node-port-range`. minikube doesn't expose this directly;
you'd need to start minikube with `--extra-config=apiserver.service-node-port-range=...`.

### 2. NodePorts are cluster-wide

Every node listens on the chosen NodePort. The kube-proxy forwards
traffic to the right Pod regardless of which node received the
request, so you can hit any node's IP. But this means you can't
reuse the same NodePort across two Services pointing at different
Pods on different nodes — node ports are a cluster-wide resource.

### 3. NodePort isn't a great fit for production

NodePort gives you a numbered port URL with no DNS, no TLS
termination, no path-based routing, no virtual hosts. It works for
testing and internal admin endpoints. For real external traffic:

- **`LoadBalancer` Services** — cloud providers (or `minikube tunnel`
  in dev) front the Service with a real load balancer
- **Ingress** — host- and path-based HTTP routing via the
  `ingress` addon you enabled in §5

We'll touch ingress when §9 deploys a chart that uses it.

## Cleanup

```bash
kubectl delete -f examples/07-nodeport-service/manifests/
```

Deletes Deployment and Service. The image `nginx-custom:v1` stays
in the cluster's image cache (built in §6, shared here).

## Verification: examples/07-nodeport-service/

`examples/07-nodeport-service/demo.sh` runs the §7 happy path:

1. Pre-flight: cluster up; if `nginx-custom:v1` isn't already in
   the cluster's image cache (e.g. you haven't run §6's demo yet),
   it builds it from §6's Containerfile automatically
2. Clears any prior `nginx-np` resources
3. Applies the manifests
4. Waits for the Deployment to be `Available` (dumps pod logs on
   timeout, same pattern as §6)
5. Retrieves the URL via `minikube service nginx-np --url`
6. Curls the URL, checks for the sentinel string from the baked-in
   index.html
7. Cleans up Deployment + Service on exit (`trap`)

Run it:

```bash
cd examples/07-nodeport-service
./demo.sh
```

Expected duration: 25-40 seconds if §6's image is already cached;
add 2-4 minutes the first time if §6 hasn't run yet (the demo
will build the image automatically).

[On to §8: Persistent volumes →]({{ "/docs/08-persistent-volumes/" | relative_url }})
