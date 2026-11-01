# Ambassador

Runnable example for the [Ambassador chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/09-ambassador/).

Worked against **shipping-service**, with zero Postgres-related environment
variables, plus an ambassador sidecar (`postgres-ambassador`) that proxies
`127.0.0.1:5432` to the real `patterns-postgres` Service.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f ambassador/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f ambassador/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=60s
```

Confirm the app is serving, with nothing in its own manifest naming
`patterns-postgres` at all:

```bash
kubectl --context mof-patterns get deployment shipping-service -n patterns \
  -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
kubectl --context mof-patterns port-forward -n patterns svc/shipping-service 8080:80 &
curl -s http://127.0.0.1:8080/healthz | jq .
```

### Breaking only the ambassador

Point the ambassador at a Service name that doesn't exist, without touching
`shipping-service`'s own container at all:

```bash
kubectl --context mof-patterns set env deployment/shipping-service -n patterns \
  --containers=postgres-ambassador UPSTREAM_HOST=patterns-postgres-missing.patterns.svc.cluster.local
kubectl --context mof-patterns rollout status deployment/shipping-service -n patterns
curl -s http://127.0.0.1:8080/healthz -w ' [%{http_code}]\n'
```

`/healthz` now returns `503`: shipping-service still connects to
`127.0.0.1:5432` exactly as before, but the ambassador behind that address
can no longer reach anything. Point it back:

```bash
kubectl --context mof-patterns set env deployment/shipping-service -n patterns \
  --containers=postgres-ambassador UPSTREAM_HOST=patterns-postgres.patterns.svc.cluster.local
kubectl --context mof-patterns rollout status deployment/shipping-service -n patterns
curl -s http://127.0.0.1:8080/healthz | jq .
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f ambassador/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f ambassador/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
