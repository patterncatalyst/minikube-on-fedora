# Observability and Debugging

Runnable example for the [Observability and Debugging
chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/30-observability-and-debugging/).

Worked against **shipping-service** plus a trivial `heartbeat` sidecar
container that exists only so `kubectl logs -c` and `kubectl exec -c` have a
second container to pick between.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f observability-and-debugging/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f observability-and-debugging/01-configmap.yaml
kubectl --context mof-patterns apply -n patterns -f observability-and-debugging/02-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=120s
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].metadata.name}')
```

### Logs: plain, follow, by container, after a restart

```bash
kubectl --context mof-patterns logs -n patterns "$POD" -c shipping-service
kubectl --context mof-patterns logs -n patterns "$POD" -c heartbeat
kubectl --context mof-patterns logs -n patterns "$POD" -c heartbeat -f --since=20s   # Ctrl-C to stop
```

Force a restart, then read the terminated container's last run with `-p`:

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -c shipping-service -- kill 1
sleep 3
kubectl --context mof-patterns get pod -n patterns "$POD"       # RESTARTS now 1
kubectl --context mof-patterns logs -n patterns "$POD" -c shipping-service --previous
```

### exec and port-forward

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -c shipping-service -- env | grep SERVICE_SCHEMA
kubectl --context mof-patterns port-forward -n patterns "$POD" 8080:8080 &
curl -s http://127.0.0.1:8080/healthz | jq .
kill %1
```

### describe and events

```bash
kubectl --context mof-patterns describe pod -n patterns "$POD"
kubectl --context mof-patterns get events -n patterns --sort-by=.metadata.creationTimestamp
```

### kubectl debug: ephemeral containers

```bash
kubectl --context mof-patterns debug -n patterns "$POD" -c probe-net --image=registry.access.redhat.com/ubi10/ubi:10.2-1791444044 -- curl -s http://localhost:8080/health
kubectl --context mof-patterns logs -n patterns "$POD" -c probe-net
kubectl --context mof-patterns debug -n patterns "$POD" -c probe-proc --target=shipping-service --image=registry.access.redhat.com/ubi10/ubi:10.2-1791444044 -- sh -c 'for p in /proc/[0-9]*; do printf "%s %s\n" "${p#/proc/}" "$(cat $p/comm 2>/dev/null)"; done'
kubectl --context mof-patterns logs -n patterns "$POD" -c probe-proc
kubectl --context mof-patterns get pod -n patterns "$POD" -o jsonpath='{range .status.ephemeralContainerStatuses[*]}{.name}{"\n"}{end}'
```

Same two probes the capstone's `examples/17-capstone/demos/debug-ephemeral.sh`
runs against `notification-service`: one proves the ephemeral container shares
the pod's network namespace, the other (`--target`) proves it shares the app
container's process namespace.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f observability-and-debugging/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f observability-and-debugging/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f observability-and-debugging/01-configmap.yaml
```

Ephemeral containers can't be removed individually; deleting the pod (via the
Deployment delete above) is the only way to clear them.

To remove the whole profile instead: `minikube delete -p mof-patterns`.
