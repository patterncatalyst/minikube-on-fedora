---
title: Services and NodePort
order: 7
description: Service types compared, NodePort mechanics, and how minikube publishes NodePorts to host loopback so no helper process is needed.
duration: 20 minutes
---

§6 exposed nginx through a `ClusterIP` Service — reachable from
inside the cluster only. §6's own Service already used the type this
section explains: **NodePort**, a Service type that opens a port on
every node and makes the workload reachable from outside the cluster.

By the end you'll know when to reach for NodePort vs ClusterIP vs
LoadBalancer, how the `minikube` profile publishes NodePorts to
`127.0.0.1` on your host, and which gotchas are worth knowing before
NodePort touches a real network. Commands assume the `minikube`
kubectl context from §4.

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

The default is `ClusterIP`. This section is NodePort. LoadBalancer
requires cloud integration (an external load-balancer controller)
that a local minikube node does not have; a `LoadBalancer` Service
there keeps `<pending>` as its external IP, though it still gets a
nodePort. Ingress is a different resource type — separate from
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
`minikube -p minikube ip` returns its IP (typically `192.168.49.2`
on the docker driver).

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
    # Pinned for predictability. Omit nodePort to let Kubernetes
    # pick one from 30000-32767. 30808 chosen for memorability —
    # ":8080 on every node, prefixed 30".
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
same `nginx-custom:v1` image (`imagePullPolicy: Never`, loaded in
§6), same probes and resources.

Apply both manifests:

```bash
kubectl apply -f examples/07-nodeport-service/manifests/
```

## Publishing NodePorts to host loopback

A NodePort listens on the minikube node, which on the docker driver
is a container. Docker Engine can publish that container's ports to
the host, and minikube exposes the mechanism as `--ports` on
`minikube start`:

```bash
minikube start -p minikube --driver=docker --container-runtime=containerd \
  --kubernetes-version=v1.35.1 \
  --ports=127.0.0.1:18080:30080,127.0.0.1:18081:30808,127.0.0.1:18090:30900
```

Each entry is `127.0.0.1:<hostPort>:<nodePort>`. Traffic to the host
loopback port lands on the node's NodePort, and kube-proxy routes it
to a matching Pod. Binding to `127.0.0.1` keeps the ports private to
your machine. Nothing runs in the foreground, and nothing
disconnects.

Two properties follow from Docker publishing the ports:

- **The mapping is fixed at creation.** Docker cannot add a published
  port to an existing container. Adding a mapping means recreating the
  profile: `minikube delete -p minikube`, then `minikube start` again
  with the extended `--ports` list. The scripts in this repository
  create the `minikube` profile with the full list below, and their
  preflight checks tell you the exact recreate command if a port is
  missing
- **Verify what is published** with `docker port`:

```bash
docker port minikube 30808/tcp
```

```
127.0.0.1:18081
```

An empty answer means the profile lacks that mapping.

### The port map

The `minikube` profile publishes three ports
(`CORE_PORTS` in `scripts/lib/_helpers.sh`):

| Host port       | nodePort | Used by                                                          |
|-----------------|----------|------------------------------------------------------------------|
| `127.0.0.1:18080` | 30080  | §6, §8, §9, §12 (http): one at a time, they share the slot       |
| `127.0.0.1:18081` | 30808  | §7 (`nginx-np`)                                                  |
| `127.0.0.1:18090` | 30900  | §5 dashboard companion Service                                   |

Slot 30080 is shared on purpose: a nodePort can belong to only one
Service. Each demo's preflight fails with "delete X first" if another
Service already holds it.

### Using it

With the Service from this section applied:

```bash
curl http://127.0.0.1:18081/
```

You should see the baked-in page ("Test Page for nginx on UBI 10
Minimal"). The same request works from a script, a browser, or an
editor's REST client, with no URL to discover and no process to keep
alive.

### Other ways in, and why they are not used

<!-- policy-exempt:start -->
`minikube service` and `minikube tunnel` both need a foreground
process on the host, and they stop working when that terminal or SSH
session disconnects. The same goes for `kubectl port-forward`.
Published ports are held by Docker, so they survive. A `LoadBalancer`
Service would need `minikube tunnel` to receive an external IP, so
this tutorial uses NodePort for everything host-facing.
<!-- policy-exempt:end -->

- **The node IP directly.** `curl "http://$(minikube -p minikube
  ip):30808/"` works on the docker driver from the host. The address
  changes when the profile is recreated, and it is not reachable from
  other machines or VMs, so the loopback ports are the stable choice
- **Ingress.** HTTP routing by host and path through the `ingress`
  addon; a different resource, noted in §9

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

- **`LoadBalancer` Services** — cloud providers front the Service
  with a real load balancer
- **Ingress** — host- and path-based HTTP routing via the
  `ingress` addon you enabled in §5

We'll touch ingress when §9 deploys a chart that uses it.

## Cleanup

```bash
kubectl delete -f examples/07-nodeport-service/manifests/
```

Deletes Deployment and Service. The image `nginx-custom:v1` stays
loaded in the node (built in §6, shared here).

## Verification: examples/07-nodeport-service/

`examples/07-nodeport-service/demo.sh` runs the §7 happy path:

1. Pre-flight: checks Docker Engine, ensures the `minikube` profile
   with its published ports, and pins the kubectl context. If
   `nginx-custom:v1` isn't loaded yet (e.g. you haven't run §6's demo),
   it builds it from §6's Containerfile with `docker build` and loads
   it with `minikube -p minikube image load`
2. Clears any prior `nginx-np` resources
3. Applies the manifests
4. Waits for the Deployment to be `Available` (dumps pod logs on
   timeout, same pattern as §6)
5. Confirms `docker port minikube 30808/tcp` shows 127.0.0.1:18081
6. Curls `http://127.0.0.1:18081/`, checks for the sentinel string
   from the baked-in index.html
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
