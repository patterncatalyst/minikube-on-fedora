# Init Container

Runnable example for the [Init Container chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/06-init-container/).

Worked against **notification-service**: a real Alembic migration (`alembic
upgrade head`) runs as an init container before the main container starts, so
the `notifications` schema and table exist before the app issues a single
query.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh notification-service v1
```

Apply the Deployment first, out of order, with no Postgres for the init
container to reach:

```bash
kubectl --context mof-patterns apply -n patterns -f init-container/01-deployment.yaml
kubectl --context mof-patterns get pods -n patterns -w
```

The Pod sits at `Init:Error` then `Init:CrashLoopBackOff`: the `migrate` init
container exits non-zero immediately (there is no retry loop in Alembic's
`env.py`, unlike the app's own startup code) and the kubelet restarts it on
backoff. The main container never starts; `kubectl --context mof-patterns
describe pod -n patterns -l app.kubernetes.io/name=notification-service`
shows it `Waiting: PodInitializing` the whole time. Now give the init
container something to reach:

```bash
kubectl --context mof-patterns apply -n patterns -f init-container/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
```

Watch the next restart of the init container succeed and the main container
start:

```bash
kubectl --context mof-patterns get pods -n patterns -w
```

Confirm the migration actually ran:

```bash
PG_POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=patterns-postgres -o name)
kubectl --context mof-patterns exec -n patterns "$PG_POD" -- \
  psql -U capstone_app -d capstone -c '\dt notifications.*'
```

`notifications.notifications` and `notifications.alembic_version` both exist,
created entirely by the init container before the app process ever ran.
Confirm the app is serving:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/notification-service 8080:80 &
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/healthz | jq .
```

Inspect the init container's own status once everything is `Running`:

```bash
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=notification-service \
  -o jsonpath='{.items[0].status.initContainerStatuses[0].name}{" restarts="}{.items[0].status.initContainerStatuses[0].restartCount}{"\n"}'
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f init-container/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f init-container/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
