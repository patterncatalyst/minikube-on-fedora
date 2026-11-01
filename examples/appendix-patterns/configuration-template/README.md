# Configuration Template

Runnable example for the [Configuration Template chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/20-configuration-template/).

Worked against **inventory-service**: an init container renders a config file
from a template and an environment overlay before the main container starts.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh inventory-service v1
```

Apply the template, both overlays, and Postgres, then the Deployment (wired
to the dev overlay by default):

```bash
kubectl --context mof-patterns apply -n patterns -f configuration-template/01-configmap-template.yaml
kubectl --context mof-patterns apply -n patterns -f configuration-template/02-configmap-dev-overlay.yaml
kubectl --context mof-patterns apply -n patterns -f configuration-template/03-configmap-prod-overlay.yaml
kubectl --context mof-patterns apply -n patterns -f configuration-template/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f configuration-template/04-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=inventory-service -n patterns --timeout=60s
```

Read the rendered file from the main container:

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=inventory-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$POD" -- cat /config/app/app.conf
```

```ini
[inventory-service]
environment=development
log_level=debug
rendered_by=init-container
```

Confirm the init container ran and exited before the main container started:

```bash
kubectl --context mof-patterns get pod -n patterns "$POD" \
  -o jsonpath='{.status.initContainerStatuses[0].name}{"\n"}{.status.initContainerStatuses[0].state}{"\n"}'
```

Now switch to the production overlay. Patching the Deployment's init
container to reference `inventory-prod-overlay` and recreating the Pod is the
whole mechanism:

```bash
kubectl --context mof-patterns patch deployment inventory-service -n patterns --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/initContainers/0/envFrom/0/configMapRef/name","value":"inventory-prod-overlay"}]'
kubectl --context mof-patterns rollout restart deployment/inventory-service -n patterns
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=inventory-service -n patterns --timeout=60s
```

```bash
NEWPOD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=inventory-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns exec -n patterns "$NEWPOD" -- cat /config/app/app.conf
```

```ini
[inventory-service]
environment=production
log_level=warning
rendered_by=init-container
```

inventory-service's own REST and gRPC surfaces (`/health`, `/healthz`,
`/stock`) are unaffected by any of this: `SERVICE_SCHEMA` and the Postgres
settings still arrive as plain env vars, exactly as in the
[Env Var Configuration example](../env-var-configuration/).

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f configuration-template/04-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/00-postgres.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/03-configmap-prod-overlay.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/02-configmap-dev-overlay.yaml
kubectl --context mof-patterns delete -n patterns -f configuration-template/01-configmap-template.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
