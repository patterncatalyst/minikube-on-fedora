---
title: "Stateful Service"
order: 15
part: "Behavioral"
description: "Give a workload stable per-Pod identity and sticky storage with a StatefulSet and a headless Service, and see exactly what a stateless Deployment can't offer."
duration: "25 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what a headless Service (`clusterIP: None`) provides: per-Pod DNS records instead of one load-balanced address
- Use `volumeClaimTemplates` to give each StatefulSet replica its own PersistentVolumeClaim, created once and reused across restarts
- Explain why a StatefulSet creates and deletes Pods in strict ordinal order, unlike a Deployment's default parallel behavior
- Confirm that a Pod's storage and name both survive a Pod deletion, which is the entire point of the pattern

## Why this matters

Stateless Service named the default shape most workloads should take and the three properties that make it safe. This chapter is the explicit exception: a workload where at least one of those three properties doesn't hold at all, because the workload itself needs something a stateless Deployment structurally cannot provide. A stable identity a specific piece of storage is tied to, re-attached after every restart rather than handed to whichever replacement Pod happens to come up next.

The example runs `shipment-archive`, three independent, **non-replicating** `postgres:17-alpine` instances standing in for a per-zone archive. This is not the §17 data mesh's actual CloudNativePG-managed Postgres, and the three instances are not configured to replicate data between each other. The point of this example isn't to build a real multi-node database; it's to give a workload that is unavoidably stateful (each instance's data lives only on that instance, and losing its storage would lose data no other instance has a copy of) to demonstrate StatefulSet mechanics against, without the complexity of wiring up actual Postgres streaming replication, which is a separate and much larger subject.

## The headless Service: identity over load balancing

Every Service this appendix has used until now has had a real, load-balanced `ClusterIP`: a stable virtual address that picks one of its matching Pods per connection, with no way to address a specific one. `shipment-archive`'s Service gives that up, because addressing a specific instance is exactly what this workload needs:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shipment-archive
spec:
  clusterIP: None
  selector:
    app.kubernetes.io/name: shipment-archive
  ports:
    - name: postgres
      port: 5432
```

`clusterIP: None` is what makes a Service headless: kube-dns stops returning one load-balanced address for the Service name and instead returns a DNS A record for *each* backing Pod individually, at a predictable name: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`. For `shipment-archive`, that's `shipment-archive-0.shipment-archive.patterns.svc.cluster.local`, `shipment-archive-1.shipment-archive.patterns.svc.cluster.local`, and `shipment-archive-2.shipment-archive.patterns.svc.cluster.local`: three distinct, individually addressable names, not three equally-valid answers behind one name. This is the mechanism a stateful workload needs and a stateless one has no use for. A client (or a peer replica, in a system with working replication) that needs to reach *that specific instance's* data has a name for it, resolvable the same way any other Service name is, with no extra discovery layer required.

## StatefulSet: ordinal identity

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: shipment-archive
spec:
  serviceName: shipment-archive
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: shipment-archive
```

`serviceName` ties the StatefulSet to the headless Service that provides its Pods' DNS identity, a field a Deployment has no equivalent of, because a Deployment's Pods were never meant to be individually addressable in the first place. Where a Deployment generates Pod names with a random hash suffix (`payment-service-7d8f9c6b5-x2k4p`, as the Stateless Service chapter showed), a StatefulSet assigns strictly ordinal names: `shipment-archive-0`, `shipment-archive-1`, `shipment-archive-2`, numbered from zero and never reused arbitrarily. Delete `shipment-archive-1` specifically and its replacement comes back as `shipment-archive-1` again, not a new name. The ordinal is the Pod's identity, not an accident of creation order.

That ordinal identity also governs the order Pods are created and deleted in, and it's a strict order, not a preference. `shipment-archive-0` must reach `Ready` before `shipment-archive-1` is even created, and `shipment-archive-1` before `shipment-archive-2`, the opposite of a Deployment's default behavior of creating every replica in parallel. Scaling down reverses the order: the highest ordinal goes first. This ordering exists because many stateful workloads (a primary that must exist before replicas can join it, a cluster that bootstraps from its first member) depend on it. `shipment-archive`'s three independent Postgres instances don't need it for correctness, but the StatefulSet controller applies the same ordered discipline regardless, because it has no way to know a given workload doesn't need it.

![A headless Service providing per-Pod DNS names for three ordinal StatefulSet Pods, each bound to its own PersistentVolumeClaim]({{ "/assets/diagrams/appendix-15-stateful-service.svg" | relative_url }})
*Each ordinal gets a stable DNS name and its own sticky storage, created in order and reattached to the same claim on every restart.*

## volumeClaimTemplates: storage that's sticky, not shared

```yaml
volumeClaimTemplates:
  - metadata:
      name: archive-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 128Mi
```

A Deployment's Pod template can reference a PersistentVolumeClaim, but every replica referencing the same claim name shares the *same* PVC. That's fine for a ReadWriteMany volume multiple Pods can actually share, and actively wrong for a database where each instance needs its own independent storage. `volumeClaimTemplates` solves this by templating the claim itself rather than naming one fixed claim: the StatefulSet controller creates a distinct PVC per ordinal the first time that Pod is created (`archive-data-shipment-archive-0`, `archive-data-shipment-archive-1`, `archive-data-shipment-archive-2`), and every subsequent Pod carrying that ordinal reattaches to the *same* claim rather than getting a fresh one.

Deleting `shipment-archive-0` and watching its replacement come back proves this directly: data written before the delete (a row inserted into a demo table) is still there after the replacement Pod reaches `Ready`, because the new Pod mounted the exact same PVC the old one wrote to, not a fresh empty volume. This is the single clearest contrast against Stateless Service's own delete-and-replace demonstration. There, a new Pod identity meant nothing carried forward, by design; here, the identical ordinal identity is precisely what guarantees the storage carries forward too.

That stickiness persists even past the StatefulSet's own lifetime. Deleting the StatefulSet object itself does not delete its PVCs. They remain bound and untouched, so that recreating the StatefulSet (same name, same `volumeClaimTemplates`) reattaches every ordinal to its pre-existing data rather than starting over. Removing the data entirely requires deleting the PVCs explicitly, a separate action rather than an automatic side effect of removing the workload that was using them: the same asymmetry a database administrator would expect from any real storage system, encoded directly into how the controller behaves.

## podManagementPolicy: opting out of strict ordering

The ordered create-and-delete behavior described above is the default (`OrderedReady`), but it isn't the only option. `podManagementPolicy: Parallel` relaxes it for workloads whose replicas don't depend on each other's startup order at all:

```yaml
spec:
  podManagementPolicy: Parallel
```

With `Parallel` set, the controller creates and deletes every ordinal at once, the same all-at-once behavior a Deployment uses by default. Every other StatefulSet guarantee (stable per-ordinal names, per-ordinal `volumeClaimTemplates`, headless-Service DNS records) stays exactly the same. `shipment-archive`'s three independent Postgres instances are a reasonable candidate for `Parallel` in practice, since none of them depends on another's startup order. The example leaves the default `OrderedReady` behavior in place because watching ordinals come up one at a time is what makes the ordering guarantee itself visible and confirmable, something `Parallel` would make instant and much harder to observe directly.

## Rolling updates on a StatefulSet

A StatefulSet's `updateStrategy` governs a changed Pod template the same way a Deployment's does, but applies the same ordinal discipline to updates that it applies to initial creation:

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0
```

With the default `partition: 0`, a template change rolls out starting from the *highest* ordinal and working down to zero: the reverse order from initial creation, though it still respects the same underlying principle of touching one ordinal at a time and waiting for it to become `Ready` before moving to the next. Raising `partition` to a number greater than zero is the StatefulSet-specific trick to know: it tells the controller to only update ordinals at or above that number, leaving everything below untouched. Setting `partition: 2` on a three-replica StatefulSet updates only `shipment-archive-2`, holding `shipment-archive-0` and `shipment-archive-1` on the old template indefinitely. That's a built-in canary mechanism for validating a change against one ordinal before committing to the rest, with no separate canary Deployment or traffic-splitting infrastructure required.

## Why this example doesn't attempt real replication

A limitation already flagged earlier in this chapter deserves a direct explanation: three `postgres:17-alpine` containers run side by side under one StatefulSet does not produce a replicated database, and nothing in this example's manifests makes any attempt at wiring one up. Each ordinal's Postgres process starts with an empty database of its own and has no awareness that the other two ordinals exist, let alone any streaming-replication configuration connecting them. A database cluster that actually replicates on Kubernetes almost always delegates that problem to a purpose-built operator. CloudNativePG (the operator the §17 data mesh's own production database runs under) or Patroni are the common choices, specifically because correct replica promotion, failover, and split-brain avoidance are a substantial distributed-systems problem in their own right, layered on top of the StatefulSet mechanics this chapter covers rather than replacing them. The StatefulSet pattern here is the right foundation either way: stable identity and sticky storage are exactly what a real operator-managed replicated database still needs underneath it. Understanding this chapter's mechanics directly, without an operator's abstraction hiding them, is useful even for a reader whose actual production Postgres will always run through CloudNativePG or an equivalent, never through hand-written StatefulSet manifests like this example's.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Design & Build (20%), storage
> **Competency:** Understand StatefulSets, headless Services, and `volumeClaimTemplates` for stable per-Pod storage
> **Drill:** `kubectl get pvc -n patterns -l app.kubernetes.io/name=shipment-archive -o custom-columns=NAME:.metadata.name,STATUS:.status.phase`

> **🤖 Explore with your agent**
>
> "Scale shipment-archive from 3 replicas down to 1, then back up to 3, and show me whether the PVCs for the ordinals that were removed and re-added still have their original data or start fresh."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f stateful-service/02-statefulset.yaml
kubectl --context mof-patterns delete -n patterns -f stateful-service/01-service.yaml
kubectl --context mof-patterns delete -n patterns -f stateful-service/00-secret.yaml
kubectl --context mof-patterns delete pvc -n patterns -l app.kubernetes.io/name=shipment-archive
```

## Verification: examples/appendix-patterns/stateful-service/

The runnable example brings up `shipment-archive` at three replicas, confirms their ordered creation and per-ordinal DNS names, writes a row to one instance, deletes that Pod, and confirms both its name and its data return intact. It then deletes the whole StatefulSet and shows its PVCs surviving regardless. Full walkthrough in `examples/appendix-patterns/stateful-service/README.md`.
