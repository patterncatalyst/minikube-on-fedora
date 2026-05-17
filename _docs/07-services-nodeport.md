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

Here's where the story branches by how your minikube driver
networks the cluster node — and where my earlier framing in this
section had a subtle bug worth calling out, because it shapes how
the rest of the tutorial talks about Service exposure.

### The two cases

In a real-world or production Kubernetes cluster, every node has
an IP your client can reach. NodePort works by opening a port on
each of those node IPs. In minikube, "each node IP" means the one
minikube node, and whether that IP is reachable from your host
depends on the driver:

- **Host-routable node IP** — rootful podman (with bridge
  networking), kvm2, virtualbox. The minikube node IP (typically
  `192.168.49.2` for podman, `192.168.39.x` for kvm2) is on a
  network bridge your host can reach. `curl http://<minikube
  ip>:30808/` works directly
- **Non-routable node IP** — **rootless podman (our default)**,
  qemu, macOS with the docker driver, Podman Desktop's VM. The
  cluster lives in a user network namespace (slirp4netns or
  pasta for rootless podman) or behind a hypervisor; the IP
  exists but isn't on a bridge your host can reach. `curl` to
  the node IP fails with "no route to host" or hangs

Our §1 prerequisites and §3 startup both put us firmly in the
**rootless podman** camp — that's the right default for Fedora
(no kernel modules to load, no privilege escalation). So the
non-routable case applies to this tutorial throughout. NodePort
still works inside the cluster; it just needs a tunnel to be
reached from your host shell.

### `minikube service <name> --url` — the right tool

`minikube service` knows which case applies and handles both:

```bash
minikube service nginx-np --url
```

In the **host-routable** case, it prints the URL and exits:

```
http://192.168.49.2:30808
```

In our **non-routable** (rootless) case, it sets up an auto-tunnel
via the equivalent of `kubectl port-forward`, prints a localhost
URL once the tunnel is up, and **keeps running** until you Ctrl-C
it:

```
🏃  Starting tunnel for service nginx-np.
|-----------|----------|-------------|------------------------|
| NAMESPACE |   NAME   | TARGET PORT |          URL           |
|-----------|----------|-------------|------------------------|
| default   | nginx-np |             | http://127.0.0.1:42367 |
|-----------|----------|-------------|------------------------|
http://127.0.0.1:42367
❗  Because you are using a Docker driver on linux, the terminal
needs to be open to run it.
```

Tunnel setup is 20-30 seconds on first run. The URL works from the
moment the tunnel is up until you Ctrl-C the `minikube service`
process.

For scripting, run it in the background and watch its stdout for
the URL line — that's exactly what the §7 demo does. The pattern
is the same one §6's demo uses for `kubectl port-forward`.

### Other approaches and when they apply

- **`minikube ip` + the NodePort directly** — `curl
  "http://$(minikube ip):30808/"`. Works on rootful podman, kvm2.
  Hangs on rootless podman because the IP isn't routable
- **`minikube service <name>` (no `--url`)** — opens the URL in
  your browser. Convenient interactively; useless for scripts.
  Same auto-tunnel behavior under rootless
- **`minikube tunnel`** (separate command, not to be confused with
  the `--url` auto-tunnel) — sets up a LoadBalancer-style tunnel
  that grants reachability to all cluster Service IPs at once,
  not just one NodePort. Runs as a long-lived process. Useful
  when you have several services to expose; overkill for a single
  NodePort
- **`kubectl port-forward`** (§6's pattern) — works regardless of
  driver/networking, because it tunnels through the kube-apiserver
  rather than relying on host-cluster routing. The most portable
  fallback when none of the above work

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
