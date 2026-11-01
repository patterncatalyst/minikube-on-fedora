# Env Var Configuration

Runnable example for the [Env Var Configuration chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/18-env-var-configuration/).

Worked against **notification-service**: one env block populated from three
sources, a literal value, a `ConfigMap` key, and a `Secret` key.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh notification-service v1
```

Apply the ConfigMap, then the Deployment:

```bash
kubectl --context mof-patterns apply -n patterns -f env-var-configuration/01-configmap.yaml
kubectl --context mof-patterns apply -n patterns -f env-var-configuration/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f env-var-configuration/02-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=notification-service -n patterns --timeout=60s
```

Inspect the resolved environment inside the running container:

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=notification-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$POD" -- env | grep -E '^(SERVICE_SCHEMA|PG_|KAFKA_|APICURIO_)'
```

All nine variables are visible from inside the container, indistinguishable
from one another at that point. The only way to tell a literal from a
ConfigMap-sourced value from a Secret-sourced one is to look back at the
manifest.

Confirm the service is serving:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/notification-service 8080:80 &
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/healthz | jq .
```

Now edit the ConfigMap and watch nothing happen:

```bash
kubectl --context mof-patterns patch configmap notification-config -n patterns \
  --type merge -p '{"data":{"kafka_order_topic":"order-placed-v2"}}'
kubectl --context mof-patterns exec -n patterns "$POD" -- env | grep KAFKA_ORDER_TOPIC
```

The container still reports the old value. Env vars are resolved once, at
container start; editing the backing ConfigMap or Secret never updates an
already-running container. Restart the Pod to pick up the change:

```bash
kubectl --context mof-patterns rollout restart deployment/notification-service -n patterns
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=notification-service -n patterns --timeout=60s
NEWPOD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=notification-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$NEWPOD" -- env | grep KAFKA_ORDER_TOPIC
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f env-var-configuration/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f env-var-configuration/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f env-var-configuration/01-configmap.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
