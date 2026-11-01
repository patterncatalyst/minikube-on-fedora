# Process Containment

Runnable example for the [Process Containment chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/28-process-containment/).

Worked against **review-service**: a full pod- and container-level
`securityContext` (non-root UID, dropped capabilities, no privilege
escalation, read-only root filesystem), plus a disposable namespace enforcing
the baseline Pod Security Standard.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh review-service v1
```

```bash
kubectl --context mof-patterns apply -n patterns -f process-containment/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f process-containment/01-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=review-service -n patterns --timeout=60s
```

## Verify the hardening from inside the container

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=review-service -o jsonpath='{.items[0].metadata.name}')

kubectl --context mof-patterns exec -n patterns "$POD" -- id
# uid=1001 gid=0(root) groups=0(root)

kubectl --context mof-patterns exec -n patterns "$POD" -- sh -c 'cat /proc/1/status | grep CapEff'
# CapEff: 0000000000000000

kubectl --context mof-patterns exec -n patterns "$POD" -- sh -c 'touch /opt/app-root/src/test-file'
# touch: /opt/app-root/src/test-file: Read-only file system

kubectl --context mof-patterns exec -n patterns "$POD" -- sh -c 'touch /tmp/test-file && echo ok'
# ok — the one writable exception this hardening leaves in place
```

Confirm the service is still serving normally:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/review-service 8080:80 &
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/healthz | jq .
```

## Pod Security Standards

```bash
kubectl --context mof-patterns apply -f process-containment/02-pss-namespace.yaml
kubectl --context mof-patterns apply -f process-containment/03-compliant-pod.yaml
kubectl --context mof-patterns get pod pss-compliant -n patterns-pss-demo
# Running, no warning printed
```

Now attempt the privileged Pod, which the baseline standard rejects outright:

```bash
kubectl --context mof-patterns apply -f process-containment/04-privileged-pod-rejected.yaml
# Error from server (Forbidden): error when creating "...": pods "privileged-demo" is forbidden:
# violates PodSecurity "baseline:latest": privileged (container "demo" must not set
# securityContext.privileged=true)
```

No Pod named `privileged-demo` is ever created:

```bash
kubectl --context mof-patterns get pod privileged-demo -n patterns-pss-demo
# Error from server (NotFound): pods "privileged-demo" not found
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns-pss-demo -f process-containment/03-compliant-pod.yaml
kubectl --context mof-patterns delete namespace patterns-pss-demo
kubectl --context mof-patterns delete -n patterns -f process-containment/01-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f process-containment/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
