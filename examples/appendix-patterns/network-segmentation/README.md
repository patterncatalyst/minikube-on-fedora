# Network Segmentation

Runnable example for the [Network Segmentation chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/27-network-segmentation/).

Worked against **inventory-service**, **payment-service**, and
**graphql-gateway**: default-deny `NetworkPolicy` for the first two, one
narrow allow rule for the gateway's real gRPC call into inventory-service, an
egress restriction on inventory-service, and a disposable curl client for
every negative check.

## The CNI prerequisite

minikube's default CNI does not enforce `NetworkPolicy` at all; applying one
succeeds but changes nothing about real traffic. This example needs Calico,
set at profile creation:

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh --replace --calico
```

```bash
kubectl --context mof-patterns get pods -n kube-system | grep calico
```

## Run it

```bash
./scripts/build-service.sh inventory-service v1
./scripts/build-service.sh payment-service v1
./scripts/build-service.sh graphql-gateway v1
```

```bash
kubectl --context mof-patterns apply -n patterns -f network-segmentation/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f network-segmentation/01-inventory-service.yaml
kubectl --context mof-patterns apply -n patterns -f network-segmentation/02-payment-service.yaml
kubectl --context mof-patterns apply -n patterns -f network-segmentation/03-graphql-gateway.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=inventory-service -n patterns --timeout=60s
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=payment-service -n patterns --timeout=60s
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=graphql-gateway -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f network-segmentation/08-test-client.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod/netseg-test-client -n patterns --timeout=60s
```

## Before any policy: everything is open

```bash
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 -o /dev/null -w '%{http_code}\n' http://inventory-service:80/health
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 -o /dev/null -w '%{http_code}\n' http://payment-service:80/health
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 http://inventory-service:50051
```

All three succeed or at least connect (the last one gets a protocol error
from the gRPC server, not a timeout: proof the TCP path is open). This is
the baseline the rest of this example changes.

## Default-deny, scoped per workload

```bash
kubectl --context mof-patterns apply -n patterns -f network-segmentation/04-deny-all-inventory.yaml
kubectl --context mof-patterns apply -n patterns -f network-segmentation/06-deny-all-payment.yaml
```

```bash
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 http://inventory-service:80/health
# times out
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 http://payment-service:80/health
# times out
```

Confirm Postgres itself is untouched (it carries no label either policy's
`podSelector` names):

```bash
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 patterns-postgres:5432
# connects (gets a protocol error from Postgres, not a timeout)
```

## Allow exactly one caller

```bash
kubectl --context mof-patterns apply -n patterns -f network-segmentation/05-allow-gateway-to-inventory.yaml
```

The test client is still denied: its label was never named by the allow rule:

```bash
kubectl --context mof-patterns exec -n patterns netseg-test-client -- curl -sm 3 http://inventory-service:50051
# times out
```

A short-lived Pod labeled to match `graphql-gateway`'s selector proves the
rule itself works. `NetworkPolicy` matches on labels, not on what's actually
running inside the Pod, which is exactly what this proves, and because this
label is also `graphql-gateway`'s own Service selector, the probe is deleted
immediately after the one check it exists for, rather than left running
alongside the real Deployment's Pods:

```bash
kubectl --context mof-patterns run netseg-probe-gateway \
  --image=docker.io/curlimages/curl:8.11.0 \
  --labels="app.kubernetes.io/name=graphql-gateway" \
  --restart=Never -n patterns --command -- sleep infinity
kubectl --context mof-patterns wait --for=condition=Ready pod/netseg-probe-gateway -n patterns --timeout=30s

kubectl --context mof-patterns exec -n patterns netseg-probe-gateway -- curl -sm 3 http://inventory-service:50051
# connects (gRPC protocol error, not a timeout): the allow rule's selector matched

kubectl --context mof-patterns delete pod netseg-probe-gateway -n patterns
```

## Restrict egress

```bash
kubectl --context mof-patterns apply -n patterns -f network-segmentation/07-egress-inventory-restricted.yaml
```

The cleanest proof this is compatible with the workload actually running is
its own readiness probe, which depends on reaching Postgres:

```bash
kubectl --context mof-patterns rollout restart deployment/inventory-service -n patterns
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=inventory-service -n patterns --timeout=60s
```

A `Ready` Pod after the restart confirms DNS resolution and the Postgres
connection both still work under the egress restriction, with nothing else
in the destination list.

## Cleanup

```bash
kubectl --context mof-patterns delete pod netseg-probe-gateway -n patterns --ignore-not-found
kubectl --context mof-patterns delete -n patterns -f network-segmentation/08-test-client.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/07-egress-inventory-restricted.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/06-deny-all-payment.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/05-allow-gateway-to-inventory.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/04-deny-all-inventory.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/03-graphql-gateway.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/02-payment-service.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/01-inventory-service.yaml
kubectl --context mof-patterns delete -n patterns -f network-segmentation/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
