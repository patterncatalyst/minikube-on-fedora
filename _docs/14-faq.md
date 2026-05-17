---
title: FAQ
order: 14
description: Common pain points hit while working through this tutorial, with the diagnostic commands and the fixes. Plus a consolidated cleanup-recipes section at the end.
duration: 5 minutes
---

Reference material, not linear prose. Skim or search for the
question you're hitting. Every entry here corresponds to
something that actually went wrong at least once during the
tutorial's development — none are hypothetical.

## Installation and startup

### Q: `minikube start` fails with podman socket errors

The most common cause is that the rootless podman socket isn't
running. Check with `systemctl --user status podman.socket`. If
it's inactive, `systemctl --user enable --now podman.socket`
starts it persistently. The Podman driver in minikube needs
the user-level socket, not the system one.

### Q: minikube starts but `kubectl` can't reach it

Almost always the kubectl context is pointing at a different
cluster. Run `kubectl config current-context` to see which one
kubectl is using, and `kubectl config get-contexts` to see all
of them. `kubectl config use-context minikube` switches back.
If `minikube` isn't in the context list at all, the cluster
didn't actually start — re-run `minikube start -p minikube`
and watch the output for errors.

### Q: my minikube cluster is unbearably slow

Two common causes: (1) the cluster is sized too small — check
`minikube profile list` for current CPU/memory allocation, and
recreate with bigger numbers if needed (`minikube delete -p
minikube` then `minikube start -p minikube --memory=8g --cpus=6
--container-runtime=containerd --rootless=true`); (2) the host
machine is swapping — `free -h` will tell you. Kubernetes
control plane components are CPU- and memory-hungry; less than
4 GB for the cluster causes constant pressure.

### Q: I want to start completely over

```bash
minikube delete --all --purge
rm -rf ~/.minikube ~/.kube
```

This nukes every minikube profile, its disk images, and your
kubectl config. Useful when something has gotten genuinely
wedged. The next `minikube start` recreates everything from
scratch.

## Running containers and Pods

### Q: Pods stuck in `ImagePullBackOff` or `ErrImagePull`

```bash
kubectl describe pod [pod-name] | grep -A 5 Events
```

The Events block will tell you what went wrong. Most common
reasons: the image name is wrong (typo), the image tag doesn't
exist on the registry, the registry requires authentication
you haven't configured, or your minikube profile can't reach
the internet (try `minikube ssh -p minikube -- ping -c 2
8.8.8.8`).

### Q: I thought Podman uses crun — why does the diagram show containerd?

Both are correct, and they live at different layers. On the
host, **rootless Podman** uses **crun** to run containers — one
of which is the "minikube node" container. Inside that
container, Kubernetes is installed with its own CRI
runtime that the kubelet talks to. The `--container-runtime`
flag we passed in §3 chose **containerd** for that inner
layer; alternatives are `cri-o` (recommended for rootful
Podman, but problematic in rootless mode) or `docker`
(deprecated). So Podman+crun runs the outer node container;
containerd inside that container runs the actual Pods.

The minikube docs spell out the recommendation:
[rootless Podman → containerd, rootful Podman → CRI-O](https://minikube.sigs.k8s.io/docs/drivers/podman/).
We're rootless, so containerd is the right inner choice.

### Q: my image built locally but Kubernetes can't find it

Locally-built images live in your host's container runtime
(Docker or Podman). Kubernetes inside minikube uses a
*different* container runtime — containerd, running inside
the minikube node container, not on your host. To make
local images visible, either:

```bash
# Build directly into the minikube profile (recommended)
minikube -p minikube image build -t myimage:v1 -f Containerfile .

# Or push from your host into minikube
minikube -p minikube image load myimage:v1
```

`imagePullPolicy: IfNotPresent` in your Deployment manifest
keeps Kubernetes from trying to pull from a public registry
when the image is local.

### Q: Pod is Running but the app inside isn't responding

```bash
kubectl logs [pod-name]                    # stdout/stderr
kubectl exec -it [pod-name] -- /bin/sh     # shell inside the container
kubectl describe pod [pod-name]            # readiness/liveness probe status
```

Common causes: the app isn't binding to `0.0.0.0` (only
`127.0.0.1`), so traffic from outside the container can't
reach it; the app's port doesn't match the Service's
`targetPort`; or the readiness probe is failing and traffic
isn't being routed to the Pod yet.

### Q: the Pod restarts every few seconds (CrashLoopBackOff)

`kubectl logs [pod-name] --previous` shows the logs from the
previous (crashed) instance, which usually contains the
actual error. If the logs don't show anything useful, the
crash is happening so fast the app hasn't logged anything —
`kubectl describe pod` shows the exit code and the OOMKilled
flag if the container ran out of memory.

## Networking

### Q: `kubectl port-forward` works but the NodePort URL doesn't

Rootless minikube networking puts the cluster IP behind
slirp4netns, which isn't routable from the host directly. Use
`minikube service [name] --url -p minikube` instead of trying
to hit the NodePort by IP — it sets up a tunnel for you. See
§7 for the full pattern.

### Q: requests through the KEDA HTTP interceptor return 404

You're probably using `hey -H 'Host: nginx.local'`. **hey is
written in Go, and Go's `net/http` silently strips Host
headers set via the headers map** (issue golang/go#7682, open
since 2014). Use `hey -host nginx.local` instead — hey has a
dedicated flag for this. curl handles `-H 'Host:'` correctly
because curl treats Host as a special case; many other tools
do not.

### Q: I can't reach the cluster from another machine on my LAN

By design — minikube creates a single-machine cluster bound to
loopback. If you need LAN-accessible workloads, you're past
minikube's scope; look at k3s or kind running on a server, or
expose specific services via `kubectl port-forward --address
0.0.0.0` (development only — that bypasses your firewall).

## Storage

### Q: my PersistentVolume isn't bound

```bash
kubectl get pv,pvc -A
kubectl describe pvc [pvc-name]
```

The Events on the PVC will tell you why it's not binding. Most
common: the PVC requests a `storageClassName` that doesn't
exist on the cluster (default minikube ships `standard`), or
the PVC's requested size exceeds what any available PV can
satisfy. Pending PVCs keep their pod in `ContainerCreating`
indefinitely.

### Q: I deleted a workload but the PVC is still there

PVCs are not removed when the Deployment that uses them goes
away — that's intentional, so you don't lose data accidentally.
`kubectl delete pvc [name]` removes it explicitly. The
underlying PV's behavior on PVC delete depends on the
PV's `persistentVolumeReclaimPolicy` (typically `Delete` for
dynamically-provisioned, `Retain` for hand-created).

## Multi-cluster / multi-profile

### Q: `kubectl` is talking to the wrong cluster

This is the daily papercut when running both `minikube` and
`istio` profiles. Two fixes:

```bash
# Switch context explicitly
kubectl config use-context minikube
kubectl config use-context istio

# Or, see at a glance which one you're on (add to your shell prompt)
kubectl config current-context
```

`kubectx` (installed via krew in §2) gives an interactive
picker if you have a lot of contexts.

### Q: I'm getting "Too many open files" from operators

You're hitting the default inotify limits, sized for a single
minikube cluster. Two profiles need higher limits. From §1:

```bash
sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF
fs.inotify.max_user_instances=512
fs.inotify.max_user_watches=524288
EOF
sudo sysctl --system
```

The Istio Cluster Operator surfaces this as opaque "control
group inotify object" errors. The fix applies persistently on
reboot.

### Q: I want to remove one profile but keep the other

```bash
minikube delete -p istio                  # removes only the istio profile
minikube profile list                     # confirm the minikube profile is still there
```

## Updates and rollouts

### Q: I changed a ConfigMap but the Pod still shows the old value

Kubernetes doesn't restart Pods when a referenced ConfigMap
changes — the env vars / volume mounts get the new values only
when the Pod is recreated. Three options:

{% raw %}
```bash
# Option 1: force a restart
kubectl rollout restart deployment/[name]

# Option 2: use a checksum annotation in the Pod template
#         (helm pattern, see §9)
template:
  metadata:
    annotations:
      checksum/config: "{{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}"

# Option 3: use the Reloader operator (third-party)
```
{% endraw %}

The §9 helm section covers the checksum approach in detail —
it's the most robust way to handle ConfigMap-triggered
rollouts.

### Q: I want to roll back a Deployment to a previous version

```bash
kubectl rollout history deployment/[name]
kubectl rollout undo deployment/[name]             # last revision
kubectl rollout undo deployment/[name] --to-revision=3
```

For helm-managed deployments, `helm rollback [release] [revision]` is the equivalent.

## Operator-specific issues

### Q: Strimzi says "Unsupported Kafka.spec.kafka.version"

Strimzi 0.51 supports **only Kafka 4.1.0, 4.1.1, and 4.2.0** —
the entire 3.x line was dropped. If you have an older manifest
pinning Kafka 3.9.x, edit `kafka-cluster.yaml` to use
`version: 4.1.0` and remove any explicit `metadataVersion`
field (Strimzi defaults it to match the Kafka version when not
specified). See §12 prose for the full context.

### Q: Istio sidecar isn't getting injected into my Pod

Three things to verify, in order:

1. The namespace has `istio-injection=enabled` label:
   `kubectl get ns -L istio-injection`
2. The injector webhook is up:
   `kubectl get mutatingwebhookconfiguration | grep istio`
3. The webhook's `caBundle` is populated:
   `kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o jsonpath='{.webhooks[0].clientConfig.caBundle}'`
   (empty = webhook not yet ready, common during install)

Note: in Istio 1.29+, the sidecar appears as an **initContainer
with `restartPolicy: Always`** (KEP-753 native sidecars), not
as a regular container. `kubectl get pod [name] -o
jsonpath='{.spec.initContainers[*].name}'` is the check that
works on both old and new Istio versions.

### Q: KEDA's HPA shows zero replicas but my workload is running

That's normal during the cooldown period. KEDA scales the
Deployment to zero by deleting the underlying HPA (HPA can't
manage 0-replica Deployments). When traffic returns, KEDA
recreates the HPA. If your workload IS running but the
ScaledObject shows 0 desired replicas, check
`kubectl describe scaledobject [name]` — the conditions block
shows why KEDA disagrees with the current state.

## System-level

### Q: my disk is filling up — what should I clean?

```bash
# Old minikube profile disk images
minikube delete --all --purge

# Unused podman images (host)
podman image prune -a

# Containerd images inside the running minikube
minikube -p minikube ssh -- sudo crictl rmi --prune
```

The minikube image cache inside the profile is the most common
culprit — `nginx-custom`, `order-processor`, and the Kafka /
Istio images all accumulate. The `crictl rmi --prune` is safe;
it removes images that aren't currently in use by any Pod.

### Q: I want to upgrade kubectl/helm/minikube

```bash
# kubectl
sudo dnf upgrade -y kubectl

# helm
sudo dnf upgrade -y helm

# minikube (binary install, not from dnf)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

After upgrading minikube, existing profiles continue working
on the old K8s version. To upgrade the Kubernetes version
inside a profile: `minikube start -p minikube
--kubernetes-version=v1.36.1` (or whatever current is).

## Cleanup recipes

Three tiers depending on what you want to keep. See the
per-example-dir `cleanup.sh` scripts for the per-section
detail.

### Just clean up the demo I just ran

The demo's cleanup trap handles this automatically on exit
(whether the demo passed, failed, or you Ctrl-C'd it). No
action needed.

### Clean up a section's heavyweight state

Each §11 and §12 example dir has a `cleanup.sh` with options.
Examples:

```bash
# Remove Kafka cluster + topics, keep Strimzi + KEDA installed
cd examples/12-keda-kafka && ./cleanup.sh

# Also remove Strimzi + KEDA + their CRDs
cd examples/12-keda-kafka && ./cleanup.sh --remove-operators

# Remove nginx workload, keep KEDA
cd examples/12-keda-http && ./cleanup.sh

# Remove Bookinfo + addons, keep Istio control plane
cd examples/11-istio && ./cleanup.sh

# Also remove Istio control plane
cd examples/11-istio && ./cleanup.sh --remove-istio

# Drop the entire istio minikube profile
cd examples/11-istio && ./cleanup.sh --remove-istio --remove-profile
```

`./cleanup.sh --help` lists every option for each script.

### Full reset — back to a fresh Fedora

```bash
minikube delete --all --purge          # all profiles + their disk images
rm -rf ~/.minikube ~/.kube             # config and state
podman image prune -a                  # host-cached container images
helm repo remove kedacore strimzi      # if you added them
```

This leaves your installed binaries (`minikube`, `kubectl`,
`helm`, `hey`) in place — uninstalling those is rarely what
you actually want. To remove them too, `sudo dnf remove
minikube kubectl helm` (assuming they came from dnf; `hey`
came from `go install`, so `rm $(go env GOPATH)/bin/hey`).

---

If you've hit something not listed here, the per-section
READMEs under `examples/*/README.md` each have a "When this
fails" section with section-specific symptoms. And the
diagnostic-dump output from any failing `demo.sh` includes
the most relevant logs and resource state — the demo scripts
are designed to fail informatively, not silently.

[On to §15: Where to go next →]({{ "/docs/15-where-to-go-next/" | relative_url }})
