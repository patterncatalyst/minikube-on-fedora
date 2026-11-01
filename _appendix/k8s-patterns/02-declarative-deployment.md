---
title: "Declarative Deployment"
order: 2
part: "Foundational"
description: "Roll a new version out with a Deployment's RollingUpdate and Recreate strategies, then compare them against kubectl rollout status, history, and undo."
duration: "20 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain what a `Deployment` actually manages, and why you update the Deployment rather than the Pods
- Tune `maxSurge` and `maxUnavailable` to control how a `RollingUpdate` trades extra capacity against guaranteed availability
- Compare `RollingUpdate` against `Recreate` and state which workloads need the latter
- Use `kubectl rollout status`, `kubectl rollout history`, and `kubectl rollout undo` to drive and reverse a rollout

## Why this matters

A Deployment is a declaration, not a one-time instruction. You don't tell Kubernetes "start three pods now"; you tell it "three pods matching this template should always exist," and a controller spends the lifetime of that Deployment reconciling reality toward that statement. Change the template (a new image tag, a new environment variable, anything in `spec.template`) and the same controller treats the difference between old and new as work to do, not as a one-off command to execute.

That reconciliation loop is what makes a rollout safe to automate. `kubectl set image` doesn't restart pods directly; it edits the Deployment's desired state, and the Deployment controller works out how to get there. Which strategy it uses for "how" is the entire subject of this chapter, and it's the difference between a release nobody notices and a release that pages someone at 2 a.m.

## Deployment, ReplicaSet, Pod

A Deployment never manages Pods directly. It manages a `ReplicaSet`, and the ReplicaSet is what actually owns the Pods: `kubectl get rs -n patterns` shows this layer directly, usually invisible because the Deployment's own status summarizes it away. Every distinct Pod template (every image tag, every environment variable change) gets its own ReplicaSet, created fresh, scaled up as the rollout proceeds. The *previous* template's ReplicaSet isn't deleted when a rollout finishes; it's scaled down to zero replicas and kept around, which is the entire mechanism behind `kubectl rollout undo`: a rollback is nothing more than scaling the old ReplicaSet back up and the current one back down, using the exact same `RollingUpdate` or `Recreate` logic that drove the forward rollout. `revisionHistoryLimit` (covered below) is really capping how many of these retired ReplicaSets stick around.

This layering is also why a Deployment's `spec.selector` is immutable after creation: the selector is how the Deployment finds its own ReplicaSets and, through them, its Pods, and changing it out from under a running rollout would orphan everything already running. Changing the Pod *template* (`spec.template`) is exactly what triggers a new ReplicaSet and a new rollout; changing the *selector* that decides which Pods belong to this Deployment at all is a different, far riskier operation that Kubernetes refuses outright.

## RollingUpdate: replace without a gap

The example deploys `shipping-service` at three replicas with an explicit strategy:

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

`maxSurge` caps how many Pods above the replica count the controller may create at once; `maxUnavailable` caps how many may be missing at once. With `maxSurge: 1` and `maxUnavailable: 0`, a rollout of three replicas can briefly run four Pods (three old, one new) but never fewer than three. Bump the image tag:

```bash
kubectl set image deployment/shipping-service -n patterns shipping-service=shipping-service:v2
```

The controller creates one new Pod, waits for it to pass its readiness probe, then terminates one old Pod and repeats, cycling through all three without the Service's endpoint count ever dropping. That wait is what makes the whole guarantee hold: a `RollingUpdate` with no readiness probe at all isn't actually safe, because the controller has no signal to wait on and will route traffic to a Pod that's still initializing regardless. The Deployment's `readinessProbe` against `/healthz` (covered in full in the next chapter) is what makes `maxUnavailable: 0` a real guarantee instead of a hopeful one.

`kubectl rollout status deployment/shipping-service -n patterns` blocks until the rollout finishes or fails, which is what a CI pipeline calls after triggering a deploy. `kubectl rollout history deployment/shipping-service -n patterns` lists every revision the Deployment has gone through, an audit trail with no extra tooling to install. And when the new version turns out to be wrong, `kubectl rollout undo deployment/shipping-service -n patterns` rolls back to the previous revision using exactly the same mechanism, zero-downtime guarantees included, because undo is just another declared-state change for the same controller to reconcile toward.

![RollingUpdate keeps at least three Pods serving at all times by surging one extra; Recreate drops to zero Pods before the replacement starts]({{ "/assets/diagrams/appendix-02-declarative-deployment.svg" | relative_url }})
*RollingUpdate overlaps old and new Pods to avoid a gap; Recreate tears every replica down before any replacement starts.*

## Recreate: when overlap isn't safe

`RollingUpdate` assumes old and new Pods can coexist. Most stateless HTTP services satisfy that assumption trivially; a few workloads don't, usually because two versions holding an exclusive lock, writing to the same non-shared volume, or speaking an incompatible wire protocol to each other would corrupt something. For those, the `Recreate` strategy is the correct alternative:

```yaml
spec:
  replicas: 3
  strategy:
    type: Recreate
```

`Recreate` terminates every existing Pod before creating any replacement. There's no `maxSurge` or `maxUnavailable` to tune, because there's no overlap to bound: the Deployment goes from three old Pods to zero Pods to three new Pods, in that order, and the "zero" step holds until every old Pod has actually terminated.

Switch the running Deployment to `Recreate` and repeat the same image bump:

```bash
kubectl apply -f declarative-deployment/02-deployment-recreate.yaml
kubectl set image deployment/shipping-service -n patterns shipping-service=shipping-service:v2
```

A curl loop against the Service, running the whole time, shows the difference immediately: during the `RollingUpdate` every request succeeded; during `Recreate` there's a stretch (bounded by how fast the old Pods terminate and the new ones pass their startup probe) where every request fails, because there are zero Pods behind the Service. That gap isn't a bug in `Recreate`; it's the strategy doing exactly what it promises, which is why the decision to use it belongs to whoever understands the workload's actual constraint, not to whichever default the manifest happened to inherit.

## Choosing between them

The decision is almost always made by the workload, not by preference. A stateless HTTP service with a correct readiness probe should default to `RollingUpdate`: it costs nothing but a moment of extra capacity and buys continuous availability. A workload where two versions actively conflict (schema migrations that aren't backward-compatible, exclusive file locks, singleton processes) needs `Recreate`, and attempting a rolling update anyway just delays the conflict until it hits in production instead of catching it at deploy time. There's no scenario where `Recreate` is strictly safer for a stateless service; it only trades downtime for correctness on workloads that need that trade.

## Reading a Deployment's own conditions

`kubectl rollout status` is convenient, but the signal it's reading is already on the Deployment object itself, as a pair of conditions visible in `kubectl describe deployment`. `Progressing` reports whether the rollout is actively making forward progress (new Pods coming up, old ones going down) and flips to `False` with reason `ProgressDeadlineExceeded` if nothing has changed within `spec.progressDeadlineSeconds` (ten minutes by default): a new Pod stuck in `ImagePullBackOff`, for instance, would eventually surface here even if nobody is watching `rollout status` at the time. `Available` reports whether enough replicas have been continuously ready for at least `minReadySeconds` to count as the Deployment satisfying its own availability target; a Pod that flaps between ready and not ready resets that clock, which is precisely why a flaky readiness probe is worse than a strict one that just takes longer to pass.

Two more knobs shape how a rollout behaves without changing which strategy is in use. `kubectl rollout pause deployment/shipping-service -n patterns` freezes a `RollingUpdate` mid-flight, useful for holding a partial rollout at, say, one new Pod out of three while watching its metrics before committing further; `kubectl rollout resume` picks it back up from exactly where it stopped. And `revisionHistoryLimit` (ten by default) caps how many old `ReplicaSet` revisions a Deployment keeps around purely for `rollout undo` and `rollout history` to reference; set it low on a Deployment that rolls out often and `rollout undo` eventually has nothing further back to return to.

`kubectl rollout undo` also accepts a specific target with `--to-revision=N`, which matters once more than one rollout has happened since the version a reader actually wants back: undoing twice in a row doesn't walk two steps further into history, it alternates between the two most recent revisions, since each undo is itself a new revision pointing at an old template. Reaching revision three from revision five needs `--to-revision=3` explicitly, not two bare `rollout undo` calls.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Deployment (20%)
> **Competency:** Apply rolling and non-rolling update strategies, and use kubectl to manage rollouts
> **Drill:** `kubectl rollout history deployment/shipping-service -n patterns --revision=2`

> **🤖 Explore with your agent**
>
> "Add a `minReadySeconds` of 10 to the shipping-service Deployment, trigger another rolling update, and show me how that changes the pace of the rollout compared to the default of 0."

## Cleanup

```bash
kubectl --context mof-patterns delete deployment/shipping-service service/shipping-service -n patterns
kubectl --context mof-patterns delete -n patterns -f declarative-deployment/00-postgres.yaml
```

## Verification: examples/appendix-patterns/declarative-deployment/

The runnable example builds two tags of `shipping-service`, rolls from one to the other under `RollingUpdate` while a curl loop confirms zero failed requests, checks `rollout history` and `rollout undo`, then switches to `Recreate` and repeats the rollout to show the contrast directly. Full walkthrough in `examples/appendix-patterns/declarative-deployment/README.md`.
