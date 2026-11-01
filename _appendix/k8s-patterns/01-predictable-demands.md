---
title: "Predictable Demands"
order: 1
part: "Foundational"
description: "Declare what a container needs to run: CPU and memory requests and limits, a PriorityClass, and the ConfigMaps and PersistentVolumeClaims it can't start without."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Set CPU and memory requests and limits on a container, and explain what each number actually bounds
- Assign a Pod a `PriorityClass` and explain how it changes scheduling and eviction order
- Reason about a Pod stuck in `Pending` or `CreateContainerConfigError` because a ConfigMap or PersistentVolumeClaim it depends on doesn't exist yet
- Read `kubectl describe pod` events to diagnose which hard requirement is still missing

## Why this matters

A container that doesn't say how much CPU and memory it needs is a container the scheduler is guessing about. Pack enough unguessed pods onto a node and one of two things happens: the node runs out of memory and the kernel's OOM killer picks a victim more or less at random, or CPU contention turns every pod's latency unpredictable at once. Neither failure shows up in a code review. Both show up in production, usually during the busiest hour of the day.

Predictable Demands is the first Kubernetes pattern because everything else depends on it. A rolling update (the next chapter) assumes the scheduler can place a replacement pod somewhere. Autoscaling assumes a replica's resource footprint is known ahead of time. None of that works if the pods already running haven't told the scheduler what they cost.

The pattern has three parts: declare CPU and memory requests and limits on every container, use a `PriorityClass` to tell the scheduler and the kubelet's eviction logic which pods matter more under pressure, and treat ConfigMaps and PersistentVolumeClaims as hard requirements a Pod should refuse to start without, rather than optional extras a container silently does without.

## Requests and limits

`shipping-service`, the §17 data mesh's fulfillment data product, ships as a plain FastAPI container with no resource declarations of its own: a Kubernetes manifest adds them. The example's `04-deployment.yaml` sets:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 192Mi
  limits:
    memory: 512Mi
```

A **request** is what the scheduler reserves. When the scheduler is deciding which node has room for this Pod, it looks at each node's allocatable capacity minus the requests already placed there, never at actual usage. Request 100 millicores and 192Mi, and the scheduler only considers nodes with at least that much unclaimed, regardless of whether the container ever uses it.

A **limit** is what the kernel enforces once the container is running. Exceed the memory limit and the kernel's cgroup controller kills the process with an out-of-memory error, visible as `OOMKilled` in `kubectl describe pod`. Exceed a CPU limit and the container is throttled, not killed: the kernel's CFS bandwidth controller simply denies it further CPU time until the next accounting period.

Notice the memory limit here is 512Mi (over double the 192Mi request) but there's no CPU limit at all. That's deliberate, not an oversight. A CPU limit throttles a container even when the node has idle cores sitting right next to it, because CFS bandwidth accounting works per-container, not per-node; a memory limit protects the node from a single leaking process without that downside, since a process using slightly more memory than it asked for usually isn't a cluster-wide problem the way one hogging every core is. The combination (requests close to what the service actually needs, a memory limit for safety, no CPU limit) is a common, well-reasoned production default, not a shortcut.

The two numbers also decide the Pod's **Quality of Service class**, which never appears explicitly in the manifest but governs eviction order. Requests below limits, as here, earns `Burstable`: if the node runs short on memory, the kubelet evicts `BestEffort` pods (no requests or limits at all) first, then `Burstable` pods, and only evicts `Guaranteed` pods (requests exactly equal to limits, on every resource) as a last resort. Check a running Pod's class directly:

```bash
kubectl get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].status.qosClass}'
```

## PriorityClass

Quality of Service decides eviction order inside a class; `PriorityClass` decides which pods get first claim on a node at all, independent of QoS. The example's `01-priorityclass.yaml` defines one:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: patterns-high-priority
value: 1000000
globalDefault: false
```

`value` is an arbitrary integer; higher wins. The Deployment's Pod template sets `priorityClassName: patterns-high-priority`, which does two things. First, if the scheduler can't fit every pending pod, it schedules higher-priority pods first, queue position be damned. Second, if a node is critically short on resources, the kubelet's node-pressure eviction considers priority ahead of QoS class when choosing what to evict: a `Guaranteed` pod at default priority can still be evicted before a `Burstable` pod at high priority, because priority is checked first. In a fulfillment system, that's the right order: a shipping confirmation that's late by thirty seconds is a worse outage than a batch report that's late by an hour, and the PriorityClass encodes that judgment once, in one manifest, instead of hoping every on-call engineer remembers it during an incident.

![ConfigMap and PersistentVolumeClaim as hard requirements feeding a Pod, with the scheduler applying its PriorityClass]({{ "/assets/diagrams/appendix-01-predictable-demands.svg" | relative_url }})
*A Pod with declared requests and limits, gated on a ConfigMap and a PersistentVolumeClaim, and scheduled under a PriorityClass.*

## Hard requirements: ConfigMap and PersistentVolumeClaim

The third part of the pattern is less about numbers and more about sequencing. `shipping-service` reads its Postgres schema name from a `SERVICE_SCHEMA` environment variable, and the example wires that variable to a ConfigMap key instead of a literal string:

```yaml
env:
  - name: SERVICE_SCHEMA
    valueFrom:
      configMapKeyRef:
        name: shipping-config
        key: schema
```

Apply the Deployment before the ConfigMap exists and the Pod gets scheduled, then sits in `CreateContainerConfigError`: the kubelet can schedule a Pod whose environment it can't yet populate, but it can't start the container until every `configMapKeyRef` and `secretKeyRef` resolves. `kubectl describe pod` reports the specific missing key, not just a generic failure.

A PersistentVolumeClaim behaves differently because it's checked earlier, during scheduling rather than during container start. `03-pvc.yaml` claims 64Mi with no `storageClassName`, so it binds against whatever the cluster's default storage class is (on minikube, the `standard` class backed by the `storage-provisioner` addon, enabled by default). Apply the Deployment before the PVC exists and the Pod never gets scheduled at all: it sits in `Pending`, and the scheduling event reads `persistentvolumeclaim "shipping-data" not found`. Create the PVC after the fact and the next scheduling attempt succeeds without touching the Deployment.

Both failure modes are visible, not silent: a missing ConfigMap or PVC is not a shipping-service bug, it's a cluster state the Pod correctly refuses to paper over. That's the entire point of treating them as hard requirements. The alternative (a container that falls back to a hardcoded default schema name when the ConfigMap is missing, or writes to local ephemeral storage when the PVC isn't bound) hides a misconfiguration until it causes a data problem somewhere downstream, usually much later and much harder to trace back to its cause.

## Comparing requests against actual usage

Declaring requests and limits is only half the job; the other half is checking whether the declared numbers still match reality once the service has run under real traffic for a while. `kubectl top pod` reads live usage from the metrics pipeline (the same `metrics-server` addon the `mof-patterns` profile enables) and prints it next to each Pod, which is the fastest way to tell a request that's too generous (wasted scheduling headroom on every node that could run this Pod) from one that's too tight (a container constantly brushing its limit):

```bash
kubectl top pod -n patterns -l app.kubernetes.io/name=shipping-service
```

A container that's repeatedly `OOMKilled` almost always traces back to a memory limit set lower than the process's real working set, visible in `kubectl describe pod` as `Last State: Terminated, Reason: OOMKilled`. The fix is rarely cleverness in the application; it's raising the limit (and, if the request was equally tight, raising that too, so the scheduler doesn't keep placing this Pod somewhere that can't actually support it). Ephemeral storage can be requested and limited the same way CPU and memory are (`resources.requests.ephemeral-storage` and `resources.limits.ephemeral-storage`), which matters for any container writing logs, temp files, or an unpacked archive to its writable layer rather than to a volume; left undeclared, a container with a runaway disk write can trigger node-level eviction for every Pod on that node, not just itself, since the kubelet's disk-pressure check isn't scoped per-container the way an OOM is.

Everything in this chapter so far declares demands at the Pod level. A `LimitRange` does the equivalent at the namespace level: a default request and limit every container in that namespace inherits if its own manifest omits one, plus a minimum and maximum any explicit value has to stay inside. A `ResourceQuota` caps the namespace's total consumption across every Pod combined. Neither replaces per-container requests and limits; both exist to keep one namespace's defaults sane and one namespace's total footprint bounded, which is a cluster operator's concern layered on top of the per-workload concern this chapter covers.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%)
> **Competency:** Define resource requirements (requests/limits) for a container, and understand how a Pod references a ConfigMap or PersistentVolumeClaim
> **Drill:** `kubectl set resources deployment/shipping-service -n patterns --requests=cpu=150m,memory=256Mi --limits=memory=768Mi`

> **🤖 Explore with your agent**
>
> "Add a `LimitRange` to the `patterns` namespace that sets default CPU and memory requests for any container that omits them, then show me a Pod in that namespace scheduled without explicit resources to confirm the default applied."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f predictable-demands/04-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f predictable-demands/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f predictable-demands/03-pvc.yaml
kubectl --context mof-patterns delete -n patterns -f predictable-demands/02-configmap.yaml
kubectl --context mof-patterns delete -f predictable-demands/01-priorityclass.yaml
```

## Verification: examples/appendix-patterns/predictable-demands/

The runnable example builds `shipping-service` onto the `mof-patterns` profile, applies the Deployment in the wrong order first, to surface both the `CreateContainerConfigError` and the `Pending` scheduling failure, then resolves each one and confirms the Pod reaches `Ready` with the declared priority and resources intact. Full walkthrough, including the exact `kubectl` sequence and cleanup, in `examples/appendix-patterns/predictable-demands/README.md`.
