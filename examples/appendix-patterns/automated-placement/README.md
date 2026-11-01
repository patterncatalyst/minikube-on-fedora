# Automated Placement

Runnable example for the [Automated Placement chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/05-automated-placement/).

Placement doesn't depend on what the container does, so these manifests use a
minimal UBI image rather than a shipping service (the same call the
Kubernetes Patterns book's own Automated Placement example makes). The
labels name the real services for continuity: `shipping-service-placeholder`,
`order-service-placeholder`.

This example needs a **second node**, which the `mof-patterns` profile
doesn't have by default.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
minikube node add -p mof-patterns
kubectl --context mof-patterns get nodes
```

Two nodes: `mof-patterns` (control-plane) and `mof-patterns-m02` (worker).

### nodeSelector

```bash
kubectl --context mof-patterns apply -n patterns -f automated-placement/01-node-selector.yaml
kubectl --context mof-patterns get pod shipping-warehouse -n patterns
```

`Pending`: no node carries `zone=warehouse-a`. Label the worker and watch it schedule:

```bash
kubectl --context mof-patterns label node mof-patterns-m02 zone=warehouse-a
kubectl --context mof-patterns get pod shipping-warehouse -n patterns -w
```

### Node affinity

```bash
kubectl --context mof-patterns apply -n patterns -f automated-placement/02-node-affinity.yaml
kubectl --context mof-patterns get pod order-fulfillment -n patterns
```

Also `Pending`: the required rule needs `tier=fulfillment`.

```bash
kubectl --context mof-patterns label node mof-patterns-m02 tier=fulfillment
kubectl --context mof-patterns get pod order-fulfillment -n patterns -o wide -w
```

It lands on `mof-patterns-m02`: the required rule is satisfied there, and the
preferred rule's weight nudges the scheduler away from the control-plane node
whenever both are candidates.

### Pod anti-affinity

```bash
kubectl --context mof-patterns apply -n patterns -f automated-placement/03-pod-anti-affinity.yaml
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipping-ha-placeholder -o wide
```

The two replicas land one per node. Scale to 3 and the third stays `Pending`:
two nodes can satisfy the anti-affinity rule for at most two replicas.

```bash
kubectl --context mof-patterns scale deployment/shipping-ha -n patterns --replicas=3
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipping-ha-placeholder
kubectl --context mof-patterns scale deployment/shipping-ha -n patterns --replicas=2
```

### Taints and tolerations

Taint the worker so nothing schedules there without an explicit toleration:

```bash
kubectl --context mof-patterns taint nodes mof-patterns-m02 dedicated=fulfillment:NoSchedule
kubectl --context mof-patterns apply -n patterns -f automated-placement/04-toleration.yaml
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=fulfillment-placeholder -o wide
```

`fulfillment-no-toleration` stays `Pending` (it matches the `zone=warehouse-a`
selector, but the taint still repels it); `fulfillment-with-toleration`
schedules onto `mof-patterns-m02`.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns \
  -f automated-placement/01-node-selector.yaml \
  -f automated-placement/02-node-affinity.yaml \
  -f automated-placement/03-pod-anti-affinity.yaml \
  -f automated-placement/04-toleration.yaml
kubectl --context mof-patterns taint nodes mof-patterns-m02 dedicated=fulfillment:NoSchedule-
```

Remove the second node (or delete the whole profile, since published ports
and this node layout are both easiest to recreate from scratch):

```bash
minikube node delete mof-patterns-m02 -p mof-patterns
# or
minikube delete -p mof-patterns
```
