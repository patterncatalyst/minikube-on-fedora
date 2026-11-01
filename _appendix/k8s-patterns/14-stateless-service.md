---
title: "Stateless Service"
order: 14
part: "Behavioral"
description: "Name the default shape most services should take: interchangeable Pods with no stable identity and no per-Pod storage, scaled horizontally through an ordinary Deployment."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- State the three properties that make a service fully stateless: no per-Pod storage, no stable network identity, no in-memory state a client depends on
- Explain why a stateless service's Pods can be deleted and replaced with no coordination at all
- Scale a stateless Deployment horizontally and explain why that operation needs nothing beyond a replica count
- Recognize when a service that looks stateless isn't, and what breaks first when that assumption is wrong

## Why this matters

Earlier Foundational chapters already built and scaled Deployments; this chapter isn't introducing a new mechanism, it's naming a property the earlier chapters assumed without stating it directly. `shipping-service` in Predictable Demands, `notification-service` in Managed Lifecycle, every Deployment this appendix has shown so far has rested on the same assumption, left unstated until now: that any replica can handle any request, that losing one and getting a new one back changes nothing a client depends on, and that scaling the replica count up or down is purely an availability and capacity decision with no data to reconcile. That assumption has a name. The next two chapters (Stateful Service, and later Singleton Service's scaling behavior) are precisely the patterns for workloads where it doesn't hold.

Statelessness isn't a property Kubernetes enforces on a Deployment. It's a property of the application code running inside it, and a Deployment manifest that looks identical to a fully stateless one can just as easily front a service writing to local disk without saying so, or holding a client's session in memory, breaking the moment that specific Pod disappears. The pattern matters because the guarantee only holds when the application honors it.

## The three properties

A service earns the label "stateless" by satisfying three things at once, and the example's `payment-service` Deployment is built to satisfy all three rather than merely look like it does:

```yaml
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: payment-service
          image: payment-service:v1
```

**No per-Pod storage.** There's no `volumeClaimTemplates`, no `volumeMounts` pointing at anything Pod-specific, nothing a replacement Pod would need to inherit from the Pod it replaces. Whatever `payment-service` needs to persist, it persists to Postgres, a dependency external to every replica rather than local to any one of them. A Pod that writes meaningful data to its own writable container layer or an `emptyDir` has already broken this property, even if nothing else about its manifest looks any different from one that honors it.

**No stable network identity.** Every replica answers to the same label selector and the same Service, and nothing addresses `payment-service`'s *second* replica specifically: there's no name or address that singles one out from another. Compare this to the headless Service and ordinal Pod names the Stateful Service chapter builds next, where a stateful workload's whole mechanism depends on exactly the identity this pattern has none of.

**No in-memory state a client depends on.** A client's second request doesn't need to land on the same replica as its first. This is the property that's easiest to violate by accident (an in-process cache that drifts out of sync across replicas, a websocket session held in memory with no shared backing store, a rate limiter counting in a single Pod's RAM instead of a shared store) and the hardest to catch from the manifest alone, because nothing in YAML distinguishes a replica that honors statelessness from one that only looks that way until two clients hit two different Pods and get two different answers.

![payment-service's Service fronting three interchangeable Pods; one is deleted and replaced with a new identity while the Service keeps answering throughout]({{ "/assets/diagrams/appendix-14-stateless-service.svg" | relative_url }})
*No Pod owns storage or a name the Service depends on, which is why deleting one and getting a brand-new replacement changes nothing visible from outside.*

## What deleting a replica proves

The cleanest way to confirm all three properties hold in practice, rather than just on paper, is to delete a running replica and watch what the Service does:

```bash
kubectl delete pod "$VICTIM" -n patterns
kubectl get pods -n patterns -l app.kubernetes.io/name=payment-service -o wide -w
```

The ReplicaSet notices one Pod short of its desired count and creates a replacement with a brand-new generated name and a brand-new IP address. Nothing about the deleted Pod's identity transfers to it, because a ReplicaSet never tracked identity in the first place, only a count. A client polling the Service throughout this delete-and-replace cycle sees nothing beyond the ordinary, momentary dip in available replicas any rolling change produces: the two still-running Pods keep answering, and the new one joins the rotation the moment its readiness probe passes. None of that required any coordination between the old Pod and the new one, because there was nothing for them to coordinate. The new Pod isn't resuming the old one's work; it's one more interchangeable instance of the same stateless template.

## Horizontal scale needs nothing but a number

```bash
kubectl scale deployment/payment-service -n patterns --replicas=5
```

Scaling a stateless Deployment up or down is the single operation that most directly demonstrates why this pattern earns its own name. There's no data migration to plan, no rebalancing of state across the new replica count, no question of which existing replica "owns" which slice of anything: the ReplicaSet creates or deletes Pods from the identical template until the count matches. Compare the effort this takes against scaling a StatefulSet's per-pod storage, or against the Automated Placement chapter's `podAntiAffinity` rules needing to account for exactly how many nodes exist. Statelessness is precisely what turns horizontal scaling into a one-line operation instead of a capacity-planning exercise, and that's the reason it's the default shape to reach for unless a specific requirement rules it out.

The converse holds too: if a workload needs per-replica storage, a stable per-replica network identity, or in-memory state a specific client depends on, reaching for StatefulSet instead of forcing it into this shape isn't a design failure. The two patterns divide a real distinction between them; neither one is strictly better than the other.

## sessionAffinity: an escape hatch, not a contradiction

A Service's default load-balancing picks a different backend Pod per connection, which is exactly what statelessness assumes. `sessionAffinity: ClientIP` is the one Service-level setting that changes that, routing all traffic from the same client IP to the same backend Pod for a configurable window (`sessionAffinityConfig.clientIP.timeoutSeconds`, three hours by default):

```yaml
spec:
  sessionAffinity: ClientIP
```

It's easy to mistake for evidence that a service needs stateful treatment when it doesn't. `sessionAffinity` is usually reached for to smooth out an in-process cache's warm/cold inconsistency across replicas, or to make debugging easier when watching one specific backend's logs during a client session, not because the application requires it structurally. A service that would break if `sessionAffinity` were turned off (a client's second request landing on a different Pod and failing) was never stateless to begin with; it was relying on affinity to paper over state it should have put somewhere shared instead. `payment-service` in this example runs with the Service's default (`sessionAffinity: None`), specifically so the delete-and-replace demonstration proves the statelessness claim rather than assuming it.

## Readiness probes matter more here than almost anywhere else

Of every property a stateless Deployment depends on, the one most likely to be wrong in a real deployment without anyone noticing is the readiness probe backing it. A Service only routes traffic to Pods currently reporting `Ready`, and a stateless Deployment scaling up five new replicas at once is relying entirely on each one's readiness probe to hold traffic back until that specific Pod can serve a request correctly. That's also precisely what makes `maxUnavailable: 0` rolling updates (Declarative Deployment) a real guarantee rather than a hopeful one for this exact workload shape. A readiness probe that returns `200` the instant the process starts accepting connections, before the application has finished whatever startup work it needs (establishing its own connection pool, warming any local cache it legitimately does keep), breaks the "any replica can serve any request" promise this whole pattern depends on. Not because the Deployment or Service did anything wrong, but because the one signal that was supposed to gate traffic lied about being ready. `startupProbe`, covered in Health Probe, is the specific tool for separating a service's one-time startup cost from its ongoing readiness check, and the two Foundational chapters together are what this one leans on rather than repeating: statelessness is the reason horizontal scale is cheap, correct probes are the reason it's also safe.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%)
> **Competency:** Understand storage and volume concepts well enough to recognize when a workload has none, and what distinguishes it from one that does
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=payment-service -o jsonpath='{.items[*].metadata.name}'` before and after a delete, to compare the Pod name sets directly

> **🤖 Explore with your agent**
>
> "Add an emptyDir volume to payment-service that writes a per-Pod counter file, delete a replica, and show me what happens to that counter in the replacement Pod compared to what a fully stateless service should look like."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f stateless-service/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f stateless-service/00-postgres.yaml
```

## Verification: examples/appendix-patterns/stateless-service/

The runnable example deploys `payment-service` at three replicas, deletes one at random to confirm the Service keeps answering throughout and the replacement gets an entirely new identity, then scales to five and back to three with no manifest change beyond the replica count. Full walkthrough in `examples/appendix-patterns/stateless-service/README.md`.
