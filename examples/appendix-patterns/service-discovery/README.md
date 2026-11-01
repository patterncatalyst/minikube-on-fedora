# Service Discovery

Runnable example for the [Service Discovery chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/16-service-discovery/).

Worked against **order-service**, **inventory-service**, and
**graphql-gateway**: a `ClusterIP`, a `NodePort`, a `LoadBalancer`, and an
`Ingress`, all reaching their backends by DNS name alone.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
minikube addons enable ingress -p mof-patterns
./scripts/build-service.sh order-service v1
./scripts/build-service.sh inventory-service v1
./scripts/build-service.sh graphql-gateway v1
kubectl --context mof-patterns apply -n patterns -f service-discovery/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f service-discovery/01-order-service.yaml
kubectl --context mof-patterns apply -n patterns -f service-discovery/02-inventory-service.yaml
kubectl --context mof-patterns apply -n patterns -f service-discovery/03-gateway.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=order-service -n patterns --timeout=60s
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=inventory-service -n patterns --timeout=60s
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=graphql-gateway -n patterns --timeout=60s
```

### DNS, not IPs

```bash
kubectl --context mof-patterns run -n patterns dns-check --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi10/ubi-minimal:10.2-1792742351 -- \
  getent hosts order-service.patterns.svc.cluster.local
```

`graphql-gateway` never learns `order-service`'s Pod IP: it's configured
with `ORDER_REST_URL=http://order-service`, a name kube-dns resolves fresh
on every call, which is exactly why restarting `order-service`'s Pod
(getting a new IP) never requires touching the gateway.

### ClusterIP, NodePort, LoadBalancer

```bash
kubectl --context mof-patterns get svc -n patterns order-service inventory-service graphql-gateway
```

`order-service` is `ClusterIP`, reachable only inside the cluster.
`inventory-service` is `NodePort`, reachable on port `30180` of any node's
own IP:

```bash
kubectl --context mof-patterns get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
curl -s -o /dev/null -w '%{http_code}\n' "http://$(minikube -p mof-patterns ip):30180/health"
```

`graphql-gateway` is `LoadBalancer`, which on a real cloud provisions an
external balancer; minikube has no cloud provider underneath to do that, so
`EXTERNAL-IP` stays `<pending>` until `minikube tunnel` (run in its own
terminal, needs sudo) simulates one:

```bash
sudo minikube tunnel -p mof-patterns &
kubectl --context mof-patterns get svc graphql-gateway -n patterns -w
```

Once `EXTERNAL-IP` populates, the Service answers on port 80 at that
address directly, the same contract a real cloud load balancer provides.

### Ingress: one entry point, routed by path

```bash
kubectl --context mof-patterns apply -n patterns -f service-discovery/04-ingress.yaml
kubectl --context mof-patterns get ingress patterns-gateway -n patterns
INGRESS_IP=$(minikube -p mof-patterns ip)
curl -s "http://${INGRESS_IP}/graphql" | head -c 200; echo
curl -s "http://${INGRESS_IP}/health"; echo
```

One address, two backends: `/graphql` reaches `graphql-gateway`'s own
GraphiQL endpoint, `/health` reaches `order-service`'s liveness endpoint —
no rewrite is configured, so each `path` here points at something that
genuinely exists on that backend rather than relying on ingress-nginx to
rewrite the path into something that does.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f service-discovery/04-ingress.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/03-gateway.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/02-inventory-service.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/01-order-service.yaml
kubectl --context mof-patterns delete -n patterns -f service-discovery/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
