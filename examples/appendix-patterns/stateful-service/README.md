# Stateful Service

Runnable example for the [Stateful Service chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/15-stateful-service/).

`shipment-archive`: three independent, non-replicating `postgres:17-alpine`
instances run as a `StatefulSet`, each with its own `PersistentVolumeClaim`
and a stable, individually addressable DNS name. Not the §17 capstone's
CloudNativePG-managed Postgres — a disposable stand-in used only to practice
the pattern.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
kubectl --context mof-patterns apply -n patterns -f stateful-service/00-secret.yaml
kubectl --context mof-patterns apply -n patterns -f stateful-service/01-service.yaml
kubectl --context mof-patterns apply -n patterns -f stateful-service/02-statefulset.yaml
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipment-archive -w
```

### Ordered, named Pods

```bash
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=shipment-archive
```

`shipment-archive-0`, `shipment-archive-1`, `shipment-archive-2`, created in
that exact order and not in parallel: the StatefulSet controller waits for
each Pod to become `Ready` before starting the next one, the opposite of a
Deployment's default all-at-once creation. Each one also has its own stable
DNS name through the headless Service:

```bash
kubectl --context mof-patterns run -n patterns dns-check --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi10/ubi-minimal:10.2-1792742351 -- \
  getent hosts shipment-archive-0.shipment-archive.patterns.svc.cluster.local
```

### Sticky storage survives Pod deletion

```bash
kubectl --context mof-patterns exec -n patterns shipment-archive-0 -- \
  psql -U capstone_app -d archive -c "CREATE TABLE zone_marker (id serial primary key, note text); INSERT INTO zone_marker (note) VALUES ('zone-a');"
kubectl --context mof-patterns delete pod shipment-archive-0 -n patterns
kubectl --context mof-patterns wait --for=condition=Ready pod/shipment-archive-0 -n patterns --timeout=60s
kubectl --context mof-patterns exec -n patterns shipment-archive-0 -- \
  psql -U capstone_app -d archive -c "SELECT * FROM zone_marker;"
```

The replacement Pod comes back with the **same name** (`shipment-archive-0`,
not a new random suffix) and the **same PersistentVolumeClaim**
(`archive-data-shipment-archive-0`), so the row written before deletion is
still there. Compare this to Stateless Service, where deleting a Pod
produces a brand-new identity with nothing carried forward — the entire
distinction between the two patterns, demonstrated as directly as
Kubernetes can show it.

### Deleting the StatefulSet doesn't delete the data

```bash
kubectl --context mof-patterns delete statefulset shipment-archive -n patterns
kubectl --context mof-patterns get pvc -n patterns -l app.kubernetes.io/name=shipment-archive
```

All three PVCs remain bound after the StatefulSet (and its Pods) are gone —
`volumeClaimTemplates` is deliberately conservative: recreating the
StatefulSet reattaches each ordinal to its existing claim rather than
starting from empty storage, exactly the behavior a database tier needs.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f stateful-service/02-statefulset.yaml
kubectl --context mof-patterns delete -n patterns -f stateful-service/01-service.yaml
kubectl --context mof-patterns delete -n patterns -f stateful-service/00-secret.yaml
kubectl --context mof-patterns delete pvc -n patterns -l app.kubernetes.io/name=shipment-archive
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
