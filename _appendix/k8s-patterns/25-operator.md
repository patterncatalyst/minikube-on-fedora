---
title: "Operator"
order: 25
part: "Advanced"
description: "A CRD and a controller together, packaging an application's own operational knowledge as a Kubernetes API: the ShippingPolicy operator, built from scratch in Go with controller-runtime."
duration: "35 min"
---

## Learning objectives

By the end of this chapter you can:

- Define a CustomResourceDefinition's spec and status, and explain what `+kubebuilder` markers generate from them
- Explain precisely what turns a controller into an Operator, and what doesn't
- Trace a `ShippingPolicy` object from `kubectl apply` through reconciliation to a running Deployment and ConfigMap
- State what OLM and OperatorHub add on top of an operator's own code, and why this chapter doesn't build that part

## Why this matters

The Controller chapter established the loop: watch, observe, diff, act, running identically whether the watched kind ships with Kubernetes or was invented for this project. `ShippingPolicy`, the custom resource that controller reconciles, is where the other half of the Operator pattern lives, the half the Controller chapter never needed to cover: the API itself. A controller needs something to watch. An Operator is the combination of a controller and a CRD that gives it something to watch that didn't exist in Kubernetes before this project defined it, a first-class API object with its own schema, validation, and `kubectl get` support, standing in for operational knowledge about `shipping-service` that would otherwise live in a README, a runbook, or a senior engineer's memory.

That distinction, controller versus Operator, is easy to state and easy to blur in practice, so this chapter draws it as precisely as the code allows. `ShippingPolicyReconciler`'s reconcile loop is identical in shape to the ReplicaSet controller's, covered already. What makes the whole system an Operator rather than just a controller is `ShippingPolicy` itself: a `CustomResourceDefinition` registering a new API group (`shipping.patterncatalyst.io`), a new kind (`ShippingPolicy`), a validated schema (`carrier` is required and non-empty, `replicas` can't be negative), and a status subresource the reconciler writes to independently of the spec a human wrote. None of that existed in Kubernetes before this chapter's CRD registered it. The controller is the half that acts; the CRD is the half that gives a fulfillment team's own domain concept, "a shipping policy for one carrier lane," a real, typed, validated place to live in the cluster's own API, reachable by every tool that already knows how to talk to that API: `kubectl get shippingpolicy`, `kubectl describe`, RBAC scoped to the `shippingpolicies` resource, all included at no extra cost, the moment the CRD is registered.

## The CRD: a new kind, typed and validated

`ShippingPolicySpec` is a plain Go struct with `+kubebuilder` markers controlling what the generated OpenAPI schema enforces:

```go
type ShippingPolicySpec struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Carrier string `json:"carrier"`

	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=1
	MaxTransitDays int `json:"maxTransitDays"`

	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=0
	Replicas int32 `json:"replicas"`

	// +optional
	PriorityClassName string `json:"priorityClassName,omitempty"`
}
```

`controller-gen`, the code generator `kubebuilder`-style projects use, turns these markers into a real `CustomResourceDefinition` manifest with a full OpenAPI v3 schema: `carrier` becomes a required string with `minLength: 1`, `maxTransitDays` a required integer with `minimum: 1`, and so on. That schema is enforced by the apiserver itself, on every `create` and `update`, before a `ShippingPolicy` object is ever persisted, let alone reconciled: `kubectl apply` a `ShippingPolicy` with an empty `carrier` and the apiserver rejects it outright with a validation error naming the exact field, the same category of protection a Deployment's own schema already gives a malformed `replicas` field, now extended to a type this project invented. This is the one guarantee a fake client in a unit test cannot make at all, since a fake client never runs the apiserver's own schema validation at all; this appendix's own test suite covers it with a real `envtest` control plane specifically to prove the rejection happens where it's supposed to, against a real apiserver rather than an in-memory stand-in.

`ShippingPolicyStatus` is the second half of the CRD, and it's where the pattern's "status reflects observed state, spec reflects desired state" discipline lives:

```go
type ShippingPolicyStatus struct {
	// +optional
	ObservedReplicas int32 `json:"observedReplicas,omitempty"`

	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}
```

`+kubebuilder:subresource:status` on the `ShippingPolicy` type itself splits `spec` and `status` into fully separate API subresources, which does more than organize the YAML: a client with write access to `shippingpolicies` but not `shippingpolicies/status` can create and edit the spec but can never forge the status, the same separation of concerns RBAC already relies on for a Deployment's own `status.replicas`. `ShippingPolicyReconciler` is the only writer of `status.observedReplicas` and the `Ready` condition precisely because the RBAC in `config/rbac/role.yaml` grants the operator's own `ServiceAccount` write access to that subresource and nothing else does.

## Reconciling: spec to real objects

`Reconcile` turns a `ShippingPolicy` into exactly two owned objects, a Deployment and a ConfigMap, both named after the policy itself:

```go
func (r *ShippingPolicyReconciler) reconcileDeployment(ctx context.Context, policy *v1alpha1.ShippingPolicy) (int32, error) {
	deploy := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{
		Name: policy.Name, Namespace: policy.Namespace,
	}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, deploy, func() error {
		deploy.Spec.Replicas = &policy.Spec.Replicas
		deploy.Spec.Template.Spec.PriorityClassName = policy.Spec.PriorityClassName
		// ... container spec, env, resources, probes ...
		return controllerutil.SetControllerReference(policy, deploy, r.Scheme)
	})
	...
}
```

Every field the Deployment needs traces directly back to the `ShippingPolicy`'s own spec: `replicas` sets the Deployment's own `spec.replicas` one-to-one, `priorityClassName` flows straight through to the Pod template, the same `PriorityClass` mechanism Predictable Demands covers for a hand-written Deployment, now set by a controller instead of a human. The ConfigMap carries the policy's own data, `carrier` and `maxTransitDays`, mounted into the running container via `envFrom`, so `shipping-service`'s own process can read back the policy governing it, the same category of self-description the Downward API covers for a Pod's own metadata, here extended to data an Operator generated rather than the Kubernetes control plane itself.

`controllerutil.SetControllerReference` is called on both children, which is what makes `ShippingPolicy` the garbage-collection root for everything it owns: delete the `ShippingPolicy` and the apiserver's own garbage collector, not `ShippingPolicyReconciler`'s code, removes the Deployment and ConfigMap automatically, with no finalizer in this operator at all. That absence is a design choice: a finalizer exists to block deletion until a controller releases something external to the cluster (a cloud load balancer, an external DNS record), and `ShippingPolicy`'s two owned objects are both ordinary in-cluster Kubernetes objects the built-in garbage collector already knows how to clean up correctly on its own. Adding a finalizer here would introduce a real failure mode (an object stuck in `Terminating` if the finalizer's removal logic ever errors) in exchange for nothing a reader could point to as a benefit.

Status comes last, reading the Deployment's own observed state back rather than assuming the write that was just issued already took effect:

```go
var current appsv1.Deployment
r.Get(ctx, types.NamespacedName{Name: policy.Name, Namespace: policy.Namespace}, &current)
policy.Status.ObservedReplicas = current.Status.Replicas
```

`status.replicas` on a freshly created or updated Deployment often still reads its *previous* value, or zero, until the Deployment controller and the ReplicaSet controller underneath it have both had a chance to run their own reconciles and the kubelet has actually started the resulting Pods; `ShippingPolicy`'s own `Ready` condition stays `False`, with a `ReplicasReconciling` reason, for exactly that gap, flipping to `True` only once a later reconcile observes `ObservedReplicas` actually matching `spec.replicas`. This is the same observe-before-trusting discipline the Controller chapter's `req` design enforces at the request level, applied here to writing status: never assert something is true because an API call to make it true was issued, only because a subsequent read confirms it.

![A ShippingPolicy custom resource watched by the operator's Reconcile loop, which owns a child Deployment and ConfigMap, creating and updating both from the spec and reading the Deployment's own status.replicas back into the ShippingPolicy's status.conditions]({{ "/assets/diagrams/appendix-25-operator.svg" | relative_url }})
*The CRD gives the fulfillment domain's own concept, a shipping policy, a real place in the API; the reconciler is what keeps it true.*

## Building and verifying it like real Go, because it is

Everything in this chapter is ordinary `controller-runtime`, the library most Operators (including every Operator SDK project, whatever language it's generated in) are built on, and that means it's ordinary Go, testable with ordinary Go tools rather than anything specific to Kubernetes operators. `shipping-policy-operator`'s own test suite proves the reconciler's behavior two ways: three tests against `controller-runtime`'s fake client, an in-memory object tracker with no real apiserver behind it at all, asserting the Deployment and ConfigMap come out shaped correctly, that a second reconcile with no spec change is a true no-op (confirmed by checking the Deployment's own `generation` is unchanged, not just that the test didn't error), and that the `Ready` condition correctly tracks the gap between desired and observed replicas across two separate reconciles. A fourth test runs the identical reconcile against `envtest`, a real `etcd` and `kube-apiserver` pair with no kubelet, specifically to prove the one thing a fake client structurally cannot: that the generated CRD's own schema validation rejects a `ShippingPolicy` with no `carrier` before the reconciler ever sees it.

`go build ./...`, `go vet ./...`, and `go test ./...` all run green on this operator with no cluster running anywhere: writing an Operator doesn't require a live Kubernetes cluster to develop or verify against, because `controller-runtime`'s fake client and `envtest`'s real-but-kubelet-free control plane both run entirely as local Go test infrastructure. The multi-stage Containerfile backing the operator's own image (a `golang` builder producing one static binary, a `ubi10/ubi-micro` runtime carrying nothing else, both non-root) only matters once that tested code is ready to actually run inside the cluster it watches.

## Why a typed, tested binary instead of a script

The earliest, and still common, way to write a small Operator is a shell script in a Pod: `curl` the apiserver through a local proxy container, poll for changes to a custom resource on an interval, `jq` the JSON response apart, and shell out to `kubectl` to act on what it finds. That approach works, and it's a reasonable way to learn what an Operator does with the smallest possible number of moving parts. `shipping-policy-operator` takes a different path, and the differences aren't cosmetic. A shell script polling on an interval is edge-triggered in spirit even when it's technically re-reading current state each time, because "did anything change since last time" is usually answered by diffing against a value the script itself cached, a much easier thing to get subtly wrong than `controller-runtime`'s watch-based informer cache, which the framework maintains and invalidates correctly without any reconciler code having to manage it by hand. A shell script's `jq` parsing has no compile-time check that a field exists or holds the type a later command assumes; `ShippingPolicySpec`'s Go struct fields are checked by the compiler before the binary is ever built, and `go vet` catches a wide class of mistakes (nil dereferences, format-string mismatches) that a shell script's runtime would otherwise surface only when the production reconcile loop actually hits that code path. And a shell script's "test suite," if it has one, almost always means running it against a real cluster by hand; `shipping-policy-operator`'s own fake-client and envtest suites run in milliseconds to seconds, entirely offline, on every change, which is the difference between catching a reconciler bug in CI and catching it in production.

None of this makes a shell-script controller wrong for its own purposes, a config-watcher restarting Pods on a ConfigMap change doesn't need a typed API or a CRD schema to do its one job well. It does mean that the moment an Operator's job grows to include a real API surface (validated fields, a status subresource, RBAC scoped to a specific custom resource), the tooling this chapter uses, kubebuilder-style project layout, `controller-gen` for code and manifest generation, `controller-runtime` for the manager and reconciler machinery, stops being extra ceremony and starts being the more direct path, because it generates and tests the exact scaffolding a hand-rolled shell-and-curl approach would otherwise have to reinvent, less reliably, one `ShippingPolicy` field at a time.

## What an Operator is not: OLM and OperatorHub

Nothing in this chapter installs this operator through the Operator Lifecycle Manager, and that's worth being explicit about rather than silent on. OLM is a separate layer, distinct from everything this chapter built: it manages an Operator's own install, upgrade, and dependency lifecycle as a packaged artifact (a `ClusterServiceVersion` plus a subscription to a channel in a catalog), the mechanism behind OperatorHub's one-click installs on OpenShift and other OLM-enabled clusters. `shipping-policy-operator` here is deployed the plainer way, a `CustomResourceDefinition`, a `Role`/`RoleBinding`/`ServiceAccount`, and a Deployment, applied directly with `kubectl apply -f install.yaml`, no different in mechanism from any other workload in this appendix. That's a legitimate, complete way to run an Operator, and it's also the layer OLM exists to add structure on top of once an Operator needs versioned upgrades, a dependency graph against other Operators, or a one-click install experience for cluster operators who never want to read this chapter's own `install.yaml` at all. Building that packaging layer is out of scope here; understanding that it exists, and what problem it solves that a flat manifest doesn't, is the CKAD-relevant half.

> **🎓 CKAD exam lens**
>
> **Domain:** Application Environment, Configuration & Security (25%): discover and use resources that extend Kubernetes (CRDs, Operators)
> **Competency:** Understand a CRD-based Operator packaging an application's own operational knowledge as a Kubernetes API
> **Drill:** `kubectl get shippingpolicy ground-standard -n patterns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'`

> **🤖 Explore with your agent**
>
> "Add a new required field, destinationRegion, to ShippingPolicySpec, regenerate the CRD, apply an existing ShippingPolicy that doesn't set it, and show me the exact apiserver validation error that results."

## Cleanup

```bash
kubectl --context mof-patterns delete -f ../operator/config/samples/shipping_v1alpha1_shippingpolicy.yaml
kubectl --context mof-patterns delete -f ../operator/install.yaml
```

## Verification: examples/appendix-patterns/operator/

The runnable example is the operator itself: `go build ./...`, `go vet ./...`, and `go test ./...` all run green, covering both the controller-runtime fake-client suite and an envtest-backed test proving the generated CRD's own schema validation. Deploying it live applies the generated CRD, RBAC, and the operator's own Deployment, then a sample `ShippingPolicy` whose `Ready` condition flips `True` once its child Deployment's observed replicas match the spec. Full build, load, deploy, and try walkthrough in `examples/appendix-patterns/operator/README.md`.
