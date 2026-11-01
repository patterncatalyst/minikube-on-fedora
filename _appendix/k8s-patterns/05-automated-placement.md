---
title: "Automated Placement"
order: 5
part: "Foundational"
description: "Steer the scheduler with nodeSelector, node and pod affinity, and taints and tolerations, and spread a service's replicas across nodes for availability."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Constrain a Pod to nodes carrying a given label with `nodeSelector`
- Write a `nodeAffinity` rule that distinguishes a hard requirement from a soft preference
- Spread a Deployment's replicas across nodes with `podAntiAffinity`, and explain why that matters for availability
- Taint a node to repel Pods by default, and grant a specific Pod a `toleration` to schedule there anyway

## Why this matters

The default Kubernetes scheduler already does real work without any help: it ranks every schedulable node by fit (enough CPU and memory, no conflicting port, satisfied node selectors) and picks a good one. For a homogeneous cluster running interchangeable replicas of one service, that default is often enough on its own. Real clusters are rarely that homogeneous. Some nodes have local SSDs and some don't; some sit in one availability zone and some in another; some are reserved for a specific workload tier and shouldn't run anything else. Automated Placement is the set of primitives that let a Pod spec describe which of those differences actually matter to it, instead of leaving every placement decision to chance.

Two distinct motivations run through the four mechanisms in this chapter. `nodeSelector` and `nodeAffinity` answer "does this specific node have what I need:" a label, a zone, a hardware feature. `podAntiAffinity` answers a different question entirely: "should I avoid running near another instance of myself," which is the foundation of spreading a service's replicas for availability rather than steering them toward specific hardware. Taints and tolerations flip the direction of control: instead of a Pod expressing a preference, a node declares that it repels Pods by default, and only Pods that explicitly tolerate the taint may land there.

None of these mechanisms depend on what a container actually does, so this chapter's example uses a minimal placeholder image labeled to stand in for `shipping-service` and `order-service`: the scheduling outcome is identical to what a real container would see.

## Setting up a second node

Every other chapter in this appendix runs on the single-node `mof-patterns` profile. Placement decisions are uninteresting with only one schedulable node, since there's nowhere else for a Pod to go; this chapter adds a second:

```bash
minikube node add -p mof-patterns
kubectl get nodes
```

Two nodes result: `mof-patterns` (the original control-plane node) and `mof-patterns-m02` (a worker). Other chapters that don't need the second node run unaffected on the same profile.

## nodeSelector

The simplest placement constraint is a direct label match. A Pod standing in for `shipping-service` requests a node labeled for a specific fulfillment zone:

```yaml
spec:
  nodeSelector:
    zone: warehouse-a
```

Apply it before any node carries that label and the Pod goes `Pending`, with a scheduling event reading `0/2 nodes are available: 2 node(s) didn't match node selector`. Label the worker node and the very next scheduling attempt succeeds, with no change to the Pod spec:

```bash
kubectl label node mof-patterns-m02 zone=warehouse-a
```

`nodeSelector` only supports exact key/value matches, combined with implicit AND if there's more than one. For anything requiring ranges, set membership, or a mix of required and merely preferred conditions, the next mechanism is the one that actually has that vocabulary.

## Node affinity: required versus preferred

A Pod standing in for `order-service` needs a node labeled for its fulfillment tier, and additionally prefers to avoid the control-plane node when there's a real alternative:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: tier
              operator: In
              values: ["fulfillment"]
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 10
        preference:
          matchFields:
            - key: metadata.name
              operator: NotIn
              values: ["mof-patterns"]
```

`requiredDuringSchedulingIgnoredDuringExecution` behaves like `nodeSelector` with a richer expression language (`In`, `NotIn`, `Exists`, `Gt`, `Lt`): fail to satisfy it and the Pod stays unschedulable, exactly as before. `preferredDuringSchedulingIgnoredDuringExecution` is different in kind, not just in strictness: it's a scoring hint. The scheduler adds `weight` to a node's score for each preference it satisfies, then picks the best-scoring node among the ones that already meet every required rule. A preference that nothing can satisfy doesn't block scheduling at all; it just has no effect on the final choice.

The `IgnoredDuringExecution` suffix on both rules means neither is re-evaluated once the Pod is already running: label a node out of compliance after the Pod has landed there, and Kubernetes won't evict it to fix the mismatch. Affinity governs placement, not continuous enforcement.

![Node selector, node affinity, pod anti-affinity, and tolerations placing Pods across the two mof-patterns nodes]({{ "/assets/diagrams/appendix-05-automated-placement.svg" | relative_url }})
*Label and taint rules on mof-patterns-m02 draw the fulfillment-tagged placeholders there, while anti-affinity spreads shipping-ha's two replicas one per node.*

## Pod anti-affinity: spreading replicas for availability

Node affinity steers a Pod toward specific hardware. Pod affinity and anti-affinity steer a Pod relative to *other Pods*, which is the mechanism behind one of the most common production requirements: don't put every replica of the same service on the same node, because a single node failure shouldn't be able to take the whole service down with it.

A two-replica Deployment standing in for a highly available `shipping-service` sets a required anti-affinity rule against its own label:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: shipping-ha-placeholder
        topologyKey: kubernetes.io/hostname
```

`topologyKey: kubernetes.io/hostname` means the rule's unit of separation is the individual node: no two Pods matching the label selector may share a node. With two nodes and two replicas, each lands on a different one. Scale to three replicas and the third stays `Pending`: there's no third node for it to occupy without violating the rule, and `requiredDuringSchedulingIgnoredDuringExecution` means the scheduler won't bend it. Swap in `preferredDuringSchedulingIgnoredDuringExecution` instead and the third replica would schedule anyway, doubling up on a node rather than staying unscheduled, trading a strict guarantee for a best effort. Which one is correct depends entirely on whether a replica Pending somewhere is worse than a replica sharing a node with another one; for availability-sensitive services, a required rule is almost always the right default even if it occasionally means a replica waits for capacity.

## Taints and tolerations

Every mechanism so far has a Pod pulling itself toward something. Taints and tolerations work in the opposite direction: a node pushes Pods away by default, and only a Pod with a matching toleration is allowed back in.

```bash
kubectl taint nodes mof-patterns-m02 dedicated=fulfillment:NoSchedule
```

With this taint applied, the scheduler won't place any Pod on `mof-patterns-m02` unless that Pod's spec explicitly tolerates `dedicated=fulfillment:NoSchedule`. Two otherwise identical Pods make the contrast concrete: both carry the same `nodeSelector: {zone: warehouse-a}`, but only one carries a matching toleration:

```yaml
tolerations:
  - key: dedicated
    operator: Equal
    value: fulfillment
    effect: NoSchedule
```

The Pod without the toleration stays `Pending`: it matches the node selector, but the taint overrides that match entirely, because a taint's `NoSchedule` effect repels every Pod by default regardless of what else matches. The Pod with the toleration schedules normally. That asymmetry is the entire design: a node selector or affinity rule only says what a Pod wants, and plenty of other Pods might want the same node too; a taint says what a node refuses by default, and only an explicit toleration is an exception to that refusal. Dedicating a node to one workload tier, in other words, is a property of the node, enforced regardless of how many other Pods come looking for it, not a property of the Pods that happen to prefer it.

A `NoSchedule` taint only blocks new scheduling; it has no effect on a Pod already running there. `NoExecute` is the stricter of the three effects (`NoSchedule`, `PreferNoSchedule`, `NoExecute`): applied to a node, it evicts any already-running Pod that doesn't tolerate it, not just new ones. A toleration can also carry `tolerationSeconds` against a `NoExecute` taint, which lets a Pod stay for a bounded grace period after the taint appears rather than being evicted the instant it's applied, useful for riding out a brief node condition (like the automatic taints Kubernetes applies to a node that's become unreachable) without an immediate reschedule.

## Topology spread as an alternative to anti-affinity

`podAntiAffinity` answers "never co-locate with this specific set of Pods," which is exactly what the availability use case in this chapter needs. `topologySpreadConstraints` (a newer, complementary mechanism) answers a related but distinct question: "keep this group of Pods evenly spread across a topology domain," which matters once a cluster has more than two nodes or multiple availability zones and "never share a node" alone no longer implies "evenly distributed." A constraint like `maxSkew: 1` with `topologyKey: topology.kubernetes.io/zone` keeps the difference in replica count between any two zones at one Pod or fewer, which `podAntiAffinity` has no vocabulary for expressing on its own; the two mechanisms solve overlapping but not identical problems and are often used together on the same workload.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%): scheduling basics; node affinity, taints, and tolerations lean toward the CKA exam
> **Competency:** Understand the Kubernetes scheduler, including node selectors, affinity/anti-affinity, and taints/tolerations
> **Drill:** `kubectl get pods -n patterns -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName`

> **🤖 Explore with your agent**
>
> "Add a `topologySpreadConstraints` entry to the shipping-ha Deployment that spreads replicas across a `zone` label instead of per-node, relabel the two mof-patterns nodes into two zones, and show me how the scheduling outcome compares to the podAntiAffinity rule already in place."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns \
  -f automated-placement/01-node-selector.yaml \
  -f automated-placement/02-node-affinity.yaml \
  -f automated-placement/03-pod-anti-affinity.yaml \
  -f automated-placement/04-toleration.yaml
kubectl --context mof-patterns taint nodes mof-patterns-m02 dedicated=fulfillment:NoSchedule-
minikube node delete mof-patterns-m02 -p mof-patterns
```

## Verification: examples/appendix-patterns/automated-placement/

The runnable example adds the second node, works through all four mechanisms in sequence (node selector, node affinity, pod anti-affinity, taints and tolerations), and confirms each `Pending`-to-`Running` transition as the matching label, affinity target, or toleration is added. Full walkthrough in `examples/appendix-patterns/automated-placement/README.md`.
