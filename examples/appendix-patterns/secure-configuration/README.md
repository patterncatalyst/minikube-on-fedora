# Secure Configuration

Runnable example for the [Secure Configuration chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/29-secure-configuration/).

Worked against **inventory-service**: its own, distinctly named Postgres
credential, created with `stringData`, decoded back to confirm base64 isn't
encryption, and consumed both as env vars and as a 0400-mode mounted file.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh inventory-service v1
```

```bash
kubectl --context mof-patterns apply -n patterns -f secure-configuration/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f secure-configuration/01-secret.yaml
kubectl --context mof-patterns apply -n patterns -f secure-configuration/02-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=inventory-service -n patterns --timeout=60s
```

## base64 is not encryption

```bash
kubectl --context mof-patterns get secret inventory-db-credentials -n patterns -o yaml
# data.password is base64, e.g. Y2hhbmdlbWU=

kubectl --context mof-patterns get secret inventory-db-credentials -n patterns -o jsonpath='{.data.password}' | base64 -d
# changeme

kubectl --context mof-patterns describe secret inventory-db-credentials -n patterns
# password:  8 bytes: describe redacts the value; get -o yaml and jsonpath don't
```

## Two consumption paths, one Secret

```bash
POD=$(kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=inventory-service -o jsonpath='{.items[0].metadata.name}')

kubectl --context mof-patterns exec -n patterns "$POD" -- env | grep -E '^PG_(USER|PASSWORD|DATABASE)='

kubectl --context mof-patterns exec -n patterns "$POD" -- ls -l /etc/inventory/credentials/
# -r--r----- for username, password, dbname (0440: owner+group, matching
# this container's gid, not 0400, which a non-root container could never
# read, since a projected volume's files are always owned by root)

kubectl --context mof-patterns exec -n patterns "$POD" -- cat /etc/inventory/credentials/password
# changeme
```

Confirm the service is serving:

```bash
kubectl --context mof-patterns port-forward -n patterns svc/inventory-service 8080:80 &
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/healthz | jq .
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f secure-configuration/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f secure-configuration/01-secret.yaml
kubectl --context mof-patterns delete -n patterns -f secure-configuration/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
