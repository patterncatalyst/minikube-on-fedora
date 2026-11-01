# Controller

Runnable example for the [Controller chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/22-controller/).

Two reconcile loops, stacked on the same cluster: the **built-in**
ReplicaSet controller keeping `shipping-service`'s Pods at two replicas, and
the **custom** `ShippingPolicy` controller from `../operator/` keeping a
Deployment and ConfigMap matching a `ShippingPolicy`'s spec. Same
observe-diff-act shape, one layer apart.

## Part 1: the built-in controller

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f controller/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f controller/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=60s
```

Two Pods, each owned by a ReplicaSet, which is itself owned by the
Deployment:

```bash
kubectl --context mof-patterns get deployment,replicaset,pod -n patterns -l app.kubernetes.io/name=shipping-service
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"\n"}'
```

The last command prints `ReplicaSet`, not `Deployment`: the Deployment
controller only ever manages ReplicaSets, and the ReplicaSet controller is
the one that actually owns and counts Pods. Kill one directly and watch the
ReplicaSet controller notice the gap and close it, with nothing in this
repository involved in making that happen:

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns delete pod "$POD" -n patterns
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service
```

A new Pod, a new name, same count: two. The ReplicaSet controller's watch
fired the moment the apiserver recorded the deletion, it diffed
`status.replicas` (now 1) against `spec.replicas` (still 2), and it created
a replacement. It doesn't know or care *why* the count dropped: a manual
delete, an OOM kill, a node failure, and a rolling update all produce the
exact same diff, and the exact same reaction. That's the level-triggered
design every controller in this chapter shares.

## Part 2: the custom controller

Build and deploy the operator from `../operator/` (see that directory's own
`README.md` for the full walkthrough):

```bash
cd ../operator
docker build -t shipping-policy-operator:v1 -f Containerfile .
minikube -p mof-patterns image load shipping-policy-operator:v1
kubectl --context mof-patterns apply -f install.yaml
kubectl --context mof-patterns wait --for=condition=Available deployment/shipping-policy-operator -n patterns --timeout=60s
cd ../controller
```

Apply this chapter's own `ShippingPolicy`:

```bash
kubectl --context mof-patterns apply -f 02-shippingpolicy.yaml
kubectl --context mof-patterns wait --for=condition=Ready shippingpolicy/controller-demo -n patterns --timeout=60s
kubectl --context mof-patterns get deployment,configmap -n patterns -l shipping.patterncatalyst.io/policy=controller-demo
```

A Deployment and a ConfigMap, both named `controller-demo`, both owned by
the `ShippingPolicy` object, neither one hand-written: the reconciler built
both from the spec the instant it saw the object. Watch the reconciler's own
log while poking at its children from a second terminal:

```bash
kubectl --context mof-patterns logs -f -n patterns deployment/shipping-policy-operator
```

### Scale the Deployment directly

```bash
kubectl --context mof-patterns scale deployment/controller-demo -n patterns --replicas=5
kubectl --context mof-patterns get deployment controller-demo -n patterns -w
```

Replicas climb to 5 for a moment, then settle back to 2. `SetupWithManager`
in `../operator/internal/controller/shippingpolicy_controller.go` calls
`.Owns(&appsv1.Deployment{})`, so the manager watches every Deployment this
`ShippingPolicy` owns, not just the `ShippingPolicy` object itself; the scale
command is exactly the kind of out-of-band edit that watch exists to catch. A
new reconcile fires within moments, compares `spec.replicas` (still 2, since
nothing touched the `ShippingPolicy` itself) against the Deployment's current
`5`, and corrects it, the same observe-diff-act shape as the ReplicaSet
controller in Part 1, just one object layer higher: this controller's
"replicas" are Deployments and ConfigMaps, not Pods.

### Delete the ConfigMap directly

```bash
kubectl --context mof-patterns delete configmap controller-demo -n patterns
kubectl --context mof-patterns get configmap controller-demo -n patterns
```

Gone, then back, usually inside a second. `.Owns(&corev1.ConfigMap{})`
covers this exactly the way `.Owns(&appsv1.Deployment{})` covered the scale
command above.

![The reconcile loop: a watch fires, Reconcile observes current state, diffs it against spec, and acts, whether the watched object is a Pod (built-in) or a Deployment and ConfigMap (custom)]({{ "/assets/diagrams/appendix-22-controller.svg" | relative_url }})
*Both controllers in this example run the identical loop; only the kind of object being watched, diffed, and corrected changes.*

## Cleanup

```bash
kubectl --context mof-patterns delete -f 02-shippingpolicy.yaml
kubectl --context mof-patterns delete -f ../operator/install.yaml
kubectl --context mof-patterns delete -n patterns -f 01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f 00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
