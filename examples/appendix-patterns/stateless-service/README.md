# Stateless Service

Runnable example for the [Stateless Service chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/14-stateless-service/).

Worked against **payment-service** at three replicas: a plain `Deployment`
with no per-pod storage and no stable identity, so any replica can answer
any request.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh payment-service v1
kubectl --context mof-patterns apply -n patterns -f stateless-service/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f stateless-service/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=payment-service -n patterns --timeout=60s
```

### Interchangeable replicas

```bash
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=payment-service -o wide
```

Three Pods, random hash suffixes, no ordinal numbering and no claim on which
node they land on beyond what the scheduler decides. Kill one at random:

```bash
VICTIM=$(kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=payment-service -o jsonpath='{.items[0].metadata.name}')
kubectl --context mof-patterns delete pod "$VICTIM" -n patterns
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=payment-service -o wide -w
```

The replacement Pod gets a brand-new name and a brand-new IP; nothing about
the deleted Pod's identity carries forward, because the ReplicaSet never
promised identity in the first place, only a count. Meanwhile the Service
keeps answering throughout:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/payment-service 8080:80 &
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' http://127.0.0.1:8080/health; done; echo
```

### Horizontal scale with no manifest change

```bash
kubectl --context mof-patterns scale deployment/payment-service -n patterns --replicas=5
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/name=payment-service -w
kubectl --context mof-patterns scale deployment/payment-service -n patterns --replicas=3
```

Scaling up adds more interchangeable Pods behind the same Service with no
new identity to account for; scaling down removes Pods with no data to
reconcile, because none of them held any. That's the entire statelessness
contract: the ReplicaSet owns a count, the Service owns a stable name, and
no individual Pod owns anything either of those depends on.

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f stateless-service/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f stateless-service/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
