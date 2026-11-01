# Self Awareness

Runnable example for the [Self Awareness chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/17-self-awareness/).

Worked against **shipping-service**: Downward API fields injected as
environment variables, plus a `downwardAPI` volume exposing labels,
annotations, and a resource limit as files.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f self-awareness/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f self-awareness/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=60s
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].metadata.name}')
```

### Environment variables: fixed at container start

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -- env | grep -E '^(POD_|NODE_NAME|CPU_REQUEST|MEMORY_LIMIT)'
```

`POD_NAME`, `POD_NAMESPACE`, `POD_IP`, and `NODE_NAME` all come straight from
the Pod's own `metadata`/`status`/`spec`, with no ConfigMap, no Secret, and
no call to the API server from inside the container. `CPU_REQUEST` and
`MEMORY_LIMIT` read this exact container's own declared resources back out
as a `resourceFieldRef` — the same numbers Predictable Demands declares, now
visible to the process itself.

### The downward API volume: updated in place

```bash
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /etc/podinfo/labels
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /etc/podinfo/annotations
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /etc/podinfo/cpu_limit
```

The labels file lists `app.kubernetes.io/name` and
`app.kubernetes.io/part-of`; the annotations file shows
`patterns.example.com/owner="fulfillment-team"`; `cpu_limit` reads `500`
(millicores, since the volume item sets `divisor: 1m`). Patch the
annotation and the file updates without a Pod restart, which an environment
variable could never do:

```bash
kubectl --context mof-patterns annotate pod "$POD" -n patterns patterns.example.com/owner=platform-team --overwrite
sleep 2
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /etc/podinfo/annotations
```

`PG_PASSWORD` and the rest of this Deployment's `secretKeyRef`/
`configMapKeyRef` environment variables are also a form of the Pod telling a
container about itself, but the Downward API is narrower and more specific:
it exposes only what the API server already knows about *this exact Pod
object*, never arbitrary application configuration a human wrote down
somewhere else.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f self-awareness/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f self-awareness/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
