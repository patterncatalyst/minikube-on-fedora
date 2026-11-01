---
title: "Service Discovery"
order: 16
part: "Behavioral"
description: "Reach a workload by a name that outlives any specific Pod: ClusterIP, NodePort, and LoadBalancer Services, kube-dns, and path-based routing through an Ingress."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what a `Service` provides: a stable name and virtual address in front of a changing set of Pods
- Compare `ClusterIP`, `NodePort`, and `LoadBalancer` Service types and know which audience each one is reachable from
- Trace how kube-dns resolves a Service name to its virtual IP without the caller ever learning a Pod IP
- Route multiple backends through one address with an `Ingress`, and explain what it adds beyond a Service alone

## Why this matters

Every chapter in this appendix so far has used a Service without stopping to name what it is. `shipping-service`, `order-service`, and `graphql-gateway` were all reached by name, never by Pod IP, and that worked precisely because a Service exists between the caller and the Pods doing the work. Stateless Service and Stateful Service both depend on this layer without describing it directly: a stateless Deployment can replace a Pod with a brand-new IP address *because* nothing outside the cluster was ever calling that IP directly in the first place. Service Discovery is the pattern that makes every other pattern's "any replica can serve any request" claim hold up in practice, by giving the cluster a name that survives individual Pods coming and going.

The example works through all three Service types plus an Ingress, reaching `order-service`, `inventory-service`, and `graphql-gateway` by name throughout, to make the contrast between "reachable from where" concrete rather than abstract.

## ClusterIP: the default, and the one most workloads need

```yaml
apiVersion: v1
kind: Service
metadata:
  name: order-service
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: order-service
  ports:
    - port: 80
      targetPort: 8080
```

A `ClusterIP` Service gets a stable virtual IP, assigned from the cluster's internal Service CIDR, reachable only from inside the cluster. It is not a Pod IP and not associated with any single node; kube-proxy (or an eBPF-based dataplane doing the equivalent job) programs every node to route traffic addressed to that virtual IP toward one of the Service's currently-matching, currently-ready Pods, chosen by whatever load-balancing algorithm the dataplane implements. This is the type every Service in this appendix has defaulted to when the `type` field was left unset, and it's the right default for the overwhelming majority of in-cluster traffic: `graphql-gateway` never needs to be reachable from outside the pod network to call `order-service`, so there's no reason to give `order-service` more exposure than that.

## NodePort: reachable from outside, through every node

```yaml
apiVersion: v1
kind: Service
metadata:
  name: inventory-service
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: 8080
      nodePort: 30180
```

A `NodePort` Service does everything a `ClusterIP` does and additionally opens the same port (`30180` here, from the default `30000`–`32767` range) on *every node's own IP address*, cluster-wide, regardless of whether that specific node happens to be running one of the Service's Pods. A request landing on any node's `30180` gets routed internally to a matching Pod wherever it lives, which is what makes this reachable from outside the cluster with nothing more than a node's address: `curl http://$(minikube ip):30180/health` reaches `inventory-service` with no additional infrastructure. That convenience is also the type's limitation in production: a real cluster rarely wants every node's raw IP and a hardcoded port range exposed directly, which is why `NodePort` is more often a building block (what a cloud `LoadBalancer` type ultimately routes traffic into) than a type end users are meant to call directly.

![Services of three types in front of order-service, inventory-service, and graphql-gateway, with an Ingress routing by path through a single address]({{ "/assets/diagrams/appendix-16-service-discovery.svg" | relative_url }})
*A caller always reaches a Service name or address, never a Pod IP directly: kube-dns and kube-proxy make that substitution invisible.*

## LoadBalancer: what a cloud provisions, and what minikube simulates

```yaml
apiVersion: v1
kind: Service
metadata:
  name: graphql-gateway
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
```

On a real cloud, requesting `type: LoadBalancer` triggers the cloud provider's own controller to provision an actual external load balancer (an AWS NLB, a GCP forwarding rule, and so on) and populate `status.loadBalancer.ingress` with its public address once ready. Minikube has no cloud provider underneath it to do any of that, so `kubectl get svc graphql-gateway` shows `EXTERNAL-IP: <pending>` indefinitely on its own. `minikube tunnel` fills that gap for local development: it runs a process on the host that routes a local address to the Service, standing in for what a real cloud's load-balancer controller would otherwise do, so the `LoadBalancer` type behaves the same way functionally even though no managed cloud load balancer exists underneath it at all. The Service manifest itself never changes between a real cloud and minikube; only what provisions the external address does.

## kube-dns: the layer that makes a name resolve

Every call in this chapter's example reaches its target by Service name, never by IP, and that's kube-dns's job specifically. Every Service gets an A record at `<service-name>.<namespace>.svc.cluster.local` automatically, resolving to that Service's `ClusterIP` (or, for a headless Service as the Stateful Service chapter showed, to the backing Pods' own IPs directly instead). `graphql-gateway`'s own configuration shows the practical consequence:

```yaml
env:
  - name: ORDER_REST_URL
    value: http://order-service
  - name: INVENTORY_GRPC_ADDR
    value: inventory-service:50051
```

Neither value is a Pod IP, and neither has to change for the lifetime of the Deployment: `order-service` resolves fresh via kube-dns on every call `graphql-gateway` makes, so a Pod restart on either end (a new IP, same name) never requires touching this configuration. Within the same namespace the short name (`order-service`) is enough, because kube-dns's search path tries the current namespace first; reaching across namespaces needs the fuller `order-service.other-namespace.svc.cluster.local` form, since the short name would otherwise resolve (or fail to resolve) against the caller's own namespace instead.

## Ingress: one address, routed by path

A Service solves "reach this one backend by a stable name." An `Ingress` solves a related but distinct problem: exposing several backends through a single external address, routed by HTTP-layer rules an L4 Service has no concept of at all.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: patterns-gateway
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /graphql
            pathType: Prefix
            backend:
              service:
                name: graphql-gateway
                port:
                  number: 80
          - path: /health
            pathType: Exact
            backend:
              service:
                name: order-service
                port:
                  number: 80
```

An `Ingress` object on its own does nothing; `ingressClassName: nginx` tells the cluster which Ingress controller (here, the `ingress` addon's bundled ingress-nginx, enabled separately with `minikube addons enable ingress`) watches this object and programs itself accordingly. Once it does, one address serves both rules: `/graphql` reaches `graphql-gateway`'s own GraphQL endpoint, and `/health` reaches `order-service`'s liveness endpoint, both without the caller needing to know either Service's internal name, `ClusterIP`, or port. This example's manifest sets no `rewrite-target` annotation at all. Without one, ingress-nginx forwards the matched path unchanged to the backend, so each rule above points at a path that really does exist on that specific backend. A rule routing `/orders` to `order-service` without a corresponding rewrite would forward the literal path `/orders` to a service that only answers `/health` and `/healthz`, precisely the kind of path-matching mistake an `Ingress` manifest with a rewrite can mask and one without it cannot.

`pathType: Prefix` versus `pathType: Exact` governs how strictly a rule matches: `Prefix` matches the given path and anything below it (`/graphql`, `/graphql/anything`), while `Exact` matches only that literal path and nothing else, which is why the `/health` rule uses `Exact` rather than letting an unrelated path like `/health-check` accidentally match a prefix rule that was only ever meant to catch the one literal endpoint.

## Endpoints: what a Service's selector produces

A Service's `selector` doesn't route traffic by itself: it's the input to a separate, automatically managed object, an `EndpointSlice` (the modern, scalable successor to the older single `Endpoints` object), that lists the real IP:port pairs of every currently-matching, currently-ready Pod. kube-proxy watches these, not the Service's selector directly, to program each node's routing rules:

```bash
kubectl get endpointslices -n patterns -l kubernetes.io/service-name=order-service
```

Checking this directly is the fastest diagnostic the first time a Service "isn't working" despite its Pods looking healthy in `kubectl get pods`: an empty `EndpointSlice` on a perfectly correct-looking Service almost always means the selector's labels don't match the Pod template's labels, a typo that `kubectl describe service` surfaces as zero endpoints with no further explanation. A Service with no selector at all is also valid and has a real use: it produces no automatic `EndpointSlice`, leaving the addresses to be managed manually or by an external mechanism, which is the pattern behind pointing a Service at a workload that isn't running as Kubernetes Pods at all (a database running outside the cluster, reached through a manually maintained `Endpoints` object carrying its real address).

## ExternalName: a different kind of indirection

One Service type this chapter's example doesn't use still belongs in the full set: `type: ExternalName` returns a `CNAME` record pointing at an arbitrary external DNS name, with no `ClusterIP`, no selector, and no `EndpointSlice` involved at all.

```yaml
spec:
  type: ExternalName
  externalName: reporting.example.com
```

It solves a narrower problem than the other three types: giving an external dependency (a SaaS API, a database hosted outside the cluster) a cluster-internal name that's consistent with how every in-cluster dependency is already addressed, so an application never needs to know whether `payments-provider` resolves to a Pod inside the cluster or a service running somewhere else entirely. None of the shipping services in this appendix's examples need it, since every dependency so far has been another workload running on the same `mof-patterns` profile, but it rounds out the full set of Service types a CKAD candidate should recognize by name and behavior, not just the three this chapter demonstrates live.

> **🎓 CKAD exam lens**
>
> **Domain:** Services & Networking (20%)
> **Competency:** Understand Services (ClusterIP, NodePort, LoadBalancer), DNS resolution, and Ingress path-based routing
> **Drill:** `kubectl get svc -n patterns order-service inventory-service graphql-gateway -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP`

> **🤖 Explore with your agent**
>
> "Add a second Ingress rule routing /inventory to inventory-service's own /healthz endpoint, apply it, and show me the exact curl command that reaches it through the single Ingress address."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f service-discovery/04-ingress.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/03-gateway.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/02-inventory-service.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/01-order-service.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/00-postgres.yaml
```

## Verification: examples/appendix-patterns/service-discovery/

The runnable example stands up `order-service` behind a `ClusterIP`, `inventory-service` behind a `NodePort`, and `graphql-gateway` behind a `LoadBalancer` (simulated with `minikube tunnel`), confirms DNS resolution between them, then layers an `Ingress` on top routing two distinct paths to two distinct backends through one address. Full walkthrough in `examples/appendix-patterns/service-discovery/README.md`.
