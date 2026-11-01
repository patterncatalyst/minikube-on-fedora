# Configuration Resource

Runnable example for the [Configuration Resource chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/19-configuration-resource/).

Worked against **payment-service**: a ConfigMap and a Secret, each bulk-exposed
as environment variables with `envFrom` and simultaneously mounted as files.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh payment-service v1
```

Apply the ConfigMap and Postgres (which carries the Secret), then the
Deployment:

```bash
kubectl --context mof-patterns apply -n patterns -f configuration-resource/01-configmap.yaml
kubectl --context mof-patterns apply -n patterns -f configuration-resource/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f configuration-resource/02-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=payment-service -n patterns --timeout=60s
```

Confirm the bulk-exposed env vars landed:

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=payment-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$POD" -- env | grep -E '^(service_schema|pg_host|pg_port|pg_user|pg_password|pg_database)='
```

Check the event the kubelet raised for the key `envFrom` skipped:

```bash
kubectl --context mof-patterns describe pod -n patterns "$POD" | grep -A3 Events:
```

A Warning event names `payment-service.conf` as an invalid environment
variable name: the ConfigMap key reached the container as a file instead,
exactly as intended. Confirm the file and its permissions:

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /config/app/payment-service.conf
kubectl --context mof-patterns exec -n patterns "$POD" -- ls -l /config/app/payment-service.conf /config/secrets/pg_password
```

Both files show mode `-r--------` (0400): readable only by the file's
owning UID, not world- or group-readable.

Now edit the ConfigMap's file-shaped key and watch the mounted file update on
its own, no restart required:

```bash
kubectl --context mof-patterns patch configmap payment-config -n patterns --type merge \
  -p '{"data":{"payment-service.conf":"[payment-service]\nschema=payments\nnote=updated in place\n"}}'
sleep 90
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /config/app/payment-service.conf
```

The file changes within roughly a minute (the kubelet's sync period) without
touching the Pod. Compare that against the bulk env vars from the same patch
attempt on a different key: those still require a restart, as in the
[Env Var Configuration example](../env-var-configuration/).

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f configuration-resource/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-resource/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-resource/01-configmap.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
