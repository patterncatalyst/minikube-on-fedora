---
title: "Singleton Service"
order: 13
part: "Behavioral"
description: "Protect a single-instance service from voluntary disruption with a PodDisruptionBudget, and learn exactly which operations it governs and which it doesn't."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain why a service might choose to run at `replicas: 1` instead of being made redundant
- Set `minAvailable` or `maxUnavailable` on a `PodDisruptionBudget` and explain the difference
- Distinguish voluntary disruption (the Eviction API) from involuntary disruption (a node crash) and from a direct Pod delete
- Read a PDB's `ALLOWED DISRUPTIONS` status to tell whether it currently has any room to give

## Why this matters

Most of this appendix assumes a service should be made redundant: Stateless Service (the next chapter) treats interchangeable replicas as the default good shape, and Automated Placement spread them across nodes for exactly that reason. Some workloads cannot take that shape at all: a process holding an exclusive lock, a leader-elected controller where exactly one instance may act at a time, a legacy component that was never built to run more than one copy safely. For those, `replicas: 1` isn't a temporary state waiting to be fixed; it's the correct design, and the cost is that the *one* Pod that exists is a single point of failure for anything that depends on it.

Singleton Service is the pattern for protecting that one Pod from the specific category of disruption Kubernetes itself might otherwise cause: a cluster operator draining a node for maintenance, a cluster autoscaler shrinking the node pool, a descheduler rebalancing load. None of these are malicious and none are bugs, yet every one of them is capable of removing the one Pod a singleton workload can't survive losing without a human's attention. `PodDisruptionBudget` is the object that tells those actors "not this one, not right now."

## minAvailable and maxUnavailable

The example protects `order-service`, run at `replicas: 1`, with a PDB:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: order-service-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
```

A PDB takes exactly one of two mutually exclusive fields. `minAvailable` states a floor: at least this many matching Pods must remain available through any voluntary disruption, expressed as either an absolute number (as here) or a percentage of the selector's current matches. `maxUnavailable` states a ceiling instead: at most this many may become unavailable at once. For a single-replica singleton the two are functionally identical (`minAvailable: 1` and `maxUnavailable: 0` both mean "this one Pod may never be voluntarily removed"), and the choice between them mostly comes down to which one reads more naturally for the workload: `minAvailable: 1` states directly that "this Pod must survive," which is the clearer statement of intent for something whose entire selector matches one Pod.

For a multi-replica service that still wants singleton-adjacent protection (a 5-replica Deployment that can tolerate losing one at a time but never two), `maxUnavailable: 1` is the more natural expression, since `minAvailable` would need recalculating every time the replica count changed. Neither field loosens on its own as replicas scale up: a PDB with `maxUnavailable: 0` on a service scaled from 1 replica to 10 still permits zero voluntary disruptions, because the budget was written as an absolute rule about availability, not a rule that happens to have been satisfied at one particular replica count.

## Reading ALLOWED DISRUPTIONS

```bash
kubectl get pdb order-service-pdb -n patterns
```

The `ALLOWED DISRUPTIONS` column is the PDB controller's own live computation: given the current number of healthy, matching Pods and the budget's `minAvailable`/`maxUnavailable`, how many more Pods could be voluntarily removed right now without violating the rule. With one healthy replica and `minAvailable: 1`, that number is `0`: there is no room at all, and any voluntary-disruption request against the matching Pod will be refused until either the budget changes or (for a multi-replica case) more healthy replicas appear. This number recalculates continuously as Pods come and go; a PDB isn't evaluated once at creation and then left static, it's a live constraint the disruption-handling code checks at the moment of each request.

![An Eviction API request against order-service's single replica blocked by its PodDisruptionBudget, contrasted with a direct pod delete that bypasses it entirely]({{ "/assets/diagrams/appendix-13-singleton-service.svg" | relative_url }})
*The PDB governs the Eviction API specifically; a direct kubectl delete pod never consults it at all.*

## Voluntary disruption: the Eviction API

A PDB's protection is narrower than "nothing can remove this Pod," and the exact boundary is worth knowing precisely, because it's a common source of confusion on the exam and in production alike. `kubectl drain`, the cluster autoscaler scaling a node down, and a descheduler rebalancing Pods all go through the same path: a `POST` to the Pod's `eviction` subresource, which the API server checks against every PDB matching that Pod before honoring it.

```bash
kubectl create --raw "/api/v1/namespaces/patterns/pods/${POD}/eviction" \
  -f - <<EOF
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"${POD}","namespace":"patterns"}}
EOF
```

Against `order-service`'s single Pod with `ALLOWED DISRUPTIONS: 0`, this call fails with `429 Too Many Requests` and a message naming the budget directly: `Cannot evict pod as it would violate the pod's disruption budget.` `kubectl drain` reports the identical failure when it reaches this Pod during a node drain, because under the hood it's issuing the same eviction request and respecting the same refusal. A human running `kubectl drain` on a node hosting this Pod sees the drain stall here specifically, with the error naming exactly which PDB is responsible, instead of the drain succeeding and taking the singleton down along with the rest of the node.

## Direct delete bypasses the budget entirely

```bash
kubectl delete pod "$POD" -n patterns
```

This succeeds immediately, with no 429, no PDB check, nothing. `kubectl delete pod` calls the ordinary delete endpoint, not the eviction subresource, and a PDB only ever intercepts eviction requests: it was never wired into the plain delete path, because plain delete isn't the category of disruption a PDB is meant to guard against. The distinction matters practically: a PDB protects a singleton against automated cluster-maintenance tooling making an independent decision to remove it, not against a human (or a script, or a controller) explicitly choosing to delete that specific Pod. A Deployment controller replacing a deleted Pod with a fresh one is the ordinary reconciliation this appendix has relied on throughout; the PDB has no opinion about that replacement cycle at all, only about whether the *removal* that triggered it came through the Eviction API.

This also means a PDB is not a substitute for making a workload resilient to real, involuntary disruption: a node crashing outright, the kubelet failing, a kernel panic. None of those go through the eviction path at all; they take the Pod down regardless, and the PDB has no mechanism to prevent or even delay that. A PDB's entire domain is the one category it was built for: automated, voluntary, API-mediated removal that a human operator or a piece of cluster-maintenance tooling could otherwise trigger without realizing a specific Pod can't safely be replaced right now.

## drain --force: the explicit override

`kubectl drain` normally respects a PDB the same way the raw Eviction API call does, stalling on a node that hosts a singleton it can't evict. `--force` is the explicit, human-initiated override for a planned maintenance window where the operator has already decided the singleton's brief unavailability is acceptable:

```bash
kubectl drain mof-patterns --ignore-daemonsets --delete-emptydir-data --force
```

`--force` doesn't turn the PDB check off outright; it changes `drain`'s own behavior to fall back to a direct delete (the same bypass this chapter already demonstrated by hand) for any Pod the Eviction API refuses, after attempting the polite path first. This is the correct way to plan around a singleton's protection on a known schedule, rather than deleting the PDB first (which would also stop protecting the Pod from every *other*, unplanned voluntary disruption in the meantime): use the one flag that says "I've accounted for this specific Pod's unavailability" at the exact moment it's needed, and nowhere else.

## A PDB applies to any matching selector, not just one Deployment

Nothing about a PodDisruptionBudget's `selector` ties it to a single Deployment by name. It matches on labels, the same mechanism a Service uses, which means a PDB written against `app.kubernetes.io/name: order-service` would apply identically to a StatefulSet, a ReplicaSet, or even a set of unmanaged Pods carrying that same label, should any of those exist alongside the Deployment. This is a design choice, not an oversight: a PDB describes an availability constraint about a *set of Pods identified by label*, independent of which specific controller happens to be managing them, which is also why `kubectl get pdb` output never mentions the Deployment it's "protecting" by name: from the PDB's own perspective, there is no such relationship to report, only a selector and a count.

## When the right fix is removing the singleton, not protecting it harder

A PDB protects a singleton from *voluntary* disruption, but it does nothing about the node crashing outright, which is the involuntary case this pattern was never meant to cover. A workload where that gap is unacceptable, where even an involuntary outage of a few minutes while the Deployment controller notices and replaces the Pod is too costly, usually needs leader election instead: multiple replicas running simultaneously, with only one actively doing the singleton's work at a time and the others standing by to take over the moment the active one disappears, voluntarily or not. That's a materially larger undertaking than a PDB (it needs a coordination mechanism, typically a Lease object or an equivalent distributed lock, and application code that takes part in the handover directly), and it's the right escalation specifically when "protected from planned maintenance" stops being enough and "survives an unplanned node failure within seconds" becomes the real requirement. Recognizing which of the two a given workload needs, and not reaching for leader election's added complexity when a PDB's narrower guarantee already covers the case, is itself part of applying this pattern correctly.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Deployment (20%): disruption handling; PodDisruptionBudget leans toward the CKA exam
> **Competency:** Understand PodDisruptionBudget and the distinction between voluntary and involuntary disruption
> **Drill:** `kubectl get pdb order-service-pdb -n patterns -o jsonpath='{.status.disruptionsAllowed}'`

> **🤖 Explore with your agent**
>
> "Scale order-service to 2 replicas without changing the PodDisruptionBudget, then try the Eviction API against one of them, and show me whether ALLOWED DISRUPTIONS changed and why."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f singleton-service/02-pdb.yaml
kubectl --context mof-patterns delete -n patterns -f singleton-service/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f singleton-service/00-postgres.yaml
```

## Verification: examples/appendix-patterns/singleton-service/

The runnable example deploys `order-service` at `replicas: 1` behind a `minAvailable: 1` PDB, confirms the Eviction API is refused with `429`, and then shows a direct `kubectl delete pod` succeeding immediately against the same Pod to make the distinction concrete. Full walkthrough in `examples/appendix-patterns/singleton-service/README.md`.
