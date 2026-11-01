# shipping-policy-operator

A real [controller-runtime](https://github.com/kubernetes-sigs/controller-runtime)
operator backing the [Controller](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/22-controller/)
and [Operator](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/25-operator/)
chapters. It defines one CRD, `ShippingPolicy` (group
`shipping.patterncatalyst.io`, version `v1alpha1`), and reconciles each
`ShippingPolicy` into a `shipping-service` Deployment and a ConfigMap, sized
and prioritized from the policy's own spec.

## Layout

```
operator/
  api/v1alpha1/              # ShippingPolicy, ShippingPolicySpec, ShippingPolicyStatus
  cmd/main.go                # manager entrypoint
  internal/controller/       # the reconciler + its tests
  config/
    crd/bases/                # generated CRD
    rbac/                     # ServiceAccount, Role, RoleBinding (namespaced to patterns)
    manager/                  # the operator's own Deployment
    samples/                  # a sample ShippingPolicy
    default/                  # kustomization combining the three above
  install.yaml                # flattened `kustomize build config/default`
  Containerfile                # golang builder -> ubi10/ubi-micro runtime
```

## The API

```yaml
apiVersion: shipping.patterncatalyst.io/v1alpha1
kind: ShippingPolicy
metadata:
  name: ground-standard
  namespace: patterns
spec:
  carrier: ground              # required
  maxTransitDays: 5            # required, >= 1
  replicas: 3                  # required, >= 0
  priorityClassName: patterns-high-priority   # optional
status:
  observedReplicas: 3
  conditions:
    - type: Ready
      status: "True"
      reason: ReplicasMatch
```

## The reconciler

`internal/controller/shippingpolicy_controller.go`'s `Reconcile` is the
observe-diff-act loop chapter 22 describes: given a `ShippingPolicy`, it

1. creates or updates a ConfigMap named after the policy, carrying
   `carrier` and `maxTransitDays`,
2. creates or updates a Deployment named after the policy, running
   `shipping-service:v1` at `spec.replicas` with `spec.priorityClassName`
   and `imagePullPolicy: Never` (the same policy every other chapter's
   example uses, no registry, image loaded straight into the profile), and
3. re-reads the Deployment's own `status.replicas` and writes it to
   `status.observedReplicas`, setting a single `Ready` condition True once
   observed matches desired.

Both children carry a controller owner reference back to the
`ShippingPolicy` (`controllerutil.SetControllerReference`), so deleting the
`ShippingPolicy` garbage-collects both without a finalizer: there's nothing
external to clean up before the object is allowed to go away, so a finalizer
would only add a failure mode (an object stuck in `Terminating` if the
finalizer's own logic ever errors) without buying anything a finalizer is
actually for.

`SetupWithManager` watches `ShippingPolicy` directly and owns both child
kinds, so hand-editing the Deployment (or deleting the ConfigMap) also
triggers a reconcile, not just a spec change on the `ShippingPolicy` itself.

## Verification run

```
$ go build ./...
$ go vet ./...
$ go test ./... -v
=== RUN   TestReconcile_CreatesDeploymentAndConfigMap
--- PASS: TestReconcile_CreatesDeploymentAndConfigMap
=== RUN   TestReconcile_StatusReadyOnceReplicasMatch
--- PASS: TestReconcile_StatusReadyOnceReplicasMatch
=== RUN   TestReconcile_IsIdempotent
--- PASS: TestReconcile_IsIdempotent
=== RUN   TestEnvtest_ReconcileAgainstRealAPIServer
--- PASS: TestEnvtest_ReconcileAgainstRealAPIServer
PASS
```

Three tests run against the controller-runtime **fake client**
(`sigs.k8s.io/controller-runtime/pkg/client/fake`): object creation and
shape, the Ready condition tracking observed-vs-desired replicas across two
reconciles, and idempotency (a second reconcile with no spec change leaves
the Deployment's generation untouched). A fourth runs against a real
**envtest** control plane (etcd + kube-apiserver, no kubelet) to prove the
generated CRD's own OpenAPI validation rejects a `ShippingPolicy` missing
`carrier`, something a fake client can't check since it never runs the
apiserver's schema validation.

envtest needs `KUBEBUILDER_ASSETS` pointed at real `etcd`/`kube-apiserver`
binaries:

```bash
setup-envtest use 1.29.0 -p path   # prints the path; install it first if needed:
                                    # go install sigs.k8s.io/controller-runtime/tools/setup-envtest@v0.25.2
export KUBEBUILDER_ASSETS="$(setup-envtest use 1.29.0 -p path)"
go test ./...
```

Without `KUBEBUILDER_ASSETS` set, `TestMain` logs that the envtest
environment is unavailable to stderr and the envtest-backed test skips
itself; the three fake-client tests still run and the package still passes.
Both lanes were run and are green on this machine.

## Regenerating code and manifests

```bash
controller-gen object paths=./api/...                                  # zz_generated.deepcopy.go
controller-gen crd paths=./api/... output:crd:artifacts:config=config/crd/bases
controller-gen rbac:roleName=shipping-policy-operator paths=./... output:rbac:artifacts:config=config/rbac
```

`controller-gen rbac` always emits a `ClusterRole`; `config/rbac/role.yaml`
is hand-edited afterward from `ClusterRole` to a namespaced `Role` in
`patterns`, since this operator only ever reconciles objects in that one
namespace. Re-apply that namespace edit after regenerating.

## Build, load, deploy, try, cleanup

Everything below targets the `mof-patterns` profile (see
`examples/appendix-patterns/README.md` for creating it) and the `patterns`
namespace.

### Build and load the operator image

There's no registry, the same `imagePullPolicy: Never` approach
`scripts/build-service.sh` uses for every other example in this appendix:

```bash
cd examples/appendix-patterns/operator
docker build -t shipping-policy-operator:v1 -f Containerfile .
minikube -p mof-patterns image load shipping-policy-operator:v1
```

Build `shipping-service` itself the normal way, from the appendix root:

```bash
cd examples/appendix-patterns
./scripts/build-service.sh shipping-service v1
```

### Deploy

```bash
cd examples/appendix-patterns/operator
kubectl --context mof-patterns apply -f install.yaml
kubectl --context mof-patterns wait --for=condition=Available deployment/shipping-policy-operator -n patterns --timeout=60s
```

(`kustomize build config/default | kubectl --context mof-patterns apply -f -`
produces the same manifests as `install.yaml`; `install.yaml` is checked in
so a reader doesn't need `kustomize` installed just to try the operator.)

### Try it

```bash
kubectl --context mof-patterns apply -f config/samples/shipping_v1alpha1_shippingpolicy.yaml
kubectl --context mof-patterns get shippingpolicy -n patterns
kubectl --context mof-patterns wait --for=condition=Ready shippingpolicy/ground-standard -n patterns --timeout=60s
kubectl --context mof-patterns get deployment ground-standard -n patterns
kubectl --context mof-patterns get configmap ground-standard -n patterns -o jsonpath='{.data}'
```

Edit the sample's `replicas` or `carrier` and re-apply; the Deployment and
ConfigMap follow without the operator restarting:

```bash
kubectl --context mof-patterns patch shippingpolicy ground-standard -n patterns --type=merge -p '{"spec":{"replicas":5}}'
kubectl --context mof-patterns get deployment ground-standard -n patterns -o jsonpath='{.spec.replicas}'
```

Delete the `ShippingPolicy` and both children disappear through their owner
references, with no finalizer delay:

```bash
kubectl --context mof-patterns delete shippingpolicy ground-standard -n patterns
kubectl --context mof-patterns get deployment,configmap -n patterns -l shipping.patterncatalyst.io/policy=ground-standard
```

### Cleanup

```bash
kubectl --context mof-patterns delete -f install.yaml
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
