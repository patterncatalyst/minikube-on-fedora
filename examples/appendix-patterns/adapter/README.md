# Adapter

Runnable example for the [Adapter chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/08-adapter/).

Worked against **shipping-service**, unmodified, plus an adapter sidecar
(`metrics-adapter`) that polls its `/healthz` endpoint over localhost and
re-serves the result as Prometheus exposition text on port `9100`.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f adapter/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f adapter/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=60s
```

Compare the app's own output with the adapter's translation of it:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/shipping-service 8080:80 9100:9100 &
curl -s http://127.0.0.1:8080/healthz | jq .
curl -s http://127.0.0.1:9100/metrics
```

The first call returns `shipping-service`'s own JSON body. The second returns
the same underlying fact (is `/healthz` reporting ready) re-expressed as
Prometheus exposition text:

```
# HELP shipping_service_up Whether shipping-service's /healthz reported ready.
# TYPE shipping_service_up gauge
shipping_service_up 1
```

Scale Postgres to zero and shipping-service's own `/healthz` starts failing
(it can no longer reach the database); watch the adapter's translation follow
it down without the adapter itself needing to know anything about Postgres:

```bash
kubectl --context mof-patterns scale deployment/patterns-postgres -n patterns --replicas=0
sleep 5
curl -s http://127.0.0.1:8080/healthz -w ' [%{http_code}]\n'
curl -s http://127.0.0.1:9100/metrics
kubectl --context mof-patterns scale deployment/patterns-postgres -n patterns --replicas=1
```

`/healthz` now returns `503` and `shipping_service_up` reads `0`: the adapter
didn't crash or need a code change, because it only ever reads what the app
already reports.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f adapter/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f adapter/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
