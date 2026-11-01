---
title: "Elastic Scale"
order: 23
part: "Advanced"
description: "Three ways to change a workload's replica count without a human running kubectl scale: HPA and VPA reading the Pods themselves, and KEDA reading an external signal instead, which is the only path to zero."
duration: "30 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what a HorizontalPodAutoscaler actually reads, and why it can never legitimately scale a workload to zero
- Explain why running a VerticalPodAutoscaler in `Auto` mode alongside an HPA on the same resource is a real conflict, and how `Off` mode avoids it
- Define a KEDA `ScaledObject` and `HTTPScaledObject`, and explain how each one answers "is anyone waiting" without the workload needing to be running to measure it
- State precisely why scale-to-zero requires an external signal, and can never come from resource metrics alone

## Why this matters

Every autoscaler in this chapter answers the same question, "how many replicas should this workload have right now," but they disagree sharply about where the answer comes from, and that disagreement has a hard floor built into it. A HorizontalPodAutoscaler and a VerticalPodAutoscaler both read the Pods themselves: CPU and memory usage reported by the kubelet, the same `metrics-server` pipeline Predictable Demands introduced for `kubectl top pod`. That's a structural limitation, not a configuration choice: a metric computed from a running Pod's own resource usage cannot exist until a Pod is running, which means neither autoscaler can ever legitimately justify a replica count of zero. There's nothing to measure.

KEDA, the **K**ubernetes **E**vent-**d**riven **A**utoscaler, answers the same question from outside the Pods entirely: Kafka consumer lag, HTTP request concurrency, a queue depth, a cron schedule, any of dozens of external signals a workload's own absence doesn't prevent from existing. A Kafka topic still has a lag number when its consumer has zero replicas; an HTTP request still arrives at an interceptor sitting in front of a Deployment that currently has zero Pods. That's the entire mechanism behind scale-to-zero, and it's also exactly the gap this appendix's reconciliation plan flagged when it replaced a Knative Serving lane with KEDA: Knative's own scale-to-zero autoscaler reads request concurrency the same way KEDA's HTTP add-on does, just bundled inside a heavier serving abstraction this appendix doesn't otherwise need. KEDA gets the same scale-to-zero property on top of plain Deployments, with no separate serving runtime to adopt.

This chapter works through resource-based scaling on `shipping-service` first, then switches to event-based scaling on `graphql-gateway` for the scale-to-zero half of the story, and closes with a manifest-only look at the Kafka consumer-lag trigger this appendix's own `shipping-service` skeleton can't yet exercise live. A note on scope: more of this chapter's content (installing and operating cluster-wide autoscaling infrastructure) sits closer to the CKA curriculum's territory than CKAD's; the CKAD competency is narrower, understanding *that* an HPA or VPA exists and what it does to a workload, not configuring the autoscaling stack itself.

## HorizontalPodAutoscaler: replicas from CPU

An HPA needs exactly one thing from the Deployment it targets that nothing else in this chapter requires: an explicit CPU request on the container, because utilization is always computed as a percentage of that request, never of a limit or of absolute core counts.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: shipping-service
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: shipping-service
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

`averageUtilization: 50` means the HPA controller's own reconcile loop (yes, the identical observe-diff-act shape the Controller pattern describes, running inside `kube-controller-manager` against the metrics API rather than the core API) tries to keep the average CPU usage across every Pod at 50% of each Pod's own 100m request. Push usage above that and the controller computes a higher replica count and patches the Deployment's `spec.replicas` directly, no different in mechanism from a human running `kubectl scale`; let it settle back down and the controller eventually scales back in, after a stabilization window meant to avoid flapping on a brief spike. `minReplicas: 1` is the floor this autoscaler is structurally incapable of crossing on its own: there is no CPU percentage computable from zero running Pods, so the lowest `minReplicas` an HPA can be configured with that still means anything is one.

Generating load against `shipping-service`'s cheap `/health` endpoint from inside the cluster (a `busybox` Pod in a tight `wget` loop, since no load-generation tool needs installing beyond what the cluster already has) pushes the observed percentage up; watching `kubectl get hpa -w` shows the climb from one replica toward the ceiling of five, then the settle back down once the load stops. The replica count moves in both directions without anyone touching `kubectl scale` again, which is the whole value proposition: capacity that tracks real demand instead of a number a human guessed at deploy time and never revisited.

## VerticalPodAutoscaler: a second axis, carefully scoped

Where an HPA changes *how many* Pods exist, a VerticalPodAutoscaler changes *how big* each one is, computing a recommended CPU and memory request from a Pod's own historical usage rather than a fixed number a manifest hardcoded. This appendix's example runs it in the one mode that can't conflict with anything else on the cluster:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: shipping-service
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: shipping-service
  updatePolicy:
    updateMode: "Off"
```

`updateMode: "Off"` means the VPA's recommender component still watches `shipping-service`'s actual usage and still computes a recommendation, visible directly with `kubectl describe vpa`, but nothing in the cluster acts on that recommendation automatically: no Pod gets evicted, no Deployment gets patched. `Auto` mode would do both, evicting a Pod whose request has drifted too far from the current recommendation so its replacement can be created with the updated number, since a running Pod's resource requests can't be changed in place without a restart (a known general limitation prior Kubernetes versions share; some newer Kubernetes releases support limited in-place resize for specific cases, but VPA's own default mechanism remains evict-and-recreate). That's precisely the behavior that can't safely coexist with an HPA scaling the same resource on the same Deployment: VPA rewriting the CPU request out from under a running Pod changes the denominator the HPA's utilization percentage is computed against, mid-flight, with neither controller aware the other is reacting to a number it just changed. `Off` mode sidesteps the conflict entirely rather than trying to coordinate around it: a human (or a separate, intentional automation) reads the recommendation and decides whether to act on it, which keeps VPA's useful signal (this workload's real resource footprint, measured rather than guessed) without introducing a second controller silently fighting the first one over the same field.

![HPA and VPA on shipping-service reading the Pods themselves, contrasted with KEDA's HTTPScaledObject on graphql-gateway reading request concurrency from outside the Pods entirely, which is what lets it scale to zero]({{ "/assets/diagrams/appendix-23-elastic-scale.svg" | relative_url }})
*Resource-based scaling needs a running Pod to measure; event-based scaling measures the world outside the Pod instead, and that's the entire difference.*

## KEDA: the HTTP add-on, scaling a gateway from zero

`graphql-gateway` sits behind an `HTTPScaledObject`, the KEDA HTTP add-on's own CRD, scoped here to the exact shape the §17 data mesh runs in production against the same gateway:

```yaml
apiVersion: http.keda.sh/v1alpha1
kind: HTTPScaledObject
metadata:
  name: graphql-gateway-http
spec:
  hosts:
    - graphql-gateway.patterns
  scaleTargetRef:
    name: graphql-gateway
    kind: Deployment
    service: graphql-gateway
    port: 80
  replicas:
    min: 0
    max: 3
  scaledownPeriod: 30
  scalingMetric:
    concurrency:
      targetValue: 5
```

The add-on installs an **interceptor**, a small HTTP proxy that every request to `graphql-gateway` routes through first, keyed on the `Host` header named in `spec.hosts`. With the gateway's Deployment at zero replicas (its starting state in this chapter's manifest, since nothing short of this `HTTPScaledObject` has any business deciding otherwise), the interceptor holds the first incoming request open rather than returning an error, asks KEDA's generated HPA to scale the Deployment up from zero, waits for a Pod to report Ready, and only then forwards the held request through. Every request after that one is a normal proxy pass-through, since there's now a Ready Pod to send it to; `scalingMetric.concurrency.targetValue: 5` tells the generated HPA to add replicas once in-flight requests per replica exceed five, and `scaledownPeriod: 30` is how long the Deployment has to sit with zero in-flight requests before KEDA removes the generated HPA and sets replicas back to zero.

That one request's extra latency, the gap between "request arrives at zero replicas" and "first Pod reports Ready," is the entire cost of scale-to-zero, paid exactly once per idle-to-active transition rather than continuously. Nothing about this mechanism requires Knative, a separate serving runtime, or a custom resource beyond the `HTTPScaledObject` itself: `graphql-gateway`'s own manifest is a plain Deployment and a plain Service, identical in shape to every other Deployment in this appendix, with the scale-to-zero behavior bolted on entirely from outside.

## KEDA: the Kafka consumer-lag shape, shown but not run

The other canonical KEDA trigger measures a queue's backlog rather than HTTP concurrency, and the §17 data mesh runs it in production against `notification-service`, a Kafka consumer with its own consumer group and topic subscription:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: notification-service-scaler
spec:
  scaleTargetRef:
    name: notification-service
  pollingInterval: 5
  cooldownPeriod: 30
  minReplicaCount: 0
  maxReplicaCount: 3
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: capstone-kafka-kafka-bootstrap.capstone.svc.cluster.local:9092
        consumerGroup: notification-service
        topic: order-placed
        lagThreshold: "5"
```

This appendix's own `shipping-service` is the same REST-only skeleton every other chapter uses: `/health`, `/healthz`, a Postgres connection, nothing consuming a Kafka topic. The example directory includes the identical manifest shape pointed at `shipping-service` purely as a reference, explicitly not applied in this chapter's own run, because its `bootstrapServers` trigger would have nothing real to poll against on the `mof-patterns` profile. Reading it alongside the `HTTPScaledObject` above still pays off: `lagThreshold: "5"` means one replica for every five messages of unprocessed backlog, computed by KEDA polling Kafka's own committed-offset-versus-log-end-offset gap for that consumer group every `pollingInterval` seconds, entirely independent of whether a consumer is currently running to report it. That independence from a running Pod is precisely the property an HPA's CPU-percentage metric structurally lacks, and it's the reason this trigger, like the HTTP add-on, can legitimately set `minReplicaCount: 0` where an HPA never could.

## Diagnosing a stuck autoscaler

An HPA that isn't scaling almost always traces back to one of two causes, both visible directly in `kubectl describe hpa` without touching logs anywhere: either the target Deployment's containers never declared a CPU request, in which case `TARGETS` reads `<unknown>/50%` indefinitely because there's no denominator to compute a percentage against, or `metrics-server` itself isn't reachable, in which case the `AbleToScale` condition in the HPA's own `status.conditions` reports `False` with a reason naming the metrics-API failure directly. Both are config problems a human caused, not autoscaler bugs, and both show up as the exact same symptom (replicas never move) to someone who only checks `kubectl get hpa` instead of `describe`. The KEDA-generated HPA behind a `ScaledObject` or `HTTPScaledObject` fails the identical way when its own trigger can't resolve: `kubectl describe scaledobject` surfaces a connection error to the named `bootstrapServers` the same way `describe hpa` surfaces a metrics-API failure, which is exactly the failure mode this chapter's own reference-only Kafka `ScaledObject` would hit if someone applied it against a `shipping-service` with no real Kafka cluster behind it.

## Why the two families don't compete

Nothing in this chapter asks a reader to choose HPA versus KEDA as though they were alternatives solving the same problem. KEDA doesn't replace HPA; the moment a `ScaledObject` or `HTTPScaledObject` is created, KEDA generates an ordinary HPA behind the scenes, wired to KEDA's own external-metrics adapter instead of `metrics-server`. From the generated HPA's own perspective, Kafka lag or HTTP concurrency is just another external metric, scaled the identical way a CPU percentage would be, down to the same stabilization-window behavior on scale-down. The only new capability KEDA adds on top of what an HPA already does is the ability to delete that generated HPA entirely and hold a Deployment at zero, something an HPA object, which always assumes at least one replica exists to measure, has no mechanism to express on its own. Treat HPA and VPA as the baseline every resource-backed workload should have (the `minReplicas: 1` floor is a direct statement of what a Pod's own resource usage can tell you), and reach for KEDA specifically for the subset of workloads, consumers and bursty HTTP services both, where the correct answer to "how many replicas right now" is sometimes legitimately zero.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Deployment (20%): note: HPA/VPA/KEDA installation and tuning lean toward CKA's cluster-operations territory; the CKAD competency is understanding what each autoscaler reads and does to a workload, not configuring the autoscaling stack from scratch
> **Competency:** Understand HorizontalPodAutoscaler and VerticalPodAutoscaler for elastic scaling, including event-driven scale-to-zero
> **Drill:** `kubectl get hpa,scaledobject,httpscaledobject -n patterns`

> **🤖 Explore with your agent**
>
> "Lower graphql-gateway-http's scalingMetric.concurrency.targetValue from 5 to 1, reapply it, and show me the difference in how quickly replicas climb under the same load as before."

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f elastic-scale/05-gateway-httpscaledobject.yaml
kubectl --context mof-patterns delete -n patterns -f elastic-scale/04-gateway-deployment.yaml
helm uninstall --kube-context mof-patterns keda-add-ons-http -n keda
helm uninstall --kube-context mof-patterns keda -n keda
kubectl --context mof-patterns delete -n patterns -f elastic-scale/03-vpa.yaml --ignore-not-found
kubectl --context mof-patterns delete -n patterns -f elastic-scale/02-hpa.yaml
kubectl --context mof-patterns delete -n patterns -f elastic-scale/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f elastic-scale/00-postgres.yaml
```

## Verification: examples/appendix-patterns/elastic-scale/

The runnable example puts an HPA and a Recommendation-only VPA on `shipping-service`, confirms the HPA's replica count actually climbs under generated load and settles back down, then switches to `graphql-gateway` behind a KEDA `HTTPScaledObject` to confirm the full zero-to-N-to-zero lifecycle through the HTTP add-on's interceptor. A reference-only Kafka consumer-lag `ScaledObject` rounds out the manifest set without being applied live. Full walkthrough, including the exact `helm` install commands for KEDA, in `examples/appendix-patterns/elastic-scale/README.md`.
