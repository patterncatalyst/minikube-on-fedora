# Packaging: Helm and Kustomize

Runnable example for the [Packaging: Helm and Kustomize
chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/31-packaging-helm-and-kustomize/).

The same `shipping-service` image, deployed two ways into the same
namespace: a Helm chart (`chart/`, release name `shipping-helm`) and a
Kustomize base with `dev`/`prod` overlays (`kustomize/`, resource name
`shipping-kustomize`). The two deployments use distinct names so they can
run side by side without colliding.

For a from-scratch Helm chart walkthrough, see
[§9: Helm](https://patterncatalyst.github.io/minikube-on-fedora/docs/09-helm/);
this example assumes that mechanism and focuses on the CKAD command surface
and on the Kustomize alternative.

## Run it

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
./scripts/build-service.sh shipping-service v1
kubectl --context mof-patterns apply -n patterns -f packaging-helm-and-kustomize/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
```

### Helm: install, upgrade, rollback

```bash
cd packaging-helm-and-kustomize
helm --kube-context mof-patterns lint ./chart
helm --kube-context mof-patterns template shipping-helm ./chart --namespace patterns
helm --kube-context mof-patterns install shipping-helm ./chart --namespace patterns
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/instance=shipping-helm -n patterns --timeout=120s
helm --kube-context mof-patterns list -n patterns
```

Upgrade with a different value, confirm the config-checksum annotation rolls
the Pod, then look at history and roll back:

```bash
helm --kube-context mof-patterns upgrade shipping-helm ./chart --namespace patterns --set replicaCount=2
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/instance=shipping-helm
helm --kube-context mof-patterns history shipping-helm -n patterns
helm --kube-context mof-patterns rollback shipping-helm 1 -n patterns
kubectl --context mof-patterns get pods -n patterns -l app.kubernetes.io/instance=shipping-helm
```

Clean up the release:

```bash
helm --kube-context mof-patterns uninstall shipping-helm -n patterns
```

### Kustomize: base + dev/prod overlays

```bash
kubectl --context mof-patterns kustomize kustomize/overlays/dev
kubectl --context mof-patterns apply -n patterns -k kustomize/overlays/dev
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-kustomize -n patterns --timeout=120s
kubectl --context mof-patterns get deployment shipping-kustomize -n patterns -o jsonpath='{.spec.replicas}{"\n"}{.spec.template.spec.containers[0].resources}{"\n"}'
```

Switch to the prod overlay in place (same resource names, different
replicas/resources/schema):

```bash
kubectl --context mof-patterns diff -n patterns -k kustomize/overlays/prod
kubectl --context mof-patterns apply -n patterns -k kustomize/overlays/prod
kubectl --context mof-patterns get deployment shipping-kustomize -n patterns -o jsonpath='{.spec.replicas}{"\n"}{.spec.template.spec.containers[0].resources}{"\n"}'
```

## Cleanup

```bash
helm --kube-context mof-patterns uninstall shipping-helm -n patterns 2>/dev/null || true
kubectl --context mof-patterns delete -n patterns -k kustomize/overlays/prod
kubectl --context mof-patterns delete -n patterns -f 00-postgres.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
