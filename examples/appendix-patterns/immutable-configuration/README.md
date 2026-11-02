# Immutable Configuration

Runnable example for the [Immutable Configuration chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/21-immutable-configuration/).

Worked against **graphql-gateway**: a `ConfigMap` marked `immutable: true`,
and what happens when that config needs to change.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh graphql-gateway v1
```

graphql-gateway is stateless: no Postgres needed. Apply the ConfigMap, then
the Deployment:

```bash
kubectl --context mof-patterns apply -n patterns -f immutable-configuration/01-configmap-v1.yaml
kubectl --context mof-patterns apply -n patterns -f immutable-configuration/02-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=graphql-gateway -n patterns --timeout=60s
```

Try to patch the immutable ConfigMap in place:

```bash
kubectl --context mof-patterns patch configmap gateway-config-v1 -n patterns \
  --type merge -p '{"data":{"order_rest_url":"http://order-service-v2"}}'
```

The API server rejects the request outright: the error names the `data`
field and that the ConfigMap is immutable. There is no flag or
force option that gets around this; the only way forward is a new ConfigMap.

Create it and confirm the running Pod is unaffected by its mere existence:

```bash
kubectl --context mof-patterns apply -n patterns -f immutable-configuration/03-configmap-v2.yaml
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=graphql-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$POD" -- env | grep order_rest_url
```

Still `http://order-service`. Now roll the Deployment onto the new
ConfigMap:

```bash
kubectl --context mof-patterns apply -n patterns -f immutable-configuration/04-deployment-v2.yaml
kubectl --context mof-patterns rollout status deployment/graphql-gateway -n patterns
```

Changing which ConfigMap name the Pod template references is itself a Pod
template change, so this is a normal rolling update: a new ReplicaSet, new
Pods, the old ones terminated once the new ones are ready.

```bash
NEWPOD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=graphql-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$NEWPOD" -- env | grep order_rest_url
```

Now `http://order-service-v2`. Confirm the old ConfigMap can be deleted once
nothing references it:

```bash
kubectl --context mof-patterns get deployment graphql-gateway -n patterns \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}{"\n"}'
kubectl --context mof-patterns delete configmap gateway-config-v1 -n patterns
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f immutable-configuration/04-deployment-v2.yaml
kubectl --context mof-patterns delete configmap gateway-config-v2 -n patterns --ignore-not-found
kubectl --context mof-patterns delete configmap gateway-config-v1 -n patterns --ignore-not-found
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
