# Singleton Service

Runnable example for the [Singleton Service chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/13-singleton-service/).

Worked against **order-service** run at `replicas: 1`, protected by a
`PodDisruptionBudget` with `minAvailable: 1`.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh order-service v1
kubectl --context mof-patterns apply -n patterns -f singleton-service/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f singleton-service/01-deployment.yaml
kubectl --context mof-patterns apply -n patterns -f singleton-service/02-pdb.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=order-service -n patterns --timeout=60s
```

### Read the PDB's own status

```bash
kubectl --context mof-patterns get pdb order-service-pdb -n patterns
```

`ALLOWED DISRUPTIONS` reads `0`: with exactly one healthy replica and
`minAvailable: 1`, the budget has no room to let any voluntary disruption
through.

### The Eviction API honors the budget

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=order-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns create --raw "/api/v1/namespaces/patterns/pods/${POD}/eviction" \
  -f - <<EOF
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"${POD}","namespace":"patterns"}}
EOF
```

The call fails with `429 Too Many Requests` and a message naming the PDB:
`Cannot evict pod as it would violate the pod's disruption budget.` This is
exactly the API `kubectl drain`, the descheduler, and a cluster autoscaler
all call internally before removing a Pod — none of them can remove this
one while it's the only replica.

### A direct delete bypasses it entirely

```bash
kubectl --context mof-patterns delete pod "$POD" -n patterns
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=order-service -w
```

`kubectl delete pod` calls the ordinary delete endpoint, not the Eviction
subresource, so the PDB has no say in it at all. The Deployment controller
replaces the Pod immediately, same as any other restart; the PDB only ever
governs *voluntary, API-mediated* disruption, never a direct delete.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f singleton-service/02-pdb.yaml
kubectl --context mof-patterns delete -n patterns -f singleton-service/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f singleton-service/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
