# Sidecar

Runnable example for the [Sidecar chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/07-sidecar/).

Worked against **shipping-service**, unmodified, plus a native sidecar
(`probe-tailer`) that polls its `/health` and `/healthz` endpoints over
localhost every five seconds and appends the result to a shared `emptyDir`
log file.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f sidecar/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f sidecar/01-deployment.yaml
```

### Startup order

```bash
kubectl --context mof-patterns get pods -n patterns -w
```

Watch the `READY` column: it goes `0/2` while only the sidecar is up, briefly
shows the sidecar `Running` with the main container still `PodInitializing`
(the native sidecar starts first), then `2/2` once shipping-service passes
its startup probe.

### The tailed log

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service -o name)
kubectl --context mof-patterns exec -n patterns "$POD" -c probe-tailer -- tail -n 5 /var/log/shipping-service/probe-tail.log
```

Each line is a timestamp and the HTTP status the sidecar got from
`shipping-service` over `127.0.0.1`, entirely inside the Pod's own network
namespace: no Service, no DNS, no network policy involved.

### Shutdown order

Tail the sidecar's log in one terminal, then delete the Pod from another and
watch both containers' states:

```bash
kubectl --context mof-patterns get pod -n patterns "$POD" -o jsonpath='{.status.containerStatuses[*].name}{"\n"}'
kubectl --context mof-patterns delete pod -n patterns "$POD" &
kubectl --context mof-patterns get pod -n patterns "$POD" -w
```

The main container's status flips to `Terminating` first; the native sidecar
keeps running until shipping-service has actually exited, then stops last,
the reverse of its startup order.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f sidecar/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f sidecar/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
