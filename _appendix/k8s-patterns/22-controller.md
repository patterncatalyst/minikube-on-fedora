---
title: "Controller"
order: 22
part: "Advanced"
description: "The reconcile loop every controller shares: watch an object, compute the difference between its current and desired state, and act on only that difference, whether the controller ships with Kubernetes or is code you wrote yourself."
duration: "30 min"
---

## Learning objectives

By the end of this chapter you can:

- Explain the observe-diff-act reconcile loop and why it's level-triggered rather than edge-triggered
- Trace a built-in controller (the ReplicaSet controller) through that same loop using nothing but `kubectl`
- Read a `controller-runtime` reconciler's `SetupWithManager` to see what it watches and why
- Explain what a controller owner reference buys a reconciler, and what breaks without one

## Why this matters

Every pattern chapter before this one described a shape a Pod or a set of Pods should hold: a resource request, a probe, a volume, a label. None of those chapters said who keeps that shape true once the cluster starts drifting away from it, because the answer is always the same, and it's the subject of this one. A Deployment's `replicas: 3` isn't a command that runs once and finishes; it's a standing instruction that something, somewhere, keeps re-checking for as long as the Deployment exists. That something is a controller, and the loop it runs is the single mechanism the rest of Kubernetes is built on top of.

A controller is a program that watches one kind of object (or several), and for each one, repeatedly computes the gap between what the object's spec says should exist and what's actually running, then closes that gap. Not "handles an event." Not "runs a callback when something changes." A controller doesn't trust that it saw every event, doesn't care whether the triggering event was a create, an update, a delete, or nothing at all (a periodic resync). It only cares about the current difference between desired and observed state, computed fresh every time it runs. That property has a name, **level-triggered**, and it's the reason a controller that misses an event, crashes mid-reconcile, or starts fresh after the whole control plane reboots still converges the cluster back to correct: the next time it runs, the diff is still sitting there waiting to be closed, regardless of how it got that way.

This chapter proves that claim two ways against the same cluster. First with a controller nobody in this appendix wrote: the ReplicaSet controller, compiled into `kube-controller-manager` and running on every Kubernetes cluster that has ever existed, which this chapter pokes at using nothing more than `kubectl delete pod`. Second with a controller this project did write: `ShippingPolicyReconciler`, the Go code backing the `ShippingPolicy` custom resource the Operator chapter builds out fully. Both loops have the identical shape. The only difference is which kind of object gets watched, diffed, and corrected.

## The loop, named

Every controller in Kubernetes, built-in or custom, runs the same four-step cycle:

1. **Watch**: subscribe to change notifications for one or more object kinds, via the apiserver's watch API, so the controller learns about a create, update, or delete without polling for it.
2. **Observe**: on each reconcile, read the current state of the object (and, often, related objects) directly from the API, rather than trusting whatever the watch event happened to carry.
3. **Diff**: compare that current state against the object's own spec, which encodes the desired state a human or another controller wrote down.
4. **Act**: issue exactly the API calls needed to close the gap, create what's missing, update what's wrong, delete what shouldn't exist, nothing else.

The watch step is what makes a controller efficient (it reacts to changes instead of polling the entire cluster on a timer), but the diff-and-act steps are what make it *correct*, and they're also what make the watch step non-essential to correctness: a controller that somehow missed every single watch event for an object, and only ever got told to resync on a fixed interval, would still eventually bring that object back in line, just slower. Compare that to an edge-triggered design, one that reacts only to the specific event ("a Pod died") and tries to compute what to do from the event's own payload rather than re-reading current state: miss one event, process events out of order, or crash between receiving an event and acting on it, and the system can drift permanently out of sync with no way to self-correct, because nothing ever asks "what's true right now?" again. Kubernetes controllers are uniformly level-triggered by design, for exactly this reason.

## The built-in instance: ReplicaSet controller

A Deployment doesn't manage Pods directly. It manages ReplicaSets, and a ReplicaSet manages Pods; this two-layer indirection is what makes a rolling update possible (a new ReplicaSet in parallel with the old one, which the Declarative Deployment pattern covers), but it also means there are two controllers running for every Deployment on the cluster: the Deployment controller, which watches Deployments and ReplicaSets and creates/scales ReplicaSets to match a Deployment's spec and rollout strategy, and the ReplicaSet controller, which watches ReplicaSets and Pods and creates/deletes Pods to match a ReplicaSet's `spec.replicas`. Both ship inside `kube-controller-manager`; neither is something a cluster operator installs separately or can disable without losing Deployments entirely.

This chapter's example applies a plain Deployment running `shipping-service` at two replicas, then goes straight for the ReplicaSet controller's own loop:

```bash
kubectl get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}'
```

This prints `ReplicaSet`, not `Deployment`. Every Pod's owner is the ReplicaSet that created it, confirmed directly in the object itself rather than inferred: `kubectl get pod -o yaml` shows an `ownerReferences` entry naming the ReplicaSet by UID, not by a label match or a naming convention. That owner reference is what lets `kubectl delete pod` prove the loop live:

```bash
kubectl delete pod "$POD" -n patterns
kubectl get pod -n patterns -l app.kubernetes.io/name=shipping-service
```

A new Pod, a new generated name, same count: two. Nothing ran a script to notice the gap. The ReplicaSet controller was already watching Pods with labels matching its selector; the delete fired a watch event; the controller's next reconcile read the ReplicaSet's current state (now one matching Pod, since the watch event told it which object to re-check), diffed `status.replicas` (1) against `spec.replicas` (2), and issued exactly one Pod creation to close the gap. Delete two Pods instead of one and the exact same reconcile runs, just computing a gap of two instead of one; the controller's code never special-cased "exactly one Pod died," because a level-triggered loop never needs to.

The Deployment controller one layer up runs an identical loop over a different pair of objects: it watches Deployments and the ReplicaSets they own, and when a Deployment's `spec.replicas` or `spec.template` changes, it diffs the Deployment against its current ReplicaSets and creates, scales, or retires ReplicaSets to match, handing the Pod-level work back down to the ReplicaSet controller underneath it. Two controllers, two different object kinds, the identical observe-diff-act shape stacked on top of each other, cooperating only because each one owns the objects it's responsible for and leaves the other kind alone.

![Two reconcile loops with the identical shape: the generic Watch to Reconcile() to Owned objects cycle, instantiated once as the built-in ReplicaSet controller over Pods and once as the custom ShippingPolicy controller over a Deployment and ConfigMap]({{ "/assets/diagrams/appendix-22-controller.svg" | relative_url }})
*The loop never changes shape; only the watched kind and the owned objects it acts on do.*

## The custom instance: ShippingPolicyReconciler

The second half of this chapter's example runs the identical loop against a kind nobody but this project defined: `ShippingPolicy`, a custom resource the Operator chapter introduces with its own CRD. `ShippingPolicyReconciler`, the Go type backing it, wires itself into the exact same watch-and-reconcile machinery `kube-controller-manager`'s built-in controllers use, via `controller-runtime`, the library most custom Kubernetes controllers (and every Operator SDK project) are built on:

```go
func (r *ShippingPolicyReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&shippingv1alpha1.ShippingPolicy{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.ConfigMap{}).
		Named("shippingpolicy").
		Complete(r)
}
```

`For` names the primary kind this controller reconciles: a change to any `ShippingPolicy` object enqueues a reconcile request naming that object. The two `Owns` calls do something a hand-rolled loop would otherwise have to build by hand: they tell the manager to also watch every `Deployment` and every `ConfigMap` that carries a controller owner reference back to a `ShippingPolicy`, and to enqueue a reconcile for the *owning* `ShippingPolicy` whenever one of those owned objects changes, not just when the `ShippingPolicy` itself does. That's what makes `kubectl scale deployment/controller-demo --replicas=5` (an edit to a Deployment the reconciler owns, not to the `ShippingPolicy` that governs it) trigger a correction within moments: the manager's watch on Deployments fired, matched the owner reference, and queued the same `ShippingPolicy` for reconciliation the original `kubectl apply` would have.

`Reconcile` itself, the method `controller-runtime` calls once per queued request, reads cleanly as the same four steps:

```go
func (r *ShippingPolicyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	var policy shippingv1alpha1.ShippingPolicy
	if err := r.Get(ctx, req.NamespacedName, &policy); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}
	// reconcileConfigMap and reconcileDeployment each read current state,
	// diff it against policy.Spec, and act only on the difference.
	...
}
```

`req` carries only a namespace and a name, never a payload describing what changed: the reconciler has to re-`Get` the object's current state from the API on every single call, which is the same discipline that makes the loop level-triggered rather than edge-triggered. A reconciler that instead trusted fields carried on the watch event itself would be reconstructing an edge-triggered design on top of a level-triggered framework, quietly reintroducing the exact failure mode (missed or stale events leaving the cluster permanently wrong) the whole mechanism exists to prevent. `controller-runtime` doesn't stop a reconciler from doing that; it just makes the correct discipline the natural shape of the code, since `req` has nothing else in it to misuse.

Inside `reconcileDeployment`, the diff-and-act steps use a helper, `controllerutil.CreateOrUpdate`, that is itself a small, generic version of the same loop: given a desired mutation function, it fetches the object if it exists, applies the mutation, and issues an update only if the result actually differs from what's already there, or creates the object from scratch if it's missing entirely. That last clause matters for idempotency: calling `Reconcile` twice in a row with no change to the `ShippingPolicy` produces no Kubernetes API writes the second time (confirmed directly in this appendix's own test suite, which asserts the Deployment's `generation` is unchanged after a no-op reconcile), the same way re-running `kubectl apply -f` against unchanged YAML is a no-op. A controller that instead unconditionally re-wrote every field on every reconcile, whether anything needed to change or not, would still converge correctly, but it would also generate a constant stream of no-op API writes and trigger its own watch on every pass, a wasteful, self-perpetuating reconcile storm that `CreateOrUpdate`'s diff check avoids by construction.

## Watches, predicates, and why owner references matter

A controller that watched every object of a given kind cluster-wide, with no filtering, would spend most of its time reconciling objects it has no business touching. `ShippingPolicyReconciler`'s `Owns` calls carry an implicit filter: a watch on Deployments scoped to "only the ones with a controller owner reference pointing at a `ShippingPolicy`" rather than every Deployment in the namespace, which is how `shipping-service`'s own plain Deployment in this appendix's other chapters coexists peacefully on the same cluster as the operator's generated ones without either one's controller noticing the other. This filtering mechanism, generically, is what `controller-runtime` calls a predicate: a cheap check run against every watch event before it's turned into a reconcile request, so a controller's queue only ever fills with work that's actually its own.

The owner reference itself does two separate jobs, best named individually because it's easy to credit it with only one. The first is the filtering job just described: it's the field a predicate checks. The second is garbage collection, entirely independent of any controller's own code: when the apiserver deletes an object that owns other objects via a *controller* owner reference (the `controller: true` flag `controllerutil.SetControllerReference` sets), it cascades the deletion to every owned object automatically, as a built-in apiserver behavior, not something `ShippingPolicyReconciler` has to implement, watch for, or even know is happening. Deleting a `ShippingPolicy` removes its Deployment and ConfigMap with no finalizer, no explicit cleanup code, and no window where the `ShippingPolicy` is gone but its children linger: the garbage collector is itself a controller, running the identical observe-diff-act loop this chapter has been describing, just watching for a different kind of difference (an owner that no longer exists) than any reconciler in this appendix writes by hand.

A finalizer exists for the opposite case: when a controller needs to do something *before* the apiserver is allowed to actually delete an object, typically releasing an external resource Kubernetes itself has no visibility into (a cloud load balancer, a DNS record, an external database). `ShippingPolicyReconciler` has no such external resource. Both of its owned objects live entirely inside the cluster, and the garbage collector's owner-reference cascade already handles removing them correctly on its own; adding a finalizer here would buy nothing a reader could point to, while adding a real failure mode every finalizer carries: an object stuck in `Terminating` forever if the finalizer's own removal logic ever errors out and is never retried successfully. The right number of finalizers for a controller with no external state to release is zero, and knowing when *not* to reach for a mechanism is as much a part of the Controller pattern as knowing how to use it.

## Self-healing as a side effect, not a feature

Nothing described above was written as a self-healing mechanism specifically. There's no retry loop, no health check, no explicit "detect drift and repair" logic anywhere in `ShippingPolicyReconciler`. The self-healing behavior this chapter's example demonstrates (scale the Deployment directly, watch it return to the spec's replica count; delete the ConfigMap, watch it reappear) falls directly out of running the same observe-diff-act loop on every watch event, with no separate code path for "someone tampered with my child object" versus "a human update wants a legitimate rollout." Both look identical to the reconciler: a watch fired, so compute the current diff and close it. A controller that special-cased "this looks like tampering, let me warn instead of correct" would be adding a judgment the level-triggered design was built specifically to avoid needing. The uniformity is the point: every difference between desired and observed state gets closed the same way, regardless of how it got there, which is exactly what makes a controller boring enough to trust running unattended, forever, on every cluster that exists.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%) `[verify]`
> **Competency:** Understand a custom controller's watch-and-reconcile loop extending the Kubernetes control plane
> **Drill:** `kubectl get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[*].metadata.ownerReferences[0].name}'`

> **🤖 Explore with your agent**
>
> "Scale controller-demo's Deployment to 1 replica instead of 5, delete its ConfigMap at the same moment, and show me which reconcile (the scale-driven one or the delete-driven one) the operator's log records first."

## Cleanup

```bash
kubectl --context mof-patterns delete -f controller/02-shippingpolicy.yaml
kubectl --context mof-patterns delete -f ../operator/install.yaml
kubectl --context mof-patterns delete -n patterns -f controller/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f controller/00-postgres.yaml
```

## Verification: examples/appendix-patterns/controller/

The runnable example deploys a plain `shipping-service` Deployment to exercise the built-in ReplicaSet controller directly with `kubectl delete pod`, then builds and deploys the `shipping-policy-operator` from `examples/appendix-patterns/operator/` and applies a `ShippingPolicy` to exercise the custom controller the same way: a direct `kubectl scale` on its child Deployment and a direct `kubectl delete` on its child ConfigMap, both corrected by the reconciler within moments. Full walkthrough in `examples/appendix-patterns/controller/README.md`.
