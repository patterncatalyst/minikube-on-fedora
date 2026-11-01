# Health Probe

Runnable example for the [Health Probe chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/03-health-probe/).

Worked against **inventory-service**: startup, liveness, and readiness
probes, plus a manually-satisfied readiness gate.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh inventory-service v1
kubectl --context mof-patterns apply -n patterns -f health-probe/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f health-probe/01-deployment.yaml
```

### Readiness gate

```bash
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=inventory-service -o wide
```

Once the startup probe clears, both containers show `1/1`, but the
`READINESS GATES` column reads `0/1`: `patterns.example.com/InventorySeeded`
has no controller to satisfy it here. Patch it by hand, the way a real
controller would after confirming the demo stock seeded:

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=inventory-service -o name)
kubectl --context mof-patterns patch "$POD" -n patterns --type='json' --subresource=status \
  -p='[{"op": "add", "path": "/status/conditions/-", "value": {"type": "patterns.example.com/InventorySeeded", "status": "True"}}]'
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=inventory-service -o wide
```

`READINESS GATES` now reads `1/1` and the Pod's overall `Ready` condition is
`True`.

### Liveness versus readiness

Scale the backing Postgres to zero to simulate a dependency outage:

```bash
kubectl --context mof-patterns scale deployment/patterns-postgres -n patterns --replicas=0
kubectl --context mof-patterns port-forward -n patterns svc/inventory-service 8080:80 &
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health    # still 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz   # 503
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=inventory-service
```

The Pod drops out of `READY` (removed from the Service's endpoints) without
restarting: the liveness probe never fires, because the process itself is
fine. Bring Postgres back and readiness recovers on its own:

```bash
kubectl --context mof-patterns scale deployment/patterns-postgres -n patterns --replicas=1
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=inventory-service -w
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f health-probe/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f health-probe/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
