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

### Q: `minikube start` fails with docker daemon or context errors

minikube follows the active Docker context, so it needs the Docker
Engine daemon running on its default socket. Check in this order:

```bash
sudo systemctl enable --now docker     # daemon not running
docker context show                    # must print: default
docker context use default             # fix a leftover context
sudo usermod -aG docker "$USER"        # "permission denied" on the socket
```

After `usermod`, log out and back in (or `newgrp docker`) so the
group applies. If `docker context show` keeps reverting, look for a
`DOCKER_HOST` export in `~/.bashrc` or `~/.zshrc`. The repo's demo
scripts run the same checks (`require_docker_engine`) and print the
fix for whichever one fails.

### Q: minikube starts but `kubectl` can't reach it

Almost always the kubectl context is pointing at a different
cluster. Run `kubectl config current-context` to see which one
kubectl is using, and `kubectl config get-contexts` to see all
of them. Pass `--context minikube` on the command, or run
`kubectl config use-context minikube` to switch. If `minikube`
isn't in the context list at all, the cluster didn't actually
start — re-run `minikube start -p minikube` and watch the output
for errors.

### Q: my minikube cluster is unbearably slow

Two common causes: (1) the cluster is sized too small — check
`minikube profile list` for current CPU/memory allocation, and
recreate with bigger numbers if needed (`minikube delete -p
minikube`, then `minikube start -p minikube --driver=docker
--container-runtime=containerd --kubernetes-version=v1.35.1
--memory=8192 --cpus=6 --ports=127.0.0.1:18080:30080,127.0.0.1:18081:30808,127.0.0.1:18090:30900`,
the `CORE_PORTS` map from `scripts/lib/_helpers.sh`); (2) the host
machine is swapping — `free -h` will tell you. Kubernetes
control plane components are CPU- and memory-hungry; less than
4 GB for the cluster causes constant pressure.

### Q: I want to start completely over

```bash
minikube delete -p minikube
```

For a wholesale reset, `minikube delete --all --purge` followed by
`rm -rf ~/.minikube ~/.kube` removes **every** minikube profile on the
host, including profiles other projects use, plus your kubectl
config. Useful when something has gotten genuinely
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

### Q: why containerd with runc, and why not mix runtimes?

minikube's docker driver runs each Kubernetes node as a container
on Docker Engine. Inside the node, the kubelet talks to a CRI
runtime; this tutorial passes `--container-runtime=containerd`, and
containerd runs Pods with **runc**. That pairing is the one
minikube documents for the docker driver and the one every example
here uses.

<!-- policy-exempt:start -->
Don't mix runtimes. Pairings are fixed: the retired Podman path
ran containers with crun and needed containerd on top of it, while
the Docker path runs containerd with runc. Switching a profile's
runtime or driver in place leaves state from the old pairing
behind, and the symptom is an opaque `runc` "paused" check failure
at start. If you change driver or runtime, `minikube delete -p
[profile]` first and create a fresh profile.
<!-- policy-exempt:end -->

### Q: my image built locally but Kubernetes can't find it

Locally-built images live in Docker Engine on your host. The
Kubernetes node is a container running its own containerd, which
doesn't see the host's images. Build with Docker, then load the
image into the profile:

```bash
docker build -f Containerfile -t myimage:v1 .
minikube -p minikube image load myimage:v1
```

Use a pinned tag (not `latest`) and `imagePullPolicy: IfNotPresent`
(or `Never`) in the Deployment so Kubernetes uses the loaded image
instead of trying a public registry. Don't run
`eval $(minikube docker-env)` with containerd: that variable points
the docker CLI at a Docker daemon inside the node, and a containerd
node doesn't run one, so builds land nowhere useful. After loading a
new image under an existing tag, `kubectl --context minikube rollout
restart deployment/[name]` makes the Pods pick it up.

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

### Q: the NodePort URL doesn't answer

This tutorial reaches every Service through a NodePort published on
`127.0.0.1` when the profile is created. Check what the node
actually publishes:

```bash
docker port minikube
```

You should see lines such as `30080/tcp -> 127.0.0.1:18080`. If
the NodePort you need isn't listed, the profile was created without
it, and published ports can't be added later. Delete and recreate the
profile with `--ports` (the commands are in §3 and §4):

```bash
minikube delete -p minikube
minikube start -p minikube --driver=docker --container-runtime=containerd \
    --kubernetes-version=v1.35.1 \
    --ports=127.0.0.1:18080:30080,127.0.0.1:18081:30808,127.0.0.1:18090:30900
```

If the port is published but still silent, the Service has no ready
endpoints: `kubectl --context minikube get endpoints [name]`. Also
confirm only one Service holds the shared NodePort 30080 (§6, §8,
§9, and §12's HTTP demo take turns; delete the previous one first).

### Q: requests through the KEDA HTTP interceptor return 404

You're probably using `hey -H 'Host: nginx.local'`. **hey is
written in Go, and Go's `net/http` silently strips Host
headers set via the headers map** (issue golang/go#7682, open
since 2014). Use `hey -host nginx.local` instead — hey has a
dedicated flag for this. curl handles `-H 'Host:'` correctly
because curl treats Host as a special case; many other tools
do not.

### Q: I can't reach the cluster from another machine on my LAN

By default every published port binds to `127.0.0.1`, so only the
host itself can reach it. When the host is a VM (or you need
another machine to reach a demo), publish on the VM's own address
at profile creation: in the `--ports` map, replace `127.0.0.1` with the
VM's address (for example `192.168.122.50:18080:30080`), using the address of the
interface the other machine can reach. Ports are fixed at creation, so this means
recreating the profile. If the host runs firewalld, also allow the
port (`sudo firewall-cmd --add-port=18080/tcp`, then add
`--permanent` once it works). Publish only the Services you intend
to share: the dashboard, Kiali, and Grafana should stay on
`127.0.0.1`.

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
`istio` profiles. The repo's scripts and chapters pass
`--context` on every command, and you can do the same:

```bash
kubectl --context minikube get pods
kubectl --context istio get pods

# Or switch the default and check it at a glance
kubectl config use-context istio
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

Always name the profile. Profile names must be unique per host; if
another project already uses a name, pick a different one for this
tutorial (the capstone uses `mof-capstone` for that reason).

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
# Unused Docker images (host)
docker image prune -a

# Containerd images inside the running minikube
minikube -p minikube ssh -- sudo crictl rmi --prune

# Whole profiles you no longer need
minikube delete -p istio
```

The minikube image cache inside the profile is the most common
culprit — `nginx-custom`, `order-processor`, and the Kafka /
Istio images all accumulate. The `crictl rmi --prune` is safe;
it removes images that aren't currently in use by any Pod.

> **Do not run `docker system prune --volumes`.** A stopped minikube
> profile is a stopped container plus a Docker volume that holds its
> state. The prune treats both as unused and deletes them, taking the
> cluster with them. `docker image prune` is safe because it only
> touches images.

### Q: I want to upgrade kubectl/helm/minikube

```bash
# kubectl
sudo dnf upgrade -y kubectl

# helm
sudo dnf upgrade -y helm
```

minikube is pinned on purpose: the chapters, the port maps, and the
flag set are tested against v1.38.1, installed from the release RPM
in §2. Upgrading it is a deliberate change, not a routine update.
To move, install the newer RPM the same way as §2 and re-run the
demos before relying on it.

After upgrading minikube, existing profiles continue working
on the old Kubernetes version. The tutorial pins
`--kubernetes-version=v1.35.1`; a different version means a new
profile.

### Q: pods or VMs lose network after Docker starts (iptables FORWARD DROP)

Docker Engine's daemon sets the host `iptables` FORWARD policy to
DROP and manages its own chains. On a host that also runs libvirt
VMs, traffic to and from the VM bridge can stop flowing once
`dockerd` starts. Check:

```bash
sudo iptables -S FORWARD | head -1      # -P FORWARD DROP
sudo iptables -S DOCKER-USER
```

If the libvirt bridge (`virbr0`) is affected, accept its traffic in
the `DOCKER-USER` chain, which Docker leaves alone:

```bash
sudo iptables -I DOCKER-USER -i virbr0 -j ACCEPT
sudo iptables -I DOCKER-USER -o virbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Those rules last until reboot; persist them through your firewall
tooling once they work. This is a host-level interaction between two
packet filters rather than a minikube fault, so verify it on your
own machine before relying on it.

<!-- policy-exempt:start -->
### Q: Why did this tutorial move off rootless podman?

An earlier revision ran minikube on rootless Podman. It worked, but
the node had no host-routable address, which forced tunnels and
port-forwards for every demo, and the pairing rules for runtime,
storage, and image loading kept producing failures that had nothing
to do with Kubernetes. Docker Engine with `--ports` published at
creation removes those workarounds. The symptom-by-symptom record is
[LESSONS-LEARNED, Part 4](https://github.com/patterncatalyst/minikube-on-fedora/blob/main/onboarding/LESSONS-LEARNED.md).
<!-- policy-exempt:end -->

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
minikube delete -p minikube            # repeat for -p istio and any other tutorial profile
rm -rf ~/.minikube ~/.kube             # config and state (affects every minikube profile)
docker image prune -a                  # host-cached container images
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
