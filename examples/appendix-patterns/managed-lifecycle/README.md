# Managed Lifecycle

Runnable example for the [Managed Lifecycle chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/04-managed-lifecycle/).

Worked against **notification-service**: a `postStart` hook, a `preStop`
hook that simulates connection draining, and `terminationGracePeriodSeconds`
sized to cover both, observed through the process's own SIGTERM-triggered
shutdown.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh notification-service v1
kubectl --context mof-patterns apply -n patterns -f managed-lifecycle/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f managed-lifecycle/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=notification-service -n patterns --timeout=60s
```

### postStart

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=notification-service -o name)
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /tmp/managed-lifecycle-ready
```

A timestamp from container start confirms the hook ran before the probes did.

### preStop and graceful shutdown

Tail the logs in one terminal:

```bash
kubectl --context mof-patterns logs -f -n patterns "$POD"
```

Delete the Pod from another terminal and time it:

```bash
time kubectl --context mof-patterns delete pod -n patterns "$POD"
```

The delete takes just over 10 seconds: Kubernetes removes the Pod from the
Service's endpoints immediately, then waits for the `preStop` hook's 10-second
sleep to finish before sending SIGTERM. Once SIGTERM lands, the log stream
shows uvicorn's own shutdown sequence (cancel the consumer task, dispose the
database pool) completing in well under a second, nowhere near the 30-second
`terminationGracePeriodSeconds` ceiling.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f managed-lifecycle/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f managed-lifecycle/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
