# Namespace Governance

Runnable example for the [Namespace Governance
chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/32-namespace-governance/).

A `ResourceQuota` and a `LimitRange` on the `patterns` namespace, worked
against **shipping-service** (two replicas, a third rejected on the pod
cap) and two stand-in pods (one missing resources entirely, one exceeding
the LimitRange's max).

## Run it

Governance objects first, so every pod that lands afterward is admitted
under them:

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -f namespace-governance/01-priorityclass.yaml
kubectl --context mof-patterns apply -n patterns -f namespace-governance/02-resourcequota.yaml
kubectl --context mof-patterns apply -n patterns -f namespace-governance/03-limitrange.yaml
kubectl --context mof-patterns apply -n patterns -f namespace-governance/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
```

### ResourceQuota: pods, requests, and limits totals

```bash
kubectl --context mof-patterns apply -n patterns -f namespace-governance/04-configmap.yaml
kubectl --context mof-patterns apply -n patterns -f namespace-governance/05-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=120s
kubectl --context mof-patterns describe resourcequota patterns-quota -n patterns
```

`Used` shows 3 of 3 pods (Postgres plus two shipping-service replicas).
Scale to a third replica and watch it get rejected:

```bash
kubectl --context mof-patterns scale deployment/shipping-service -n patterns --replicas=3
kubectl --context mof-patterns get events -n patterns --field-selector reason=FailedCreate --sort-by=.metadata.creationTimestamp | tail -3
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipping-service
```

The ReplicaSet controller keeps retrying and keeps failing with `pods
"shipping-service-..." is forbidden: exceeded quota: patterns-quota,
requested: pods=1, used: pods=3, limited: pods=3` — only two Pods ever exist.
Scale back down:

```bash
kubectl --context mof-patterns scale deployment/shipping-service -n patterns --replicas=2
```

### LimitRange: defaults for a pod that specifies nothing

```bash
kubectl --context mof-patterns apply -n patterns -f namespace-governance/06-pod-no-resources.yaml
kubectl --context mof-patterns get pod inventory-defaults-check -n patterns \
  -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```

The pod's manifest has no `resources` block at all, but the object the API
server stored carries the LimitRange's `defaultRequest` and `default`
values: `requests: {cpu: 50m, memory: 128Mi}`, `limits: {cpu: 200m, memory:
256Mi}`. Nothing in `06-pod-no-resources.yaml` set those numbers.

### LimitRange: rejecting an out-of-band value

```bash
kubectl --context mof-patterns apply -n patterns -f namespace-governance/07-pod-over-max.yaml
```

This fails immediately, with no pod created:
`maximum cpu usage per Container is 500m, but limit is 600m`. Lower
`06-pod-no-resources.yaml`'s stand-in to within the band and it would be
admitted; the LimitRange enforces the ceiling the same way it supplies the
floor.

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

To remove the whole profile instead: `minikube delete -p mof-patterns`.
