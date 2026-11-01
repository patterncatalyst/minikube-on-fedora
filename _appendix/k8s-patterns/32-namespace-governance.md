---
title: "Namespace Governance"
order: 32
part: "CKAD gaps"
description: "The namespace-level complement to a pod's own resource declarations: ResourceQuota caps a namespace's total consumption, LimitRange defaults and bounds every container in it, and PriorityClass still decides who wins when both are tight."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Cap a namespace's total pod count, requests, and limits with a
  `ResourceQuota`, and read `kubectl describe resourcequota` to see what's
  used against what's allowed
- Set a `LimitRange`'s `default`, `defaultRequest`, `min`, and `max` so every
  container in a namespace gets sane resource values even when its own
  manifest doesn't specify any
- Explain the order LimitRange and ResourceQuota admission run in, and why
  that order is what makes a `limits.cpu` quota compatible with a container
  that sets no CPU limit of its own, by design
- Recap `PriorityClass` as the piece namespace governance doesn't replace:
  who wins when a tight quota or a resource-pressured node forces a choice

## Why this matters

Predictable Demands covers requests, limits, and priority at the
level of one Pod: a container declares what it needs, and the scheduler and
kubelet honor that declaration. Nothing in that chapter stops every team
sharing a cluster from each declaring generous, individually reasonable
requests that together add up to far more than the cluster actually has, or
stops one careless manifest from omitting resource declarations altogether
and quietly consuming whatever's left. That's a cluster-operator problem, not
a workload-author problem, and it's exactly the gap `ResourceQuota` and
`LimitRange` close: the first caps what a namespace can consume in total, the
second bounds and defaults what any single container inside it can ask for.
Both sit squarely in CKAD's Application Environment, Configuration and
Security domain, the exam's largest single slice at 25%.

The shipping example in this chapter reuses two of the same shapes from
Predictable Demands (`shipping-service`'s requests and limits, and the
`patterns-high-priority` `PriorityClass`), specifically so the contrast with
namespace-level governance is concrete: the same pod, the same resource
numbers, now admitted (or rejected) against rules nobody wrote directly into
its own Deployment.

## ResourceQuota: capping the namespace's total

A `ResourceQuota` is a single object per namespace (in practice; a namespace
can technically hold more than one, and the strictest hard limit on each
dimension wins) that caps aggregate consumption across every pod in that
namespace combined:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: patterns-quota
  namespace: patterns
spec:
  hard:
    pods: "3"
    requests.cpu: "1"
    requests.memory: "1Gi"
    limits.cpu: "2"
    limits.memory: "2Gi"
```

`pods` counts every pod regardless of its resource numbers; `requests.cpu` /
`requests.memory` and `limits.cpu` / `limits.memory` sum the declared values
across every container of every pod. This chapter's quota sets `pods` tight
(3: the disposable Postgres plus two `shipping-service` replicas) and the
cpu/memory dimensions generously, so the one failure mode that actually bites
in the worked example is the pod count, not a resource total: a choice made
to keep the first thing you see the simplest, most common exam
scenario.

```bash
kubectl scale deployment/shipping-service -n patterns --replicas=3
```

A third replica never reaches `Pending`, `CreateContainerConfigError`, or any
other pod-level state at all, because no Pod object is ever created for it:
the ReplicaSet controller's attempt to create one is rejected outright by
quota admission, and the rejection shows up as an **event on the ReplicaSet**,
not on any pod:

```bash
kubectl get events -n patterns --field-selector reason=FailedCreate
```

This is the detail most worth carrying out of this section: a ResourceQuota
violation is a different *kind* of failure than the hard-requirement failures
Predictable Demands covers. A missing ConfigMap or PVC still creates a Pod
object that sits visibly in `Pending` or `CreateContainerConfigError`,
reporting its own problem through its own events. A quota violation prevents
the Pod object from existing in the first place: there's nothing to `kubectl
describe pod` because there is no pod, and the only trail is the controller's
event and
`kubectl describe resourcequota`, which shows `Used` against `Hard` for every
dimension the quota tracks.

`ResourceQuota` has one more consequence worth knowing before it surprises
you: declaring `requests.cpu` or `limits.cpu` (or the memory equivalents) in
a quota means every *new* pod created in that namespace must specify that
exact dimension explicitly, or be rejected. A container with no CPU request
at all is inadmissible the moment a `requests.cpu` quota exists, no exception.
`shipping-service`'s Deployment, following Predictable Demands' own reasoning,
sets no CPU *limit*, by design. Reconciling that choice with a
`limits.cpu` quota is exactly what the next section's `LimitRange` provides.

## LimitRange: defaults, minimums, and maximums per container

A `LimitRange` operates one level down from a `ResourceQuota`, on individual
containers rather than namespace totals, and it does two different jobs at
once: it supplies a value a container didn't specify, and it rejects a value
a container specified that falls outside an allowed band.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: patterns-limits
  namespace: patterns
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 50m
        memory: 128Mi
      default:
        cpu: 200m
        memory: 256Mi
      min:
        cpu: 25m
        memory: 64Mi
      max:
        cpu: 500m
        memory: 512Mi
```

`defaultRequest` and `default` are the mutating half: any container that
omits a request or a limit for a given resource gets these values stamped in
at admission time, before the object is ever stored. A pod applied with no
`resources` block at all comes back from the API server with a full
`resources` section already populated:

```bash
kubectl apply -n patterns -f namespace-governance/06-pod-no-resources.yaml
kubectl get pod inventory-defaults-check -n patterns \
  -o jsonpath='{.spec.containers[0].resources}{"\n"}'
# {"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"128Mi"}}
```

Nothing in that pod's own manifest set any of those four numbers. This also
answers the question the previous section left open: `shipping-service`'s
container specifies a CPU *request* but no CPU *limit*, and the namespace's
`ResourceQuota` requires one. The `LimitRange`'s `default.cpu: 200m` supplies
exactly that missing value, and it does so **before** quota admission runs:
LimitRange is a mutating admission step, ResourceQuota a validating one, and
Kubernetes always runs mutating admission ahead of validating admission for
the same request. By the time the quota check inspects the pod, the CPU limit
LimitRange just added is already there to count.

`min` and `max` are the validating half, and they apply to any value in the
final pod spec regardless of whether it arrived as an explicit author choice
or a LimitRange default: a container that explicitly asks for more than
`max` is rejected outright, with no pod created, the same way a quota
rejection creates nothing:

```bash
kubectl apply -n patterns -f namespace-governance/07-pod-over-max.yaml
# Error: ... maximum cpu usage per Container is 500m, but limit is 600m
```

That rejection happens immediately, synchronously, as part of the `kubectl
apply` call itself: there's no controller retry loop to watch, because
there's no object for a controller to retry creating. Compare that to the
`ResourceQuota` pod-count rejection two sections up, which showed up as a
*ReplicaSet* event because a Deployment's ReplicaSet controller does retry: a
bare Pod manifest applied directly against a tight LimitRange fails exactly
as synchronously as a quota violation does when nothing stands between the
`kubectl apply` and the API server's admission chain.

![A namespace with a ResourceQuota capping totals and a LimitRange defaulting and bounding each container, alongside the PriorityClass recap that governs scheduling and eviction order underneath both]({{ "/assets/diagrams/appendix-32-namespace-governance.svg" | relative_url }})
*ResourceQuota counts and caps; LimitRange defaults and bounds; PriorityClass decides who wins when either one is tight.*

## PriorityClass, again: what quota and limits don't decide

`ResourceQuota` and `LimitRange` both answer "how much," at the namespace and
container level respectively. Neither answers "who first," and that
question doesn't go away just because every pod in a namespace fits
comfortably under quota. If the quota is exactly full (as this chapter's
`pods: "3"` is exactly full by design, once Postgres and two `shipping-service`
replicas are running) and a higher-priority workload needs to land, quota
alone offers no mechanism to make room: it only ever says yes or no to a new
pod, never which existing one should go.

That's still `PriorityClass`'s job, unchanged from Predictable Demands:
`patterns-high-priority`'s `value: 1000000` makes the scheduler place a pod
carrying that class ahead of pending pods at the default priority, and makes
the kubelet's node-pressure eviction logic consider priority before it
considers QoS class when choosing what to evict under a resource squeeze. A
`ResourceQuota` can optionally be scoped to a specific `PriorityClass` via a
`scopeSelector` (a quota that applies only to pods at or above a given
priority), which lets an operator grant a generous quota to high-priority
workloads and a tighter one to everything else in the same namespace.
Building that scoped example is **[verify]** left out of this chapter's
runnable manifests since it needs more exam-irrelevant setup than it's worth,
but it's a real, documented field worth knowing exists. The three mechanisms
layer cleanly: `ResourceQuota` caps the whole namespace, `LimitRange` bounds
and defaults each container inside it, and `PriorityClass` decides order when
either one runs out of room: three different cluster-operator concerns,
each answering a question the other two don't.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration and Security (25%)
> **Competency:** Create and use ResourceQuota and LimitRange to govern a namespace's resource consumption, and relate them to a Pod's own PriorityClass
> **Drill:** `kubectl describe resourcequota patterns-quota -n patterns` (read `Used` against `Hard` for every tracked dimension, then predict whether the next `kubectl apply` in this chapter succeeds before running it)

> **🤖 Explore with your agent**
>
> "Add a ResourceQuota scopeSelector that applies a separate, tighter quota only to pods WITHOUT the patterns-high-priority PriorityClass, then show me a high-priority shipping-service pod still getting admitted after the unscoped quota alone would have rejected it."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f namespace-governance/05-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f namespace-governance/06-pod-no-resources.yaml
kubectl --context mof-patterns delete -n patterns -f namespace-governance/04-configmap.yaml
kubectl --context mof-patterns delete -n patterns -f namespace-governance/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f namespace-governance/03-limitrange.yaml
kubectl --context mof-patterns delete -n patterns -f namespace-governance/02-resourcequota.yaml
kubectl --context mof-patterns delete -f namespace-governance/01-priorityclass.yaml
```

## Verification: examples/appendix-patterns/namespace-governance/

The runnable example applies the quota and limit range before any workload,
deploys `shipping-service` at two replicas (exactly filling the pod quota
alongside the disposable Postgres), confirms a third replica is rejected,
then applies one pod with no resources (confirming the LimitRange defaults
land) and one pod over the LimitRange's max (confirming it's rejected
outright). Full walkthrough in
`examples/appendix-patterns/namespace-governance/README.md`.
