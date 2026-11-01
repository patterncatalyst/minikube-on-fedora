# Declarative Deployment

Runnable example for the [Declarative Deployment chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/02-declarative-deployment/).

Worked against **shipping-service**: a `RollingUpdate` versus a `Recreate`
strategy, driven by `kubectl set image`, `kubectl rollout status`, and
`kubectl rollout undo`.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f declarative-deployment/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f declarative-deployment/01-deployment-rolling.yaml
kubectl --context mof-patterns rollout status deployment/shipping-service -n patterns
```

Build a second tag (same source: the point of this chapter is the rollout
mechanics, not an application change) and roll to it:

```bash
./scripts/build-service.sh shipping-service v2
kubectl --context mof-patterns set image deployment/shipping-service -n patterns shipping-service=shipping-service:v2
kubectl --context mof-patterns get pods -n patterns -w
```

In another terminal, confirm the Service never drops all backends during the
rollout:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/shipping-service 8080:80 &
while true; do curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health; sleep 0.5; done
```

Check history and roll back:

```bash
kubectl --context mof-patterns rollout history deployment/shipping-service -n patterns
kubectl --context mof-patterns rollout undo deployment/shipping-service -n patterns
```

Now switch strategies and repeat the image bump:

```bash
kubectl --context mof-patterns apply -n patterns -f declarative-deployment/02-deployment-recreate.yaml
kubectl --context mof-patterns set image deployment/shipping-service -n patterns shipping-service=shipping-service:v2
kubectl --context mof-patterns get pods -n patterns -w
```

With `Recreate`, every Pod terminates before any replacement starts: the curl
loop above will show a stretch of connection failures that `RollingUpdate`
never produced.

## Cleanup

```bash
kubectl --context mof-patterns delete deployment/shipping-service service/shipping-service -n patterns
kubectl --context mof-patterns delete -n patterns -f declarative-deployment/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
