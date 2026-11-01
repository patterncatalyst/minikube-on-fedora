# Predictable Demands

Runnable example for the [Predictable Demands chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/01-predictable-demands/).

Worked against **shipping-service**: resource requests/limits, a
`PriorityClass`, and two hard requirements (a ConfigMap and a PVC) that the
Pod cannot start without.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
```

Apply the Deployment first, out of order, to see the hard requirements bite:

```bash
kubectl --context mof-patterns apply -n patterns -f predictable-demands/01-priorityclass.yaml
kubectl --context mof-patterns apply -n patterns -f predictable-demands/04-deployment.yaml
kubectl --context mof-patterns get pods -n patterns -w
```

The Pod sits in `Pending` (no `shipping-data` PVC), then
`CreateContainerConfigError` (no `shipping-config` ConfigMap) once it's
scheduled. `kubectl --context mof-patterns describe pod -n patterns -l app.kubernetes.io/name=shipping-service`
shows both events. Now satisfy the two hard requirements:

```bash
kubectl --context mof-patterns apply -n patterns -f predictable-demands/02-configmap.yaml
kubectl --context mof-patterns apply -n patterns -f predictable-demands/03-pvc.yaml
kubectl --context mof-patterns apply -n patterns -f predictable-demands/00-postgres.yaml
```

Wait for Postgres, then watch the Pod come up:

```bash
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns get pods -n patterns -w
```

Confirm it's serving:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/shipping-service 8080:80 &
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/healthz | jq .
```

Inspect the requests/limits and priority that landed:

```bash
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service \
  -o jsonpath='{.items[0].spec.priorityClassName}{"\n"}{.items[0].spec.containers[0].resources}{"\n"}'
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f predictable-demands/04-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f predictable-demands/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f predictable-demands/03-pvc.yaml
kubectl --context mof-patterns delete -n patterns -f predictable-demands/02-configmap.yaml
kubectl --context mof-patterns delete -f predictable-demands/01-priorityclass.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
