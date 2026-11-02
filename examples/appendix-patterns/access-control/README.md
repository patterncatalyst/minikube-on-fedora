# Access Control

Runnable example for the [Access Control chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/26-access-control/).

Worked against **payment-service**: a dedicated `ServiceAccount`, a `Role`
scoped by `resourceNames` to exactly the ConfigMap and Secret it owns, and a
`RoleBinding` connecting the two. A decoy ConfigMap and Secret, plus a second
`ServiceAccount` bound to the built-in `view` `ClusterRole`, round out the
`kubectl auth can-i` checks.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh payment-service v1
```

Apply everything:

```bash
kubectl --context mof-patterns apply -n patterns -f access-control/00-postgres.yaml
kubectl --context mof-patterns apply -n patterns -f access-control/01-configmap.yaml
kubectl --context mof-patterns apply -n patterns -f access-control/02-decoys.yaml
kubectl --context mof-patterns apply -n patterns -f access-control/03-serviceaccount.yaml
kubectl --context mof-patterns apply -n patterns -f access-control/04-rbac.yaml
kubectl --context mof-patterns apply -n patterns -f access-control/05-ops-readonly.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f access-control/06-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=payment-service -n patterns --timeout=60s
```

## Prove the allowed reads

```bash
kubectl --context mof-patterns auth can-i get configmap/payment-config \
  --as=system:serviceaccount:patterns:payment-service -n patterns
# yes

kubectl --context mof-patterns auth can-i get secret/patterns-postgres-app \
  --as=system:serviceaccount:patterns:payment-service -n patterns
# yes
```

## Prove the denials

```bash
# A ConfigMap and Secret the Role never names:
kubectl --context mof-patterns auth can-i get configmap/other-team-config \
  --as=system:serviceaccount:patterns:payment-service -n patterns
# no
kubectl --context mof-patterns auth can-i get secret/other-team-secret \
  --as=system:serviceaccount:patterns:payment-service -n patterns
# no

# list is not granted at all (and resourceNames couldn't scope it even if it were):
kubectl --context mof-patterns auth can-i list configmaps \
  --as=system:serviceaccount:patterns:payment-service -n patterns
# no

# The Role is namespaced: the identical check in a different namespace is denied.
kubectl --context mof-patterns auth can-i get configmap/payment-config \
  --as=system:serviceaccount:patterns:payment-service -n default
# no

# Pods were never granted at all.
kubectl --context mof-patterns auth can-i list pods \
  --as=system:serviceaccount:patterns:payment-service -n patterns
# no
```

Audit everything this identity can do in one shot:

```bash
kubectl --context mof-patterns auth can-i --list \
  --as=system:serviceaccount:patterns:payment-service -n patterns
```

## The ClusterRole-via-RoleBinding reuse

```bash
kubectl --context mof-patterns auth can-i list pods \
  --as=system:serviceaccount:patterns:ops-readonly -n patterns
# yes: the built-in "view" ClusterRole, bound by a namespaced RoleBinding

kubectl --context mof-patterns auth can-i list pods \
  --as=system:serviceaccount:patterns:ops-readonly -n default
# no: same ClusterRole, but the RoleBinding only reaches the patterns namespace
```

## Confirm the service is serving

```bash
kubectl --context mof-patterns port-forward -n patterns svc/payment-service 8080:80 &
curl -s http://127.0.0.1:8080/health | jq .
curl -s http://127.0.0.1:8080/healthz | jq .
```

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f access-control/06-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/05-ops-readonly.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/04-rbac.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/03-serviceaccount.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/02-decoys.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/01-configmap.yaml
kubectl --context mof-patterns delete -n patterns -f access-control/00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
