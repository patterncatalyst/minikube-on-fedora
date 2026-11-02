# Image Builder

Runnable example for the [Image Builder chapter](https://patterncatalyst.github.io/minikube-on-fedora/appendix/k8s-patterns/24-image-builder/).

Two ways to build `shipping-service`'s image without Docker Engine on the
host, as a contrast with `scripts/build-service.sh` (every other chapter's
approach: build on the host, load into the node): `minikube image build`,
which builds on the node itself through minikube's own tooling, and Kaniko, a
Job that builds entirely inside a Pod and pushes to an in-cluster registry,
the way a CI pipeline running on the cluster itself would.

## Part 1: minikube image build, build on the node

```bash
cd examples/appendix-patterns
./scripts/setup-patterns-profile.sh
minikube -p mof-patterns image build \
  -f Containerfile \
  -t shipping-service:v1 \
  ../17-capstone/services/shipping-service
minikube -p mof-patterns image ls | grep shipping-service
```

`-f Containerfile` is the file's name *inside the build context*, not a path
on the host: `minikube image build` tars the context directory, unpacks it on
the node, and resolves `-f` against that unpacked copy, so a host-relative
path like `../17-capstone/.../Containerfile` would point at a file that does
not exist on the node and the build would fail.

No `docker build` ran on the host at all. `minikube image build` ships the
build context to the node and runs the build there, using the same container
runtime (containerd, on this profile) the node already uses to run Pods; the
result lands directly in that runtime's local image store, which is exactly
where `imagePullPolicy: Never` looks. This is the fastest path to an
in-cluster-ish build and needs nothing beyond minikube itself, but it isn't a
Kubernetes object: there's no Pod, no Job, nothing `kubectl get` can show you
mid-build, because the build runs through minikube's own host-to-node
tooling rather than through the Kubernetes API at all.

## Part 2: Kaniko, a real in-cluster build as a Kubernetes object

Kaniko is the other end of that spectrum: a Job, submitted through the
normal Kubernetes API, that builds a Containerfile inside its own Pod with no
privileged container and no Docker daemon anywhere in the cluster, then
pushes the result to a registry the way any CI system would.

Enable the registry addon first; there's no registry anywhere else in this
appendix, since every other chapter's examples use `imagePullPolicy: Never`
to skip needing one entirely:

```bash
minikube -p mof-patterns addons enable registry
kubectl --context mof-patterns apply -n patterns -f image-builder/00-postgres.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=patterns-postgres -n patterns --timeout=60s
kubectl --context mof-patterns apply -n patterns -f image-builder/01-kaniko-job.yaml
kubectl --context mof-patterns wait --for=condition=Complete job/shipping-service-kaniko-build -n patterns --timeout=180s
kubectl --context mof-patterns logs -n patterns job/shipping-service-kaniko-build
```

The Job's own Pod does the entire build: it fetches the build context
straight from this repository's `main` branch (a git context with
`--context-sub-path` pointed at `shipping-service`'s own directory, so no
host mount or pre-staged tarball is needed at all), runs through the
Containerfile's build stages exactly as Docker Engine would, and pushes the
result to `registry.kube-system.svc.cluster.local`, the registry addon's
in-cluster Service name. A Pod reaches that name through ordinary cluster
networking, the same way any Service in this appendix is reached by name.

### Pulling the built image back

```bash
kubectl --context mof-patterns apply -n patterns -f image-builder/02-deployment.yaml
kubectl --context mof-patterns wait --for=condition=Ready pod -l app.kubernetes.io/name=shipping-service -n patterns --timeout=60s
```

The Deployment's image is `localhost:5000/shipping-service:kaniko`, a
different address for the exact same registry. The Kaniko Job pushed as a
Pod, using the cluster's normal Service DNS; the kubelet pulls as the node
itself, through the node's own containerd, which shares the node's network
namespace rather than any Pod's. The registry addon's `registry-proxy`
DaemonSet listens on `localhost:5000` on every node specifically so the
node's container runtime can reach the registry without any insecure-registry
configuration at all: `localhost` really does mean the same host for both
containerd and the proxy, since neither one is a Pod. Confirm with
`imagePullPolicy: Always` actually pulling rather than reusing a cached
layer:

```bash
kubectl --context mof-patterns get pod -n patterns -l app.kubernetes.io/name=shipping-service -o jsonpath='{.items[0].status.containerStatuses[0].image}{"\n"}'
kubectl --context mof-patterns describe pod -n patterns -l app.kubernetes.io/name=shipping-service | grep -A2 "Pulling image"
```

![Two in-cluster build paths: minikube image build runs on the node directly with no Kubernetes object at all, while a Kaniko Job builds inside a Pod and pushes to an in-cluster registry a Deployment later pulls from]({{ "/assets/diagrams/appendix-24-image-builder.svg" | relative_url }})
*minikube image build bypasses the Kubernetes API entirely; Kaniko is itself a Pod the API schedules, builds, and tears down like any other workload.*

## Cleanup

```bash
kubectl --context mof-patterns delete -n patterns -f image-builder/02-deployment.yaml
kubectl --context mof-patterns delete -n patterns -f image-builder/01-kaniko-job.yaml
kubectl --context mof-patterns delete -n patterns -f image-builder/00-postgres.yaml
minikube -p mof-patterns addons disable registry
minikube -p mof-patterns image rm shipping-service:v1
```

To remove the whole profile instead: `minikube delete -p mof-patterns`.
