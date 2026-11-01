---
title: "Network Segmentation"
order: 27
part: "Security"
description: "Deny all ingress to a service by default, allow only the one caller that legitimately needs it, and restrict egress to the destinations a workload talks to, with NetworkPolicy."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain why every Pod in a cluster can reach every other Pod by default, and why that default is the thing NetworkPolicy exists to change
- Write a default-deny `NetworkPolicy` scoped to one workload's Pods, rather than an entire namespace
- Allow ingress from one specific Pod selector while leaving every other source denied
- Restrict a workload's egress to the destinations it needs (DNS, its own database) and explain what a NetworkPolicy's selectors do and don't guarantee about traffic origin

## Why this matters

A freshly created Kubernetes cluster has no network segmentation at all: any Pod can open a connection to any other Pod's IP and port, across every namespace, with nothing in the cluster network layer checking whether that connection should be allowed. That flat network is convenient right up until one workload is compromised, at which point it's also the reason a single vulnerable container can reach every database, every internal API, and every other service in the cluster without needing to escalate privileges or move laterally through anything more sophisticated than a TCP connection. Network Segmentation is the pattern for closing that gap: a `NetworkPolicy` resource that tells the cluster's network layer which connections are allowed, with everything else denied by default once any policy selects a given Pod.

The "once any policy selects a given Pod" clause is the part worth sitting with. A `NetworkPolicy` is additive and Pod-scoped, not a single cluster-wide switch: a Pod with no `NetworkPolicy` selecting it is still fully open, exactly as if NetworkPolicy didn't exist, and a Pod that becomes the target of even one policy's `podSelector` flips to deny-by-default for whichever direction (ingress, egress, or both) that policy's `policyTypes` names, with only the rules that policy (and any other policy also selecting it) explicitly allow surviving. That's why this chapter's example writes a default-deny policy for `inventory-service`'s Pods specifically and a separate one for `payment-service`'s Pods specifically, rather than one sweeping policy with an empty `podSelector` that would deny-by-default for every Pod in the `patterns` namespace at once, including the Postgres container and every other chapter's example still running there.

`inventory-service`, `payment-service`, and `graphql-gateway` are the worked example. `graphql-gateway` is the legitimate caller: it federates reads by calling `inventory-service` over gRPC (the same real call its own resolver code makes), so this chapter's allow rule protects a connection the gateway's code actually makes, not a synthetic stand-in. `payment-service` has no legitimate caller at all yet in this codebase, which makes it the cleanest possible case for a service that should be fully isolated by default.

## The CNI prerequisite

NetworkPolicy is a Kubernetes API object, but enforcing it is the job of the cluster's Container Network Interface (CNI) plugin, not the API server. minikube's default CNI doesn't implement NetworkPolicy at all: applying a policy against it succeeds (the object is stored) but changes nothing about actual traffic, which is a confusing, silent way to fail this chapter's example. The `mof-patterns` profile needs Calico, set at profile creation:

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh --replace --calico
```

Confirm it landed before continuing:

```bash
kubectl --context mof-patterns get pods -n kube-system | grep calico
```

## Starting point: everything open

Before any `NetworkPolicy` exists, a disposable `curlimages/curl` test Pod in the same namespace can reach both `inventory-service` and `payment-service` on their container ports without restriction, which is worth confirming explicitly rather than assuming: it's the baseline this chapter's policies change, and it's the thing to re-check first if a policy later appears not to be working. `inventory-service` listens on a gRPC port, 50051, which doesn't speak HTTP, but `curl` can still probe TCP reachability against it: a connection that completes (even one the gRPC server immediately closes for speaking the wrong protocol) is a different outcome from a connection that times out, and that distinction is enough to prove whether a `NetworkPolicy` is blocking the network path at all.

## Default-deny, scoped to one workload

A `NetworkPolicy` with an empty `ingress` list and no rules at all denies every inbound connection to the Pods it selects, once its `policyTypes` includes `Ingress`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-inventory
  namespace: patterns
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: inventory-service
  policyTypes:
    - Ingress
```

`podSelector` is what keeps this scoped: only Pods carrying the label `app.kubernetes.io/name: inventory-service` are affected. Postgres, `payment-service`, `graphql-gateway`, and every other chapter's leftover Pods in `patterns` are untouched by this policy; only `inventory-service`'s own Pods flip to deny-all-ingress. `payment-service` gets the identical treatment in its own policy, scoped to its own label, and because nothing in this chapter grants `payment-service` an allow rule afterward, that one policy is the entire story for it: fully isolated, by design, until a real caller exists and earns an explicit rule.

## Allowing exactly one caller

`inventory-service` does have a legitimate caller, so its isolation needs one hole punched in it, scoped as tightly as the caller it's for:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-gateway-to-inventory
  namespace: patterns
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: inventory-service
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: graphql-gateway
      ports:
        - protocol: TCP
          port: 50051
```

Two policies both selecting `inventory-service`'s Pods combine additively: a connection is allowed if *any* applicable policy's rules permit it, so `deny-all-inventory`'s empty rule list and `allow-gateway-to-inventory`'s one rule aren't a contradiction, they're deny-by-default plus one explicit exception, exactly the shape every default-deny firewall takes. The `ports` field narrows the exception further: this rule only opens port 50051, the gRPC port, not `inventory-service`'s REST port 8080 as well, so `graphql-gateway` gets exactly the one path its code dials.

![inventory-service denies all ingress by default; graphql-gateway is the one allowed caller on the gRPC port; payment-service has no allow rule at all]({{ "/assets/diagrams/appendix-27-network-segmentation.svg" | relative_url }})
*A test client's connection attempts are denied against both services; graphql-gateway's gRPC call to inventory-service is the one path an explicit rule opens.*

## A selector match, not an identity check

The thing worth being precise about here, because it's a frequent source of a false sense of security: `podSelector` matches on a Pod's **labels** and nothing more. It says nothing about what process is actually running inside a Pod carrying that label, what `ServiceAccount` it uses, or whether it's cryptographically anything in particular. A Pod that happens to carry the label `app.kubernetes.io/name: graphql-gateway` satisfies `allow-gateway-to-inventory`'s selector whether or not it's actually running `graphql-gateway`'s code, which is exactly how this chapter's example verifies the rule took effect: a short-lived `curlimages/curl` Pod, labeled to match the gateway's selector, proves the allow rule's selector math without needing `graphql-gateway`'s own container (which has no `curl` installed) to make the test connection itself.

That same fact is worth a caution in the other direction: this probe Pod, for as long as it exists, also satisfies `graphql-gateway`'s **Service** selector (`app.kubernetes.io/name: graphql-gateway`, the ordinary convention every example in this appendix uses), which means it briefly becomes an endpoint of that Service too. `NetworkPolicy` selectors and `Service` selectors are evaluated completely independently by the cluster, with no linkage between them at all; reusing the identical label for both is convenient and it's also exactly how a short-lived test Pod can accidentally join a Service's real traffic rotation. This example's probe Pod is deleted immediately after the one check it exists for, and in a cluster carrying real production traffic through `graphql-gateway`'s Service, a label collision like this is a real risk worth designing around, not merely a testing nuisance: a `Service` selector built from a label combination a test Pod is unlikely to reproduce by accident is the safer default once real traffic is on the line.

## Restricting egress, not just ingress

Everything so far restricts who can call *in* to `inventory-service` and `payment-service`. Egress works the same mechanism, pointed the other direction, and it matters for a different reason: a compromised container's most common next move isn't accepting an unexpected inbound connection, it's making an outbound one, to exfiltrate data or reach a command-and-control endpoint. `inventory-service` only legitimately needs two egress destinations: DNS (to resolve the Postgres Service's hostname and its own cluster-internal names) and the Postgres Pod itself.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: inventory-egress-restricted
  namespace: patterns
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: inventory-service
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: patterns-postgres
      ports:
        - protocol: TCP
          port: 5432
```

Once this policy's `policyTypes` includes `Egress`, `inventory-service`'s Pods lose every other outbound path by default, including any reach toward the public internet a compromised dependency might otherwise attempt. The cleanest proof this restriction is compatible with the workload running, rather than taking the restriction on faith, is the workload's own readiness probe: `inventory-service`'s `/healthz` depends on reaching Postgres, so a `kubectl rollout restart` after applying this policy and a Pod reaching `Ready` again confirms the two egress paths this policy allows are the two paths the service needs, with nothing left over.

## Combining podSelector and namespaceSelector

`allow-gateway-to-inventory`'s `from` entry names only a `podSelector`, which matches `graphql-gateway`'s Pods regardless of which namespace they're in (there's only one namespace here, `patterns`, so the distinction is invisible in this example, but it matters the moment a cluster has more than one). A single `from` entry can name both a `podSelector` and a `namespaceSelector` together, and when it does, the two are combined with AND, not OR: a source Pod has to match both the namespace label and the Pod label to satisfy that one entry.

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            team: checkout
        podSelector:
          matchLabels:
            app.kubernetes.io/name: graphql-gateway
```

This narrows the rule to Pods labeled `app.kubernetes.io/name: graphql-gateway` that are *also* running in a namespace labeled `team: checkout`, rejecting a same-named Pod sitting in any other namespace. Listing the same two selectors as two separate items in the `from` array instead of two fields on one item changes the meaning entirely, from AND to OR: either selector alone would then be enough to match, which is a much broader rule than most authors intend when they reach for both. `allow-gateway-to-inventory` in this chapter's example skips `namespaceSelector` because everything here shares one namespace; reaching for the combined form is the right move the moment a cluster's segmentation needs to span more than one.

## What a connection timeout doesn't tell you

A `NetworkPolicy` denying a connection and a Pod simply not being ready yet produce the identical symptom from a client's point of view: `curl` times out. Before concluding a policy is the cause, `kubectl get networkpolicy -n patterns` confirms which policies exist and which Pods their `podSelector` matches (a typo'd label value in a policy silently selects zero Pods, changing nothing about traffic, which looks identical to a policy working correctly until something needed denying); `kubectl get pods -n patterns -o wide --show-labels` confirms the labels on the Pods on both ends of the connection say what the policies assume they say. A `NetworkPolicy` that compiles and applies without error can still be a complete no-op if its selector doesn't match what the author pictured when they wrote it, and that failure mode produces no event, no warning, and no error, so checking the selector's actual matches comes before concluding the enforcement layer itself is misbehaving, not after.

## Istio AuthorizationPolicy: an optional extension

Everything in this chapter works against plain Kubernetes NetworkPolicy, which operates at the IP and port level (layer 3/4) and has no concept of HTTP methods, paths, or caller identity beyond a Pod's labels. A service mesh adds a finer-grained layer on top: Istio's `AuthorizationPolicy` can allow or deny traffic by HTTP path, method, and the caller's cryptographically verified mesh identity (its mTLS certificate, not just a label a Pod happens to carry), which closes exactly the selector-isn't-identity gap this chapter's probe Pod exploited to run its test. That's a real capability difference, and it comes at a real cost: it requires the mesh control plane and sidecar proxies running, which this appendix's `mof-patterns` profile doesn't carry (the [§11 Istio chapter]({{ "/docs/11-istio/" | relative_url }}) covers standing it up). `AuthorizationPolicy` is worth knowing exists and worth reaching for once a mesh is already part of the picture; it is not something this chapter's example installs, and plain `NetworkPolicy` remains the right default for a cluster that doesn't otherwise need a mesh.

> **🎓 CKAD exam lens**
>
> **Domain:** Services & Networking (20%)
> **Competency:** Write a default-deny NetworkPolicy scoped to a workload, allow one caller by podSelector and port, and restrict egress to named destinations
> **Drill:** `kubectl exec -n patterns netseg-test-client -- curl -m 3 payment-service:80` (expect a timeout, confirming payment-service has no allow rule)

> **🤖 Explore with your agent**
>
> "Add a namespaceSelector to allow-gateway-to-inventory so graphql-gateway could also be called from a different namespace labeled team: checkout, apply it, and show me the NetworkPolicy's ingress rule combining both the podSelector and the namespaceSelector correctly (both must match, not either)."

## Cleanup

```bash
kubectl --context mof-patterns delete pod netseg-probe-gateway -n patterns --ignore-not-found
kubectl --context mof-patterns delete -n patterns -f network-segmentation/08-test-client.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/07-egress-inventory-restricted.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/06-deny-all-payment.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/05-allow-gateway-to-inventory.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/04-deny-all-inventory.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/03-graphql-gateway.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/02-payment-service.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/01-inventory-service.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/00-postgres.yaml
```

## Verification: examples/appendix-patterns/network-segmentation/

The runnable example deploys `inventory-service`, `payment-service`, and `graphql-gateway`, confirms a test client can reach both protected services before any policy exists, applies default-deny policies scoped to each, confirms the test client is denied, applies the gateway-only allow rule, proves it with a short-lived labeled probe Pod, then applies and verifies the egress restriction. Full walkthrough (including the Calico setup step) in `examples/appendix-patterns/network-segmentation/README.md`.
