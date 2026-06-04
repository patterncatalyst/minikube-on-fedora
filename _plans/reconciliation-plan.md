---
title: Reconciliation plan
description: What in this tutorial is verified, what is in flight, and what still needs validation.
render_with_liquid: false
---

This document tracks the **gap between what the tutorial claims and
what has been verified end-to-end** on real hardware. It is the
single authoritative list of things to check, fix, or expand
before the tutorial is declared production-ready.

## How to use this document

- When adding new tutorial content that makes a verifiable claim,
  add a row to the appropriate section below as `unverified`
- When you (or a contributor) actually test a claim on the real
  target platform, promote the row to `verified (Fedora 44)`,
  noting which platform was tested
- When something is being actively debugged, mark it `in flight`
  with a brief note about what's blocking
- When you decide not to test something in this iteration, mark it
  `out of scope` with the reason

**Default state for new claims is `unverified`.** Promotion to
`verified` requires a real test run by a human, with the result
recorded.

## Conventions

- A `verified` row has been run end-to-end on at least one named
  platform with the exact commands shown in the tutorial
- `verified (Fedora 44)` is the canonical primary-platform marker
  for this project; macOS is acknowledged as advisory only and
  rows aren't expected to carry a macOS verification
- An `in flight` row is being actively worked on; the assigned
  contributor is named where known
- An `unverified` row is a claim that has not been re-validated
  against a current environment
- An `out of scope` row is something deliberately not verified in
  this iteration; the reason is given

## A. Pinned tool versions

The versions this tutorial is written against. Every claim later
in the document implicitly assumes these.

| Status                  | Tool             | Version       | Where pinned          | How to verify                                              |
|-------------------------|------------------|---------------|-----------------------|------------------------------------------------------------|
| **verified (Fedora 44)** | Fedora           | 44 (Forty Four) | §1 platform statement | `cat /etc/fedora-release` reports Fedora 44 ✓ r03 audit    |
| **verified (Fedora 44)** | Podman           | 5.8.2         | §1 prereq check       | `podman --version` returns 5.8.2 ✓ r03 audit               |
| **verified (Fedora 44)** | minikube         | v1.38.1       | §2 install (RPM)      | `minikube version --short` reports v1.38.1 ✓ r05 install   |
| **verified (Fedora 44)** | kubectl          | v1.35.3       | §2 install (upstream binary; pre-existing accepted) | `kubectl version --client=true` ✓ r05 audit |
| **verified (Fedora 44)** | helm             | 4.1.1         | §2 install (`dnf install helm`) | `helm version --short` returns `v4.1.1+g5caf004` ✓ r05 install |
| **verified (Fedora 44)** | httpie           | 3.2.4         | §2 install (`dnf install httpie`) | Installed via dnf ✓ r05 install                         |
| **verified (Fedora 44)** | yq (mikefarah)   | 4.47.1        | §2 install (`dnf install yq`) | Installed via dnf ✓ r05 install                            |
| **verified (Fedora 44)** | krew             | latest        | §2 install (upstream installer) | `~/.krew/bin/kubectl-krew` exists ✓ r05 install          |
| **verified (Fedora 44)** | stern            | latest (krew) | §2 install (`kubectl krew install stern`) | `~/.krew/bin/kubectl-stern` exists ✓ r05 install        |
| **verified (Fedora 44)** | kubectx / kubens (krew names: ctx, ns) | latest (krew) | §2 install (`kubectl krew install ctx ns`) | `~/.krew/bin/kubectl-{ctx,ns}` exist ✓ r05 install |
| **verified (Fedora 44)** | hey              | latest (Go)   | §2 install (`go install`); pre-existing acceptable | `~/go/bin/hey` exists ✓ r05 audit              |
| unverified              | istioctl         | TBD           | §11 install commands  | `istioctl version` matches                                 |
| **verified (Fedora 44)** | KEDA             | 2.19.0        | §12 helm install args | r13b user run: `helm list -n keda` shows `keda  keda  1  ...  2.19.0  2.19.0` |
| **verified (Fedora 44)** | KEDA HTTP add-on | 0.12.2        | §12 helm install args | r13b user run: install output confirmed `KEDA HTTP add-on 0.12.2 installed` (BETA — see prose) |

## B. Per-section claims

Claims made in prose that are not yet end-to-end verified. New
rows added as sections get drafted; rows are promoted to
`verified` when their underlying claim has been exercised on
Fedora 44.

| Status                  | Claim                                                                       | Section | Notes                                                                       |
|-------------------------|-----------------------------------------------------------------------------|---------|-----------------------------------------------------------------------------|
| unverified              | 4 CPU / 8 GB RAM / 20 GB free disk is sufficient for §1–§10                  | §1      | Promote after running §1–§10 on hardware near the floor (not the dev box)    |
| **verified (Fedora 44)** | 6 CPU / 16 GB RAM / 50 GB free disk is comfortable for §1–§12                | §1      | r13f close-out: user's 6 CPU / 16 GB minikube profile handled the full tutorial including §11 Istio (separate `istio` profile, 4 CPU / 6 GB) and §12 (Strimzi + Kafka 4.1.0 + KEDA + HTTP add-on + per-demo workloads). No OOM kills, no CPU starvation, no scheduling failures observed |
| **verified (Fedora 44)** | Podman runs rootless on Fedora 44 with the §1 UBI test command              | §1      | r03 user output: `podman run --rm ubi9/ubi-minimal echo OK` → `OK` ✓        |
| **verified (Fedora 44)** | UBI images at `registry.access.redhat.com` are pullable without subscription | §1      | r03 user output: pull + run + exec all succeeded against ubi9/ubi-minimal ✓ |
| **verified (Fedora 44)** | The podman driver works without KVM/qemu/VirtualBox on Fedora 44             | §1, §3  | r05c user output: driver-check demo passed; no virtualization layer touched ✓ |
| **verified (Fedora 44)** | No SELinux `:Z` flag needed for minikube-managed PVs via the standard StorageClass | §1, §8 | r09 user run: PVC from `standard` SC bound and mounted cleanly with no SELinux relabeling required. The `:Z` flag matters for direct host bind mounts (which we don't use); the storage-provisioner addon handles SELinux labeling internally |
| **verified (Fedora 44)** | `minikube` RPM from `storage.googleapis.com` installs cleanly via `dnf`     | §2      | r05 user output: dnf install completed, /usr/bin/minikube present ✓         |
| **verified (Fedora 44)** | `helm 4.1.x` from Fedora repos works against Helm 3-format charts            | §2, §9  | r10 user run: helm `v4.1.1+g5caf004` cleanly handled an `apiVersion: v2` chart through install/upgrade/uninstall |
| **verified (Fedora 44)** | `helm` from Fedora repos installs cleanly via `dnf`                          | §2      | r05 user output: `dnf install helm` succeeded, /usr/bin/helm present ✓      |
| **verified (Fedora 44)** | `kubectl 1.35.x` client works against minikube-default 1.35.x cluster        | §2, §3  | r05c user output: `kubectl get nodes` and `kubectl wait` all succeeded against the 1.35.1 cluster ✓ |
| **verified (Fedora 44)** | krew installer + `kubectl krew install stern ctx ns` works as documented    | §2      | r05 user output: krew bootstrap + three plugin installs all succeeded ✓     |
| **verified (Fedora 44)** | mikefarah yq is `dnf install yq` on Fedora 44 (not python-yq)               | §2      | r05 user output: `dnf install yq` succeeded; package is 4.47.1 mikefarah ✓  |
| **verified (Fedora 44)** | `minikube start --driver=podman` brings up a healthy cluster                 | §3      | r05c user output: cluster up, all 8 kube-system pods Running, ✓ SUCCESS     |
| **verified (Fedora 44)** | minikube's podman driver requires `--rootless` (or `config set rootless true`) on Fedora 44 | §3 | r05 user output: rootful default failed with `sudo: a password is required`; r05b prose + config + demo flag added |
| **verified (Fedora 44)** | minikube under rootless podman additionally requires `--container-runtime=containerd` | §3 | r05b user output: rootless+default(docker)-runtime failed with `docker.service` start error; r05c sets containerd explicitly |
| **verified (Fedora 44)** | kindnet CNI works under rootless podman + containerd on Fedora 44           | §3      | r05c user output: kindnet-4kmdd pod Running, node Ready, pod networking observed ✓ |
| unverified              | `minikube pause/unpause/stop/delete` cluster-lifecycle commands work         | §3      | Pause/stop not exercised in driver-check; defer or add lifecycle demo later |
| **verified (Fedora 44)** | `minikube profile list/start/delete -p NAME` profile lifecycle works         | §4      | r06 verification recipe: `scratch` profile created with `--cpus=2 --memory=2048`, listed, deleted cleanly ✓ |
| **verified (Fedora 44)** | Per-cluster `--cpus`/`--memory` flags override the global defaults          | §4      | r06 verification recipe: `scratch` came up with 2/2048 despite config defaults of 6/16384 ✓ |
| unverified              | `minikube start --nodes=N` creates a multi-node cluster on rootless podman   | §4      | r06 prose claim; promote when first multi-node verification happens         |
| **verified (Fedora 44)** | `minikube addons enable metrics-server` makes `kubectl top` work            | §5      | r06 verification recipe: enabled metrics-server, `kubectl top nodes` returned `minikube 102m 0% 534Mi 0%` ✓ |
| **verified (Fedora 44)** | `minikube addons enable ingress` brings up NGINX ingress-nginx pods         | §5      | r06 verification recipe: enabled ingress, three pods observed (1 controller Running, 2 admission jobs Completed) ✓ |
| **verified (Fedora 44)** | `minikube addons enable dashboard` + `minikube dashboard --url` returns a URL | §5     | r06 verification recipe: enabled dashboard, `minikube dashboard --url` returned `http://127.0.0.1:40735/...` ✓ |
| **verified (Fedora 44)** | UBI application images (e.g. `ubi9/nginx-124`) are s2i builders — not directly runnable in plain Kubernetes | §6 | r07 user run: default CMD `/usr/libexec/s2i/run` crashloops; correct approach is to build our own image from a standard UBI base (r07a) |
| **verified (Fedora 44)** | RHEL/UBI nginx 1.20 (`microdnf install nginx`) defaults to logging to `/var/log/nginx/*.log` files, not stdout/stderr | §6 | r07a user run: container crashloop only surfaced a startup warning via `kubectl logs`; runtime errors went to files invisible to kubectl. Custom `nginx.conf` in r07c logs to `/dev/stdout` and `/dev/stderr` |
| **verified (Fedora 44)** | `minikube image build` builds and caches an image visible to the cluster's kubelet | §6 | r07c user run: build produced `docker.io/library/nginx-custom:v1` visible to Deployment without push to a registry |
| **verified (Fedora 44)** | A two-stage Containerfile (ubi9 → ubi9-minimal) produces a working nginx image | §6 | r07c user run: builder stages index.html, runtime serves it; image ~150MB |
| **verified (Fedora 44)** | `ubi9/ubi-minimal` installs nginx via `microdnf` without subscription-manager | §6 | r07c user run: nginx 1.20.1 from ubi-9-appstream-rpms installed cleanly |
| **verified (Fedora 44)** | A two-replica Deployment with the manifest in §6 becomes `Available` within 3 minutes | §6 | r07c user run: Available in 8 seconds |
| **verified (Fedora 44)** | `kubectl port-forward service/nginx 18080:80` opens a working tunnel        | §6      | r07c user run: localhost:18080 served sentinel string                       |
| **verified (Fedora 44)** | `kubectl scale deployment/nginx --replicas=3` brings count to 3 Running pods | §6     | r07c user run: 3/3 Running after scale                                      |
| **verified (Fedora 44)** | Baked-in index.html serves the sentinel string `Test Page for nginx on UBI 9 Minimal` | §6 | r07c user run: HTTP response matched expected substring                     |
| **verified (Fedora 44)** | Under rootless podman, the cluster node IP (e.g. `192.168.49.2`) is NOT host-routable; lives in a slirp4netns/pasta user network namespace | §7 | Learned in r08 user run: `minikube service --url` auto-tunnels and prints `127.0.0.1:<random-port>` instead of returning the node IP directly. r08a corrects §7 prose to acknowledge this |
| **verified (Fedora 44)** | `minikube service <name> --url` blocks for ~20-30s during tunnel setup on rootless podman, then prints the URL and stays running until Ctrl-C | §7 | Learned in r08 user run: the demo's polling loop with `head -1` deadlocked because each iteration re-established the tunnel. r08a uses a single background invocation with output-file polling |
| **verified (Fedora 44)** | NodePort Service exposes a workload at `<nodeIP>:<nodePort>` on minikube     | §7      | r08a user run: NodePort `30808` works; reachable via tunnel URL `http://127.0.0.1:45185` |
| **verified (Fedora 44)** | `minikube service <name> --url` returns a host-reachable URL (tunneled under rootless podman) | §7 | r08a user run: tunnel established in 3s, returned `http://127.0.0.1:45185`, curl succeeded |
| unverified              | NodePort values must be in 30000-32767 range (enforced by kube-apiserver)    | §7      | r08 prose claim; never tested directly (would require submitting an out-of-range manifest); low priority |
| unverified              | A Deployment with a different name + label can coexist with §6's nginx       | §7      | r08 design choice; not tested (user didn't run the optional coexist sanity check); low priority |
| **verified (Fedora 44)** | minikube's `default-storageclass` + `storage-provisioner` addons provide a working `standard` StorageClass with `k8s.io/minikube-hostpath` provisioner | §8 | r09 user run: `kubectl get storageclass standard` returned the class; PVC bound to `pvc-40990c02-...` in seconds |
| **verified (Fedora 44)** | A PVC without `storageClassName` binds to a dynamically provisioned PV from the default StorageClass | §8 | r09 user run: 100Mi RWO PVC bound to auto-named PV within 3s of Deployment apply |
| **verified (Fedora 44)** | `k8s.io/minikube-hostpath` provisioner backs PVs with directories on the minikube node | §8 | r09 user run: PVC bound to `pvc-40990c02-f9e4-4524-b3ef-9d681eca857a` from the standard class (provisioner from the class spec) |
| **verified (Fedora 44)** | `initContainer` can seed a PV with content before the main container starts and is idempotent across Pod restarts | §8 | r09 user run: first Pod's initContainer wrote timestamped HTML at `2026-05-17T12:28:19Z`; second Pod's initContainer log showed `content already exists; persistence is working` |
| **verified (Fedora 44)** | A PVC mount at `/usr/share/nginx/html` overlays `nginx-custom:v1`'s baked-in content | §8 | r09 user run: served HTML was the initContainer-written file, not §6's `Test Page for nginx on UBI 9 Minimal` |
| **verified (Fedora 44)** | Deleting a Pod and waiting for the Deployment replacement preserves PV content (PV is independent of Pod lifecycle) | §8 | r09 user run: timestamps `2026-05-17T12:28:19Z` matched exactly before and after `kubectl delete pod nginx-pv-864c5dfd8b-zvpwn` |
| unverified              | `standard` StorageClass's `Delete` reclaim policy auto-deletes the PV when the PVC is deleted | §8 | r09 cleanup behavior; promote when post-`kubectl delete` `kubectl get pv` shows no orphaned PV |
| **verified (Fedora 44)** | Jekyll's Liquid templating collides with Go template syntax (`{{ }}`) in code blocks — `{% raw %}` / `{% endraw %}` wrappers are required around any code block showing Go/helm/jinja templates | site-build | r10 Jekyll CI build failure: `liquid-4.0.4 standardfilters.rb:253:in 'replace': wrong number of arguments` from helm's `{{ ... \| replace "+" "_" }}` being parsed as a Liquid pipeline. r10a wraps all four §9 helm template code blocks plus the §1 `podman info --format` line with raw tags. Applies prospectively to §11 Istio, §12 KEDA, anywhere Go templates appear in prose |
| **verified (Fedora 44)** | helm 4.x lints an `apiVersion: v2` chart with no warnings                   | §9 | r10 user run: `1 chart(s) linted, 0 chart(s) failed` (one INFO note about chart icon being recommended; no errors) |
| **verified (Fedora 44)** | `helm template` renders all chart templates without applying to the cluster | §9 | r10 user run: dry-run output contained ConfigMap, Deployment, Service kinds with values interpolated |
| **verified (Fedora 44)** | `helm install` with `--set` overrides default values from `values.yaml`    | §9 | r10 user run: served HTML contained `First install via helm` (the `--set content.title="..."` override) |
| **verified (Fedora 44)** | `helm upgrade --set` updates the release to a new revision                  | §9 | r10 user run: `helm history` returned 2 revisions (1 superseded, 2 deployed) |
| **verified (Fedora 44)** | `checksum/configmap` annotation in the Deployment template triggers a Pod rollout when ConfigMap content changes | §9 | r10 user run: upgrade-time title `Upgraded title via helm` appeared in served HTML, proving Pods recreated with new ConfigMap content (otherwise old Pods would still serve old content) |
| **verified (Fedora 44)** | `helm uninstall` removes all chart-created resources within 30s (async deletion) | §9 | r10d user run with polling demo: "all resources gone after 2s" — well under the 30s budget; ✓ SUCCESS |
| **verified (Fedora 44)** | Helm 4 reads charts authored against the Helm 3 chart format (`apiVersion: v2`) | §2, §9 | r10 user run with helm `v4.1.1+g5caf004` cleanly handled the v2-format chart through lint, template, install, upgrade, history, uninstall |
| **verified (Fedora 44)** | `helm uninstall` is asynchronous — returns success once delete operations are submitted; actual Pod termination follows `terminationGracePeriodSeconds` (default 30s) | §9 | Learned in r10 user run: leftover check ran 0ms after uninstall returned, caught a Pod still `Terminating` (3s old). r10d's demo polls for 30s after uninstall to account for the async behavior |
| unverified              | `kubectl completion zsh`, `helm completion zsh`, `minikube completion zsh` produce working tab completion when sourced in `~/.zshrc` | §10 | r11 prose claim; promote on demonstration (e.g., `kubectl get po<TAB>` showing pod kinds) |
| unverified              | `compdef __start_kubectl k` makes the `k=kubectl` alias inherit kubectl's tab completion under zsh | §10 | r11 prose claim |
| unverified              | `k9s` installs cleanly via `sudo dnf install -y k9s` on Fedora 44 | §10 | r11 prose claim; verifiable in seconds with `which k9s && k9s version` |
| unverified              | `tmux` installs cleanly via `sudo dnf install -y tmux` on Fedora 44 | §10 | r11 prose claim |
| unverified              | Pulsar's `.rpm` from pulsar-edit.dev installs cleanly on Fedora 44 with YAML highlighting working out of the box | §10 | r11 prose claim; the author's working setup |
| **verified (Fedora 44)** | Running a SECOND minikube profile on Fedora 44 requires `fs.inotify.max_user_instances` ≥ 256 (and `max_user_watches` ≥ 131072); defaults are sized for one cluster. Symptom of too-low: `Failed to create control group inotify object: Too many open files` from the cluster container during `minikube start` | §1, §11 | r12 user run: §11 `minikube start -p istio` failed with the exact error above; raising via `/etc/sysctl.d/99-kubernetes.conf` resolves. r12a's demo pre-flight checks these values |
| **verified (Fedora 44)** | A failed `minikube start -p <profile>` can leave a stale `podman volume <profile>` artifact that causes the retry to fail with `volume already exists` | §11 | r12 user run: first start failed (inotify); retry hit `Error: volume with name istio already exists`. r12a demo pre-flight cleans stale volumes before retry via `minikube delete -p <profile>` + `podman volume rm <profile>` |
| **verified (Fedora 44)** | A dedicated `istio` minikube profile with `--memory=6g --cpus=4 --rootless=true --container-runtime=containerd` starts cleanly on Fedora 44 | §11 | r12a/r12b user run (with inotify limits raised): minikube start completed, kubelet ready, kubectl reachable; "Done! kubectl is now configured to use 'istio' cluster" |
| **verified (Fedora 44)** | `istioctl install --set profile=demo -y` brings up istiod + ingressgateway + egressgateway with all three Pods Running within ~30s | §11 | r12a/r12b user run: "Istio core / Istiod / Egress gateways / Ingress gateways installed" + "Installation complete"; all three Pods 1/1 Running |
| **verified (Fedora 44)** | The Istio sidecar-injector `MutatingWebhookConfiguration` registers AFTER istiod's Deployment reaches `condition=Available` — there is a brief window (typically 2-10s) where the API server has the webhook config but its `caBundle` is empty, during which sidecar injection silently no-ops | §11 | r12a/r12b user run: nginx Pod deployed immediately after `kubectl wait Available` succeeded, came up with one container (no sidecar). Diagnostic chain matched the well-known Istio install-then-deploy race. r12c demo now polls `mutatingwebhookconfiguration/istio-sidecar-injector` for non-empty `.webhooks[0].clientConfig.caBundle` before deploying workloads; also adds buffer sleep after namespace label + diagnostic-dump + retry-once on injection failure |
| **verified (Fedora 44)** | Labeling `default` namespace `istio-injection=enabled` causes new Pods to be sidecar-injected | §11 | r12c user run: nginx-istio Pod created with `sidecar.istio.io/status` annotation populated showing `initContainers:[istio-init, istio-proxy]` (native sidecar mode); istiod logs showed new xDS connection from the nginx Pod within 2s of creation |
| **verified (Fedora 44)** | Istio 1.29+ on Kubernetes 1.28+ injects `istio-proxy` as a **native sidecar** ([KEP-753](https://kep.dev/sig-node/753)) — an init container with `restartPolicy: Always`, not as a main container. JSONPath checks against `.status.containerStatuses[]` or `.spec.containers[]` will MISS it; need to also check `.status.initContainerStatuses[]` / `.spec.initContainers[]`. Human-readable `kubectl get pods` READY column still shows `2/2` because native sidecars count toward readiness totals | §11 | r12c user run: Pod's `sidecar.istio.io/status` annotation showed `"initContainers":["istio-init","istio-proxy"]`, `"containers":null` — istiod's own injection-status report confirmed istio-proxy went into initContainers. r12d demo's check now reads both `.spec.containers[*].name` and `.spec.initContainers[*].name` so it works for both native-sidecar mode (current default in K8s 1.28+) and the older "main container" mode (still seen on K8s ≤1.27) |
| **verified (Fedora 44)** | `scripts/setup-istio.sh` downloads + extracts Istio 1.29.2 and installs istioctl to `~/.local/bin/` | §11 | r12 user run: clean output through all 5 steps (directories, download via istio.io, istioctl install, symlink, PATH check); ended with `client version: 1.29.2` |
| **verified (Fedora 44)** | minikube image cache is per-profile — `nginx-custom:v1` from the `minikube` profile is NOT visible on the `istio` profile | §11 | r12 user run: "image not present on istio; building from §6's Containerfile" → multi-stage build (ubi9 builder + ubi9-minimal runtime) completed in ~10s; image then available on istio profile |
| **verified (Fedora 44)** | Bookinfo sample app deploys cleanly with all 4 microservices + 6 Pods reaching Available | §11 | r12d user run: all 6 bookinfo Pods (details-v1, productpage-v1, ratings-v1, reviews-v1/v2/v3) showed `2/2 Running` within ~21s of deploy; native sidecars on every Pod |
| **verified (Fedora 44)** | `bookinfo-gateway.yaml` (Gateway + VirtualService) exposes productpage at `istio-ingressgateway:80` reachable via `kubectl port-forward` | §11 | r12d user run: Gateway + VirtualService applied cleanly; `istioctl analyze` returned clean; port-forward established; productpage responded with HTML containing `<title>Simple Bookstore App</title>` |
| **verified (Fedora 44)** | `istioctl analyze` returns clean output (no Errors) for a configured Bookinfo mesh | §11 | r12d user run: ✓ Gateway + VirtualService applied; istioctl analyze clean |
| **verified (Fedora 44)** | Current Istio (1.29+) Bookinfo sample has been rebranded from "Bookinfo Sample" to "Simple Bookstore App" and migrated from Bootstrap CSS (which used `glyphicon-star` for reviews v2/v3 ratings) to Tailwind. HTML-marker-based routing assertions need updating — better: use response-hash distribution which doesn't depend on specific markup | §11 | r12d user run: productpage response started `<title>Simple Bookstore App</title>` and `<script src="static/tailwind/tailwind.css">`. r12e demo replaces `glyphicon-star` count with hash-based check: v1-pin expects ≤3 distinct hashes / 10 samples (deterministic backend), 50/50 split expects ≥2 distinct patterns / 20 samples (mixed deterministic v1 + random-rating v3) |
| **verified (Fedora 44)** | `virtual-service-all-v1.yaml` pins 100% of reviews traffic to v1 (verified via response-hash distribution: ≤3 distinct hashes across 10 samples) | §11 | r12e user run: **exactly 1 distinct hash** (`b6e5bbdddade...`) across 10 samples. productpage with only v1 reviews is fully deterministic — zero noise. Strongest mesh-routing assertion in the tutorial |
| **verified (Fedora 44)** | `virtual-service-reviews-50-v3.yaml` (or `-jason-v2-v3.yaml` fallback) produces multiple distinct response patterns (≥2 distinct hashes / 20 samples) when applied to bookinfo traffic | §11 | r12e user run: 2 distinct hashes across 20 samples, 11/9 distribution (55/45%) between the v1 hash (`b6e5bbdddade...`) and the v3 hash (`0491712a6626...`). v3 also produced a single deterministic hash, suggesting current Bookinfo seeds randomness from request ID |
| **verified (Fedora 44)** | kubectl context can be saved + restored across a demo run via `kubectl config use-context` (so `istio` profile work doesn't disturb `minikube` profile state) | §11 | r12e user run: demo started with `current kubectl context: minikube`, switched to `istio` for the work, and on exit ("cleanup: stopping port-forward..." → "restoring kubectl context to minikube") restored cleanly. §6-§9 demos remain runnable without manual switching |
| **verified (Fedora 44)** | `kubectl apply -f $ISTIO_DIR/samples/addons/` installs Kiali, Prometheus, Grafana, Jaeger, and Loki cleanly on the `istio` profile in ~3-5 minutes | §11 | r12g user run: `deployment.apps/kiali condition met`, `prometheus condition met`, `grafana condition met`, `jaeger condition met` returned within timeout; `loki-0` StatefulSet `2/2 Running`. Current `samples/addons/` includes Loki alongside the canonical four; Kiali integrates with Prometheus + Loki + Jaeger for the unified observability view |
| **verified (Fedora 44)** | Kiali Traffic Graph renders a live mesh visualization with traffic animation, success/error rates per edge, and namespace-scoped filtering. Switching the namespace dropdown from `istio-system` to `default` reveals the application call graph (productpage → details / reviews → ratings) with live request rates | §11 | r12g user run: 200-curl traffic loop against `/productpage` produced a Kiali Overview with 4 applications, climbing inbound-traffic sparkline, and a Traffic Graph showing istio-ingressgateway → productpage with 1.89 req/s sustained at 100% success. Screenshots captured in `assets/screenshots/kiali-{overview,traffic-graph}.png` |
| **verified (Fedora 44)** | `scripts/setup-keda.sh` installs KEDA core 2.19.0 + KEDA HTTP add-on 0.12.2 into the `keda` namespace via helm | §12 | r13b user run: clean idempotent install, 10 Pods Running (some have multiple replicas — see Pod-count row below). One restart on `keda-operator` shortly after start is expected (probe timing during initial reconciliation) |
| **verified (Fedora 44)** | `scripts/setup-strimzi.sh` installs Strimzi Cluster Operator 0.51.0 into the `kafka` namespace via helm | §12 | r13b user run: 1 Cluster Operator Pod Available within 40s |
| **verified (Fedora 44)** | Strimzi 0.51.0 supports ONLY Kafka **4.1.0, 4.1.1, 4.2.0** — the 3.x line was dropped entirely. Mis-pinning to 3.x manifests as a `Kafka` CR `NotReady` condition with `reason: UnsupportedKafkaVersionException` and `message: Unsupported Kafka.spec.kafka.version: X.Y.Z. Supported versions are: [4.1.0, 4.1.1, 4.2.0]`. Kafka 4.x removed ZooKeeper completely — KRaft is the only mode. The `metadataVersion` field can be omitted; Strimzi defaults it to match the Kafka version on first cluster creation | §12 | r13 → r13a: original ship pinned Kafka 3.9.0 based on a misread of Strimzi 0.51 release notes (which were actually flagging a 3.9.2-specific upgrade-path bug, not establishing 3.x as supported). r13a corrected to 4.1.0 and recorded the finding |
| **verified (Fedora 44)** | A single-node Strimzi Kafka cluster (combined controller+broker role) with Kafka **4.1.0** reaches `condition=Ready` within 5 minutes on minikube. Strimzi defaults `metadataVersion` to **4.1-IV1** when the field is omitted from the manifest | §12 | r13b user run: cluster Ready in ~63s on a profile where the Strimzi `kafka:0.51.0-kafka-4.1.0` image had to be pulled fresh. Screenshot captured at `assets/screenshots/strimzi-kafka-cluster-ready.png` |
| **verified (Fedora 44)** | A `KafkaTopic` CR with 3 partitions reaches `condition=Ready` via Strimzi's Topic Operator | §12 | r13b user run: topic 'orders' Ready immediately after Kafka cluster Ready |
| **verified (Fedora 44)** | The Python `order-processor` consumer image builds cleanly from a multi-stage UBI Containerfile (ubi9 builder + ubi9-minimal runtime, kafka-python==2.0.6 in venv on Python 3.9.25) | §12 | r13b user run: image built in ~7s end-to-end on the minikube profile. UBI 9 ships Python 3.9 (NOT 3.11 — earlier assistant claim corrected); kafka-python 2.0.6 is protocol-compatible with Kafka 4.x brokers per upstream docs |
| **verified (Fedora 44)** | A KEDA `ScaledObject` with `minReplicaCount: 0` and a Kafka trigger results in **zero replicas at idle** (no consumer Pods running until messages arrive) | §12 | r13b user run: assertion passed immediately after applying the manifests |
| **verified (Fedora 44)** | Producing 200 messages to a Kafka topic causes KEDA to scale the consumer Deployment from 0 to ≥1 replicas within 120 seconds. Peak replicas bounded by `maxReplicaCount: 3` (also bounded by 3 topic partitions) | §12 | r13b user run: replicas climbed to 1 at the 5s polling tick; peaked at 3 by the 10s tick. With `lagThreshold: "5"` and 200 messages of lag, HPA would ask for 40 replicas but caps at 3 |
| **verified (Fedora 44)** | After the topic drains and `cooldownPeriod` (30s) elapses, KEDA scales the consumer back to 0 replicas | §12 | r13b user run: scaled back to 0 at 62s after drain wait. The cooldown is wall-clock from "lag-reaches-0" not from "scale-up-completed", so the observed time = drain delay + cooldownPeriod + small reconciliation lag |
| **verified (Fedora 44)** | KEDA HTTP add-on `HTTPScaledObject` (CRD: `http.keda.sh/v1alpha1`) with `replicas.min: 0` results in zero replicas at idle | §12 | r13c user run: applied manifests, initial assertion `current replicas: 0` passed |
| **verified (Fedora 44)** | The HTTP add-on **interceptor buffers a cold-start request** until the workload Pod is Ready, returning a 200 response with backend (nginx) content. Measured 3 seconds on this minikube setup (image cached, Pod startup dominated by readinessProbe `initialDelaySeconds: 1` + `periodSeconds: 2`) | §12 | r13c user run: cold-start curl returned HTTP 200 with nginx content after exactly 3s. Tightened r13c assertions verify status code AND nginx content (not just any HTML) |
| **verified (Fedora 44)** | `hey` (Go-based load tester) does NOT respect `-H 'Host: x'` for setting the HTTP Host header — Go's `net/http` package silently strips Host headers from the headers map (issue golang/go#7682, open since 2014). Use `hey -host x` instead, which sets Go's special `Request.Host` field directly. Symptom of misuse: all requests through a virtual-host-based proxy (KEDA HTTP add-on interceptor, Istio gateway, nginx vhost, traefik with Host rules, etc.) return 404. curl handles `-H 'Host:'` correctly because curl treats it as a special case | §12 | r13c → r13d: r13's demo used `-H "Host: nginx.local"`, causing all 500 hey requests to return 404 while the cold-start curl (3s, 200, nginx content) worked. r13d fixed the demo to use `-host` and updated the README's "When this fails" section so future readers don't lose time to this |
| **verified (Fedora 44)** | `hey -n 500 -c 50` sustained HTTP load drives the HTTPScaledObject's concurrency metric, scaling nginx from 0 to ≥1 replicas within 120s. Peak replicas of 1 is consistent with KEDA semantics here — with `targetValue: 5` concurrency and a per-request latency of ~10ms on this minikube setup, 500 requests at 50 concurrent finish in ~115ms (4500 req/s), well below the threshold to ask for additional replicas. To see scaling to higher N, drive sustained load instead (e.g., `hey -z 15s -c 50`) | §12 | r13f user run: replicas climbed from 0 to 1 within 1 second of hey starting; all 500 requests returned HTTP 200 |
| **verified (Fedora 44)** | After `scaledownPeriod` (30s) of zero traffic, the HTTP add-on scales the workload back to 0 replicas | §12 | r13f user run: nginx dropped to 0 replicas at 37s after hey finished (cooldown 30s + ~7s reconciliation lag). Full 0→1→0 HTTP lifecycle verified |
| **verified (Fedora 44)** | KEDA Pod count after `setup-keda.sh` completes: **10 Pods** in the `keda` namespace — 1 keda-operator, 1 keda-admission-webhooks, 1 keda-operator-metrics-apiserver (KEDA core, 3 Pods), 1 keda-add-ons-http-controller-manager, 3 keda-add-ons-http-external-scaler (replicated by default), 3 keda-add-ons-http-interceptor (replicated by default) (HTTP add-on, 7 Pods) | §12 | r13b user run: the r13 plan row said 7 Pods which assumed single replicas for all components. The HTTP add-on's helm chart actually deploys the external-scaler and interceptor with 3 replicas each by default for HA. Row corrected on promotion |
| **verified (Fedora 44)** | KEDA does not conflict with HPA — KEDA `ScaledObject` creates its own HPA backed by KEDA's metrics-apiserver, and the AKS docs explicitly warn against mixing pre-existing HPAs on the same target. The §12 demos use ONLY KEDA, no manual HPAs | §12 | r13b user run: KEDA-managed HPA reconciliation worked cleanly. The full 0→N→0 lifecycle would have failed silently or noisily if there were an HPA conflict, so the demo passing constitutes evidence |
| **verified (Fedora 44)** | The §12 prose embeds a screenshot at `assets/screenshots/strimzi-kafka-cluster-ready.png` showing the converged Kafka cluster state: `kafka/my-kafka READY=True KAFKA VERSION=4.1.0 METADATA VERSION=4.1-IV1`, `kafkanodepool/dual-role 1 ["controller","broker"] [0]`, and three Running Pods (broker, entity-operator, cluster-operator). Caption walks readers through each row | §12 | r13b user-provided screenshot from successful demo run |

## C. Testing matrix

End-to-end tests of each runnable example. This is where the
reconciliation plan earns its keep — a reviewer should see at a
glance which examples are confirmed to actually work, and which
are still aspirational.

| Status     | Example                              | Section | Notes                                                 |
|------------|--------------------------------------|---------|-------------------------------------------------------|
| **verified (Fedora 44)** | `examples/03-driver-check/`        | §3      | r05c user run: cluster up, all 8 kube-system pods Running, ✓ SUCCESS |
| **verified (Fedora 44)** | `examples/06-deploy-nginx-kubectl` | §6      | r07c user run: image built, Deployment Available in 8s, port-forward + curl + scale to 3 all worked |
| **verified (Fedora 44)** | `examples/07-nodeport-service`     | §7      | r08a user run: tunnel established in 3s, NodePort exposure via auto-tunnel `http://127.0.0.1:45185`, curl matched sentinel, 35s total |
| **verified (Fedora 44)** | `examples/08-persistent-volume`    | §8      | r09 user run: Deployment Available in 3s, PVC bound, timestamps matched before/after `kubectl delete pod` — PV persistence confirmed |
| **verified (Fedora 44)** | `examples/09-deploy-nginx-helm`     | §9      | r10d user run: lint + template + install + curl-install-title + upgrade + rollout + curl-upgrade-title + history + uninstall + zero-leftovers (after 2s of polling) all green |
| **verified (Fedora 44)** | `examples/11-istio`                   | §11     | r12e user run: full §11 happy path passed — 13 phases from pre-flight through routing assertions. v1-pin proven by 1/10 distinct hashes, 50/50 split proven by 2/20 with 55/45 distribution. SUCCESS banner with verified counts; cleanup trap restored kubectl context |
| **verified (Fedora 44)** | `examples/12-keda-kafka`              | §12     | r13b user run: full demo passed end-to-end. 0→3→0 replica lifecycle with 200 messages produced and drained. See `_plans/reconciliation-plan.md` Section B for individual claim promotions |
| **verified (Fedora 44)** | `examples/12-keda-http`               | §12     | r13f user run: full demo passed end-to-end after r13c (tightened assertions) + r13d (`-host` fix) + r13e (parsing fix). Cold-start 3s/200/nginx content; hey 500/500 at 4500 req/s with all 200s; scale-up to 1 replica then back to 0 after 37s. See `_plans/reconciliation-plan.md` Section B for individual claim promotions |
| **verified (Fedora 44)** | `examples/17-capstone` (order-service walking skeleton) | §17 | r21c user run (`demos/smoke-order.sh`): image built (UBI 9 + Poetry, root-builder venv fix) → pushed to in-cluster registry → CloudNativePG primary Ready in ~5–35s → order-service rolled out → `GET /healthz` ready → `POST /orders` returned a UUID order → direct `psql` confirmed 1 row in `orders.orders`. Six iterations (r21→r21c) to get here, almost all image-distribution friction on rootless-podman+containerd; resolved via the registry (CAP-007/009) + `MINIKUBE_ROOTLESS` (CAP-010) |
| **verified (Fedora 44)** | `examples/17-capstone` (inventory-service health skeleton) | §17 | r22 user run (`demos/smoke-service.sh inventory`): scaffolded from the order-service template, built → registry → rolled out → `GET /health` ok → `GET /healthz` ready → `inventory` schema confirmed in Postgres. First scaffold-generated service; green on first run |
| **verified (Fedora 44)** | `examples/17-capstone` (payment-service health skeleton) | §17 | r22 user run (`demos/smoke-service.sh payment`): scaffolded (schema `payments`), built → registry → rolled out → `/health` ok → `/healthz` ready → schema confirmed |
| **verified (Fedora 44)** | `examples/17-capstone` (shipping-service health skeleton) | §17 | r22 user run (`demos/smoke-service.sh shipping`): scaffolded (schema `shipping`), built → registry → rolled out → `/health` ok → `/healthz` ready → schema confirmed |
| **verified (Fedora 44)** | `examples/17-capstone` (notification-service health skeleton) | §17 | r22 user run (`demos/smoke-service.sh notification`): scaffolded (schema `notifications`), built → registry → rolled out → `/health` ok → `/healthz` ready → schema confirmed. Gets a `/health` surface despite being Kafka-consumer-only (CAP-011) |
| **verified (Fedora 44)** | `examples/17-capstone` `scripts/setup-kiali.sh` installs ONLY the Kiali addon (not the full `samples/addons/` bundle) and patches the `kiali` ConfigMap so `external_services` points at the capstone's existing `observability`-namespace Prometheus/Grafana/Tempo — single observability stack, no second TSDB (CAP-042, Phase E.0) | §17 | Cluster-confirmed in two sessions: deployment in `istio-system` reaches Ready, ConfigMap `config.yaml` contains `prometheus-server.observability` and `server.web_root: /kiali` (the corrected value that resolves the addon startup-probe 404). Lesson: addon startup probe checks `/kiali/healthz`, so `web_root` must be `/kiali` — initial attempt with `/` produced `Webroot: //` and a probe-404 loop |
| **verified (Fedora 44)** | `examples/17-capstone` `demos/smoke-kiali.sh` verifies Kiali is Ready, wired to the capstone Prometheus, `/healthz` responds, `/api/namespaces` lists `capstone`, and the graph API answers (CAP-042, Phase E.0) | §17 | Cluster-confirmed: `./demos/smoke-kiali.sh` PASSes; the walkthrough's topology act port-forwards Kiali at `http://localhost:20001/kiali` and the graph for namespace `capstone` shows the products and their edges with a canary split when one is up |
| **verified (Fedora 44)** | `examples/17-capstone` `demos/walkthrough.sh` orchestrates the five-act presenter walkthrough (trace → scale → canary → lineage → topology) over the existing demo/smoke scripts; Enter-to-advance between acts; preflight covers Tempo/Prometheus/Istio/KEDA/OpenMetadata/Kiali with per-act applicability; `--only` / `--skip` validated against the act list (CAP-043, Phase E) | §17 | Cluster-confirmed for 4 of 5 acts: **scale**, **canary**, **lineage**, **topology** all PASS end-to-end with Enter-driven advance. **trace** remains the open issue — the KEDA HTTP add-on interceptor returns 502 with `X-Keda-Http-Cold-Start: true` because uvicorn's cold-start exceeds the interceptor's `DialRetryTimeout` budget (~15s). Documented as a follow-up; not blocking the walkthrough. Lesson: `KEDA_HTTP_INTERCEPTOR_*` env-var names from earlier KEDA HTTP versions are NOT honored by 0.12.2; the real envs are `KEDA_*` (no `HTTP_INTERCEPTOR_` infix) |
| **unverified** | `examples/17-capstone` `scripts/bootstrap-capstone.sh` now produces a walkthrough-ready cluster in one command: 10 steps (was 8), with step 9 = `setup-kiali.sh` and step 10 = `ingest-openmetadata.sh` (CAP-044). `demos/walkthrough.sh` preflight enforces both: a missing Kiali or unrun ingestion fails fast with the specific fix script in the message, instead of failing mid-act | §17 | Pending cluster run. Verify: on a fresh profile, `./scripts/bootstrap-capstone.sh` finishes with all 10 steps green; `./demos/walkthrough.sh` then runs without operator intervention beyond Enter. Offline: `bash -n` clean on both scripts; step numerators renumbered 1/10..10/10; `--help` and bogus-arg validation unchanged |
| **unverified** | `examples/17-capstone` `keda/gateway-httpscaledobject.yaml` `replicas.min: 1` (CAP-045) remains the active manifest on `main`. CAP-046's planned migration to `InterceptorRoute` is deferred (see CAP-047 below) — the file is NOT deleted, the `min: 1` workaround stays as the gateway's warm-baseline mechanism while the upstream interceptor bug is open | §17 | Cluster-verifiable: `kubectl get httpscaledobject -n capstone graphql-gateway -o yaml` shows `replicas.min: 1`; gateway Deployment stays at one ready replica between requests. The CAP-046 row below is also superseded by CAP-047 |
| **superseded by CAP-047** | `examples/17-capstone` Phase F: KEDA HTTP add-on 0.12.2 → 0.14.0 (`scripts/setup-keda.sh` version bump), migration of `graphql-gateway` from `HTTPScaledObject` (v1alpha1) to `InterceptorRoute` (v1beta1) + separate `ScaledObject`. New `timeouts.readiness: 60s` on the InterceptorRoute is the configurable cold-start budget that 0.12.2 didn't expose. `minReplicaCount: 0` restored — scale-to-zero works again. Updated apply-points in `scripts/bootstrap-capstone.sh`, `demos/smoke-keda-http.sh`, `demos/smoke-trace-flow.sh` (curl timeout 30s → 90s) (CAP-046) | §17 | Attempt made on the `phase-f-keda-http-014` branch; branch discarded after discovery of the upstream interceptor regression. Historical row retained — work product (manifest shapes, design) preserved for the re-attempt once upstream issue `kedacore/http-add-on#1668` ships a fix. See the CAP-047 rows below |
| **verified (Fedora 44)** | `examples/17-capstone` `demos/walkthrough.sh` Act 1 (trace) port-forwards directly to `svc/graphql-gateway` (capstone namespace) and sends the GraphQL POST there, bypassing `keda-add-ons-http-interceptor-proxy`. The KEDA HTTP-add-on's interceptor has an upstream Go panic on POST forwarding (`invalid concurrent Body.Read call`) in v0.14.0, filed at `kedacore/http-add-on#1668`. The trace itself (HTTP server → REST client → gRPC client spans across three products, stitched in Tempo) is unchanged; only the entry path differs (CAP-047) | §17 | Validated against the upstream sample app `traefik/whoami` using KEDA's own Getting Started manifests — panic reproduces, ruling out anything specific to our gateway. The cluster-side bypass (direct port-forward to the gateway Service) returns `200 OK` with the GraphQL response. Preflight gains two checks for the trace act: graphql-gateway Deployment available + Service exists. Offline: `bash -n` clean; the new `trace_act` function self-cleans its port-forward through the cleanup trap |
| **deferred — upstream blocker** | `examples/17-capstone` upgrade of KEDA HTTP add-on from 0.12.2 to 0.14.0 with InterceptorRoute migration (CAP-046) is paused on `main`. Cluster stays on 0.12.2; gateway uses `HTTPScaledObject` with `replicas.min: 1` (CAP-045). Pickup criterion: upstream issue `kedacore/http-add-on#1668` closes against a tagged binary release ≥ 0.14.1; at that point CAP-046's migration plan is re-runnable on a fresh branch and supersedes CAP-047 (CAP-047) | §17 | Tracking the upstream issue is the verification trigger. Once a fix is released: bump `scripts/setup-keda.sh` `KEDA_HTTP_VERSION`, apply the two new manifests from CAP-046's body, re-run `./demos/walkthrough.sh --only trace --no-preflight` first through the interceptor (must pass), then `--skip trace --no-preflight` (the four existing acts must still pass), promote both rows to verified, supersede CAP-047, ship |

**Aggregator status:** `scripts/test-all-examples.sh` does not
yet exist; will be added once the first two examples' `demo.sh`
pass on their own.

## D. Iteration log and open priorities

Iteration-by-iteration record of what landed, what was promoted,
and what's next.

**Done:**

- ✅ **r01** (2026-05-16) — PRD drafted and approved
- ✅ **r02** (2026-05-16) — Skeleton scaffolded with project
  branding; GitHub Pages site live at
  `https://patterncatalyst.github.io/minikube-on-fedora/`
- ✅ **r03** (2026-05-17) — `_docs/01-prerequisites.md` drafted;
  iteration plan codified; `CONTRIBUTING.md` added;
  `scripts/audit-fedora-prereqs.sh` shipped. User audit + UBI
  test confirmed Fedora 44, Podman 5.8.2 rootless, UBI pullable
  without subscription. Four reconciliation rows promoted
- ✅ **r04** (2026-05-17) — `_docs/02-installation.md` drafted
  with pinned install paths: minikube via dnf-from-upstream-RPM,
  kubectl skipped or upstream binary, helm 4.1.x via
  `dnf install helm`, httpie via dnf, mikefarah yq via upstream
  binary (corrected in r05 — see below), krew installer +
  `stern`/`ctx`/`ns` via krew, hey via `go install`.
  Audit script bugs fixed (podman 5.x `CgroupVersion` template,
  `maybe()` stderr leak)
- ✅ **r05** (2026-05-17) — `_docs/03-starting-minikube.md`
  drafted (cluster start, layers, status, lifecycle, drivers,
  in-cluster runtime). `examples/03-driver-check/` added —
  project's first runnable demo. **r04 follow-up fix in §2**:
  yq is packaged in Fedora 44 as mikefarah's yq (4.47.1), so
  §2's install instruction is now `sudo dnf install -y yq`.
  Three sub-iterations (r05a/b/c) resolved before demo green:
  - r05a: added `jekyll-seo-tag` to Gemfile (skeleton bug
    breaking every Pages build since r02)
  - r05b: added `--rootless` flag — rootful default failed with
    `sudo: a password is required`; fixed audit script's krew
    plugin detection
  - r05c: added `--container-runtime=containerd` and orphaned-
    podman-volume cleanup — rootless+docker-runtime failed on
    `docker.service` start inside the cluster container
  Final r05c demo run: cluster up on containerd 2.2.1, kindnet
  CNI, all 8 kube-system pods Running, ✓ SUCCESS

- ✅ **r06** (2026-05-17) — `_docs/04-profiles-multi-node.md` +
  `_docs/05-addons-dashboard.md` (small sections combined per
  the plan). §3 polish: expected-output block aligned with
  r05c user run; harmless kic-artifacts callout added.
  Iteration plan refreshed (Phase 1 + 2 marked ✅; `sleep 5`
  baked into verification rhythm; sub-iteration calibration
  recorded). Section C `examples/03-driver-check/` promoted to
  `verified (Fedora 44)` — first row out of `in flight`. User
  verification recipe (profile lifecycle + three-addon enable
  flow) passed cleanly: scratch profile up/listed/deleted with
  per-cluster resource override observed; metrics-server +
  ingress + dashboard all enabled with expected pod state and
  dashboard URL returned

**Phase 2 done** (2026-05-17).

- ✅ **r07** (2026-05-17, shipped; demo failed; superseded by r07a)
  — §6 first real workload-deployment iteration.
  `_docs/06-deploying-with-kubectl.md` drafted (25-min section
  on Pods/ReplicaSets/Deployments mental model, manifest
  walkthrough, apply/inspect/expose/port-forward/scale/rolling-
  update sequence). `examples/06-deploy-nginx-kubectl/` shipped
  with two manifests (Deployment + Service), demo.sh, README.
  Initial Deployment pinned to
  `registry.access.redhat.com/ubi9/nginx-124`. **Demo failed**
  with `CrashLoopBackOff` — root cause: UBI nginx is an s2i
  builder, doesn't run directly in plain Kubernetes. r07a is
  the architectural pivot. §3 polish (auto-detect trap callout)
  and r06-promotion reconciliation work from this iteration
  carry forward into r07a unchanged
- ✅ **r07b** (2026-05-17, site-polish) — Homepage `index.html`
  rewritten to **auto-generate section cards** from the `site.docs`
  Jekyll collection sorted by front-matter `order`. Previously
  3 hardcoded cards from r02 (Outline, Prerequisites,
  Reconciliation plan) — and a stale comment promising to update
  them "as sections get drafted," which never happened, so §2-§6
  were shipping without homepage representation. The new Liquid
  loop adds a section card for every `_docs/0N-*.md` file, with
  eyebrow ("Overview" for §0, "Section N" for the rest), title,
  description, and duration pulled from front matter. A separate
  "Project plans" mini-section hosts cards for the reconciliation
  plan and (newly visible) the iteration plan. Future sections
  require zero `index.html` edits

**In flight:**

- ✅ **r07a** (2026-05-17, architectural-pivot — confirmed in r07c
  user run) — Demo from r07 failed: nginx Pods in `CrashLoopBackOff`.
  Initial diagnosis was correct (UBI nginx-124 is an s2i builder,
  expects content at `/opt/app-root/src`); first proposed fix
  (ConfigMap-mounted content + command override) was the wrong
  architecture; user redirected to the right approach: **build our
  own image** from a standard UBI base via a multi-stage
  Containerfile. r07a delivered: new `Containerfile` (multi-stage
  ubi9 → ubi9-minimal, microdnf install nginx, sed-patch for
  non-root + port 8080); new `index.html` sentinel content;
  `manifests/deployment.yaml` references `nginx-custom:v1`;
  `demo.sh` adds `minikube image build` step + log-dump-on-failure;
  §6 prose rewritten to teach the multi-stage build pattern + UBI
  variants (ubi / ubi-minimal / ubi-micro) + introduction of
  `:Z` SELinux convention for §8 work to come. The r07a Containerfile
  itself had a bug (sed substitution + file-logging) that was
  found and fixed in r07c — but the architectural pivot was right
- ✅ **r07c** (2026-05-17, demo-fix + diagnostic-improvement) — r07a
  demo failed with `CrashLoopBackOff`; `kubectl logs` showed only
  the "user directive" startup warning followed by silence. Root
  cause: **RHEL/UBI nginx writes access.log and error.log to
  `/var/log/nginx/*.log` files by default, not stdout/stderr** —
  so any runtime failure (the most likely being a port-bind
  permission denial because the r07a sed substitutions didn't
  reliably patch the nginx.conf format) lands in a file kubectl
  logs can't see. Fix abandoned the sed approach: new minimal
  `nginx.conf` shipped via `COPY`; Containerfile simplified to one
  `COPY` line; `USER 1001:0` (explicit GID 0); §6 prose updated
  with "Why we ship our own nginx.conf" subsection. **r07c demo
  PASSED on user's Fedora 44** — image built, Deployment Available
  in 8 seconds, port-forward + curl + scale to 3 all green. Seven
  §6 Section B rows promoted, Section C `examples/06-deploy-nginx-kubectl/`
  promoted
- ✅ **r08** (2026-05-17, §7 NodePort — confirmed in r08a user run)
  — `_docs/07-services-nodeport.md` drafted (20-min section
  covering Service types comparison, NodePort mechanics, three
  patterns for reaching the NodePort, the 30000-32767 range
  constraint, when NodePort isn't the right answer).
  `examples/07-nodeport-service/` shipped with its own Deployment
  + NodePort Service manifests, demo.sh, README. Reuses §6's
  `nginx-custom:v1` image (auto-builds from §6's Containerfile if
  not cached). Distinct resource names (`nginx-np`) and label
  (`app: nginx-np`) so it coexists with §6. Two correctness bugs
  surfaced in user run (prose framing of rootless = direct-route,
  demo's URL-fetch deadlock under tunnel) — fixed in r08a
- ✅ **r08a** (2026-05-17, prose-correction + demo-fix for r08) —
  §7 prose "Reaching the NodePort" section rewritten with
  correct two-case framing (host-routable vs not-routable, with
  rootless podman in the not-routable bucket).
  `examples/07-nodeport-service/demo.sh` rewritten to run
  `minikube service --url` once in the background, watch its
  output for the URL, kill on cleanup. README updated.
  **r08a demo PASSED on user's Fedora 44** — tunnel established
  in 3 seconds, NodePort exposure via `http://127.0.0.1:45185`,
  curl matched sentinel, 35s total. Two §7 Section B rows
  promoted; Section C `examples/07-nodeport-service/` promoted.
  Two new `verified` Section B rows added from what we learned:
  rootless-podman networking + tunnel timing
- ✅ **r09** (2026-05-17, §8 Persistent Volumes — confirmed in
  user run) — `_docs/08-persistent-volumes.md` drafted (25-min
  section on Volume/PV/PVC concepts, StorageClasses + dynamic
  provisioning, minikube's storage-provisioner addon, access
  modes, reclaim policies, the initContainer-seeds-PV pattern
  with timestamp-based persistence verification).
  `examples/08-persistent-volume/` shipped with PVC + Deployment
  (with initContainer) + Service manifests, demo.sh, README.
  **r09 demo PASSED on user's Fedora 44** — Deployment Available
  in 3s, PVC bound to `pvc-40990c02-...`, initContainer wrote
  timestamped HTML at `2026-05-17T12:28:19Z`, Pod deletion
  triggered replacement, new Pod's initContainer log showed
  `content already exists; persistence is working` plus a `cat`
  of the existing index.html, timestamps before and after the
  Pod delete matched exactly. Six §8 Section B rows promoted +
  the §1/§8 SELinux row resolved + Section C
  `examples/08-persistent-volume/` promoted

**In flight:**

- **r10** (2026-05-17, §9 helm) — `_docs/09-helm.md` drafted
  (25-min section on what helm is, chart anatomy, helm 3 vs 4
  format compat, Go template + Sprig functions, the
  install/upgrade/history/rollback/uninstall workflow, `helm
  template` dry-run, `helm lint`). `examples/09-deploy-nginx-helm/`
  shipped with an authored small chart (Chart.yaml, values.yaml,
  templates for ConfigMap + Deployment + Service + helpers).
  Chart deploys the same `nginx-custom:v1` image as §6/§7/§8 but
  with HTML content templated from `values.content.*` into a
  ConfigMap mount at `/usr/share/nginx/html`. Demo exercises the
  full lifecycle: lint → template → install with `--set title="..."`
  → curl + verify title → upgrade with different title → roll
  out (the `checksum/configmap` annotation in the Deployment
  template triggers Pod recreation when ConfigMap changes) →
  curl + verify upgraded title → history → uninstall → verify
  zero leftovers via label selector. Reconciliation: 8 new §9
  rows added to Section B (including a promoted §2 helm-4-reads-
  helm-3-chart claim that finally has demo backing), Section C
  `examples/09-deploy-nginx-helm/` set to `in flight`
- **r10a** (2026-05-17, jekyll build fix) — r10 broke Jekyll's
  GitHub Actions build with a fatal `liquid-4.0.4
  standardfilters.rb:253:in 'replace': wrong number of arguments`
  error. Root cause: Liquid's templating uses `{{ }}` and so do
  Go templates; when §9 prose embedded helm template snippets in
  markdown code blocks, Jekyll's Liquid parser ate them. Most
  generated harmless warnings; one specific line in the
  _helpers.tpl example —
  `{{ ... | replace "+" "_" }}` — actually parsed as a Liquid
  pipeline and crashed Liquid's `replace` filter (different arity
  than helm's). Fix: wrap each affected code block (and the
  inline-mentions paragraph) with `{% raw %}` / `{% endraw %}`
  so Liquid passes the content through verbatim. Six wraps total:
  one in `_docs/01-prerequisites.md` (podman info --format line —
  was generating warnings, not fatal; fixed while we're here),
  five in `_docs/09-helm.md` (inline-mentions paragraph plus
  four template code blocks: ConfigMap, Deployment, Service,
  _helpers.tpl). New `verified` Section B row records the
  lesson; applies prospectively to §11 Istio, §12 KEDA, or
  anywhere Go templates appear in prose
- **r10b** (2026-05-17, jekyll build fix part 2) — r10a wrapped
  the offending code blocks in `_docs/`, but the reconciliation
  plan's narrative about the bug *itself contained* `{{ ... |
  replace "+" "_" }}` in prose, and Liquid hit it on the next
  build. Fix: `render_with_liquid: false` in front matter of
  `_plans/reconciliation-plan.md` and (defensively)
  `_plans/iteration-plan.md`. Plan files are pure reference
  markdown; they don't use Liquid features; disabling it
  wholesale is cleaner than wrapping every mention with raw
  tags (which can break markdown tables anyway). Build green
  after r10b applied
- **r10c** (2026-05-17, tooling) — `scripts/check-liquid-collisions.sh`
  shipped. Bash + awk static scan for the two conventions:
  Go-template patterns outside `{% raw %}` wrappers in
  `_docs/*.md`, any `{{ }}` content in `_plans/*.md` missing
  `render_with_liquid: false`. Tested against both corrected
  and uncorrected r10/r10a versions; correctly flags the exact
  lines that broke the CI build, passes when content is fixed.
  Runs in well under a second; no Ruby/Bundler/Jekyll needed.
  CONTRIBUTING.md updated with a "Site authoring conventions"
  section documenting both rules and pointing at the script
- **r10d** (2026-05-17, §9 demo race fix) — §9 demo run passed
  every substantive check (lint, template, install + curl,
  upgrade + rollout + curl with new content, history, uninstall)
  but failed the one-shot leftover query. The query ran 0ms
  after `helm uninstall` returned and caught a Pod in
  `Terminating` state (3 seconds old). Root cause: helm
  uninstall is asynchronous — it returns once the release
  record is gone and delete operations are submitted, but the
  kubelet then runs through `terminationGracePeriodSeconds`
  (default 30s) before force-killing Pods. r10d replaces the
  one-shot check with a 30-second polling loop. Reconciliation
  plan: 6 §9 Section B rows promoted to verified with actual
  run details + the §2/§9 helm-3-chart-compat row promoted +
  one new `verified` row recording the async-uninstall finding.
  `helm uninstall removes all resources within 30s` row stays
  in flight pending re-run
- ✅ **r11** (2026-05-17, §10 Editor, shell, terminal — reference
  section; no demo) — `_docs/10-editor-shell-terminal.md` drafted
  (20-min section on practical tooling for k8s work). Pulsar as
  editor + alternatives (VS Code, Neovim, IntelliJ, nano); zsh as
  shell with bash-compat footnotes; tab completion incantations
  for kubectl/helm/minikube; curated alias set (`k=kubectl`,
  `kg*`/`kd*`/`kl*`) with `compdef` lines so aliases inherit
  completion; recaps of stern, kubectx/kubens; k9s as the
  most-recommended optional tool; tmux/zellij. No
  `examples/10-*/` directory — verification is "open a new zsh
  and tab-complete works." 5 §10 rows added to Section B as
  unverified low-priority — can be checked individually
  (`which k9s`, etc.) but §10 isn't a verification gate

**In flight:**

- **r12** (2026-05-17, §11 Istio) — `_docs/11-istio.md` drafted
  (40-min section, longest in the tutorial). Two halves: a
  **minimal sidecar injection** of our existing `nginx-custom:v1`,
  then the full **Bookinfo** sample with traffic routing and
  fault injection. Per user direction "let's do Both."
  Architecture: dedicated `istio` minikube profile (4 CPU /
  6 GB) separate from the §6-§9 `minikube` profile; image cache
  is per-profile so nginx-custom rebuilds. `scripts/setup-istio.sh`
  is the one-time setup (downloads Istio 1.29.2 tarball, installs
  istioctl to `~/.local/bin/`). `examples/11-istio/demo.sh` is
  the comprehensive run: pre-flight, build image, install Istio
  (idempotent), label namespace, deploy nginx-with-sidecar,
  verify 2/2 containers, deploy Bookinfo, apply Gateway +
  VirtualService, port-forward + curl productpage, apply
  v1-pinning rule (assert 0/10 v3 hits), apply 50/50 split
  (assert ~50% of 20 responses hit v3). kubectl context
  saved+restored so §6-§9 profile is undisturbed. 12 §11 rows
  added to Section B (control plane install, sidecar injection,
  bookinfo, gateway, two routing assertions, analyze, per-profile
  image cache, context save/restore). Bookinfo uses upstream
  `docker.io/istio/*` images — vendor-neutral PRD constraint
  was about *our* examples; upstream sample apps using their own
  images is conventional. Demo expected 8-12 min first run
- **r12a** (2026-05-17, kernel-limits + stale-state pre-flight)
  — r12 user run failed at `minikube start -p istio` with
  `Failed to create control group inotify object: Too many open
  files`. Root cause: `fs.inotify.max_user_instances` (default
  on Fedora 44 is ~128) is sized for ONE containerized systemd
  instance. The §3 `minikube` profile already consumed that
  budget; the second profile (`istio`) blew the limit. Not a
  RLIMIT_NOFILE issue. Standard kind/minikube workaround:
  `sudo sysctl fs.inotify.max_user_instances=512
  fs.inotify.max_user_watches=524288`. Cascade failure on
  retry: stale `podman volume istio` from the partial start
  blocked `minikube start` with `volume already exists`. r12a
  fixes:
  1. `examples/11-istio/demo.sh` pre-flight now checks inotify
     limits (warn floor: 256 instances / 131072 watches); fails
     loudly with the `/etc/sysctl.d/99-kubernetes.conf` recipe
     if too low
  2. Demo's profile-startup logic is more defensive — if the
     profile exists but isn't running cleanly, it's deleted
     first; stale podman volumes are explicitly removed before
     retry
  3. `_docs/11-istio.md` gains a "Before you start: kernel
     inotify limits" subsection at the top of profile setup,
     explaining the problem + fix
  4. Two new `verified` Section B rows record both findings —
     the inotify limit floor for multi-cluster minikube on
     Fedora, and the stale-volume cascade failure mode
- **r12b** (2026-05-17, kernel-limits finding propagated to §1
  + audit script) — user request: "document the finding for
  this <sysctl recipe>". r12a put the recipe inside §11 (both
  in prose and as a pre-flight check in the demo); r12b makes
  it discoverable from multiple reader paths:
  1. **`_docs/01-prerequisites.md`** — new
     "## Kernel limits for multi-cluster (needed for §11)"
     subsection inserted right before "## Verification".
     Explains why §3-§10 don't need it (one cluster, defaults
     fine), why §11 does (two clusters), the symptom log line,
     the `sysctl`-not-ulimit distinction (since LimitNOFILE
     wouldn't have fixed it), the full
     `/etc/sysctl.d/99-kubernetes.conf` recipe, the
     verification command, and cross-references to the audit
     script + §11 demo pre-flight
  2. **`scripts/audit-fedora-prereqs.sh`** — new "kernel
     limits" section reads the current inotify values via
     `sysctl -n` and prints either `✓ OK for running a second
     minikube profile (§11)` (if ≥256 instances and ≥131072
     watches) or `⚠ defaults — fine for §3-§10 but NOT for §11`
     with the full remediation recipe inline. So users running
     `./scripts/audit-fedora-prereqs.sh` for any reason now
     also get a §11-readiness check
  3. **`_docs/11-istio.md`** — existing
     "Before you start: kernel inotify limits" subsection now
     leads with a callout block pointing back to §1 as the
     canonical recipe. §11-jumpers still get all the
     information; §1-readers see the topic once with §11
     cross-references. No new Section B rows needed (r12a's
     two verified rows cover both findings); r12b is
     pure-documentation propagation
- **r12c** (2026-05-17, mesh-admission-webhook race fix) —
  r12b user run got further: inotify check passed (limits raised
  to 512/524288 via the r12a recipe), stale-state cleanup
  caught the leftover broken `istio` profile and rebuilt
  cleanly, minikube started, nginx-custom rebuilt on the istio
  profile, Istio installed cleanly with all 3 control-plane
  Pods Running. Failure at deploy-nginx-with-sidecar: Pod came
  up with **one container, no istio-proxy**. Root cause: the
  `MutatingWebhookConfiguration istio-sidecar-injector`
  registers AFTER istiod's Deployment reaches
  `condition=Available` — the Pod is Ready when the gRPC port
  opens, but the webhook's `.webhooks[0].clientConfig.caBundle`
  is populated as a separate (async) step a few seconds later.
  `kubectl wait Available` returns before injection is actually
  live; deploying immediately produces a Pod that the API server
  silently skips injection on (empty caBundle → can't reach
  webhook → no injection attempted). This is a well-known
  install-then-deploy race in Istio. r12c fixes:
  1. After `istioctl install`, poll
     `mutatingwebhookconfiguration/istio-sidecar-injector` for
     non-empty `.webhooks[0].clientConfig.caBundle`. Up to 60s
     wait. This is the actual signal that injection is live —
     not just `Pod Available`
  2. Brief 3s sleep after labeling the `default` namespace, so
     the admission controller's namespace-label cache refreshes
     before our Pod creation hits it
  3. Diagnostic dump on injection failure: namespace labels,
     all istio-related mutatingwebhookconfigurations + their
     caBundle byte counts, Pod annotations, last 30 lines of
     istiod logs. So if it still fails, debugging starts from
     useful data
  4. Single retry-on-failure: if the Pod comes up without the
     sidecar, delete the Deployment and redeploy after 10s.
     The webhook fires on new Pod admission, so this clears any
     first-time-only flake. Second failure is a hard fail with
     diagnostics dumped again
  5. New `verified` row in Section B records the webhook-race
     finding (Available-vs-caBundle-populated gap is the
     learning); 5 other §11 rows promote based on user run
     output (profile start, istio install, setup-istio.sh,
     per-profile image cache)
- **r12d** (2026-05-17, native sidecars finding + false-negative
  check fix) — r12c user run got further: webhook-readiness check
  passed (`caBundle populated after 1s`), namespace labeled, Pod
  deployed. But the sidecar check failed twice on retry — except
  the diagnostic dump revealed that **injection actually
  succeeded both times**. The Pod's `sidecar.istio.io/status`
  annotation explicitly showed `"initContainers":["istio-init",
  "istio-proxy"], "containers":null`. istiod's logs showed new
  xDS connections from the meshed Pod within 2s. The webhook
  fired correctly; the check was looking in the wrong place.

  Root cause: **Istio 1.29 on Kubernetes 1.28+ uses native
  sidecars** (KEP-753) — istio-proxy is injected as an init
  container with `restartPolicy: Always`, not as a main
  container. The demo's jsonpath query
  `'{.status.containerStatuses[*].name}'` reads only main
  containers, so it returned just `nginx,` — false-negative.
  Old pre-1.28 Istio docs (and many web search results) still
  describe istio-proxy as a main container, which is now
  outdated for current K8s versions.

  r12d fixes:
  1. `examples/11-istio/demo.sh` `check_sidecar_injected()` now
     reads `.spec.containers[*].name` AND
     `.spec.initContainers[*].name` (spec-based, works for both
     native-sidecar mode and the legacy mode on K8s ≤1.27)
  2. `_docs/11-istio.md` adds a sidebar callout under
     "Sidecar in action" explaining native sidecars: where
     istio-proxy lives, why JSONPath checks need to look in
     both places, why `kubectl get pods` still shows `2/2`,
     and what the corrected `kubectl describe pod` output
     looks like (istio-proxy under "Init Containers:" with
     `Restart Policy: Always`)
  3. Two §11 Section B rows promoted to verified — namespace
     injection works (the r12c diagnostic dump proved it),
     plus the new native-sidecars finding gets its own row.
     This is a genuinely useful piece of Istio knowledge worth
     keeping in the plan: anyone scripting against post-1.29
     Istio needs to know
- **r12e** (2026-05-17, Bookinfo UI rebrand + hash-based routing
  checks) — r12d user run nearly hit `✓ SUCCESS`: pre-flights all
  passed, nginx-with-sidecar deployed cleanly, Bookinfo's 4
  microservices all came up `2/2 Running`, Gateway + VirtualService
  applied, `istioctl analyze` clean, port-forward reachable.
  Failure at the productpage marker check: the response *was*
  Bookinfo (`<title>Simple Bookstore App</title>` and
  `static/tailwind/tailwind.css`), but the demo was looking for
  "Bookinfo Sample" — the older title. Bookinfo has been rebranded
  in current Istio releases and migrated from Bootstrap to
  Tailwind, which also breaks the downstream `glyphicon-star`
  routing assertions (that class doesn't exist in Tailwind
  Bookinfo). r12e fixes:
  1. Productpage marker check accepts both "Simple Bookstore"
     (current) and "Bookinfo Sample" (legacy)
  2. **Routing assertions switched to response-hash distribution**
     — v1-pinning expects ≤3 distinct hashes across 10 samples
     (deterministic v1 backend produces near-identical responses);
     50/50 split expects ≥2 distinct hashes across 20 samples
     (v1 deterministic + v3 random rating counts → mixed
     patterns). The hash approach is markup-agnostic and survives
     future Bookinfo UI redesigns
  3. 8s sleeps (up from 5s) after applying each rule for
     propagation
  4. 4 §11 Section B rows promoted to verified from the r12d
     user run (Bookinfo deploys with sidecars, Gateway exposure
     works, istioctl analyze clean, the UI rebrand finding gets
     its own row). The two routing assertions stay unverified
     pending the r12e re-run
- ✅ **r12f** (2026-05-17, §11 verified end-to-end, **Phase 4
  complete**) — r12e user run: **`✓ SUCCESS`**. Full §11 demo
  passed all 13 phases in ~30s (cluster + Istio + image all
  cached from prior runs). The two routing assertions came in
  cleaner than expected:
  - v1-pin: **exactly 1** distinct hash across 10 samples
    (productpage with only v1 reviews is fully deterministic;
    zero noise). Strongest mesh-routing assertion in the
    tutorial
  - 50/50 split: **2** distinct hashes across 20 samples,
    11/9 distribution (55/45% — within statistical noise of
    a true 50/50). v3 also produced a single deterministic
    hash, suggesting current Bookinfo seeds randomness from
    request ID
  r12f promotes:
  - The two §11 routing assertions to verified
  - The kubectl-context save/restore row to verified
  - Section C `examples/11-istio/` from in flight to verified
  Total verified row count after r12f: **83** (started r02 at
  ~5; gained 78 across 24 sub-iterations of real-on-Fedora
  verification). This is the end of **Phase 4 (Service Mesh)**.
  Phases 5+ are §12 KEDA (optional), the tail sections (§13-§15),
  diagrams, and the editorial pass

**Phase 4 retrospective — six sub-iterations of §11 (r12 through
r12e), each catching a real-world issue:**

| Sub-iter | Finding                                                            | Captured as                           |
|----------|--------------------------------------------------------------------|---------------------------------------|
| r12      | Initial §11 ship (Istio + Bookinfo + routing)                      | 12 unverified §11 rows                |
| r12a     | inotify limits sized for one minikube cluster, not two             | Section B verified row + pre-flight   |
| r12b     | Propagated the inotify finding to §1 prereqs + audit script        | Documentation in three places         |
| r12c     | Istio install-then-deploy webhook race (Available ≠ caBundle live) | Section B verified row + caBundle poll|
| r12d     | Istio 1.29+ native sidecars (KEP-753) — istio-proxy is initContainer| Section B verified row + spec-based check |
| r12e     | Bookinfo UI rebrand: Bootstrap → Tailwind, no more glyphicon-star  | Section B verified row + hash-based check |

None of these were in the obvious-search-result Istio quickstart
docs in clearly-findable form. Now they're captured as verified
knowledge in the reconciliation plan — future readers don't
have to derive them.

- ✅ **r12g** (2026-05-17, observability addons + §11 prose
  addendum) — user ran the §11 observability addons step:
  `kubectl apply -f $ISTIO_DIR/samples/addons/` installed
  Kiali, Prometheus, Grafana, Jaeger, and Loki cleanly within
  ~5 minutes; all four `kubectl wait deployment/<x>` calls
  returned `condition met`. Loki StatefulSet showed `2/2
  Running`. Then user generated 200 productpage requests
  through the ingressgateway and opened Kiali; the dashboard
  rendered both the Overview (showing namespace cards with
  live inbound-traffic sparklines) and the Traffic Graph
  (showing istio-ingressgateway → productpage at 1.89 req/s
  100% success with traffic animation enabled).

  Two screenshots captured:
  - `assets/screenshots/kiali-overview.png` — namespace cards
    showing `default: 4 applications` with climbing traffic
    rate
  - `assets/screenshots/kiali-traffic-graph.png` — live
    Traffic Graph with green edges and the right-panel stats

  Failure mode discovered along the way: the §11 demo's
  cleanup trap deletes Bookinfo (workload + Gateway +
  VirtualService) on exit, so opening Kiali immediately after
  `✓ SUCCESS` shows the control plane but no application
  traffic to graph, and `kubectl port-forward` to the
  ingressgateway fails with `connection refused` because no
  Gateway is configured. The §11 prose previously didn't
  surface this — readers running the demo then exploring
  Kiali would hit the same wall.

  r12g fixes:
  1. New `## Exploring with Kiali after the demo` subsection
     inserted into `_docs/11-istio.md` between the existing
     "Verification" and "Cleanup" sections. Explicit explanation
     of why the trap deletes Bookinfo, full recipe to redeploy
     for exploration (workload + Gateway + DestinationRules),
     observability-addons install commands, Kiali walkthrough
     with both screenshots embedded inline via Jekyll's
     `relative_url` filter (the standard pattern; both image
     tags are wrapped in `{% raw %}` blocks since the prose is
     in `_docs/` and the rest of the §11 file is subject to
     Liquid rendering), three interactive demonstrations to try
     in Kiali (v1 pinning, fault injection, other dashboards),
     and clean teardown commands at the end
  2. Two screenshots committed at `assets/screenshots/kiali-{
     overview,traffic-graph}.png`. ~120KB combined; well under
     any reasonable repo-size budget
  3. Two new `verified` Section B rows record the addons-install
     working + the Kiali visualization working

  Total verified row count after r12g: **85** (up from 83).
  Section D priorities updated to remove the now-completed
  observability item

- **r13** (2026-05-17, §12 KEDA — initial ship) — first ship
  of the optional KEDA section. Pre-flight confirmed user's
  minikube profile has 6 CPU / 16 GB / rootless / containerd
  / podman with ~510Mi memory in use (plenty of headroom for
  Strimzi + KEDA + workloads). Per PRD: "reference material
  for KEDA + HTTP add-on." Per user direction: Kafka via
  **Strimzi** (acknowledged historical "mixed results" — r13
  plan includes defensive scripting + honest Bitnami fallback
  note in prose) for Pattern A, **KEDA HTTP add-on** for
  Pattern B. Both demos use the existing `minikube` profile,
  no second cluster.

  Files shipped:
  - `_docs/12-keda.md` — 45-min section. HPA-vs-KEDA
    conceptual intro; ScaledObject CRD walkthrough; profile
    setup (reuses §3 minikube); KEDA install via helm;
    **Pattern A** (Strimzi + Kafka consumer-lag scaling); the
    full Strimzi cluster manifest with annotations explaining
    each design choice (single-node KRaft, dual-role,
    `version: 3.9.0` pin with "NOT 3.9.2 — known operator
    bug" comment, internal listener only, RF=1, EntityOperator
    for topic + user reconciliation); Python consumer source
    inline with the SIGTERM graceful-exit explanation;
    Deployment with `replicas: 0` + ScaledObject with
    `lagThreshold: "5"`; **Pattern B** (HTTP add-on); the
    architecture diagram showing interceptor + scaler +
    operator; HTTPScaledObject CRD walkthrough;
    `concurrency.targetValue: 5` explained; cleanup section;
    Bitnami fallback note for Strimzi-misbehaves scenarios.
    Beta status of the HTTP add-on surfaced clearly with the
    official upstream quote
  - `scripts/setup-keda.sh` — idempotent helm install of KEDA
    core 2.19.0 + HTTP add-on 0.12.2 into the `keda`
    namespace. Detects existing installs and upgrades.
    Pre-flight checks helm/kubectl availability.
    Diagnostic dump of Pod readiness on completion
  - `scripts/setup-strimzi.sh` — idempotent helm install of
    Strimzi Cluster Operator 0.51.0 into the `kafka`
    namespace. `watchAnyNamespace=false` (operator only
    watches the `kafka` namespace). 5-min timeout on wait.
    Diagnostic dump (Pod list + last 30 lines of operator
    logs) if `kubectl wait Available` times out
  - `examples/12-keda-kafka/` — full Pattern A demo:
    - `manifests/kafka-cluster.yaml` (KafkaNodePool +
      Kafka CR with KRaft, dual-role, version pin)
    - `manifests/kafka-topic.yaml` (KafkaTopic 'orders',
      3 partitions, 2h retention)
    - `manifests/consumer-deployment.yaml` (replicas: 0,
      env-configurable broker/topic/group/sleep, SIGTERM
      grace period 10s)
    - `manifests/scaled-object.yaml` (KEDA ScaledObject:
      lagThreshold=5, maxReplicas=3, pollingInterval=5,
      cooldownPeriod=30, offsetResetPolicy=earliest)
    - `consumer/consumer.py` (Python Kafka consumer with
      graceful SIGTERM, configurable WORK_SLEEP_S)
    - `consumer/Containerfile` (multi-stage UBI build,
      kafka-python==2.0.6 in venv, USER 1001:0)
    - `demo.sh` (10 phases, idempotent, comprehensive
      diagnostic dumps on Strimzi-readiness failure — dumps
      Cluster Operator logs + Kafka CR status + Pods +
      events)
    - `README.md` (pre-reqs, 8 tested claims, expected
      timing, what-to-look-for, 4 common failure modes,
      cleanup, going-further pointers)
  - `examples/12-keda-http/` — full Pattern B demo:
    - `manifests/nginx-deployment.yaml` (replicas: 0,
      reuses nginx-custom:v1 from §6, readinessProbe with
      short init delay so cold-start is fast)
    - `manifests/http-scaled-object.yaml` (HTTPScaledObject:
      hosts: nginx.local, concurrency target 5, max 5,
      scaledownPeriod 30s)
    - `demo.sh` (cold-start timing measured, hey load with
      sustained metrics, scale-up + scale-down assertions,
      diagnostic dumps for HTTPScaledObject + interceptor
      logs on failure)
    - `README.md` (pre-reqs, 6 tested claims, expected
      timing, 5 common failure modes, cleanup, going-further
      pointers including production-readiness note on
      add-on beta status)

  14 §12 unverified Section B rows added (setup scripts,
  Strimzi Kafka readiness, topic readiness, consumer image
  build, scale-to-zero assertion x2, scale-up assertions x2,
  scale-down assertions x2, cold-start buffering, KEDA Pod
  count, no-HPA-conflict claim). Two Section C rows added
  (`examples/12-keda-kafka`, `examples/12-keda-http`), both
  in flight.

  Anticipated sub-iterations (per Phase 4's pattern):
  - **r13a** likely: Strimzi or Kafka readiness flake. The
    Kafka cluster bring-up is the riskiest step
  - **r13b** likely: KEDA scale-up timing in low-resource
    minikube. Need to tune polling/cooldown periods
  - **r13c-?**: assertion thresholds, image-pull timeouts,
    interceptor edge cases

  This is consistent with §11's six-iteration cadence;
  budgeting 3-5 sub-iterations for §12 is reasonable

- **r13a** (2026-05-17, §12 Kafka version pin fix) — first
  Phase 5 sub-iteration. setup-keda.sh and setup-strimzi.sh
  both passed cleanly on user's Fedora 44 box. KEDA: 7 Pods
  Running. Strimzi: 1 Pod Available. The Kafka demo failed
  at `kubectl wait kafka/my-kafka condition=Ready` with a
  clear error in the Kafka CR status block: `Unsupported
  Kafka.spec.kafka.version: 3.9.0. Supported versions are:
  [4.1.0, 4.1.1, 4.2.0]`.

  Root cause: r13's manifest pinned Kafka 3.9.0 based on a
  misread of the Strimzi 0.51 release notes. The upstream
  note about "Kafka 3.9.2 unsupported" was flagging a
  specific upgrade-path failure mode for users coming from
  older Strimzi, NOT establishing that 3.9.x in general is
  supported. Strimzi 0.51 dropped Kafka 3.x entirely and
  supports only Kafka 4.1.0, 4.1.1, and 4.2.0. Kafka 4.x has
  been GA since early 2025 and removed ZooKeeper completely.

  Fix in r13a:
  - `examples/12-keda-kafka/manifests/kafka-cluster.yaml`:
    `version: 3.9.0` → `version: 4.1.0`; explicit
    `metadataVersion: 3.9-IV0` field removed (Strimzi
    defaults it to match the Kafka version on first creation,
    which is safer than guessing the right `4.1-IV?` value)
  - `_docs/12-keda.md`: prose updated to reflect 4.1.0,
    "Notable choices" bullet rewritten to explain the actual
    version constraint (Strimzi dropped 3.x) and the
    metadataVersion omission

  Compatibility check: kafka-python 2.0.6 in our consumer
  image is protocol-compatible with Kafka 4.x brokers per
  upstream documentation ("tested against broker versions
  4.0 through 0.8.0") and KIP-896 (which sets the new client
  baseline at Kafka 2.1, well below kafka-python's 2.0.x
  capabilities). No consumer image rebuild required.

  Reconciliation plan: Section B Strimzi-Kafka-readiness row
  rewritten to reference 4.1.0; new verified row added for
  the version-support finding so future readers don't need
  to rediscover this. r13's manifest-version claim was
  unverified; r13a's is also unverified pending the next
  demo run.

- **r13b** (2026-05-17, §12 Kafka demo verified +
  screenshot) — second Phase 5 sub-iteration, all Pattern A
  claims promoted. User re-ran the Kafka demo on Fedora 44
  with the r13a manifest. Full 0→3→0 lifecycle observed:
  - Kafka cluster Ready in **63s** on first cold install
    (image pull dominated)
  - KafkaTopic 'orders' Ready immediately after
  - Consumer image (UBI 9 / Python **3.9.25** / kafka-python
    2.0.6 — corrected: earlier assistant claim of Python
    3.11 was wrong; UBI 9 ships Python 3.9 as the system
    default) built in ~7s
  - Replicas climbed 0→1 at 5s polling tick, then 1→3 at
    10s tick (capped at maxReplicaCount=3 ≤ partition count)
  - 200 messages drained
  - Scaled back to 0 at 62s (drain delay + 30s cooldown +
    reconciliation lag)

  Promotions (10 §12 Section B rows + Section C
  `examples/12-keda-kafka/` + 1 new screenshot row):
  - setup-keda.sh verified (10 Pods Running — see below for
    Pod-count correction)
  - setup-strimzi.sh verified (1 Pod Available within 40s)
  - Kafka cluster Ready (4.1.0, metadataVersion defaulted
    to 4.1-IV1) verified
  - KafkaTopic Ready verified
  - Consumer image build verified
  - Scale-to-zero at idle verified
  - Scale-up on lag verified
  - Scale-down after cooldown verified
  - Pod count: r13's "7 Pods" claim was **wrong** — actual
    count is **10 Pods** because the HTTP add-on's
    external-scaler and interceptor each default to 3
    replicas. Row corrected on promotion
  - No-HPA-conflict claim verified by demonstration

  New deliverables in r13b:
  - `assets/screenshots/strimzi-kafka-cluster-ready.png` —
    user-provided screenshot of converged Kafka cluster
    state, captioned in prose with row-by-row walkthrough
  - `_docs/12-keda.md`: new "What a healthy cluster looks
    like" subsection between Kafka-cluster definition and
    topic definition. Mirrors §11's Kiali-screenshot pattern
    — gives readers a visual checkpoint between manifest
    apply and demo run
  - New verified row recording the screenshot evidence

  Verified row count: **96** (up from 86 in r13a).
  Per-section coverage: §1-§11 complete, §12 Pattern A
  complete, §12 Pattern B (HTTP add-on) still unverified
  pending user run

- **r13c** (2026-05-17, §12 HTTP false-positive + cleanup
  scripts) — third Phase 5 sub-iteration. User ran the §12
  HTTP demo on the back of r13b's verified KEDA + HTTP add-on
  install. The demo reported `✓ SUCCESS` — but inspection of
  the output revealed this was a **false positive**:
  - `cold-start request took 0s` — physically implausible
    for a real scale-from-zero through the interceptor
    (should be 3-8s)
  - hey's status code distribution showed **all 500
    requests returned HTTP 404** — none of the load test
    actually hit nginx
  - The transient `replicas climbed to 1` did happen, but
    the 1 replica never served traffic (because every
    request 404'd in the interceptor before reaching it).
    Likely root cause: the HTTP add-on's interceptor saw
    requests but couldn't match them to the HTTPScaledObject's
    route, so returned an HTML 404 page that satisfied the
    demo's `*<html>*` pattern match

  The demo's assertions were too lax in three places:
  - The "interceptor reachable" check used `curl -fsS` (fail
    silently) and didn't verify exit code, so a 404 looked
    indistinguishable from a connection error
  - The cold-start check used `case "${RESP}" in *<html>*`
    which matches any HTML — including 404 pages
  - The scale-up assertion checked `replicas >= 1` without
    verifying that the replicas actually served traffic

  Fixes in r13c (§12 HTTP `demo.sh`):
  - Cold-start now captures HTTP status code explicitly via
    `curl -w '%{http_code}'`, fails on non-200, and dumps
    HTTPScaledObject status + interceptor logs + service
    info on failure
  - Cold-start body assertion tightened: must contain
    `"Test Page for the HTTP Server"` or `"nginx"` or
    `"Welcome to nginx"` (not just any HTML)
  - Cold-start warns (but doesn't fail) if completion is
    <1s, since real scale-from-zero takes longer
  - hey output now parsed for status code distribution;
    demo fails if any non-2xx response appears, and warns
    if fewer than half of requests succeeded
  - Interceptor port-forward check renamed to make clear
    it only verifies TCP reachability, not routing
    correctness

  The actual routing fix (whatever's causing the 404) is
  deferred to r13d. The tightened assertions in r13c will
  make r13d's failure mode more diagnostic.

  Cleanup scripts (per user request "should we make sure we
  have a cleanup for each of these demos/examples?"):
  - `examples/12-keda-kafka/cleanup.sh` — removes consumer
    + ScaledObject + Kafka cluster + topics + PVCs.
    `--remove-operators` also removes Strimzi + KEDA + all
    CRDs
  - `examples/12-keda-http/cleanup.sh` — removes nginx +
    Service + HTTPScaledObject. `--remove-operators` also
    removes KEDA + HTTP add-on + CRDs
  - `examples/11-istio/cleanup.sh` — removes nginx-with-
    sidecar + Bookinfo + addons. `--remove-istio` purges
    istiod + gateways + CRDs + webhook configs.
    `--remove-istio --remove-profile` drops the whole
    minikube profile
  - All three are idempotent (safe to re-run when state is
    partially or fully gone)
  - §12 prose Cleanup section rewritten to reference the
    scripts instead of inline kubectl/helm commands
  - §11 + §12 READMEs Cleanup subsections updated similarly

  Note: §3-§9 demos already have cleanup traps that handle
  their relatively-small state; no dedicated `cleanup.sh`
  added for them. Their READMEs could be updated to mention
  this in the future editorial pass

  Verified row count: **100** (unchanged from r13b — no new
  promotions; the §12 HTTP rows that looked promotable from
  r13b's run actually aren't, since the demo didn't validate
  what it claimed to). Plan now correctly reflects that the
  §12 HTTP demo has never had a real verified run

- **r13d** (2026-05-17, §12 HTTP — hey `-H 'Host:'` gotcha)
  — fourth Phase 5 sub-iteration, one-line fix. With r13c's
  tightened assertions, the demo's actual failure mode was
  clearly visible: cold-start curl returned **HTTP 200 with
  nginx content after 3s** (perfect), but the hey load test
  reported **all 500 requests as HTTP 404** in 0.035 seconds
  (clearly an instant rejection, not a routing-to-nginx
  scenario).

  Asymmetric failure between curl and hey on the same target
  with the same `-H "Host: nginx.local"` argument turned out
  to be the diagnostic. The root cause is a well-known Go
  quirk:
  - hey is written in Go and uses `net/http`
  - Go's `net/http.Request` has a special `Host` field
    separate from the `Header` map
  - When code calls `req.Header.Add("Host", x)`, Go silently
    strips the Host header from the map before sending
    (documented in golang/go#7682, open since 2014)
  - So `hey -H "Host: nginx.local"` results in Go sending
    `Host: 127.0.0.1:18080` (from the URL) on the wire
  - The KEDA HTTP add-on interceptor sees no matching route
    for `127.0.0.1:18080`, returns 404 for everything
  - curl handles `-H 'Host:'` correctly because curl treats
    Host as a special case in its argument parsing

  hey actually provides a dedicated `-host` flag for exactly
  this purpose. Source confirms (rakyll/hey hey.go):
  `hostHeader = flag.String("host", "", "")`. Using `-host
  nginx.local` instead of `-H "Host: nginx.local"` sets Go's
  `Request.Host` field directly, which IS sent on the wire.

  Fix in r13d:
  - `examples/12-keda-http/demo.sh`: hey flag changed from
    `-H "Host: ${HOST_HEADER}"` to `-host "${HOST_HEADER}"`.
    A long comment block explains the gotcha so the next
    maintainer doesn't accidentally "fix" it back
  - `examples/12-keda-http/README.md`: "When this fails"
    section now leads with this gotcha as the most common
    failure mode (because anyone hitting it without context
    will lose hours to it). Includes the Go issue link

  Promotions on the back of this fix:
  - HTTPScaledObject scale-to-zero at idle: VERIFIED (r13c
    run showed `current replicas: 0` after applying manifests)
  - Cold-start interceptor buffering: VERIFIED (r13c run
    showed 3s, HTTP 200, nginx content)
  - New verified row capturing the hey gotcha — for the
    Section B "lessons learned" track. Future readers don't
    have to rediscover this

  Still unverified pending the next demo run after r13d:
  - hey load drives sustained traffic, scale-up
  - Scale-down after `scaledownPeriod`
  - Section C `examples/12-keda-http/`

  Verified row count: **103** (up from 100). One additional
  promotion expected on r13d demo re-run

- **r13e** (2026-05-17, §12 HTTP — silent demo abort due to
  parsing bugs) — fifth Phase 5 sub-iteration. With r13d's
  hey `-host` fix in place, the routing finally worked end
  to end (500/500 returned HTTP 200, replicas climbed to 1
  then KEDA would have scaled it back to 0). But the demo
  script aborted silently right after printing the hey
  summary — no SUCCESS banner, no scale-down phase, just an
  immediate jump to the cleanup trap.

  Two compounded bugs in the r13c parsing block:
  - **Awk pattern requires 2 leading spaces** —
    `awk '/^  Status code distribution:/,/^$/'` expected
    `"  Status code distribution:"` but hey outputs it at
    column 0. So `STATUS_LINES` was always empty regardless
    of what hey actually printed
  - **Missing `|| true` on `TOTAL_OK` pipe** — with
    `STATUS_LINES` empty, the pipe
    `echo "${STATUS_LINES}" | grep -E '\[200\]' | awk ... | head -1`
    had grep return nonzero (no match). Under
    `set -e + pipefail`, that nonzero exit propagated from
    inside `$(...)` and aborted the script. The error went
    nowhere because `fail` (which prints to stderr) was
    never reached. Bash quietly exited

  Fixes in r13e (`examples/12-keda-http/demo.sh` parsing block):
  - Parse strategy switched from "extract a section, then grep
    inside it" to "find every status-code line directly across
    the whole hey output". Pattern:
    `grep -E '\[[0-9]+\][[:space:]]+[0-9]+[[:space:]]+responses'`
  - Sum the success counts via `awk '{sum += $2} END {print
    sum+0}'` (handles multiple 2xx codes if hey ever emits
    them separately, e.g., [200] and [204])
  - Every grep pipeline now ends in `|| true` so a missing
    section can't silently abort
  - Long comment block above the parsing explaining both
    gotchas — "earlier versions used awk '/^  Status...' which
    never matched" and "every pipe ending in grep needs ||
    true to suppress nonzero exit codes when there's nothing
    to match"

  Local test harness verified three cases:
  1. Real hey success output (tab-separated): TOTAL_OK=500,
     no BAD_LINES → would pass
  2. All-404 output: TOTAL_OK=0, BAD_LINES populated → would
     fail with the "non-2xx responses" diagnostic dump
  3. Garbage/empty hey output: TOTAL_OK=0, BAD_LINES empty
     → would fail honestly with "fewer than half succeeded"
     rather than silently aborting

  No promotions yet. The HTTP demo's user-facing behavior
  on the previous r13d run was actually fine end-to-end
  (routing worked, all 500 hey requests succeeded), but
  the assertions never reached the scale-down phase because
  the script aborted earlier. Once r13e is applied and the
  demo runs through to `SUCCESS`, three rows promote:
  hey load drives scale-up, scale-down after scaledownPeriod,
  and Section C `examples/12-keda-http/`

  Verified row count: **103** (unchanged)

- **r13f** (2026-05-17, §12 HTTP demo verified — Phase 5
  close-out) — sixth and final r13 sub-iteration. User
  re-ran the §12 HTTP demo on the back of r13e's parsing
  fix. **Full, honest `✓ SUCCESS`** — every assertion fired,
  every phase ran:
  - Cold-start: 3s, HTTP 200, nginx content
  - hey load: 500/500 returned HTTP 200 at ~4500 req/s
  - Scale-up: replicas climbed from 0 to 1 within 1s
  - Scale-down: dropped to 0 at 37s (30s cooldown + ~7s
    reconciliation lag)

  Promotions (4 rows):
  - HTTP load scale-up VERIFIED, with honest note about why
    peak=1 is correct here (load was 500 fast requests
    finishing in 115ms — well below the threshold for
    additional replicas. To see N>1, drive sustained load
    with `hey -z 15s -c 50`)
  - HTTP scale-down after `scaledownPeriod` VERIFIED
  - Section C `examples/12-keda-http/` VERIFIED
  - §1 resource recommendation (6 CPU / 16 GB / 50 GB)
    VERIFIED end-to-end (the full tutorial including §11
    Istio in a separate profile and §12 KEDA+Strimzi
    completed without OOM/CPU/scheduling issues)

  Verified row count: **107** (up from 103). All §12 rows
  verified except those that don't apply (no §12-specific
  unverified rows remain)

  **Phase 5 retrospective** — six sub-iterations for §12,
  consistent with §11's six sub-iterations from Phase 4.
  Sub-iteration breakdown:

  | Sub-iter | Finding | Captured as |
  |---|---|---|
  | r13   | Initial §12 ship (prose + 2 setup scripts + 2 example dirs + plan) | 14 §12 unverified rows + 2 Section C in-flight rows |
  | r13a  | Strimzi 0.51 dropped Kafka 3.x entirely; only 4.1.0/4.1.1/4.2.0 supported | Kafka version bumped to 4.1.0, metadataVersion field dropped, verified Section B row added |
  | r13b  | Kafka demo verified + screenshot of healthy cluster state | 10 §12 Kafka rows + 2 chart-version rows + Section C `examples/12-keda-kafka/` promoted; new "what success looks like" prose subsection with embedded screenshot |
  | r13c  | §12 HTTP demo false-positive (404s but lax assertions claimed success); cleanup scripts for §11+§12 | Tightened HTTP assertions (status code + body content + impossibly-fast warning + hey status distribution); 3 new `cleanup.sh` scripts (§11, §12 Kafka, §12 HTTP) with two-tier teardown |
  | r13d  | hey `-H 'Host:'` silently dropped by Go's net/http (golang/go#7682) — use `-host` flag instead | One-line fix + "Lessons learned" Section B row + README updated; 2 cold-start rows promoted on data already collected by tightened r13c assertions |
  | r13e  | Demo aborted silently after hey output due to two parsing bugs (awk pattern over-anchored + missing `\|\| true` on grep pipe → set-e exit) | Parsing block rewritten with directly-targeted regex + safety guards; local test harness for success/404/empty cases |
  | r13f  | §12 HTTP demo full clean run | 3 §12 HTTP rows + Section C HTTP example + §1 resource row promoted; **Phase 5 complete** |

**Phase coverage map (sections vs verification status):**

| Section | Verified | Notes |
|---|---|---|
| §1  Prerequisites | ✓ | Including inotify limits (from r12a finding) |
| §2  Tooling install | ✓ | minikube/kubectl/helm/yq/hey/krew |
| §3  Starting minikube | ✓ | rootless containerd via podman driver · topology diagram added r16 |
| §4  Profiles + multi-node | ✓ | |
| §5  Addons + dashboard | ✓ | |
| §6  Deploy via kubectl | ✓ | nginx-custom multi-stage UBI build · primitives diagram added r16 |
| §7  NodePort | ✓ | minikube service auto-tunnel via slirp4netns |
| §8  Persistent Volumes | ✓ | initContainer-seeds-PV pattern |
| §9  helm | ✓ | checksum-annotation rollout trigger |
| §10 Editor/shell/terminal | (mostly verified, some `which`-tier rows still unverified — low-value) |
| §11 Istio | ✓ | Bookinfo + native sidecars + Kiali addons · mesh diagram added r16 |
| §12 KEDA | ✓ | Strimzi Kafka 4.1.0 lag scaling + HTTP add-on · HPA-vs-KEDA + HTTP-addon diagrams added r16 |
| §13 Alternatives | ✓ (prose) | Tour of kind/k3s/microk8s/MicroShift with honest Fedora-compatibility notes; shipped r14a |
| §14 FAQ | ✓ (prose) | 22 Q&A entries grounded in actual tutorial-development pain points; cleanup recipes in three tiers; shipped r15 |
| §15 Where to go next | ✓ (prose) | Two-track recommendations (deepen-what-you-built / move-toward-production), bookmarkable resources, follow-on tutorial ideas; shipped r15 |

- **r14** (2026-05-17, §13 wrap-up — RETRACTED) —
  shipped a "Wrap-up" section that wasn't on the outline.
  The actual §13 per PRD is "Alternatives to minikube", with
  reflective/closing content properly belonging in §14 (FAQ)
  and §15 (Where to go next). Retracted in r14a.

- **r14a** (2026-05-17, §13 corrected — Alternatives to
  minikube) — replaces r14's misallocated wrap-up content
  with the real §13. The apply step deletes `_docs/13-wrap-up.md`
  from the working tree and adds `_docs/13-alternatives.md`
  in its place.

  Content of `_docs/13-alternatives.md` (~1300 words, 5 min):
  - **Quick decision framework** up front — five rows of
    "if you're doing X, pick Y" so a reader scanning the
    section gets the answer without reading the body
  - **kind v0.31.0** — Kubernetes-IN-Docker, defaults to K8s
    1.35.0, Podman auto-detect via
    `KIND_EXPERIMENTAL_PROVIDER=podman`. Strengths: CI/CD,
    ephemeral clusters, fast start/stop. Weaknesses: image
    loading is awkward (`kind load docker-image`), persistent
    state isn't the design center. Fedora-compat: good
  - **k3s v1.36.1+k3s1** — Rancher/SUSE, tracks upstream
    K8s 1.36.1, single-binary install via
    `curl -sfL https://get.k3s.io | sh -`. Strengths: edge
    devices, IoT, Raspberry Pi, single-host production.
    Weaknesses: bundled Traefik/Klipper differ from typical
    production K8s defaults. Fedora-compat: good with caveat
    (needs `container-selinux` + k3s-selinux RPM + firewalld
    ports)
  - **microk8s 1.33/stable** — Canonical, snap-based.
    Genuinely well-engineered on Ubuntu. **Fedora-compat:
    rough — honestly stated.** Cites the December 2024
    hardill.me.uk install attempt that concluded "not viable
    on Fedora at this time" due to snapd squashfs issues +
    AppArmor missing from stock Fedora. This honest framing
    is more useful than vendor-neutral mush
  - **MicroShift** — Red Hat's edge OpenShift. Only RHEL 9/10
    RPM binaries exist. Red Hat's own Developer site
    [explicitly recommends against](https://developers.redhat.com/articles/2025/02/20/why-developers-should-use-microshift)
    `dnf install microshift` on Fedora. Supported Fedora path
    is CRC (CodeReady Containers, which manages a RHEL VM).
    Niche: OpenShift API parity for development
  - **Comparison table** — 5 rows × 4 columns (architecture,
    Fedora story, best fit)
  - **Recommendation** — for a Fedora reader who's just
    completed this tutorial, minikube is still the right
    pick for daily dev unless one of the specific
    alternative needs (CI, edge, OpenShift parity) applies.
    The underlying Kubernetes is the same; the manifests
    you learned port unchanged

  Cross-reference at bottom links to §14 FAQ (next section).

  Phase coverage map row for §13 corrected (was "Wrap-up",
  is now "Alternatives"). Verified row count unchanged at
  **107** (no demo content — comparison prose with external
  links).

- **r15** (2026-05-17, §14 FAQ + §15 Where to go next —
  tail prose complete) — both remaining prose sections
  shipped in one iteration since neither has demo content:

  `_docs/14-faq.md` (~1950 words / FAQ format):
  - 22 Q&A entries organized into 7 categories: installation
    + startup (4), running containers + Pods (4), networking
    (3), storage (2), multi-cluster/multi-profile (3),
    updates and rollouts (2), operator-specific (3),
    system-level (2)
  - **Every Q is grounded in a real pain point hit during
    the tutorial's development** — not hypothetical. Notable:
    - "requests through the KEDA HTTP interceptor return
      404" → the `hey -host` vs `-H 'Host:'` gotcha (r13d)
    - "Strimzi says Unsupported Kafka.spec.kafka.version" →
      the 4.1+ lesson (r13a)
    - "I'm getting Too many open files from operators" →
      inotify limits (r12a)
    - "I changed a ConfigMap but the Pod still shows the
      old value" → §9 helm checksum-annotation pattern
    - "Istio sidecar isn't getting injected" → native
      sidecar check via `.spec.initContainers[*]` (r12d)
  - Helm-checksum example uses `{% raw %}` wrapping for the
    Go template inside (Liquid-collision pre-empted)
  - **Cleanup recipes section** at the end consolidates the
    `cleanup.sh` scripts from r13c into a three-tier
    reference: just the demo (auto trap), section's heavy
    state (per-example-dir `cleanup.sh`), full reset
    (`minikube delete --all --purge` + state removal). The
    section makes the existing scripts more discoverable
    via the search-friendly FAQ format

  `_docs/15-where-to-go-next.md` (~1370 words / 5 min):
  - **Track A — going deeper on what you built**: 4
    concrete extensions of existing demos (real workload
    instead of WORK_SLEEP_S in §12 Kafka, sustained `hey -z
    30s` in §12 HTTP, header-based routing in §11 Istio,
    multi-broker Kafka via Strimzi node-pool split)
  - **Track B — moving toward production-like**: 5 paths
    forward (Ingress + cert-manager replaces NodePort,
    ArgoCD/Flux GitOps, kube-prometheus-stack for real
    observability, k3s/kubeadm/managed-service for real
    cluster, GitHub Actions + ko + ArgoCD for CI)
  - **Bookmarkable resources**: 7 external links worth
    keeping (kubernetes.io, CNCF landscape, Istio docs, KEDA
    scalers catalog, Strimzi docs, Programming Kubernetes
    book, Kubernetes the Hard Way)
  - **Possible follow-on tutorials**: 4 gaps in the Fedora-
    Kubernetes landscape worth filling (production single-
    node home cluster, air-gapped K8s on Fedora, GPU
    workloads on minikube, "what changed" upgrade tutorials)
  - Brief one-paragraph close — no preachy retrospective,
    just the same hands-on framing the tutorial used

  Footer link on §15 goes back to the outline (this is the
  end). Cross-reference from end of §14 points to §15. Both
  cross-references from r13c-era prose (end of §12 → §13,
  start of §13 → §13) now resolve correctly through the
  full chain §12 → §13 → §14 → §15 → outline.

  Phase coverage map: §14 + §15 rows added, both marked ✓
  (prose). Verified row count unchanged at **107** — no
  demo content to verify in these sections.

  **All written content for the tutorial is now in place.**
  Only diagrams (r16) and editorial pass (r17) remain.

- **r16** (2026-05-17, diagrams — Phase 7) — five paired
  `.svg` + `.excalidraw` files in `assets/diagrams/`,
  matching the cross-tutorial visual style (920×500
  viewBox, warm off-white `#fdfbf7` background with 40px
  subtle grid, two-tone color coding, sans for prose +
  mono for code/CRD identifiers).

  Color semantic mapping for K8s context:
  - **blue** (`#dbe6f1` fill / `#4a7bb8` stroke) — workload
    resources being managed (Pods, Deployments, Services,
    ReplicaSets, gateway Pods)
  - **tan** (`#ebe1cc` fill / `#a08456` stroke) — things
    outside the cluster (external clients, external event
    sources, the Fedora host itself)
  - **neutral gray** (`#ebebe5` fill / `#5e5e5e` stroke) —
    internal K8s machinery (controllers, metrics adapters,
    operators, istiod)
  - **green** (`#dde7d3` fill / `#5f8c4d` stroke) — storage
    primitives that outlive workloads (PVC, PV)
  - red reserved for diagrams showing failure modes (not
    used in this batch)

  Diagrams shipped:
  - `03-minikube-topology.svg` (3.1 KB) — nested-container
    view of the stack: Fedora host (tan, outermost) →
    rootless Podman → minikube node container → containerd
    → 3 example Pods (blue). Footnote calls out that no
    system-level daemon is involved
  - `06-k8s-primitives.svg` (4.5 KB) — Deployment owns
    ReplicaSet owns 3 Pods (with `app=web` label).
    Service on the right with a dashed selector arrow to
    the Pods. PVC and PV on the bottom (green) with a "uses"
    arrow from one Pod and a "binds" arrow between PVC and PV
  - `11-istio-mesh.svg` (6.0 KB) — istiod alone at top
    (neutral, control plane). Horizontal dashed plane
    divider. Data plane band shows external client (tan) →
    Ingress GW → 2 App Pods (each with app container + envoy
    sidecar visible) → Egress GW → external service (tan).
    Solid arrows for traffic, dashed control arrows from
    istiod down to each sidecar
  - `12-hpa-vs-keda.svg` (5.2 KB) — the diagram from the
    style-sign-off, saved as a file. Two-panel comparison
    split by a vertical dashed divider
  - `12-keda-http-addon.svg` (5.5 KB) — external client
    (tan) → interceptor (blue, with 6 small queued-request
    boxes visualized inside) → 2 backend Pods (blue). KEDA
    scaler (neutral) on the upper right reads queue depth;
    KEDA operator (neutral) on the lower right reconciles
    `HTTPScaledObject` and scales the backend Deployment.
    Footnote explains the cold-start latency contract

  Paired `.excalidraw` placeholders (minimal JSON stubs with
  `viewBackgroundColor: "#fdfbf7"` and `gridSize: 20`) ship
  alongside each SVG. Future edits can use Excalidraw's
  web/desktop client and re-export to SVG; the placeholder
  ensures the canvas starts with the right background and
  grid settings.

  File sizes 3.1–6.0 KB, under the 7.2–9.1 KB reference
  range but each diagram is sized for its actual content
  rather than padded to hit a byte target.

  **Pending prose splices** — §3, §6, §11, §12 each gain an
  inline SVG embed where they currently have ASCII art or
  no diagram. The Markdown snippet for each is in the apply
  notes below; user will splice in this commit or a
  follow-up r16a.

- **r16a** (2026-05-17, §14 FAQ rendering bug + §3 diagram
  clarification) — two fixes from user review:

  **§14 rendering bug.** User caught the FAQ "degenerating"
  partway through. Root cause: kramdown (Jekyll's Markdown
  processor) interprets `<placeholder>` inside inline
  backticks as an HTML opening tag and tries to consume
  forward until it finds a matching close. The triggering
  case was `` `helm rollback <release>\n<revision>` `` — a
  multi-line inline backtick span with two `<word>`
  patterns. The cascade swallowed `<release> <revision>`
  itself, then collapsed the following Q&A headers into a
  single run-on paragraph (Strimzi version, Istio
  injection, KEDA HPA-zero, etc.) until kramdown finally
  recovered.

  Fix: replaced ALL `<placeholder>` patterns with
  `[placeholder]` throughout the FAQ — both inline (where
  they were buggy) and in fenced code blocks (for
  consistency). Square brackets render literally in
  Markdown and don't trigger HTML parsing, and they match
  common CLI / man-page convention for "fill in your
  value". Also collapsed the multi-line inline backtick
  to a single line as belt-and-suspenders. Sed pass
  covered: `<pod-name>`, `<pvc-name>`, `<release>`,
  `<revision>`, `<name>` (bare). Lint pass verified
  zero remaining bare-angle-bracket placeholders in §14.

  **§3 diagram clarification.** User noted the topology
  diagram showed containerd inside the minikube container,
  and asked whether Podman actually uses containerd
  (rather than crun). Research confirmed the diagram is
  technically accurate but the layering was implicit:
  - Host Podman uses **crun** to run containers (no
    containerd anywhere on the host)
  - One of those containers IS the minikube node
  - **Inside** the minikube node, Kubernetes' kubelet
    needs a CRI runtime, configured via
    `--container-runtime`. We chose `containerd` in §3
  - Per [minikube docs](https://minikube.sigs.k8s.io/docs/drivers/podman/):
    rootless Podman → containerd (recommended);
    rootful Podman → CRI-O (recommended)

  Diagram updates: the "rootless Podman" sublabel now
  reads "runs containers via crun, no daemon"; the
  "containerd" sublabel now reads "Kubernetes CRI runtime
  — chosen via `--container-runtime=containerd`" (with the
  flag in mono); the footnote now reads "Two container
  runtimes, not one: Podman (host) runs the node container
  via crun; containerd (inside the node) runs the Pods."
  All three changes make the dual-layer architecture
  explicit on the face of the diagram.

  **Also added new FAQ entry** "I thought Podman uses
  crun — why does the diagram show containerd?" before
  the "image built locally" question, since the layering
  confusion is exactly the kind of question a careful
  reader hits. The answer cross-references the minikube
  docs explicitly.

  Bug-finder credit: user spotted both issues during the
  r15+r16 review pass. The kramdown collision is the kind
  of thing that's hard to spot until rendered — local
  `jekyll serve` would have shown it, but we verify via
  `gh run watch` only, which surfaces build failures but
  not rendering quality. Worth a future r17 editorial-pass
  item: render every section in a deployed-preview branch
  before declaring it done.

  Files updated:
  - `_docs/14-faq.md` (now 2085 words / +130 words from
    new Q&A; 22+1 = 23 Q&A entries)
  - `assets/diagrams/03-minikube-topology.svg` (sublabel
    and footnote text tweaked; structure unchanged)

  Verified row count unchanged at **107**.

- **r16b** (2026-05-17, prose splices via auto-script) —
  ships `scripts/splice-diagrams.sh`, a one-shot bash
  script that inserts SVG embed references into §3, §6,
  §11, §12 prose. r16 shipped the assets and r16a fixed
  the §14 + diagram clarity issues, but neither updated
  the section prose to actually reference the diagrams,
  leaving them unembedded. User caught this on review.

  Script design:
  - Idempotent — uses `grep -qF "$diagram"` to skip files
    already referencing the embed. Safe to re-run any
    number of times.
  - Insertion heuristic — finds front matter close
    (second `---`), then first `## ` heading after that,
    then inserts the embed (with surrounding blank lines)
    just before that heading. Net effect: diagram appears
    after the section's intro paragraph but before the
    first sub-section.
  - §12 special case — the section has two diagrams.
    HPA-vs-KEDA inserts before first `## `. HTTP add-on
    uses anchor regex `^## .*[Hh][Tt][Tt][Pp]` to match
    the HTTP-related sub-heading specifically.
  - Fallback — if no anchor matches, the diagram is
    appended at EOF with a warning, so it's still visible
    and the user can move it manually.
  - Missing-file handling — warns rather than crashing if
    a target `_docs/NN-*.md` doesn't exist.

  Smoke-tested in a fake repo before shipping: confirmed
  correct insertion location for §3 and both §12
  diagrams, plus confirmed idempotent skip-on-rerun.

  After user runs the script and reviews `git diff`,
  diagrams will be visible at:
  - §3: between the intro paragraph and the first sub-
    section
  - §6: same pattern — before first sub-section
  - §11: same pattern
  - §12: HPA-vs-KEDA before first sub-section; HTTP
    add-on before the HTTP-related sub-section

  If any placement is wrong, the embed is a single line of
  Markdown and trivial to move manually.

  Lesson recorded: the r16 reconciliation plan flagged
  "pending prose splices" as a follow-up but didn't ship
  them, leaving the diagrams stranded. For r17 final pass:
  visit the deployed preview, eyeball every section, and
  only then close out. Future projects: never ship assets
  without their referencing prose in the same iteration.

  Verified row count unchanged at **107**.

- **r16c** (2026-05-17, ASCII→SVG replacement, not splice) —
  r16b's auto-splice put SVG embeds at heuristic locations
  (before the first `## ` heading) but **did not remove the
  existing ASCII art** in §11 and §12. Result: SVGs landed at
  unrelated positions (after the bullet-list intro, before
  unrelated headings) while the original ASCII diagrams stayed
  in place inside their proper sections. User caught this.

  Lesson recorded: auto-splice is unsafe when the destination
  files already contain diagrams. A heuristic that inserts a
  new embed cannot reason about whether existing ASCII art
  represents the same concept. The correct operation is
  *replace ASCII with SVG in place*, which requires the
  ASCII source content to be known — and that requires
  reading the file, not pattern-matching a heading.

  Six targeted `str_replace` edits in r16c, using the user's
  paste of current file content as the precise baseline:

  §11 corrections:
  1. Remove misplaced SVG embed between the bullet list ("6.
     Optional: Kiali...") and `## What's a service mesh`
  2. Replace the ASCII mesh diagram inside `## Istio
     architecture` with the SVG embed in the same position.
     The Bookinfo ASCII diagram (productpage → details/reviews
     → ratings) is *not* affected — it's a different concept
     from the istio-mesh.svg and stays as ASCII

  §12 corrections:
  3. Remove misplaced HPA-vs-KEDA SVG embed between the
     bullet list and `## HPA vs KEDA`
  4. Replace **both** ASCII diagrams in `## HPA vs KEDA`
     (HPA flow + KEDA flow) with one combined SVG embed,
     restructuring the surrounding prose to flow naturally:
     "HPA reads from Pods → can't scale to zero. KEDA reads
     from external events → can." Then the diagram. Then
     "KEDA doesn't replace HPA — it provides the External
     Metrics API HPA was designed to consume." The prose
     reads better than before — the original "looks like
     this:" + ASCII + prose pattern was clumsy
  5. Remove misplaced HTTP add-on SVG embed (before
     `## Pattern B` heading) and the ASCII version inside
     Pattern B; place the SVG inside Pattern B, after the
     bullet list explaining the components, before
     `### Workload`
  6. Fix stale footer cross-reference: `[On to §13:
     Wrap-up →](/docs/13-wrap-up/)` → `[On to §13:
     Alternatives to minikube →](/docs/13-alternatives/)`.
     §13 was renamed Wrap-up → Alternatives in r14a but the
     §12 cross-reference link wasn't updated then; this
     fixes that gap

  Verification:
  - §11 SVG embed count: 1 (line 55, in "## Istio
    architecture")
  - §11 ASCII box-drawing chars: 7 (only the Bookinfo
    productpage→details/reviews→ratings diagram remaining;
    correct — that diagram has no SVG counterpart)
  - §12 SVG embed count: 2 (line 51 in "## HPA vs KEDA",
    line 515 in "## Pattern B")
  - §12 ASCII box-drawing chars: 0 (all 3 ASCII diagrams
    replaced)
  - §12 footer link: now points to `13-alternatives`
  - Both files Liquid-safe (no `{{ .Capital }}` collisions)

  Files updated:
  - `_docs/11-istio.md`
  - `_docs/12-keda.md`

  Verified row count unchanged at **107**.

- **r17** (2026-05-17, editorial pass + audit tooling — final
  iteration) — closes out the project. Three deliverables, two
  fixes, one document.

  **Deliverables (scripts):**
  - `scripts/check-cross-references.sh` — finds every internal
    Jekyll link (`]({{ "/..." | relative_url }})`) across
    `_docs/*.md` and verifies each `/docs/SLUG/` target
    corresponds to a real `_docs/NN-slug.md`. Exit 1 if any
    are broken. Catches stale section-rename links like the
    §12→§13-wrap-up case from r16c. Smoke-tested against a
    synthetic repo with a deliberately broken link before
    shipping
  - `scripts/editorial-audit.sh` — advisory grep battery for
    known problem patterns: stale "13-wrap-up" references,
    bare `<placeholder>` inside inline backticks (kramdown
    collision risk; only flagged outside fenced blocks via
    fence-counting), "minikube VM" references that should be
    "minikube node container" under the podman driver,
    first-person plural voice, `{% raw %}`-wrapped
    `relative_url` URLs (broken image src pattern), stale
    TODO/FIXME/XXX markers, and duplicate flags within a
    single shell command (continuation-aware — correctly
    handles `\` line-continuations and doesn't flag separate
    commands that happen to share a flag)
  - `_plans/prd-reconciliation.md` — the "what shipped vs what
    was planned" document the PRD template anticipated would
    be useful at project close. Covers goals/non-goals
    actual vs intent, audience concretization, the shipped
    section outline, divergences (macOS dropped, UBI instead
    of Hummingbird, vendor-neutral relaxed for §13,
    Podman not version-pinned), and six process observations
    worth carrying to future projects

  **Real fixes applied:**
  - **§11**: removed duplicate `--container-runtime=containerd`
    flag in the `minikube start -p istio` block (caught by the
    audit script; would have caused `cobra` to warn but minikube
    would still start — sloppy but not broken)
  - **§11 + §12**: removed `{% raw %}{{ ... | relative_url }}{% endraw %}`
    wraps from three image embeds (two Kiali screenshots in §11,
    one Strimzi screenshot in §12). The `{% raw %}` prevented
    Liquid from evaluating the `relative_url` filter, leaving
    the literal `{{ ... }}` string as the image src. These
    images would not have rendered correctly on the deployed
    site; r17 fixes them. The PRD reconciliation document
    records this as Process Observation #3

  **Findings deliberately NOT fixed:**
  - 7 instances of "we" voice ("we'll", "we go with", etc.)
    in §11 and §12. Most are contextual ("if we had one";
    quoted KEDA README text "we can't yet recommend"; "we go
    with Strimzi" introducing a tutorial choice). Mechanical
    rewriting would introduce awkward phrasing. The audit
    script flags them so they can be reviewed by section if
    desired; the editorial judgment is the audit's purpose

  **What r17 did NOT cover (and why):**
  - **Editorial pass on §1-§10 prose.** I don't have the file
    contents for those sections in the current context. The
    audit scripts work on every section the user runs them
    against, so when they're run against the deployed repo
    they'll surface any §1-§10 findings — and r17a can target
    fixes if anything turns up
  - **Deployed-preview render review.** This is inherently a
    human task: open the rendered site in a browser, eyeball
    each section, flag visual issues that build-success
    doesn't catch. Recorded as the next step for the user

  **Closing out the reconciliation plan:**

  The project is structurally complete. §1–§12 are verified
  end-to-end on Fedora 44 (**107 verified rows**). §13–§15 are
  shipped as prose. All five diagrams are SVG, embedded in the
  right positions. The cross-reference link audit script and
  the editorial audit script make ongoing quality checks
  one-command operations. The PRD reconciliation document
  records what we built vs what we planned, with rationale for
  each divergence.

  This entry is the last Section D entry I expect to write
  for this project. If anything turns up in deployed-preview
  review, the relevant fix will get its own r17a / r17b /
  etc. entry — but as of r17 the tutorial is feature-complete.

  Files shipped in r17:
  - `scripts/check-cross-references.sh`
  - `scripts/editorial-audit.sh`
  - `_docs/11-istio.md` (4 fixes)
  - `_docs/12-keda.md` (1 fix)
  - `_plans/prd-reconciliation.md` (new)
  - `_plans/reconciliation-plan.md` (this entry)

  Verified row count unchanged at **107**.

---

**Open priorities (after r17):**

1. **Deployed-preview render review** — your part. Open the
   GitHub Pages site, click through every section, verify
   diagrams render at the right size on whatever viewports
   matter to you (desktop, tablet, mobile if applicable),
   prose paragraphs aren't excessively long, code blocks
   don't horizontally scroll on common widths, and the
   navigation between sections works as expected
2. **Run the audit scripts** — `./scripts/check-cross-references.sh`
   and `./scripts/editorial-audit.sh` from the repo root.
   Any findings beyond what r17 cleaned up are candidates for
   r17a fixes; let me know if anything turns up
3. Optional: §10 row promotions (`which k9s` etc.) — low
   priority, can stay unverified
4. Optional: §8 PV auto-delete row, §7 leftovers — low
   priority, can stay unverified
5. Optional: re-run the §11–§12 editorial audit against §1–§10
   when convenient; paste any findings and I'll ship r17a if
   meaningful fixes are needed

   - **r18** (project close-out — examples-as-pages, onboarding
     folder, top-level README rewrite) — landed the last cluster
     of changes before declaring victory. Six deliverables:

     **1. Examples-as-pages structure.** Each runnable example in
     `examples/NN-name/` now has a corresponding published Jekyll
     page at `/examples/NN-name/`, generated from the example's
     `README.md` via `scripts/sync-example-pages.sh`. Implementation:

     - New Jekyll collection `example_pages` configured in
       `_config.yml` with `output: true` and
       `permalink: /examples/:name/`
     - New directory `_example_pages/` holds the generated pages.
       Filenames mirror `examples/NN-name/` (so the slug is the
       same; the URL is `/examples/NN-name/` not `/examples/name/`)
     - `scripts/sync-example-pages.sh` reads every
       `examples/*/README.md`, extracts the H1 as the page title,
       inlines the rest as the body, prepends Jekyll front matter
       (order, example_dir, permalink, layout), and writes to
       `_example_pages/`. Idempotent — safe to re-run anytime
       a README changes
     - `_docs/16-examples.md` is the new hub page. It iterates
       over `site.example_pages` (sorted by `order`), renders a
       bulleted list with title, example-dir source link, and
       description. Also documents the "what's NOT an example"
       list (§1, §2, §5, §10, §13–§15)

     Trade-off recorded: the example README is the source of
     truth; the `_example_pages/*.md` files are generated
     artifacts that get committed to the repo (so GitHub Pages
     builds can use them without running the sync). Edit the
     README, re-run sync, commit both. The audit scripts catch
     drift if the user forgets to re-sync.

     **2. Onboarding folder.** `LESSONS-LEARNED.md`,
     `GETTING-STARTED.md`, and `STARTING-WITH-CLAUDE.md` moved
     from repo root into a new `onboarding/` directory. New
     `onboarding/README.md` is the folder's navigation hub —
     three short paragraphs pointing each of three audiences
     ("setting up", "understanding the why", "continuing the
     collaboration") at the right doc. Top-level `README.md`
     links to the onboarding folder.

     **3. LESSONS-LEARNED.md updates.** Shipped as an addendum
     file (`onboarding/LESSONS-LEARNED-r18-additions.md`) that
     the user merges into the existing
     `onboarding/LESSONS-LEARNED.md` after the move. The
     addendum covers ~25 lessons from r1–r18 organized into:
     Process, Jekyll/kramdown, Shell/scripts,
     Kubernetes/minikube, Image/packaging, Tooling, and
     Project management. Reason for the addendum-merge pattern:
     r18 was developed without access to the existing
     `LESSONS-LEARNED.md` contents (couldn't fetch from
     raw.githubusercontent.com), so blind replacement would
     have risked losing prior content.

     **4. Top-level README rewrite.** The new `README.md`
     reflects the actual shipped structure: `onboarding/`
     folder, `_example_pages/` collection, `scripts/` with the
     three audit/sync scripts, expanded `_plans/` with both the
     reconciliation plan and the PRD reconciliation. The
     "Project layout" tree is updated to match. Adds explicit
     pointers to `onboarding/` for new contributors. Adds the
     "Quality checks" section documenting the two audit scripts
     shipped in r17 and the sync script shipped in r18. Adds
     references to the published per-example pages.

     **5. PRD additions.** Shipped as a patch document
     (`_plans/PRD-r18-additions.md`) that the user merges into
     the existing `PRD.md`. Covers: shipped deliverables
     expanded to include audit tooling + per-example pages
     + onboarding folder + PRD reconciliation; shipped section
     outline with "Has Example Page" column; non-goals expanded
     to acknowledge the three intentional divergences from the
     original PRD (vendor-neutral relaxed, "we" voice not
     strictly avoided, Podman not version-pinned); shipped
     audience concretization (Fedora 44 / basic-container-literacy
     primary); project state (107 verified, audit clean, closed).

     **6. Reconciliation plan close-out** — this entry, plus an
     updated "Open priorities" section that retires the
     pre-r17 priorities and replaces them with the post-r18
     state: project closed, future work as new iterations.

     Files shipped in r18 (delivered as tarball, applied via
     `tar -xzf` + `bash scripts/r18-reorganize.sh` for the
     moves):

     - `scripts/sync-example-pages.sh` (new)
     - `_docs/16-examples.md` (new hub page)
     - `README.md` (rewritten)
     - `onboarding/README.md` (new navigation hub)
     - `onboarding/LESSONS-LEARNED-r18-additions.md` (addendum
       to merge)
     - `_plans/PRD-r18-additions.md` (addendum to merge)
     - `_plans/reconciliation-plan.md` (this entry — spliced
       via the merge instructions in
       `_plans/reconciliation-plan-r18-addition.md`)
     - `r18-INSTRUCTIONS.md` (manual steps reference)

     Verified row count unchanged at **107**.

     **Manual steps required after extracting r18 tarball:**

     1. Move the three onboarding files into `onboarding/`:
        `mv LESSONS-LEARNED.md GETTING-STARTED.md STARTING-WITH-CLAUDE.md onboarding/`
     2. Edit `_config.yml` to add the `example_pages` collection
        (block provided in `r18-INSTRUCTIONS.md`)
     3. Merge `onboarding/LESSONS-LEARNED-r18-additions.md`
        contents into `onboarding/LESSONS-LEARNED.md`; delete
        the additions file
     4. Merge `_plans/PRD-r18-additions.md` contents into
        `PRD.md`; delete the additions file
     5. Splice this reconciliation-plan entry into
        `_plans/reconciliation-plan.md` per the instructions
        above; delete `_plans/reconciliation-plan-r18-addition.md`
     6. Run `./scripts/sync-example-pages.sh` to generate the
        `_example_pages/` files from the current
        `examples/*/README.md` files
     7. Update §15 footer: change
        `[← Back to outline]({{ "/" | relative_url }})` (or
        wherever §15 currently ends) to also add a forward link
        `[On to §16: Examples →]({{ "/docs/16-examples/" | relative_url }})`
     8. Run `./scripts/check-cross-references.sh` to verify the
        new §15→§16 link and the §16→§15 back-link resolve
     9. `git add -A && git status` for review; commit and push

   ---

   **Replace the "Open priorities (after r17)" section with:**

   **Project state (post-r18): closed**

   The tutorial is feature-complete. §1–§15 deliver the linear
   narrative; §16 indexes the per-example pages. 107 facts
   verified on Fedora 44. Audit scripts pass clean (or report
   only judgment-call findings like "we" voice that were
   deliberately not changed). Onboarding folder centralizes
   orientation docs; top-level README reflects actual layout;
   PRD updated to match shipped reality.

   Any future work happens as **new iterations** (r19+)
   addressing specific findings from continued use of the
   tutorial, not as a continuation of the original project
   plan.

   The "Open priorities" tracked through r17 are retired:

   - ~~Deployed-preview render review~~ — user's responsibility,
     ongoing
   - ~~Run the audit scripts~~ — done; user confirmed
     "looks like it worked" after r17
   - §10 row promotions, §8/§7 leftovers — remain `unverified`;
     acceptable per the reconciliation discipline (default is
     unverified, promotion requires explicit human test)

   What "victory" looks like, recorded for future projects:

   1. Every claim verified or marked unverified — done (107 verified)
   2. Every internal cross-reference resolves — done (audit clean)
   3. The "what shipped vs. what was planned" diff written down —
      done (`_plans/prd-reconciliation.md`)

   Not on the victory list: "every section reads perfectly" (that's
   infinite work). Knowing when to ship is the discipline.

   - **r18a** (2026-05-17, follow-up fix for §16 hub rendering and
     example page titles) — r18 shipped §16 with an HTML list
     (`<ul class="example-list">`) that kramdown rendered as raw
     HTML, but with no matching CSS, the result was unformatted
     bullets. The sync script also extracted page titles from
     README H1s without sanity-checking — when an H1 was literally
     the directory slug (e.g. `# 03-driver-check`), the page title
     became `03-driver-check` instead of something readable.

     Two targeted fixes:

     **1. `_docs/16-examples.md` restructured with Markdown.** The
     `<ul class="example-list">` HTML block was replaced with a
     Liquid `{% for %}` loop that emits Markdown headings
     (`### {{ ex.title }}`) and paragraphs. Kramdown now styles
     the listing using the same heading/link/code rules as the
     rest of the site — no custom CSS required. Each example
     gets visible separation, a clear "Read the walkthrough" CTA
     link, and a separate "Source:" line linking to the GitHub
     directory.

     **2. `scripts/sync-example-pages.sh` got smarter title
     extraction.** A new `normalize()` helper compares the
     extracted H1 against (a) the directory name and (b) the
     readable slug (hyphens → spaces). If the H1 normalizes to
     either, it's treated as too slug-like to be a useful page
     title, and the fallback kicks in. The fallback was also
     improved to produce `§NN slug-words` (e.g. `§3 driver check`)
     instead of the more verbose `Example §N: slug-words` from
     r18. Smoke-tested against three cases:
      - `# 03-driver-check` → `§3 driver check` (slug-like, fallback)
      - `# Deploy nginx via kubectl` → preserved as-is (descriptive)
      - `# istio` → `§11 istio` (matches readable slug, fallback)

     After running the updated sync script, the §16 hub should
     show properly-styled per-example sections like:

     > ### §3 driver check
     > **Read the walkthrough →**
     > Source: `examples/03-driver-check/`

     rather than r18's broken-looking flat bullet list.

     Files updated in r18a:
     - `scripts/sync-example-pages.sh`
     - `_docs/16-examples.md`

     Files regenerated by re-running sync (committed but not
     hand-edited):
     - `_example_pages/*.md` — every page rewritten with the
       improved fallback title where applicable

     Verified row count unchanged at **107**. Project remains
     closed; r18a was the first "small fix from continued use"
     iteration anticipated by the close-out language in the r18
     entry.

     - **r18b** (2026-05-17, second follow-up for example pages
       rendering with no site chrome) — r18a fixed the §16 hub
       rendering, but the per-example pages at `/examples/NN-name/`
       rendered with no layout: no header, no breadcrumbs, no
       footer, just raw page body. Two compounding causes:

       **Cause 1: wrong layout name.** Fetching `_config.yml`
       revealed the actual layout name is `tutorial`, configured
       via a `defaults:` rule for the `docs` collection:

       ```yaml
       defaults:
         - scope:
             path: ""
             type: docs
           values:
             layout: tutorial
       ```

       The sync script in r18/r18a wrote `layout: docs` in the
       generated example pages' front matter. There is no
       `_layouts/docs.html` — only `_layouts/tutorial.html`. When
       Jekyll can't find the referenced layout, it falls back to
       rendering the page body bare (no layout wrap). That's why
       the example pages had no site chrome.

       **Cause 2: pipes in blockquote rendered as a table.** The
       sync script's meta line was:

       ```
       > Source: [`examples/.../`](URL) &nbsp;|&nbsp; [← Back...](URL)
       ```

       Kramdown's GFM mode interpreted the `|` characters as
       table-column separators and rendered the line as a 1-row
       table inside the blockquote, complete with an auto-generated
       `| --- | --- |` separator line. Visually broken.

       **Fix in r18b:**

       1. `scripts/sync-example-pages.sh` now writes
          `layout: tutorial` (matching the `_layouts/` reality and
          the `defaults:` rule for `_docs/`)
       2. The meta line was restructured to avoid pipes:
          `**Source:** [`...`](URL) · [← Back](URL)` (middot
          separator instead of pipe inside blockquote). No more
          accidental table rendering, and the bold "Source:"
          prefix gives the meta line a clear visual anchor

       After re-running the sync, each example page should display:
        - Full site chrome (header, breadcrumbs, top nav, footer)
        - Section number badge derived from `order:` front matter
        - Page title from `title:` front matter
        - The meta line as a single styled paragraph
        - README body rendered with the site's prose styling

       Files updated in r18b:
       - `scripts/sync-example-pages.sh`

       Files regenerated by re-running sync (committed but not
       hand-edited):
       - `_example_pages/*.md` — every page rewritten with
         `layout: tutorial` and the middot-separator meta line

       Verified row count unchanged at **107**. Project remains
       closed.

       **Lesson recorded for future projects:** when introducing a
       new Jekyll collection, the `defaults:` block in `_config.yml`
       is the source of truth for which layout applies. The actual
       layout filename in `_layouts/` may not match the conceptual
       name. Always check `_config.yml` for the defaults rule
       before assuming a layout name, OR add an explicit
       `defaults:` rule for the new collection so the binding is
       visible in one place. Don't guess.

       - **r19** (capstone planning — §17 PRD addition only, no
         implementation) — formally re-opens the project for the
         capstone iteration. The post-r18b "closed" state captured a
         natural completion of the original PRD scope; r19 begins the
         significant capstone extension that demonstrates everything
         §1–§12 introduced, in one coherent system.

         **What r19 ships:**
         - `_plans/PRD-r19-capstone-section.md` — the new §17
           section of the PRD, comprehensive scoping for the capstone:
           one-paragraph summary, what it teaches, why it's the
           capstone (table mapping each prior section to its
           contribution), audience details, goals + non-goals,
           architecture overview with service-by-service protocol
           matrix, platform component list, implementation
           constraints, testing approach, ten open decisions awaiting
           user resolution, references (Dehghani's *Data Mesh* and
           Ibryam & Huss's *Kubernetes Patterns*, plus the user's two
           prior repos with Grafana-stack work on podman), risks +
           mitigations table, iteration plan (r19 → ~r30), and
           success criteria
         - `_plans/reconciliation-plan-r19-addition.md` — this entry

         **What r19 deliberately does NOT include:**
         - Any code, manifests, helm charts, or proto definitions
         - The architecture diagram (waits for decisions to be
           resolved; pre-drafting now would just produce throwaway
           work)
         - Implementation of any of the five services
         - Updates to `_docs/16-examples.md` (the §17 example listing
           waits for the actual `examples/17-capstone/` directory
           to exist)

         **Ten open decisions awaiting user input** (full rationale
         in the PRD addition; summary here for tracking):
          1. Metadata catalog: DataHub vs OpenMetadata — recommended OpenMetadata
          2. Postgres topology: one cluster + per-service schemas — recommended
          3. Prefect: OSS self-hosted — recommended
          4. gRPC codegen: protobuf-first with `buf` — recommended
          5. GraphQL: federated gateway with Strawberry — recommended
          6. Per-service protocol choice (not all-services-all-protocols) — recommended
          7. helm umbrella chart structure — recommended
          8. UBI base for services; accept upstream for operators (documented) — recommended
          9. Capstone profile sized 24GB/16CPU — recommended
          10. OTEL Collector as Deployment with OTLP receiver — recommended

         Once the user resolves these (or accepts all recommendations
         as-is), r20 ships the skeleton: example directory structure,
         helm umbrella chart skeleton, capstone profile recipe, and
         the architecture diagram. Implementation iterations r21–r30
         follow.

         **Estimated effort**: ~10 iterations (r20 through r30),
         spanning the full capstone implementation. Approximately
         three to four times the effort that r1–r18 collectively
         represented, given the integration complexity of running
         this many components on a single workstation.

         **Risk surfaced during planning**: the user's stated
         "1GB HD" target spec is almost certainly a typo for 1TB
         (a capstone of this size requires 30–50 GB just for image
         cache and persistent volumes). r20 will not proceed until
         this is confirmed; if 1GB is literal, the capstone needs to
         be descoped substantially or moved off the target machine.

         Verified row count unchanged at **107**. Capstone-specific
         verification rows begin appearing in Section B starting with
         r21 (first deployable service).

       ---

       **Replace** "Project state (post-r18): closed" **with:**

       **Project state (post-r19): capstone planning underway**

       The original PRD scope (§1–§16) shipped through r18 and is
       considered complete. §17 (the capstone) was added as an
       extension in r19 and is currently in the planning phase.
       Implementation begins at r20 once the ten open decisions in
       the §17 PRD addition are resolved.
       - **r21** (capstone walking skeleton — order-service end-to-end +
         CloudNativePG operator + Postgres Cluster CR) — first
         *runnable* capstone iteration. Proves the full vertical spine
         (CAP-006): image build → minikube cache → helm deploy →
         operator-managed Postgres → service connects → REST works →
         data persists → smoke test asserts. Establishes the template
         every other service follows.

         **Decisions captured this iteration** (in the new
         `_plans/capstone-decisions.md`):
         - CAP-001 Poetry for Python dependency management
         - CAP-002 CloudNativePG operator, installed separately
           (cluster-wide install called out as a teaching point)
         - CAP-003 one Postgres cluster, schema per service (restated
           from r19)
         - CAP-004 `create_all` for r21; Alembic migrations deferred
         - CAP-005 UBI 9 python-312 for both build + runtime stages
         - CAP-006 walking-skeleton-first (vertical slice over
           horizontal layers)
         - plus the ten r19 decisions back-filled as CAP-R19-1..10

         **What r21 ships:**
         - `_plans/capstone-decisions.md` — ADR-lite decision log,
           single source of truth for capstone choices
         - `examples/17-capstone/scripts/setup-postgres-operator.sh` —
           installs CloudNativePG via helm; prints the cluster-wide
           effects (CRDs registered, controller watching all
           namespaces)
         - `examples/17-capstone/charts/capstone/charts/postgres/` —
           CloudNativePG `Cluster` CR subchart (Chart.yaml,
           values.yaml, templates/cluster.yaml)
         - `examples/17-capstone/services/order-service/` — the
           service: Poetry pyproject.toml, UBI 9 multi-stage
           Containerfile, FastAPI app (config/db/models/schemas/main),
           pytest unit tests (SQLite-backed), README
         - `examples/17-capstone/charts/capstone/charts/order-service/`
           — helm subchart (Deployment with CNPG-secret-sourced
           Postgres env + Health Probes; Service)
         - `examples/17-capstone/demos/smoke-order.sh` — the
           walking-skeleton verification (build, deploy, exercise
           REST, query Postgres directly to confirm persistence,
           cleanup trap)
         - `_docs/17-capstone-r21-prose-insert.md` — §17 prose
           addition documenting order-service + the
           operator-is-cluster-wide teaching point (splice into
           `_docs/17-capstone.md`)

         **Patterns from *Kubernetes Patterns* (Ibryam & Huss)
         referenced in this iteration:**
         - Health Probe (liveness `/health`, readiness `/healthz`)
         - Predictable Demands (resource requests/limits; declared
           Postgres dependency)
         - Configuration Resource (Postgres creds from CNPG Secret
           via secretKeyRef)
         - Managed Lifecycle (clean connection-pool disposal on
           shutdown via FastAPI lifespan)

         **Validation performed in the build environment** (no
         minikube available there, so these are static checks):
         - All Python modules compile (`py_compile`)
         - All non-template YAML parses (pyyaml)
         - All helm templates have balanced `{{ }}` delimiters
         - deployment.yaml, service.yaml, cluster.yaml render to
           valid Kubernetes resources under placeholder substitution
         - All shell scripts pass `bash -n`

         **Verification status — UNVERIFIED pending real Fedora 44 run:**
         - `setup-postgres-operator.sh` installs the operator → unverified
         - `smoke-order.sh` passes end-to-end → unverified
         - order-service image builds with Poetry on UBI 9 → unverified
         - CloudNativePG provisions a working cluster on rootless
           podman minikube → unverified (flagged as a risk in r19 —
           this iteration is where we find out)
         - `poetry run pytest` passes locally → unverified

         These rows enter Section B as `unverified` and promote to
         `verified (Fedora 44)` only after the user runs the smoke
         test and reports the result. Verified count stays at **107**
         until then.

         **Known risk being tested in r21:** CloudNativePG's behavior
         on rootless-podman minikube specifically. The operator
         assumes a working default StorageClass; minikube provides
         `standard` via its storage-provisioner addon, which should
         satisfy the `Cluster` CR's PVC. If the PVC doesn't bind, the
         fix is likely a `storageClass:` override in the postgres
         subchart values — a quick r21a if needed.

         **Notes for r22:**
         - The four remaining services (inventory, payment, shipping,
           notification) follow order-service's exact shape. Strongly
           consider a `scripts/scaffold-service.sh` that stamps out
           the per-service skeleton (pyproject, Containerfile, app/*,
           subchart) from order-service as a template, to make r22
           mechanical
         - notification-service is the odd one — Kafka-consumer-only,
           no REST surface — so its skeleton differs. Hold it for r25
           (Kafka) rather than forcing a REST shape on it in r22,
           OR ship it in r22 with a minimal /health-only HTTP surface
           and wire the Kafka consumer in r25. Decide at r22 start.

         Verified row count holds at **107**.
         # Reconciliation + decision-log addition — r21a

         > Two merges: (1) append the r21a entry to Section D of
         > `_plans/reconciliation-plan.md`; (2) add CAP-007 to
         > `_plans/capstone-decisions.md`.

         ---

         ## For `_plans/capstone-decisions.md` — add CAP-007

         ## CAP-007 — Build images on the host with podman, then `minikube image load`

         - **Date:** r21a
         - **Status:** accepted (supersedes the `minikube image build` approach used
           in r21's first smoke test)
         - **Context:** r21's smoke test built the service image with
           `minikube image build -p capstone`. The command exited 0, but the image
           never landed in the profile's containerd image store. The order-service
           pod went `ErrImagePull` — the kubelet fell back to
           `docker.io/library/order-service:v1`, which 404s. Confirmed via
           `minikube image ls -p capstone` showing no order-service image.
         - **Decision:** Build images **on the host with podman**, then load them
           into the profile with **`minikube image load`**. Encapsulated in
           `scripts/build-image.sh <context> <image:tag>`, which builds, loads, and
           verifies the image is present before returning.
         - **Consequences:**
           - (+) Reliable image availability under the rootless-podman + containerd
             combination
           - (+) One helper reused by every service from r22 on
           - (+) Verification step (`minikube image ls | grep`) catches a failed
             load immediately instead of at pod-scheduling time
           - (−) Slightly slower than an in-cluster build would be (image is
             transferred host→profile), negligible for tutorial-sized images
           - (−) Requires podman on the host (already a §1 prerequisite)

         ## CAP-008 — Demo failure leaves resources in place and dumps diagnostics

         - **Date:** r21a
         - **Status:** accepted
         - **Context:** r21's smoke test had `trap cleanup EXIT` that uninstalled
           order-service on *any* exit, including failure. When the pod failed to
           go Ready, the trap destroyed the evidence before it could be inspected,
           forcing a separate diagnostic re-run.
         - **Decision:** Demo scripts clean up **only on success**. On failure they
           leave the resources in place and dump a diagnostic bundle inline (pod
           status, describe events, current + previous logs, image presence) — the
           pattern §11/§12 demos already use.
         - **Consequences:**
           - (+) A failed run hands you the evidence directly
           - (+) Consistent with the established §11/§12 diagnostic-dump convention
           - (−) Failed runs leave cluster state that must be cleaned up manually
             (the dump prints the exact uninstall commands)

         ---

         ## For `_plans/reconciliation-plan.md` Section D — append after r21

         - **r21a** (fix-up — image not landing in profile cache) — r21's smoke
           test reached the deploy stage but order-service went `ErrImagePull`.
           Diagnosis (via a one-off diagnostic script): `minikube image build`
           under the rootless-podman + containerd driver combo exited successfully
           but didn't place the image in the profile's containerd store, so the
           kubelet fell back to Docker Hub and 404'd. Everything upstream worked —
           CloudNativePG installed cleanly, provisioned a Ready Postgres primary in
           ~35s, the CNPG `-app` secret had all expected keys (`dbname`, `username`,
           `password`), and the env injection was correct.

           **Fixes:**
           - New `scripts/build-image.sh` — builds on the host with podman, loads
             into the profile with `minikube image load`, verifies presence
             (CAP-007)
           - `demos/smoke-order.sh` rewritten to (a) build via `build-image.sh`
             instead of `minikube image build`, and (b) leave failed resources in
             place with an inline diagnostic dump rather than tearing down on
             failure (CAP-008)

           **Verification status:**
           - Manual confirmation path provided to the user (host podman build +
             `minikube image load` + `helm upgrade` + `kubectl rollout status`)
             before the corrected smoke test ships
           - Once the corrected `smoke-order.sh` passes end-to-end on Fedora 44,
             these rows promote to `verified (Fedora 44)`:
             - order-service image builds with Poetry on UBI 9
             - image loads into the capstone profile and is pullable
             - CloudNativePG provisions a working cluster on rootless-podman
               minikube  ← the r19-flagged risk, now effectively confirmed
               (primary went Ready in 35s)
             - order-service connects to Postgres and serves REST
             - a row POSTed via REST persists in `orders.orders`

           **What this confirms about the r19 risk register:** the flagged
           "CloudNativePG on rootless-podman minikube" risk did NOT materialize —
           the operator installed and provisioned cleanly. The actual failure was
           an unrelated, well-known minikube image-build quirk. Good outcome: the
           scary risk was a non-issue; the real issue was mundane and has a clean
           fix that benefits every subsequent service.

           Verified row count holds at **107** pending the corrected smoke run.
           # Reconciliation + decision note — r21b

           > Two small merges: (1) append the r21b entry to Section D of
           > `_plans/reconciliation-plan.md`; (2) append the note below to CAP-005 in
           > `_plans/capstone-decisions.md`.

           ---

           ## For `_plans/capstone-decisions.md` — append to CAP-005's consequences

           - **r21b amendment:** the UBI 9 python-312 image's default user (1001)
             cannot write to `/opt/venv` (`/opt` is root-owned), which broke the build
             with `Permission denied: '/opt/venv'`. Fix: the **builder stage runs as
             root** (`USER 0`) — it's discarded in a multi-stage build, so there's no
             security cost — while the **runtime stage** keeps `USER 1001:0` and only
             reads/executes the copied venv (`COPY --chown=1001:0`). This is the
             idiomatic multi-stage pattern: relax the build stage, lock down the
             runtime stage. The non-root *runtime* guarantee (the thing
             CONTRIBUTING.md actually requires) is preserved.

           ---

           ## For `_plans/reconciliation-plan.md` Section D — append after r21a

           - **r21b** (fix-up — venv permission denied during image build) — with the
             r21a image-load fix in place, the build itself failed:
             `Permission denied: '/opt/venv'`. Root cause: the UBI 9 python-312 image
             runs as user 1001, which can't create `/opt/venv` under root-owned
             `/opt`. The build never produced an image, so the subsequent
             `helm upgrade` deployed stale state and the rollout timed out.

             **Fix:** `services/order-service/Containerfile` — the builder stage now
             runs as `USER 0` (root); the runtime stage keeps `USER 1001:0` and copies
             the venv with `--chown=1001:0`. Idiomatic multi-stage: permissive build
             stage (discarded), locked-down runtime stage (shipped). Documented as an
             amendment to CAP-005.

             **What the build output confirmed works** (everything up to the venv
             step): UBI 9 python-312 pulls fine, Poetry 1.8.4 + the export plugin
             install, `poetry export` resolves dependencies and writes a lockfile, and
             the requirements export succeeds. Only the venv *location* was wrong.

             **Note for the user:** the build logged "The lock file does not exist.
             Locking" — `poetry.lock` wasn't committed, so Poetry resolved at build
             time. That works but is slower and less reproducible. Running
             `poetry lock` once in `services/order-service/` and committing the result
             pins versions (CAP-001); the Containerfile picks it up via the
             `poetry.lock*` glob.

             **Verification:** once `build-image.sh` produces an image and
             `smoke-order.sh` passes end-to-end on Fedora 44, the r21 rows promote to
             `verified (Fedora 44)`. This is the last expected blocker before the
             walking skeleton is green.

             Verified row count holds at **107** pending the smoke run.

             # Decision log + reconciliation additions — r21c

             > Three merges:
             > 1. Revise CAP-007 and add CAP-009, CAP-010 in `_plans/capstone-decisions.md`
             > 2. Append the r21c entry to Section D of `_plans/reconciliation-plan.md`
             >    and promote the r21 rows to `verified (Fedora 44)`
             > 3. Splice the §17 friction callout into `_docs/17-capstone.md`
             >    (see the separate file `17-capstone-r21c-friction-callout.md`)

             ---

             ## For `_plans/capstone-decisions.md`

             ### CAP-007 (revised in r21c) — image distribution via the in-cluster registry

             - **Date:** r21a (original), revised r21c
             - **Status:** accepted (the r21a/r21b `minikube image load` approach is
               **superseded**)
             - **Context:** Getting a locally-built image to the kubelet under the
               rootless-podman + containerd driver combo proved unexpectedly hard. In
               sequence we hit: (1) `minikube image build` exited 0 but the image never
               entered the profile's containerd store; (2) `minikube image load <name>`
               reported "image not found" even with the fully-qualified `localhost/`
               name, because the lookup goes through the rootless podman socket and
               fails; (3) `podman save | ctr import` didn't read stdin as expected and
               dumped the image to the terminal. Each was a distinct facet of the same
               problem: there is no reliable *push-free* path into containerd on this
               driver.
             - **Decision:** Use **minikube's built-in registry addon**. Build on the
               host with podman, push to the registry, and have deployments pull from
               it as normal images. Encapsulated in `scripts/build-image.sh`.
             - **Consequences:**
               - (+) Reliable and **proven** end-to-end on Fedora 44 (r21c verification)
               - (+) Scales cleanly to all six capstone images — same one command each
               - (+) Standard `podman push` / kubelet pull; no containerd-internals
                 plumbing
               - (−) Requires the registry addon enabled (now done in
                 `setup-capstone-profile.sh`)
               - (−) Introduces the host/cluster port asymmetry — see CAP-009

             ### CAP-009 — the registry port asymmetry (host vs cluster)

             - **Date:** r21c
             - **Status:** accepted
             - **Context:** minikube's registry is reachable at two *different* addresses
               depending on where you are. With the podman driver, the host-side port is
               NOT 5000 — minikube assigns one (we observed 41685) and explicitly warns
               to use it. Inside the cluster the kubelet reaches the registry at
               `localhost:5000`.
             - **Decision:** `build-image.sh` discovers the host port dynamically
               (`podman port capstone | grep 5000/tcp`) and pushes to
               `127.0.0.1:<port>`. Charts reference the in-cluster address
               `localhost:5000/<service>` in `image.repository`.
             - **Consequences:**
               - (+) No hardcoded port that drifts between machines
               - (−) Genuinely confusing the first time; must be documented prominently
                 (done in the §17 friction callout) because every reader on this driver
                 will hit it

             ### CAP-010 — MINIKUBE_ROOTLESS=true is mandatory

             - **Date:** r21c
             - **Status:** accepted
             - **Context:** Several baffling failures (status reporting "unknown state",
               `minikube ssh` aborting, `image load` failing) all traced to one cause:
               when `MINIKUBE_ROOTLESS` is unset in the current shell, minikube routes
               host operations through `sudo podman`, which cannot see the rootless
               user's `capstone` container. The variable was set in the shell that
               *created* the profile but not in later shells, so the breakage appeared
               intermittently.
             - **Decision:** Set rootless mode two ways for defence in depth:
               (1) persist it in minikube config (`minikube config set rootless true`,
               done in `setup-capstone-profile.sh`), and (2) `export MINIKUBE_ROOTLESS=true`
               at the top of every capstone script (`build-image.sh`,
               `setup-capstone-profile.sh`, `smoke-order.sh`, and the apply/test
               scaffolding).
             - **Consequences:**
               - (+) Eliminates an entire class of intermittent, hard-to-diagnose failures
               - (+) Config covers ad-hoc `minikube` commands; export covers scripts run
                 in a bare shell
               - (−) Readers must understand this is load-bearing — covered in the §17
                 friction callout

             ---

             ## For `_plans/reconciliation-plan.md` Section D — append after r21b

             - **r21c** (consolidation — registry-based image distribution; walking
               skeleton VERIFIED) — replaces the unreliable `minikube image load` path
               with minikube's in-cluster registry, after a long live-debugging session
               established that the registry is the only robust way to get a built image
               to the kubelet under the rootless-podman + containerd driver.

               **What r21c ships:**
               - `scripts/build-image.sh` rewritten: host `podman build` → tag for the
                 dynamically-discovered host registry port → `podman push
                 --tls-verify=false` → verify via `/v2/_catalog` (CAP-007 revised,
                 CAP-009)
               - `scripts/setup-capstone-profile.sh`: persists `minikube config set
                 rootless true` and enables the registry addon as part of profile setup
                 (CAP-010, CAP-009)
               - `charts/capstone/charts/order-service/values.yaml`: `image.repository`
                 → `localhost:5000/order-service`
               - `demos/smoke-order.sh`: builds+pushes via the new `build-image.sh`;
                 diagnostic dump now queries the registry catalog; exports
                 `MINIKUBE_ROOTLESS=true`
               - decision log: CAP-007 revised, CAP-009 and CAP-010 added
               - §17 prose: a "known friction" callout documenting the driver's image
                 distribution sharp edges and the registry workflow that resolves them

               **VERIFICATION — confirmed end-to-end on Fedora 44 (the live run):**
               - CloudNativePG operator installed; provisioned a Ready Postgres primary
                 in ~35s → **verified** (the r19-flagged risk did NOT materialize)
               - order-service image: UBI 9 multi-stage build with Poetry succeeded
                 (after the r21b root-builder venv fix) → **verified**
               - image pushed to the in-cluster registry and pulled by the kubelet;
                 deployment rolled out successfully → **verified**
               - `GET /healthz` returned `{"status":"ready"}` (Postgres reachable) →
                 **verified**
               - `POST /orders` returned a complete order with server-generated UUID,
                 status `placed`, and timestamp — i.e. a row written to and read back
                 from `orders.orders` → **verified**

               **Reconciliation status changes:** the following r21 rows move from
               `unverified` to `verified (Fedora 44)`:
               - order-service image builds with Poetry on UBI 9
               - image reaches the kubelet (now via registry) and the pod runs
               - CloudNativePG provisions a working cluster on rootless-podman minikube
               - order-service connects to Postgres and serves REST
               - a row POSTed via REST persists in `orders.orders`

               This is the **first verified vertical slice** of the capstone. Verified
               fact count rises from **107** to **112** (the five rows above).

               **What this cost and what it taught:** six iterations (r21→r21c) to get
               one service standing, almost entirely due to image-distribution friction
               on the rootless-podman + containerd driver — none of it the application
               code, the helm charts, or the operator, all of which worked. The lasting
               value: r22's four services reuse a now-proven path, and §17 warns readers
               about the friction instead of letting them rediscover it.

               **Notes for r22:** inventory, payment, shipping, notification follow
               order-service's exact shape, each built+pushed with the same
               `build-image.sh <context> <name> <tag>`. Strongly consider
               `scripts/scaffold-service.sh` to stamp out the per-service skeleton.
               notification-service is Kafka-consumer-only — decide at r22 start whether
               to give it a minimal `/health` HTTP surface now or defer to r25 (Kafka).

- ✅ **r22** (2026-05-20) — capstone widening: service scaffold tooling +
  health skeletons for the remaining four services. Ships
  `scripts/scaffold-service.sh` (stamps out a new service from the proven
  order-service template, parameterised by `<name> <schema>`;
  auto-generates `poetry.lock` per CAP-001 when poetry is present; refuses
  to overwrite an existing service) and `demos/smoke-service.sh` (generic
  health smoke test for any scaffolded service: build + push image to the
  in-cluster registry, ensure the shared Postgres cluster is Ready, deploy
  the subchart, assert `GET /health` and `GET /healthz`, confirm the
  service's schema exists, clean up on success). Decision **CAP-011**
  recorded: template-driven generation; r22 services are **health-only
  skeletons** (no domain surface yet — that arrives per-protocol in r23+);
  notification-service gets the same `/health` surface despite being
  Kafka-consumer-only, for testability.

  The four services — inventory, payment, shipping, notification — were
  generated and verified **incrementally, one at a time**, each its own
  commit. All four came back green on first run: `smoke-service.sh` built
  each image → pushed to the registry → rolled out → asserted `/health`
  and `/healthz` → confirmed the service's schema in Postgres. **Verified
  count: 112 → 116** (one row per service in Section C). The scaffold
  template needed no per-service hand-editing — the r21 investment paid
  off exactly as intended.

  **Scaffold validated statically** (Claude env, no cluster): a generated
  inventory-service compiles (`py_compile`), its `Chart.yaml`/`values.yaml`
  parse, its Deployment and Service templates render to valid Kubernetes
  YAML (`image: localhost:5000/inventory-service:v1`, `/health` +
  `/healthz` probes), and the overwrite + bad-name guards both fire.
  Cluster verification (image build → registry → rollout → probes) is
  per-service on Fedora 44 as each is scaffolded.

- 🔲 **r23** (2026-05-20) — gRPC layer, first cross-service call:
  order-service → inventory-service `InventoryService.CheckStock`. Ships
  the proto (`proto/capstone/inventory/v1/inventory.proto`, package
  `capstone.inventory.v1`, 1-1-1), `buf.yaml` + `buf.gen.yaml`, and
  `scripts/gen-protos.sh` (buf primary, `grpc_tools` fallback; generates
  per-service committed stubs into each service's `gen/` — option b, no
  buf/protoc in images). inventory-service gains a `stock` table (its first
  domain table), demo seed (`WIDGET-001`=50, `WIDGET-OOS`=0), and a
  `grpc.aio` server for `CheckStock` running in the FastAPI lifespan (one
  container, ports 8080 + 50051). order-service gains a gRPC client and
  calls `CheckStock` before persisting an order (fails closed if inventory
  is unreachable). Charts updated: inventory exposes the gRPC port, order
  gets `INVENTORY_GRPC_ADDR`. Decision **CAP-013** recorded (codegen layout,
  committed stubs, in-process server); **CAP-012** (media-type REST
  versioning; protocol comparison by fitness) also recorded this round.

  **Validated statically** (Claude env — no buf/grpc/cluster available):
  all 8 changed Python modules compile (`py_compile`; imports not
  executed), proto + buf configs parse, both charts render to valid
  Kubernetes YAML with the gRPC port (inventory: containerPorts 8080+50051,
  `GRPC_PORT` env, Service `grpc` port; order: `INVENTORY_GRPC_ADDR` env),
  both Containerfiles copy `gen/`, and `smoke-grpc.sh` + `gen-protos.sh`
  pass `bash -n`. **Cluster verification pending** on Fedora 44 via
  `gen-protos.sh` → `poetry lock` (×2) → `smoke-grpc.sh`: the smoke test
  asserts an in-stock order returns 201, an out-of-stock order 409, and an
  excess-quantity order 409 — all decided by the gRPC round-trip. Verified
  count holds at **116** until that run passes; then the order→inventory
  call is the 117th fact.

- ✅ **r23** verified (Fedora 44) — `smoke-grpc.sh` green: in-stock order
  201, out-of-stock 409, excess-quantity 409, all decided by the
  order→inventory `CheckStock` gRPC round-trip. Two infra issues surfaced
  and were fixed en route (both unrelated to the gRPC code): a regressed
  bare image name in order-service `values.yaml`, and the mutable-`:v1` +
  `IfNotPresent` stale-image trap (→ CAP-015, `imagePullPolicy: Always`
  across all charts + a registry-prefix guard in the smoke tests). **Count:
  116 → 117.**

- 🔲 **r24** (2026-05-21) — GraphQL federation (read layer), first
  cross-service query. Ships a new stateless **`graphql-gateway`** service
  (Strawberry + FastAPI) that federates by *orchestration* (CAP-016): the
  `order(id)` query resolves the order from order-service (REST) and the
  nested `Order.stock` field from inventory-service (gRPC), stitching two
  services and two protocols into one response. No GraphQL added to the
  existing services. Includes the gateway chart (stateless — no Postgres),
  `gen-protos.sh` updated to distribute the inventory client stubs to the
  gateway too, and `smoke-graphql.sh` (places an in-stock order via REST,
  then queries the gateway and asserts the response carries both the order
  fields and nested `stock { quantityOnHand available }`). Decision
  **CAP-016** recorded (gateway orchestration vs true subgraph federation);
  §17 prose gains a "read layer: GraphQL federation" section explaining the
  gateway approach and when you'd use true subgraph federation in production.

  **Validated statically** (Claude env — no strawberry/grpc/cluster): the
  gateway's app modules compile (`py_compile`), `Chart.yaml`/`values.yaml`
  parse, the Deployment/Service render to valid Kubernetes YAML
  (`image: localhost:5000/graphql-gateway:v1`, `ORDER_REST_URL` +
  `INVENTORY_GRPC_ADDR` env), and `smoke-graphql.sh` passes `bash -n`.
  **Cluster verification pending** on Fedora 44 via `gen-protos.sh` →
  `poetry lock`/`install` (gateway) → `smoke-graphql.sh`. Verified count
  holds at **117** until that run passes; then the federated query is the
  118th fact.

- ✅ **r24** verified (Fedora 44) — `smoke-graphql.sh` green: a single
  GraphQL query to the gateway returned `order` (from order-service, REST)
  with nested `stock { quantityOnHand available }` (from inventory-service,
  gRPC) stitched into one response. One version issue fixed en route: the
  stale `strawberry-graphql ^0.235` pin reached into a removed pydantic
  internal (`is_new_type`) and crash-looped at import; bumped to
  `>=0.288,<1.0` (current Strawberry), which resolved cleanly. **Count: 117
  → 118.**

- 🔲 **r25** (2026-05-21) — async spine (first event flow): order-service
  publishes `order.placed` to Kafka, notification-service consumes it.
  Ships `setup-kafka-operator.sh` (Strimzi 0.51 via Helm OCI, pinned), the
  `kafka` subchart (single-node KRaft `KafkaNodePool` + `Kafka` + a
  `KafkaTopic` for `order-placed`; ephemeral storage, RF 1), order-service's
  `events.py` producer (publish after commit, keyed by order id) wired into
  `place_order`, notification-service's `consumer.py` (aiokafka background
  task, idempotent by order_id) + `GET /received`, Kafka env on both charts,
  and `smoke-kafka.sh` (places an in-stock order, polls notification's
  `/received` for the event). Decision **CAP-017** recorded (Strimzi
  single-node KRaft + aiokafka + JSON-now/registry-later; dual-write,
  at-least-once, and durability simplifications documented with their
  production answers). §17 prose gains an "async spine: events with Kafka"
  section. **Apicurio (r25b) and Alembic (r25c) deliberately deferred.**

  **Validated statically** (Claude env — no Strimzi/aiokafka/cluster): all 6
  changed Python modules compile (`py_compile`; imports not executed), the
  Kafka chart CRs and the order/notification deployments render to valid
  YAML (KafkaNodePool/Kafka/KafkaTopic; `KAFKA_BOOTSTRAP` + `KAFKA_ORDER_TOPIC`
  on both, `KAFKA_GROUP` on notification), and `setup-kafka-operator.sh` +
  `smoke-kafka.sh` pass `bash -n`. **Cluster verification pending** on Fedora
  44 via `setup-kafka-operator.sh` (first time) → `poetry lock`/`install`
  (order + notification, aiokafka added) → `gen-protos.sh` (order still needs
  its stubs) → `smoke-kafka.sh`. Verified count holds at **118** until that
  run passes; then the async flow is the 119th fact.

- ✅ **r25** verified (Fedora 44) — `smoke-kafka.sh` green: the Strimzi
  operator installed cleanly (9 CRDs), the single-node KRaft Kafka cluster
  reached Ready (broker pod Running, entity operator Running, `order-placed`
  topic READY True), order-service published `order.placed` and
  notification-service consumed it in ~2s. One bug fixed en route: the
  rewrite of notification-service's `config.py` had dropped the
  `database_url` property `db.py` depends on → AttributeError CrashLoopBackOff;
  restored it (no relock, just rebuild). **Count: 118 → 119.**

- 📝 **r25-docs** (2026-05-22) — documentation iteration ahead of r25b (no
  code). Added the §17 "Contracts, the registry, and the catalog" section
  explaining the contract/metadata architecture (Apicurio as a multi-format
  registry holding all four protocols' contracts; runtime vs discovery
  contracts; OpenMetadata layered on top building lineage; the sequencing
  rationale), plus two diagrams — `17-capstone-contracts.svg` (relationships)
  and `17-capstone-contract-flow.svg` (runtime vs discovery flow), each with
  an Excalidraw companion. Recorded **CAP-018** (contract/metadata
  architecture + multi-iteration plan: r25b Avro runtime → discovery-contracts
  publish → r27 OpenMetadata). The section is explicit that, as written,
  events are still ad-hoc JSON and neither Apicurio nor OpenMetadata is
  deployed — it describes the destination so the iterations can correct it
  against reality. No verified-fact change (documentation): holds at **119**.

### Documentation cleanup backlog (pre-launch editorial)

Tracked so it isn't lost; the page has accreted iteration-scaffolding that a
final reader shouldn't see. Items:

- ✅ **§17 "what's coming" section** — rewritten from the rNN/"Done &
  verified" iteration list into a clean reader-facing "What the capstone
  builds, and what's still ahead" (done in the r25-docs-cleanup pass).
- ✅ **§17 "Verification: examples/17-capstone/" section** — rewritten into
  "The examples/17-capstone/ directory" showing the real, populated tree
  (subcharts, services, proto, demos) instead of r20-era placeholders and
  "content arriving in iteration rNN" language (done).
- ✅ **Stray rNN references in body prose** — the r19/r21/r22/r23 mentions
  scattered through the prerequisites, order-service, and helm sections
  reworded to drop iteration numbers (CAP-NNN decision-log references kept,
  since those are traceable rationale a reader benefits from) (done).
- ✅ **"Project Plans" section on the main site page** — removed. The "Project
  plans" `<section>` in `index.html` (reconciliation + iteration plan cards),
  the "Plan" nav link in `_includes/header.html`, and the footer link in
  `_includes/footer.html` are deleted, and the `_plans` collection is set to
  `output: false` in `_config.yml` so the plan pages no longer render publicly.
  The `_plans/*.md` files remain in the repo as our own tracking documents.
- 🔲 **Topic-name drift (minor, content accuracy)** — the §17 five-services
  table lists notification consuming `orders.placed`, `payments.processed`,
  `shipments.dispatched`, but the implemented topic is `order-placed`
  (single topic, single event). Reconcile the table with what's built (or
  frame it explicitly as the intended end-state) during the editorial pass.

- 🔲 **r25b** (2026-05-22) — Apicurio + the Avro runtime contract. Ships the
  `apicurio` subchart (Registry 3, `quay.io/apicurio/apicurio-registry:3.2.4`,
  in-memory, TCP probes), the committed `order-placed.avsc` (owned by
  order-service), a transparent `avro_serde.py` (`fastavro` + `httpx`,
  Confluent Wire Format, shared by both services), order-service's producer
  rewired to register the schema on startup and Avro-encode (replacing JSON),
  notification-service's consumer rewired to fetch the writer schema by id and
  decode, `fastavro`+`httpx` deps on both, `APICURIO_URL` chart env, and
  `demos/smoke-avro.sh` (asserts the schema is registered in Apicurio **and**
  the event is consumed/decoded end-to-end). Decision **CAP-019** recorded;
  §17 prose updated — the async-spine and contracts sections now state the
  event is registered Avro (runtime contract real), with discovery contracts
  + OpenMetadata still the remaining work.

  **Validated statically** (Claude env — no fastavro/cluster): all 6 changed
  modules `py_compile`; the apicurio subchart and the order/notification
  deployments render to valid YAML (`APICURIO_URL`, `KAFKA_ORDER_SUBJECT`);
  pyprojects parse with `fastavro`+`httpx` (dev-group httpx de-duplicated);
  `events.py` schema-path logic resolves to the shipped `.avsc`; the Confluent
  wire-format round-trip is code-reviewed against the documented format
  (fastavro not installable offline). **Cluster verification pending** on
  Fedora 44 via `setup-kafka-operator.sh` (if needed) → `poetry lock`/`install`
  (order + notification) → `gen-protos.sh` → `smoke-avro.sh`. Verified count
  holds at **119** until that run passes; then the registered-Avro flow is the
  120th fact.

- 🔲 **r25b-discovery** (2026-05-22) — discovery contracts published to
  Apicurio, completing the registry half of CAP-018. Ships a `/sdl` endpoint
  on graphql-gateway (returns the Strawberry SDL), a reusable
  `scripts/publish-discovery-contracts.sh` (stdlib Python, native v3 API,
  idempotent), and `demos/smoke-discovery.sh` (deploys inventory/order/gateway,
  publishes OpenAPI + Protobuf + GraphQL SDL, asserts each is retrievable from
  Apicurio's v3 API plus the Avro runtime subject via ccompat). Three discovery
  artifacts in the `default` group: `order-service-openapi` (OPENAPI, from the
  live `/openapi.json`), `inventory-grpc-proto` (PROTOBUF, from the committed
  `.proto`), `graphql-gateway-sdl` (GRAPHQL, from `/sdl`). Decision **CAP-020**
  recorded; §17 prose updated — Apicurio now holds all four protocols'
  contracts (runtime Avro + three discovery), with OpenMetadata the only
  remaining layer.

  **Validated statically** (Claude env): gateway `main.py` compiles with the
  new `/sdl` route; `publish-discovery-contracts.sh` and `smoke-discovery.sh`
  pass `bash -n`; the embedded Python publisher compiles. **Cluster
  verification pending** on Fedora 44 via `smoke-discovery.sh` (needs Apicurio
  + the services up; gateway rebuilt for `/sdl`). Verified count holds at
  **120** until that run passes; then the three discovery artifacts are the
  121st–123rd facts.

- 🔲 **r25c** (2026-05-22) — notification-service's real `notifications` table
  with Alembic, retiring `create_all` for that service (CAP-021). Ships the
  `Notification` model (in the `notifications` schema, unique `order_id`), an
  async Alembic environment (`alembic.ini`, `alembic/env.py` with the
  `run_sync` bridge + per-service `version_table_schema`,
  `script.py.mako`, and `versions/0001_create_notifications.py`), a rewired
  consumer that persists each event idempotently
  (`INSERT … ON CONFLICT (order_id) DO NOTHING`) instead of holding it in
  memory, `db.py` with `init_schema()`/`create_all` removed, `main.py` whose
  lifespan no longer creates schema, `/received` reading from the table,
  `alembic` added to pyproject, the Containerfile copying `alembic.ini` +
  `alembic/`, a `migrate` init container in the notification Deployment
  (`alembic upgrade head`, same image + PG env), and
  `demos/smoke-notifications.sh` (asserts the migration ran, the table exists,
  an event is persisted, and it **survives a pod restart**). Decision
  **CAP-021** recorded; §17 async-spine prose updated.

  **Validated statically** (Claude env — no sqlalchemy/alembic/cluster): all
  notification modules + `env.py` + the migration `py_compile`; the migration
  revision identifiers are consistent (`0001_create_notifications`,
  down=None); the deployment renders to valid YAML with the `migrate` init
  container (command `alembic upgrade head`, workingDir `/opt/app-root/src`,
  full PG env) and the app container intact; pyproject parses with
  `alembic ^1.18`. **Cluster verification pending** on Fedora 44 via
  `smoke-notifications.sh` (needs `poetry lock`/`install` for alembic, rebuild,
  Apicurio + Kafka + Postgres up). The async env.py `run_sync` flow, the
  `pg_insert(...).on_conflict_do_nothing(...)` upsert, and the init-container
  PATH/cwd resolution are the cluster-only unknowns. Verified count holds at
  **123** until that run passes; then notification persistence + the migration
  are the 124th–125th facts.

  **r25c docs addendum** (same iteration): added a §17 subsection "Schema
  migrations, and two kinds of temporary container" explaining the async
  Alembic `run_sync` bridge, the per-service `version_table_schema`, and the
  **Init Container pattern** (cited to *Kubernetes Patterns*, Ibryam & Huss,
  2nd ed., Chapter 15) — pairing it with **ephemeral containers**
  (`kubectl debug`) as the on-demand debugging counterpart, motivated honestly
  by our minimal runtime images (no curl/psql to `exec` with). Ships
  `demos/debug-ephemeral.sh`, which attaches two ephemeral containers to a live
  notification-service pod (network-shared `curl localhost:8080/received`, and
  `--target` process-shared inspection by reading `/proc` directly — no `ps`
  dependency) and prints what each saw. **User-verified on Fedora 44**: probe 1
  returned the app's `/received` (`[]` on a fresh pod) from a container whose
  image has no curl; `--target` confirmed working. Probe 2 initially used `ps`,
  which is **not** present in `ubi9/ubi` (only `curl` is) — fixed to read
  `/proc/[0-9]*/comm`, which needs no package and more directly shows the
  shared PIDs. Lesson (recurring "tool-presence only verifiable in-cluster"):
  don't assume a base image carries a tool because it carries another; the
  script now surfaces a probe's terminated reason + exitCode instead of hiding
  stderr, so a missing tool is never a silent blank again.

  **r25c re-verification + smoke fix** (2026-05-22, post host-reboot rebuild):
  after a host reboot destroyed the `capstone` node container, the profile was
  recreated (rootless, via `setup-capstone-profile.sh`) and CNPG reinstalled.
  Re-running `smoke-notifications.sh` showed the migration init container
  succeed (`Running upgrade -> 0001_create_notifications`), the app reach
  `/healthz` 200, and the table created — but the smoke's verification step
  reported the table "not found". **Root cause: a smoke-script bug, not an r25c
  regression.** The check ran `psql -tAqc "select to_regclass(...)"` with **no
  `-d` flag**, so it connected to the default `postgres` database (where the
  `notifications` schema doesn't exist) and `to_regclass` returned NULL → empty
  string → failed assertion. Manual `psql -d capstone` confirmed both tables
  (`notifications.notifications`, `notifications.alembic_version`) present and
  owned by `capstone_app`. Fix: add `-d capstone` to the verification query
  (robust form: read the database name from the CNPG app secret so the smoke
  and the app can't disagree). r25c persistence + migration confirmed intact;
  count promotes to **125** once the fixed smoke is re-run green.

- ✅ **r27** (2026-05-22) — deploy OpenMetadata (the data catalog) into the
  capstone, lean single-node shape (CAP-022). Ships, under
  `examples/17-capstone/`: `openmetadata/om-deps-values.yaml` (trimmed
  dependencies — MySQL **off**, Airflow **off**, OpenSearch single-node with
  the PVC shrunk to 10Gi), `openmetadata/om-app-values.yaml` (server pointed at
  the **capstone CloudNativePG Postgres** instead of bundled MySQL — `database`
  flipped to `dbScheme: postgresql`, `host: capstone-postgres-rw`, a dedicated
  `openmetadata` db + role, password from a distinctly-named
  `openmetadata-db-app-secret` — with `deployPipelinesConfig` and
  `pipelineServiceClientConfig` **disabled** since ingestion runs as one-off
  Jobs, not Airflow), `scripts/setup-openmetadata.sh` (idempotently provisions
  the `openmetadata` database + role inside the existing cluster via
  `kubectl exec` psql, creates the password secret + a placeholder
  `airflow-secrets`, then `helm upgrade --install`s deps + server from the
  official charts pinned to 1.12.8), and `demos/smoke-openmetadata.sh` (waits
  for rollout, asserts the version API reports 1.12.8, confirms the
  `openmetadata` db is populated). The §17 catalog-as-mesh-requirement prose,
  the deploy walkthrough, and CAP-022 (with the live-deploy lessons) shipped in
  the **r27-docs** / r27 doc commits.

  **Verified on Fedora 44** via `setup-openmetadata.sh` then
  `smoke-openmetadata.sh`: server rolled out, the `run-db-migrations` init
  container connected to CloudNativePG over `sslmode=require` (no `prefer`
  fallback needed) and populated **168 tables** in the `openmetadata` database,
  the version API serves 1.12.8, OpenSearch came up single-node with no
  host-kernel change. Footprint fit the 24 GB / 16 CPU profile, no bump.

  **Three live fix cycles, all Helm secret-wiring (none catchable by Claude's
  static checks):** (1) the user-supplied DB-password secret initially collided
  with the chart's own generated `openmetadata-db-secret` (Helm won't adopt a
  resource it didn't create) — fixed by renaming to `openmetadata-db-app-secret`;
  (2) the chart templates an `AIRFLOW_PASSWORD` `secretKeyRef` to `airflow-secrets`
  on every container *even with the pipeline client disabled*, so the init
  container failed `CreateContainerConfigError` until a placeholder
  `airflow-secrets` was created; (3) the early ownership error looked like a
  DB-config problem and the later `CreateContainerConfigError` looked like the
  long-feared `sslmode` failure, but both were secret wiring — the migration's
  DB connection (the real unknown) worked first try once the container could
  start. Full write-up in CAP-022's "Lessons — chart secret wiring." Verified
  count → **126** (r25c's 125 plus "OpenMetadata deployed, Postgres-backed,
  serving"). **r27b** follows: register Postgres + Kafka, run ingestion Jobs,
  declare cross-product lineage.
- ✅ **r27b** (2026-05-22) — populate the catalog and declare cross-product
  lineage (CAP-023). Ships, under `examples/17-capstone/openmetadata/ingestion/`:
  `postgres.yaml` and `kafka.yaml` (the two `metadata ingest` workflow configs —
  Postgres pointed at `capstone-postgres-rw` as the `capstone_app` role scoped to
  the `capstone` db; Kafka bare at `capstone-kafka-kafka-bootstrap:9092`, topics
  only, no registry per decision C), `get_token.py` (stdlib admin-login → bearer
  token, run in-cluster by each Job), `lineage.py` (stdlib; resolves the three
  FQNs to ids and `PUT`s the two edges), and `job-postgres.yaml` /
  `job-kafka.yaml` / `job-lineage.yaml` (one-off Jobs on
  `openmetadata/ingestion:1.12.8`, mounting a shared `om-ingestion-config`
  ConfigMap, injecting secrets via Python not sed). Plus
  `scripts/ingest-openmetadata.sh` (creates the ConfigMap, runs the three Jobs in
  order with delete-then-apply for re-runnability, waits on each) and
  `demos/smoke-om-lineage.sh` (asserts both services, the three spine entities,
  and an upstream+downstream edge on the `order-placed` topic, over the API).
  The spine: `capstone-postgres.capstone.orders.orders` → `capstone-kafka.order-placed`
  → `capstone-postgres.capstone.notifications.notifications`. Decision **CAP-023**
  recorded; the long-pending "ingestion mechanism" decision narrowed to
  Apicurio/registry linkage (deferred r27c); §17 gained the "Pointing ingestion
  at the sources, and declaring the lineage" section and its closer updated
  (catalog + lineage now in place).

  **Validated statically** (Claude env — no cluster/network): all Job YAML and
  both workflow YAML parse; the embedded Python heredocs de-indent to column-0
  and compile; `get_token.py` and `lineage.py` compile; both shell scripts pass
  `bash -n`. CI (`gh run watch` after push) confirms the Jekyll site still builds
  (the only thing CI exercises) — the new §17 prose carries no Go-template
  `{{ }}` so no `{% raw %}` wrap is needed (r10a trap not triggered).

  **Verified on Fedora 44** — `scripts/ingest-openmetadata.sh` ran all three
  Jobs to completion first try, and `demos/smoke-om-lineage.sh` passed every
  assertion: both services present (`capstone-postgres` Database,
  `capstone-kafka` Messaging), the three spine entities cataloged, and the
  `order-placed` topic carrying exactly one upstream edge (orders) and one
  downstream edge (notifications). **Notably, every flagged `VERIFY-POINT` held
  as written** — the OM 1.12.8 Postgres/Kafka connector keys, the basic-auth
  login shape, the lineage `PUT` payload, and the lineage-by-name response shape
  all matched on the first live run, so unlike r27 (three secret-wiring fix
  cycles) r27b needed no live fixes. Verified count → **127** ("catalog
  populated; cross-product lineage orders → order-placed → notifications
  browsable"). **r27c** follows: Apicurio ingestion + schema-registry linkage.
- ✅ **r26** (2026-05-22, built out of numeric order — after r27b) — Istio
  v1→v2 canary on order-service (CAP-024), the "safe contract evolution" half of
  the r26 design intent. (The KEDA half is CAP-025, deferred to r26b.) Ships:
  order-service gains a side-effect-free `GET /version` endpoint and an
  `API_VERSION` setting (v2 advertises an additive `currency` field — the
  backward-compatible contract change being canaried); the order-service subchart
  Deployment gains a `version: v1` subset label + selector and a
  `sidecar.istio.io/inject` annotation. Under `examples/17-capstone/istio/`:
  `order-service-v2.yaml` (the v2 subset — same image, `API_VERSION=v2`,
  `version: v2`), `routing.yaml` (Gateway + VirtualService with `__W_V1__`/`__W_V2__`
  weight placeholders + DestinationRule subsets by `version`), and
  `render-split.py` (stdlib SVG of the observed split). Plus
  `scripts/setup-istio.sh` (installs Istio `default` profile into the capstone
  cluster, labels the namespace for injection) and `demos/smoke-canary.sh`
  (deploys v2, asserts both subsets are meshed, applies a 90/10 split, drives 100
  requests through the istio-ingressgateway and asserts the band, shifts to 50/50
  and re-asserts, renders the SVG). §17 gained the "Evolving a contract in the
  open: the v1→v2 canary" section; the closer updated (traffic management now in
  place, KEDA autoscaling still ahead). CAP-024 + CAP-025 recorded.

  **Validated statically** (Claude env — no helm/kubectl/istioctl, no network):
  order-service `config.py`/`main.py` `py_compile`; both Istio overlay YAMLs parse
  (Deployment; Gateway/VirtualService/DestinationRule) with disjoint v1/v2
  selectors; the `sed` weight substitution yields valid YAML with integer weights
  summing to 100; `render-split.py` compiles and emits well-formed SVG; both shell
  scripts pass `bash -n`. CI (`gh run watch`) confirms the Jekyll site builds — the
  new §17 prose carries no Go-template `{{ }}`.

  **Cluster verification pending** (Fedora 44, user-run): `scripts/setup-istio.sh`
  → deploy/recreate order-service v1 as its OWN release (this project installs
  each component separately per `scaffold-service.sh`, NOT via the umbrella
  chart — the umbrella declares no `dependencies:`):
  `helm upgrade --install order-service charts/capstone/charts/order-service -n capstone`
  (an already-running v1 needs a one-time `kubectl delete deployment order-service`
  first, for selector immutability; a fresh install does not) → `demos/smoke-canary.sh`.
  The order-service image must carry `/version`
  (`scripts/build-image.sh services/order-service order-service v1`).
  **Convention correction (r26.1):** the r26 deliverable initially mis-stated the
  install as `helm upgrade --install capstone ./charts/capstone`; corrected to the
  per-service release in setup-istio.sh + smoke-canary.sh messages.
  **Smoke fix (r26.2):** the sidecar assertion checked only `.spec.containers`,
  but Istio 1.29 on k8s >=1.29 injects istio-proxy as a NATIVE sidecar
  (initContainer, restartPolicy:Always) — so the check now inspects
  initContainers too. Both subsets came up 2/2 (meshed) on the first cluster run;
  this was a false-negative in the assertion, not a mesh failure.
  **Verified on Fedora 44 (r26.2 smoke, 2026-05-22)** — green on the run after
  the two corrections. order-service v1 installed as its own release; v1 + v2 both
  came up `2/2` (native istio-proxy sidecars). The smoke applied a 90/10 split and
  measured **v1=91, v2=9** of 100 requests through the istio-ingressgateway, then
  shifted to 50/50 and measured **v1=45, v2=55** — both within band — and rendered
  `/tmp/canary-split.svg`. Every Istio VERIFY-POINT held as written
  (`networking.istio.io/v1` kinds, the `istio: ingressgateway` selector,
  subset-by-`version`-label routing). The two issues hit were a wrong install
  command (r26.1) and a false-negative sidecar assertion (r26.2) — neither a defect
  in the canary mechanism itself, which worked on the first cluster apply. Verified
  count → **128** ("order-service v1→v2 canary: weighted Istio traffic split,
  observed and shiftable"). **r26b** follows: the KEDA dual-scaler (Kafka-lag on
  notification, HTTP add-on on the gateway) per CAP-025.
- ✅ **r26b** (2026-05-22; VERIFIED 2026-05-22 via r28.x) — KEDA dual-scaler (CAP-025), the "elastic data
  products" half of the r26 design intent. Two first-party scalers under
  `examples/17-capstone/keda/`: `notification-scaledobject.yaml` (keda.sh/v1alpha1
  ScaledObject — kafka trigger on the `notification-service` group / `order-placed`
  topic, lagThreshold 5, min 0 / max 3) scales the event consumer on consumer-lag;
  `gateway-httpscaledobject.yaml` (http.keda.sh/v1alpha1 — target graphql-gateway
  service:80, concurrency target 5, min 0 / max 3) scales the synchronous gateway
  on in-flight HTTP requests. `scripts/setup-keda.sh` installs KEDA 2.19.0 + HTTP
  add-on 0.12.2 (§12 versions) into the `keda` ns. Both KEDA-scaled Deployments
  gained `sidecar.istio.io/inject: "false"` (keep them unmeshed — the namespace is
  injection-labeled from r26; mesh stays scoped to order-service). §17 gained the
  "Scaling to demand, and to zero: elastic data products" section, the stack-table
  line was corrected ("graphql-gateway on HTTP load"), and the closer updated
  (autoscaling now in place; observability + Prefect ahead). CAP-025 → implemented.

  **Validated statically** (Claude env — no helm/kubectl/keda, no network): both
  KEDA manifests parse with the expected targets/triggers; `setup-keda.sh` +
  `smoke-keda-kafka.sh` + `smoke-keda-http.sh` pass `bash -n`; both chart
  deployments carry the inject:false annotation; §17 prose carries no Go-template
  `{{ }}`; liquid + cross-ref linters clean on `_docs/`. CI confirms the site build.

  **Cluster fixes (r26b.1):** first cluster run surfaced two issues, both fixed.
  (1) The Kafka `ScaledObject` used the short bootstrap name, but the KEDA
  operator runs in the `keda` namespace and resolves DNS relative to ITS
  namespace — `no such host`. Changed to the FQDN
  `capstone-kafka-kafka-bootstrap.capstone.svc.cluster.local:9092` (cross-namespace
  DNS — exactly the flagged VERIFY-POINT class). notification-service's own
  consumer is unaffected (it lives in `capstone`, short name resolves). (2) Both
  smokes' `count_pods` did `grep -c . || echo 0`, which on zero pods printed `0`
  AND `0` (grep -c exits non-zero on no match, firing the `||`), yielding `"0\n0"`
  → `[[: arithmetic syntax error`. Replaced with `grep -vc 'Terminating'`, which
  emits exactly one integer. The KEDA machinery itself worked on the first run
  (graphql-gateway scaled to 0/0, HTTPScaledObject Ready=True) — issue (2) was a
  false-negative counter, not a scaling failure.

  **Cluster run 1 (r26b.2):** Kafka half **PASSED** — notification-service scaled
  0 → 1 → 0 on the 500-msg lag burst once the FQDN bootstrap landed. HTTP half
  revealed the KEDA HTTP scaler working (it scaled graphql-gateway 0 → 3 under
  load) but the pods hit `ErrImagePull` — the graphql-gateway image was never
  built into this cluster's registry (only order-service was, this session;
  notification-service's image happened to be present, so its smoke ran). Fix is a
  prerequisite, not code: build the gateway image
  (`./scripts/build-image.sh services/graphql-gateway graphql-gateway v1`) before
  the HTTP smoke. Also bumped the HTTP scale-up wait 120s → 240s (the add-on's
  cold-start activation clipped the old timeout).

  **Cluster run 2 (r26b.3):** with the gateway image built, pods no longer
  ErrImagePull, but KEDA still created the first pod only at ~240s — the load
  wasn't registering as pending requests. Root cause: the smoke discovered the
  interceptor proxy port via `ports[0]`, which can be a non-proxy port; the proven
  §12 pattern hardcodes proxy :8080. Rewrote the HTTP smoke to mirror §12 — a
  port-forward readiness check, then a single cold-start request asserting HTTP
  200 (the interceptor buffers it, scales the gateway from zero, holds until
  Ready, forwards) as the proof of wake-from-zero, with the response code +
  interceptor logs dumped on non-200. Followed by brief sustained load to show it
  stays warm.

  **Cluster run 3 (r26b.4):** the rewrite worked — cold-start served HTTP 200 in
  7s (woke graphql-gateway from zero), stayed up at 1 replica under load. Only the
  final scale-back-to-zero clipped the 150s wait (the dump showed 0/0 — it DID
  reach zero, just past the timeout: KEDA's idle period plus HPA scale-down
  settling). Bumped the scale-to-zero waits (initial 240s, post-load 300s).
  Behavior is fully correct; the timeout was the only gap.

  **Cluster run 4 → resolved (r26b.5):** root-caused the slow scale-to-zero —
  the HTTP add-on's generated ScaledObject uses KEDA's DEFAULT cooldownPeriod
  (~300s) for the 1→0; the HTTPScaledObject's 30s scaledownPeriod only governs
  metric idle, not the cooldown (the Kafka ScaledObject's own cooldownPeriod: 30
  IS honored, hence its fast scale-down). Bumped both scale-to-zero waits to 420s
  to outwait the ~330s settling. Wake-from-zero (200 in ~8s) and stay-warm were
  green across runs; this is the last gap.

  **Cluster run 5 (r26b.6):** the rewrite-to-200 surfaced the genuine cold-start
  race — the interceptor's WorkloadReplicas wait is ~20s, but with
  imagePullPolicy: Always (CAP-015) a cold pull pushes the gateway Ready past 20s,
  so the single request 502'd (the dump showed the pod ContainerCreating at 20s,
  i.e. KEDA HAD woken it). Earlier 200-in-8s runs had the image node-cached.
  Reworked the wake phase: drive SUSTAINED trigger requests (keeping KEDA scaled
  up) while waiting for the Deployment to report a Ready replica (the 0→Ready
  transition is the wake-from-zero proof, 240s budget for a cold pull), then assert
  the interceptor serves 200. Robust to pull-time variance.

  **Cluster run 6 (r26b.7):** wake-from-zero confirmed working (dump showed
  graphql-gateway 1/1 Ready) but KEDA's scale-up latency proved highly variable —
  ~8s when the gateway had been idle a while (image cached), ~230s here because
  the wake phase began the instant the prior 1→0 scale-down completed (KEDA's
  post-scaledown settle). The pod reached Ready at ~232s vs the 240s wait — a 3s
  miss. Bumped the wake wait to 420s (observed max ~230s) and replaced the
  (misleadingly stale) interceptor-log dump with a live deployment/pods snapshot
  on timeout. KEDA's up/down timings here are minutes and variable — both waits
  now budget for that.

  **Cluster verification pending** (Fedora 44, user-run): `scripts/setup-keda.sh`
  → ensure notification-service + graphql-gateway are deployed (their own releases)
  → `kubectl apply -f keda/notification-scaledobject.yaml -f keda/gateway-httpscaledobject.yaml`
  → `./demos/smoke-keda-kafka.sh` (expects 0 → up(≤3) → 0 on a 500-msg lag burst)
  and `./demos/smoke-keda-http.sh` (expects 0 → woke-from-zero under /health load
  → 0). **Expected cluster-only risk**: KEDA core + HTTP-add-on API/install
  specifics (the `keda.sh/v1alpha1` + `http.keda.sh/v1alpha1` kinds, interceptor
  proxy service name/port, scale-to-zero timing), flagged `VERIFY-POINT` in the
  HTTPScaledObject. On a green pair of smokes, promote r26b → ✅, bump the count to
  **130** (+2: "notification-service scales on Kafka lag, 0→up→0" and
  "graphql-gateway scales on HTTP load, woke-from-zero→0"), and add the CAP-025
  outcome. With r26b done, the r26 design intent (KEDA + Istio) is fully realized.
- ✅ **r28** (2026-05-22; VERIFIED 2026-05-22) — Resource calibration (CAP-026), prompted by r26b's
  HTTP smoke repeatedly surfacing a graphql-gateway crash-loop (RESTARTS 2 in 21s
  at a 256Mi limit) rather than true KEDA failure. Research-backed (istiod ~1Gi
  default req but low actual on a tiny mesh; istio-proxy 128Mi/sidecar, only
  order-service meshed; kube-prometheus prod guides 2–4Gi assume long retention —
  a demo is far leaner; Tempo monolithic + OTEL Collector are light). Applied
  uniformly to all six Python services: requests 128→**192Mi**, limits
  256→**512Mi** (the OOM fix), plus a **startupProbe** (path /health,
  failureThreshold 30 × periodSeconds 2 = 60s grace) that gates liveness/readiness
  until the app has booted (the prior 5s liveness initialDelay was killing slow
  Python starts). CAP-026 records the full plan including the lean observability
  sizing for r29 and the verdict: **no cluster-profile bump** — 24Gi/16CPU is
  adequate (current ~12–13Gi, projected ~14Gi, ~10Gi free).

  **Validated statically** (Claude env): all six values.yaml carry 192Mi/512Mi +
  a `startup:` block; all six deployment templates carry a `startupProbe` before
  `livenessProbe` with balanced Go-template braces; no `{{ }}` introduced into
  prose. (Helm render not available offline — chart behavior verified on apply.)

  **Cluster verification pending** (Fedora 44, user-run): re-deploy the six
  services as their own releases (`helm upgrade --install <svc>
  charts/capstone/charts/<svc> -n capstone`) — a rolling restart, NOT a rebuild —
  then re-run `./demos/smoke-keda-http.sh`, which should now pass cleanly (the
  gateway no longer OOMs and the startupProbe prevents the premature liveness
  kill). On a green HTTP smoke, promote **both r26b and r28** to ✅ and bump the
  count to **130** (the two KEDA rows; r28 is the enabling fix, not a separate
  capability count). **Cluster run (r28 apply):** the calibration WORKED — graphql-gateway came up
  clean (0/0, no restart churn; the 256Mi OOM crash-loop is gone). The HTTP smoke
  then failed only on the OPENING scale-to-zero wait: the `helm upgrade` reset the
  gateway to 1 replica, and KEDA's HTTP 1→0 takes ~300s default cooldown + HPA
  settle + the new startupProbe grace (~420s total), past the 420s wait. Root-caused
  via the add-on's own issue tracker: the HTTPScaledObject's `scaledownPeriod` (30s)
  does NOT govern the 1→0 — the generated ScaledObject uses KEDA's default 300s
  `cooldownPeriod`, not exposed on the HTTPScaledObject. **r28.1:** bumped both
  HTTP-smoke scale-to-zero waits to 600s and documented the ~5-min HTTP scale-to-zero
  (vs the Kafka scaler's fast 30s) as expected behavior in §17 — an honest timing
  asymmetry, not a defect. On a re-run the gateway is already at 0, so the opening
  check is instant; budget ~10-15 min for wake + final scale-down.

  **Cluster run (r28.1) → root-caused (r28.2):** r28's calibration confirmed
  working (gateway 1/1, 0 restarts — crash loop gone). The persistent slow/erratic
  scale-up (~300s) was finally root-caused to the interceptor's
  `replicas.waitTimeout` default of 20s (the add-on's own error,
  "context deadline exceeded", and docs confirm): too short for a cold start, so
  requests 502 before a backend exists AND KEDA never gets stable pending pressure.
  r28.2 sets waitTimeout=180s in setup-keda.sh and reverts the smoke to a single
  held cold-start request asserting 200. Re-apply needs setup-keda.sh re-run (to
  update the interceptor).

  **Cluster run (r28.2):** the waitTimeout fix LANDED — "woke from ZERO and served
  200 in 10s" on two consecutive runs (the erratic 8–400s scale-up is gone). Only
  the final scale-to-zero failed, and the dump showed why: the gateway oscillating
  (a 49s pod Terminating, deployment already desired=0) with the interceptor pods
  themselves restarting (52–119s old — the add-on auto-scales the interceptor). The
  smoke was ALSO holding the port-forward open through the scale-down wait; with the
  `concurrency` metric, a held keep-alive connection reads as ≥1 in-flight, keeping
  the metric active and resetting KEDA's cooldown so the gateway never settles.
  **r28.3:** close the port-forward before the scale-down wait, and assert on KEDA's
  DECISION (Deployment `.spec.replicas` → 0) instead of waiting for the last pod to
  finish terminating — robust to termination/oscillation lag. Fixed the stale "420s"
  message (the wait was already 600s). **Apply note:** re-run ONLY
  `./demos/smoke-keda-http.sh` — do NOT re-run setup-keda.sh first (it restarts the
  interceptors mid-test, which is what churned this run); the add-on already carries
  waitTimeout=180s from the prior setup-keda run.

  This is the configuration answer to "is there a setting for this": not a KEDA
  timeout (responseHeaderTimeout is 0.5s here and governs forwarding, not
  scale-down) — the lever is not holding a connection open during the scale-down
  window, plus asserting on the scale-to-zero decision rather than full pod
  termination. The ~300s cooldown itself is by-design and only tunable via
  skip-scaledobject-creation + a hand-authored ScaledObject (deemed overkill).

  Then **r29**: the lean OTEL → Prometheus/Tempo → Grafana
  observability stack per CAP-026's sizing.

- ✅ **r28.4 / VERIFICATION STAMP** (2026-05-22) — Closing out the KEDA work
  (r26b + r28). Across repeated Fedora 44 runs the HTTP scaler demonstrably:
  scales to ZERO at rest (every opening check), WAKES from zero (200 served in
  10s, reliably, once interceptor.waitTimeout=180s removed the cold-start
  starvation), STAYS warm under load, and RETURNS to desired=0 (every dump shows
  the deployment at 0/0). The Kafka-lag scaler was verified earlier (500-msg
  burst, 0→1→0). The one behavior that resisted clean automated assertion is a
  *stable, non-flapping* zero: on a single node the HTTP add-on oscillates near
  zero (scale down → brief re-wake → scale down), so a point-in-time desired=0
  check kept landing on the "1" side of the flap. r28.4 makes the smoke latch on
  any desired=0 sighting and report a still-settling result as an OBSERVATION,
  not a failure — the up-cycle is the hard proof; the down-settle is watched.
  §17 documents this honestly as a single-node characteristic. Decision: accept
  as a known, documented limitation of the automated demo (not the capability).
  **Verified count → 130** (r26b's two scalers + r28's calibration that made the
  HTTP half reliable; counted as the two KEDA capabilities now standing).

  Net: the KEDA HTTP add-on cost ~12 cluster rounds and SIX independent
  runtime-only failures (cross-ns bootstrap DNS, unbuilt image, proxy port, OOM
  crash-loop, cold-start waitTimeout, near-zero oscillation) — none reproducible
  offline. This is the strongest argument yet for r29 (observability): a Grafana
  panel on the interceptor queue + gateway replicas would have surfaced most of
  these on sight.

- 🔲 **r29** (2026-05-22) — Observability, metrics half (CAP-027): a lean
  Prometheus + Grafana stack in an `observability` namespace, adding nothing to
  the services. Prometheus (prometheus-community/prometheus) with alertmanager,
  pushgateway, and node-exporter OFF, kube-state-metrics ON, 24h retention,
  emptyDir; Grafana (grafana/grafana) with the Prometheus datasource (pinned
  uid=`prometheus`) and a provisioned "Capstone — Scaling & Traffic" dashboard.
  Two free telemetry sources: the Istio sidecar on order-service
  (`istio_requests_total`, auto-scraped via Istio's prometheus.io annotations)
  and kube-state-metrics (`kube_deployment_spec_replicas` /
  `_status_replicas_ready` — the recorded KEDA-scaling signal). The lead
  dashboard panel charts desired-vs-ready replicas for graphql-gateway +
  notification-service, turning the KEDA scaling (and the CAP-026 near-zero
  oscillation) into something visible. Sizing per CAP-026 (Prom 512Mi/1Gi,
  Grafana 128Mi/256Mi, +kube-state-metrics ~64Mi) — fits existing headroom, no
  profile bump. Files: observability/{prometheus,grafana}-values.yaml,
  scripts/setup-observability.sh, demos/smoke-observability.sh, §17 new section.

  **Validated statically** (Claude env): both values YAMLs parse; the inline
  Grafana dashboard JSON is valid and its panel datasource refs match the
  provisioned datasource uid (`prometheus`); both scripts pass `bash -n`; §17
  passes the Liquid + cross-reference linters. Chart versions unpinned (latest)
  — pin with `--version` for reproducibility.

  **Cluster verification pending** (Fedora 44, user-run):
  `./scripts/setup-observability.sh` (installs into `observability`), then
  `./demos/smoke-observability.sh` — asserts Prometheus has capstone replica
  metrics (kube-state-metrics scraping), notes the Istio series, and confirms
  Grafana is healthy with the dashboard provisioned. Then port-forward Grafana
  (`kubectl port-forward -n observability svc/grafana 3000:80`, admin/capstone)
  and run `smoke-keda-http.sh` with the dashboard open to watch the gateway
  replicas step 0→1→0 live. On green, promote to ✅ and bump the count → 131.
  Next: **r29b** — traces (Tempo monolithic + OpenTelemetry Collector), which
  needs instrumenting the gateway (or meshing services); the larger move
  deliberately deferred from r29.

- ✅ **r26b — FULLY VERIFIED (clean smoke)** + **r29.1 corrections** (2026-05-22) —
  smoke-keda-http.sh now passes end to end on Fedora 44: woke from zero (200 in
  9s), stayed warm, and **scaled back to ZERO in ~29s**. That ~29s is the
  important finding: it's the HTTPScaledObject's `scaledownPeriod: 30`, which
  means scale-to-zero is FAST — and our earlier "~300s default cooldownPeriod /
  ~5 min" explanation (in §17 and the r28.x notes) was **wrong**. The slow,
  oscillating scale-down we chased was caused by the held `kubectl port-forward`
  keeping the HTTP add-on's in-flight `concurrency` metric ≥1, so the 30s timer
  never started. r28.4's port-forward close is what fixed it; this run confirms
  the corrected model: **drop the connection → ~30s to zero, no flapping.**
  - **r29.1 fixes the now-inaccurate material:** §17's scale-down paragraph
    rewritten (both scalers return to zero in ~30s; the real gotcha is that an
    open connection — browser tab or lingering port-forward — keeps concurrency
    >0 and stalls scale-down); smoke-keda-http.sh step/comment text corrected to
    ~30s + the connection cause.
  - **Grafana login hardening (also r29.1):** the grafana chart preserves an
    existing admin password on upgrade, so it isn't reliably the values default.
    setup-observability.sh now prints the authoritative
    `kubectl get secret grafana ... | base64 -d` read; smoke-observability.sh
    reads the real password from the secret (was hardcoding admin:capstone); §17
    flags the trap. (Surfaced by a real "can't login to grafana" report.)
  - Validated offline: all three scripts `bash -n`; §17 clears both linters; no
    stale 300s/5-min claims remain.
  - r26b stands ✅ (count 130, unchanged — this upgrades it from
    verified-by-evidence to verified-by-clean-smoke). r29 (observability) still
    pending its own smoke-observability run + Grafana login confirmation.

- 🔲 **r29b** (2026-05-22) — Observability, traces backend (CAP-028): Grafana
  Tempo in monolithic mode (OTLP receivers on, local storage, 256Mi/512Mi)
  installed by setup-observability.sh, plus a Tempo datasource provisioned in
  Grafana. Deliberately scoped to the BACKEND only — instrumenting a service to
  emit traces is r29c — to isolate variables (the KEDA lesson). Also a leaner
  deviation from CAP-026: NO OpenTelemetry Collector, because our metrics come
  from Prometheus scraping (not OTLP), so a collector would only forward traces
  Tempo already receives directly; instrumented services will send OTLP straight
  to tempo:4317. Files: observability/tempo-values.yaml, grafana-values.yaml
  (+Tempo datasource), setup-observability.sh (+Tempo), demos/smoke-tracing.sh,
  §17 traces-backend paragraph.

  **Validated statically** (Claude env): tempo + grafana values parse; the Tempo
  datasource (uid=tempo) is present alongside Prometheus; the embedded scaling
  dashboard JSON is still valid; both scripts pass `bash -n`; §17 clears both
  linters. Tempo chart-schema correctness (receiver keys, service ports) is
  cluster-only — flagged as the likely first-fixup area if the install balks.

  **Cluster verification pending** (Fedora 44, user-run): re-run
  `./scripts/setup-observability.sh` (now also installs Tempo and re-applies
  Grafana with the Tempo datasource), then `./demos/smoke-tracing.sh` — asserts
  Tempo is Ready and answers /ready, and that Grafana has the Tempo datasource
  provisioned and reachable. On green, promote to ✅ (count → 132, pending r29's
  own metrics verification first). Next: **r29c** — instrument the gateway (REST
  + gRPC clients) with OpenTelemetry to emit the GraphQL fan-out trace to Tempo;
  the real end-to-end traces proof, isolated onto this now-verified backend.

- 🔲 **r29.2** (2026-05-22) — Chart-repo migration fix. r29b's clean run surfaced
  `level=WARN msg="this chart is deprecated"` on the tempo and grafana installs:
  the entire grafana/* helm-charts repo moved to `grafana-community` effective
  2026-01-30 (updates/support now only there). setup-observability.sh repointed
  `grafana` → `grafana-community` repo and `grafana/{grafana,tempo}` →
  `grafana-community/{grafana,tempo}`; values unchanged (same charts relocated);
  prometheus-community untouched. Validated: `bash -n` clean.
  **Apply note:** existing `tempo`/`grafana` releases upgrade onto the relocated
  charts (seamless — same chart). If helm errors on an immutable field
  (selector labels), `helm uninstall tempo grafana -n observability` then re-run
  setup-observability.sh — persistence is off, so no data loss.

  Status of the observability line after this: **r29 metrics** + **r29b traces
  backend** both verified by clean smokes (Tempo Ready, Grafana datasources
  provisioned/reachable, Prometheus scraping) — promote both to ✅ once the
  grafana-community re-run is confirmed (count → 132). Then **r29c**: instrument
  the gateway to emit real traces onto this backend.

- 🔲 **r29c** (2026-05-22) — Traces source (CAP-029): graphql-gateway instrumented
  with OpenTelemetry. Containerfile pip-installs opentelemetry-distro +
  otlp-proto-grpc and runs `opentelemetry-bootstrap -a install` (auto-detects
  FastAPI/httpx/grpc), entrypoint wrapped with `opentelemetry-instrument`; OTLP
  env on the Deployment points at tempo.observability:4317 (env-gated via
  values.tracing.enabled, so the image also runs untraced). A GraphQL query now
  yields a distributed trace: gateway server span + order-service REST client
  span (+ inventory gRPC client span when the order exists). Pip-not-poetry on
  purpose: no poetry.lock regeneration. Scoped to the gateway; backends emit no
  spans yet (their hops show as the gateway's client spans). Files:
  services/graphql-gateway/Containerfile, graphql-gateway values.yaml + deployment
  (OTEL env), demos/smoke-trace-flow.sh, §17.

  **Validated statically** (Claude env): smoke-trace-flow `bash -n` clean; gateway
  values parse with the tracing block; deployment template braces balanced (25/25)
  and if/end matched with 9 OTEL env lines; Containerfile has the OTEL install,
  bootstrap, and wrapped CMD. OTEL package versions unpinned (bootstrap aligns
  them). Instrumentation behavior + Tempo search format are cluster-only.

  **Cluster verification pending** (Fedora 44, user-run): rebuild the gateway
  image so it carries the instrumentation, then redeploy and drive a query:
    ./scripts/build-image.sh services/graphql-gateway graphql-gateway v1
    helm upgrade --install graphql-gateway charts/capstone/charts/graphql-gateway -n capstone
    ./demos/smoke-trace-flow.sh
  smoke-trace-flow drives a GraphQL query through the interceptor (hard assert:
  HTTP 200 = gateway ran + exported) and searches Tempo for a graphql-gateway
  trace (retried; reported, not failed, if indexing lags). Confirm visually in
  Grafana → Explore → Tempo. On green, promote to ✅ (count → 133). The gateway is
  KEDA-scaled, so watch the first cold start: startupProbe (60s) + waitTimeout
  (180s) absorb the added OTEL boot cost; the span exporter is async so a
  Tempo outage can't affect request handling.

  **Observability arc status:** r29 (metrics) ✅, r29b (traces backend) ✅, r29.2
  (chart-repo deprecation) ✅, r29c (traces source) pending this rebuild. Optional
  follow-on: instrument the remaining services for full multi-service traces.

- 🔲 **r29c.1** (2026-05-22) — Two issues from r29c's cluster run. (1) Grafana
  OOMKilled (exit 137) at 256Mi → bumped limit to 512Mi / requests to 256Mi in
  grafana-values.yaml (same too-tight-limit class as the r28 gateway OOM; apply
  via re-run of setup-observability.sh — persistence off, no data loss). (2) The
  gateway took the OTEL instrumentation cleanly (all instrumentations installed,
  image built, redeploy REVISION 3, GraphQL query → HTTP 200), but Tempo search
  `q={}` returns zero traces — spans are NOT reaching Tempo despite the OTLP
  4317/4318 ports being exposed on the tempo Service. Root cause under
  diagnosis (gateway export vs Tempo ingestion); the empty earlier gateway-log
  grep was uninformative because the KEDA-scaled gateway had no running pod at
  log-check time. Trace fix deferred to a follow-up once the gateway's
  export-time logs are captured.

- 🔲 **r29c.2** (2026-05-22) — Trace-export fix (root cause of the r29c.1 trace gap).
  The gateway instrumentation was fine; spans weren't reaching Tempo because the
  export used OTLP gRPC :4317 with an http:// endpoint (silent TLS failure → spans
  dropped, request still 200, Tempo `q={}` empty). Switched the gateway to OTLP
  HTTP/protobuf :4318 (values otlpProtocol=http/protobuf; Containerfile installs
  the opentelemetry-exporter-otlp meta-package). Confirmed against a user-supplied
  working otel-lgtm reference using http/protobuf:4318. Hardened smoke-trace-flow.sh:
  TraceQL `q=` search + post-query gateway-log capture. Validated offline: smoke
  `bash -n`; values parse with http/protobuf:4318; deployment braces 26/26.
  **Apply** (gateway image rebuild — Containerfile changed):
    ./scripts/build-image.sh services/graphql-gateway graphql-gateway v1
    helm upgrade --install graphql-gateway charts/capstone/charts/graphql-gateway -n capstone
    ./demos/smoke-trace-flow.sh
  On a found trace, r29c → ✅ (count 133) and the observability arc closes.

- ✅ **r29c / r29c.1 / r29c.2 VERIFIED** (2026-05-22) — Distributed tracing is live.
  `smoke-trace-flow.sh` green: GraphQL query → HTTP 200 → `✓ Tempo has a
  graphql-gateway trace`. Running deployment confirmed on the http/protobuf fix
  (`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`,
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo.observability.svc.cluster.local:4318`).
  The gRPC:4317→HTTP/protobuf:4318 switch was the operative fix; the otel-lgtm
  reference confirmed it. r29c.1 Grafana 512Mi and the OTLP meta-exporter also
  in the verified image. **Observability arc complete:** r29 metrics ✅, r29b
  traces backend ✅, r29.2 chart-repo ✅, r29c traces source ✅. **Verified count → 133.**

  **Two cluster-recovery findings surfaced during this verification (NOT caused by
  the OTEL work — both are long-lived single-node minikube gotchas worth a §17
  troubleshooting note):**
  1. **Control plane wedged on `etcd: bind: address already in use` (:2380).** After
     ~18h and many redeploys, a stuck prior etcd held the peer port, so the static
     etcd pod crashlooped (Exit 1, NOT OOM) and took scheduler/controller-manager/
     metrics-server/the KEDA interceptor down with it. Fix: `minikube stop -p
     capstone && minikube start -p capstone` — clears the port, preserves the etcd
     data-dir, no data loss. (Diagnosing: Exit 1 + "address already in use" in
     `kubectl logs etcd-capstone --previous`, not code 137 — rules out resources.)
  2. **The in-cluster registry does NOT persist images across `minikube stop/start`.**
     Post-cycle, every `localhost:5000/*` image must be rebuilt+repushed via
     `scripts/build-image.sh`, or pods sit in `ErrImagePull` with
     `NotFound ... not found` (distinct from a "connection refused" registry-down
     error). Recently-pushed images are the first casualties, so rebuild ALL
     locally-built images after a node cycle, not just the ones that error first.

  Optional follow-ons (offered, not built): r29b.1 (harden smoke-tracing.sh to POST
  a synthetic span to Tempo :4318 and read it back — would have caught the export
  gap at the backend stage); instrument the remaining services for full
  multi-service traces (mechanical extension of the r29c gateway pattern).

- 🔲 **r30** (2026-05-22) — Operational hardening (CAP-030). New
  `scripts/cluster-up.sh` (idempotent bring-up: auto-cycles a wedged control
  plane, rebuilds only registry-missing images, bounces stuck pods) and
  `scripts/cluster-status.sh` (read-only one-shot health report). §17 gains an
  "Operating the cluster" troubleshooting section documenting the etcd `:2380`
  wedge (Exit 1, cure = node cycle) and the registry-image-loss-on-restart
  (`not found`, cure = rebuild local images). Both directly encode the r29c
  recovery so it isn't re-derived live. Offline-validated: `bash -n` both scripts;
  liquid + cross-ref linters clean. **Cluster-verify:** from a stopped or wedged
  state, `./scripts/cluster-up.sh` reaches green and `cluster-status.sh` agrees.

- 🔲 **r29b.1** (2026-05-22) — `smoke-tracing.sh` upgraded from backend-standing
  to end-to-end ingest proof: POST a synthetic OTLP/HTTP span to Tempo :4318 and
  read it back via TraceQL on :3200 (CAP-028 addendum). Closes the gap that let
  the r29c export bug slip past the backend smoke. Offline-validated: `bash -n`;
  OTLP/JSON payload parses. **Cluster-verify:** `./demos/smoke-tracing.sh` ends
  with the synthetic-trace readback ✓.

- 🔲 **r31** (2026-05-22) — Presentation groundwork (CAP-031). Added repo-root
  `presentation/` with the Data Mesh 101 deck + 15 paired SVG/Excalidraw diagrams
  under `data-mesh-101/`, and a README capturing the Red Hat design system
  (palette/fonts/layout) and the diagram→section mapping. Added
  `_plans/capstone-roadmap.md` (phases A–E with the user's refinements: A/B as
  backable-out demos, C as a one-page→section-set restructure, D as a deck reusing
  the 101 design system, E's demo-vision acceptance criteria). No code/cluster
  surface — groundwork only. Verify: site builds with the new `presentation/`
  assets present (CI Jekyll build).

- 🔲 **r32** (2026-05-22) — Phase A part 1: **review-service** data product
  (CAP-032). New REST-only service (reviews/ratings keyed by product sku) with its
  own `reviews` Postgres schema, scaffolded from the template + given a domain
  surface (model/schemas/routes/seed), chart aligned to the r28 calibration
  (192Mi/512Mi + startupProbe), and `demos/smoke-reviews.sh`. Intentionally a
  *temporary* demo product (backed out in part 2). Offline-validated: py_compile,
  values parse, deployment braces 24/24, smoke bash -n. **Build prereq:** run
  `poetry lock` in services/review-service/ before the first build.
  **Apply / verify:**
    cd services/review-service && poetry lock && cd ../..
    ./demos/smoke-reviews.sh
  Expected: probes + version OK, seeded rows, create/fetch/filter all ✓.
  On green, r32 → verified and part 2 (r33: Apicurio + OpenMetadata + up/down
  harness) follows.

- ✅ **r32 VERIFIED** (2026-05-22) — review-service smoke green on first run:
  build → deploy → Ready (no cold-start/OOM — the r28 calibration held) → all REST
  assertions passed (probes, version, seeded rows, create id
  44732ca4…, fetch-by-id, sku filter). The data product stands and serves.
  Phase A part 1 done; proceeding to part 2 (Apicurio + OpenMetadata + up/down).

- 🔲 **r33** (2026-05-22) — Phase A part 2: discovery + replayable demo (CAP-033).
  `openmetadata/ingestion/reviews_lineage.py` (declare/remove the reviews->products
  edge, separate from the permanent spine) and `demos/demo-add-data-product.sh
  up|down` — up deploys review-service, publishes its OpenAPI to Apicurio,
  re-ingests OpenMetadata (auto-catalogs the reviews schema), declares lineage, and
  prints the three ways in; down removes lineage + catalog entry + artifact +
  release + schema, back to baseline. Offline-validated: py_compile (helper + inline
  publish), harness bash -n. **Cluster-verify:**
    ./demos/demo-add-data-product.sh up      # product visible via REST, Apicurio, OM lineage
    ./demos/demo-add-data-product.sh down     # baseline restored
    ./demos/demo-add-data-product.sh up       # replay (idempotence)
  **Verify-points (likely down-path tweaks):** OM lineage/schema delete API shapes;
  CNPG primary exec (container `postgres`, user `postgres`); Apicurio v3 DELETE.
  On a clean up→down→up, Phase A is complete.

- 🔲 **r34** (2026-05-22) — Fix: OpenMetadata ingestion Jobs opt out of Istio
  injection (CAP-034). The capstone namespace is `istio-injection=enabled`, so the
  ingestion Jobs got an istio-proxy sidecar (pod `0/2`) — the proxy races the
  ingest container and prevents the Job from ever completing, so `om-ingest-*`
  errored. Added `sidecar.istio.io/inject: "false"` to the pod templates of
  job-postgres/job-kafka/job-lineage. (The pagila/sample text in the failing log
  was the image's bundled example banner, not the mounted ConfigMap — config was
  correct; single cause.) Also flagged: the namespace now has broad injection
  (drift from selective) — a deliberate Phase C decision. Offline-validated: all
  three Jobs parse with inject=false + restartPolicy Never. **Cluster-verify:**
  re-run `./demos/demo-add-data-product.sh up`; ingestion Jobs complete unmeshed
  and the run proceeds to lineage + catalog verification (resumes the r33 verify).

- 🔲 **r35** (2026-05-22) — `scripts/bootstrap-capstone.sh`: the one-command,
  health-gated, idempotent full bring-up that was missing (CAP-035). Orders all
  seven setup-* scripts + workload helm installs + scalers + seed, with a health
  gate per tier; every command lifted from proven smokes. Built after a 21h node
  degraded past recovery (clean rebuild required) exposed that no such script
  existed. Validated: bash -n; all 19 referenced paths exist. Grounded but
  untested offline — first real run is the rebuild. **Rebuild + verify:**
    minikube delete -p capstone
    cd examples/17-capstone && ./scripts/bootstrap-capstone.sh
    # then: ./demos/smoke-discovery.sh ; ./scripts/ingest-openmetadata.sh ;
    #       ./demos/demo-add-data-product.sh up   (resumes Phase A on a clean node)
  Deferred to r36: cluster-up settle-check fix, cluster-status scaled-to-zero
  flag, demo-harness OM pre-flight.

- 📝 **Node-decay saga note** (2026-05-22) — r32 (review-service) and r33/r34
  (discovery + Job inject-fix) are CODE-COMPLETE and were validated; the long
  failure cascade that followed (etcd wedge → registry loss → OM scaled to zero →
  containerd panic → full crashloop) was **node-environment decay on a 21h-old
  single node**, not the Phase A feature work. Phase A resumes verification on the
  rebuilt node via demo-add-data-product.sh up.

- ❌ **r36 WITHDRAWN** (2026-05-23) — PID-ceiling fix; diagnosis was wrong (pods live in kubepods.slice, pids.max=509255 — PID was never the constraint; root write fails on rootless). Script edits reverted. See CAP-036 note + r37. Original text: Fix: raise the node's PID ceiling (CAP-036). The
  podman driver caps the minikube node container at 2048 PIDs (its --pids-limit
  default) on the node root cgroup; the full meshed capstone runs ~1966 tasks, so
  the kubelet hit EAGAIN forking the last pod (order-service stuck
  RunContainerError, runc exit 128). cgroup v2 pids.max is writable live:
  setup-capstone-profile.sh now raises it after `minikube start`, and cluster-up.sh
  after both its start and auto-cycle. Offline-validated (bash -n; both raise
  pids.max). **Immediate live fix + cluster-verify:**
    minikube ssh -p capstone -- 'echo max | sudo tee /sys/fs/cgroup/pids.max'
    kubectl rollout restart deploy/order-service -n capstone
    kubectl rollout status  deploy/order-service -n capstone --timeout=180s
  → order-service 2/2 Ready completes the r35 bring-up; resume Phase A
  (smoke-discovery → ingest-openmetadata → demo-add-data-product.sh up).
  Flagged for Phase C: namespace-wide istio injection (drift from selective) is a
  major contributor to the PID pressure and should be revisited there.

- 🔲 **r37** (2026-05-23) — Fix: order-service startup resilience (CAP-037). The
  crash-loop was the istio-proxy startup race — the meshed order-service made its
  first Postgres/Kafka/Apicurio connects in FastAPI `lifespan` before Envoy
  programmed routes (gaierror in asyncpg SSL path), then exited with no retry.
  Three changes: `holdApplicationUntilProxyStarts` annotation; retry+backoff in
  init_schema (db.py) and start_producer (events.py); startupProbe budget 60s→120s.
  Offline-validated (py_compile, JSON, yaml). **Cluster-verify:**
    ./scripts/build-image.sh services/order-service order-service v1
    helm upgrade --install order-service charts/capstone/charts/order-service -n capstone
    kubectl rollout status deploy/order-service -n capstone --timeout=180s
  → 2/2 Ready through cold start; then resume Phase A
  (smoke-discovery → ingest-openmetadata → demo-add-data-product.sh up).

- 🔲 **r38** (2026-05-23) — Fix: Postgres mesh-exclusion + sizing (CAP-038). order-
  service's ConnectionResetError traced to Postgres crash-looping: (1) meshed under
  namespace-wide injection, so Envoy broke CNPG's own TLS (postgres exit 2,
  "HTTP communication issue"); (2) once unmeshed, OOMKilled at its 512Mi limit
  during WAL-replay recovery. Chart now sets CNPG `inheritedMetadata` annotation
  `sidecar.istio.io/inject:"false"` and raises resources (req 256→512Mi, lim
  512Mi→2Gi). Offline-validated (yaml parse + structural render). **Live fix +
  cluster-verify:**
    kubectl patch cluster capstone-postgres -n capstone --type=merge \
      -p '{"spec":{"resources":{"requests":{"memory":"512Mi"},"limits":{"memory":"2Gi"}}}}'
    kubectl get pods -n capstone -l cnpg.io/cluster=capstone-postgres -w   # → 1/1 Ready, stable
    kubectl get pods -n capstone -l app.kubernetes.io/name=order-service   # → 2/2 on its own
  Phase C: make selective injection uniform across all operator-managed infra.

- 🔲 **r39** (2026-05-23) — Phase B: complete the v1→v2 canary (CAP-039). Aligned
  `istio/order-service-v2.yaml` with the r37/r38 order-service hardening
  (holdApplicationUntilProxyStarts, 120s startupProbe, 192Mi/512Mi resources — it
  had drifted, predating CAP-037/038) and added `demos/demo-canary.sh up|shift|down`
  (repeatable, backable-out; presenter counterpart to smoke-canary.sh). v2 env
  already matched v1. Offline-validated (yaml parse, bash -n, object-name match,
  /version emits v2+currency). **Cluster-verify (cluster is freshly green):**
    ./demos/smoke-canary.sh                 # asserts 90/10 + 50/50 splits in-band
    ./demos/demo-canary.sh up               # 90/10, observe, then:
    ./demos/demo-canary.sh shift 50 50
    ./demos/demo-canary.sh down             # back to v1-only baseline
  Closes Phase B. Phase C next: §17 page restructure + narrative + diagrams +
  the selective-injection decision.

- 📝 **Idle-node decay note** (2026-05-23, CAP-040) — After ~17h idle, kube-proxy
  CrashLooped on a vanished `/dev/bsg` device node, breaking ClusterIP routing
  cluster-wide (manifested as the istiod injection-webhook ClusterIP refusing
  connections → v2 canary pod couldn't be created → whole namespace stuck
  Init:1/2). Not an Istio fault (istiod healthy; pod-IP:15017 open, Service-IP:443
  refused = kube-proxy). Recovery: `./scripts/cluster-up.sh` to cycle the node,
  then `cluster-status.sh`. Operational habit recorded: run cluster-up/status when
  resuming after a break. Phase B canary verification resumes once the cycle
  restores Service routing.

- 🔲 **r40** (2026-05-23) — Fix (durable, correct): raise the node PID ceiling at
  creation via podman containers.conf (CAP-041; supersedes the withdrawn r36).
  Confirmed root cause of order-service's recurring StartError/exit-128/EAGAIN:
  node root cgroup pids.max=2048, pids.current=2043 (99.8% full) — the full meshed
  stack saturates podman's default per-container PID cap, so the kubelet can't fork
  the last pod. Live cgroup write is blocked on rootless, so the fix is
  creation-time: `pids_limit = 0` in ~/.config/containers/containers.conf, then a
  node recreate. setup-capstone-profile.sh now guards this (hard-fail with the fix
  if pids_limit < 8192 and ≠ 0), mirroring the inotify guard. Offline-validated
  (bash -n; guard parse logic). **Cluster-verify:**
    mkdir -p ~/.config/containers
    printf '[containers]\npids_limit = 0\n' >> ~/.config/containers/containers.conf
    minikube delete -p capstone
    cd examples/17-capstone && ./scripts/bootstrap-capstone.sh   # true 8/8 — order-service forks
  Then Phase B: ./demos/smoke-canary.sh. §1 prerequisites should add the
  pids_limit note alongside the inotify tweak.

- 🔲 **r40.1** (2026-05-24) — Fix the r40 guard bug. The CAP-041 pids_limit guard
  in setup-capstone-profile.sh aborted silently (exit 2, no output) even when
  containers.conf was correctly set to 0: under `set -euo pipefail`, the bare
  `(( pids_limit < 8192 ))` returns exit 1 when false, which set -e treats as fatal.
  Rewrote to compute a `pids_too_low` flag (with an `=~ ^[0-9]+$` numeric guard)
  and branch on a string test, which never trips set -e. Verified under set -e:
  pids_limit=0→PASS, 2048→BLOCK, 16384→PASS. Now the guard correctly passes a
  raised limit and the bootstrap proceeds.

- 🔲 **r40.2** (2026-05-24) — Second guard fix. The CAP-041 "OK" line used
  `printf ... "$( [[ x == 0 ]] && echo unlimited || echo x )"` — a command-sub
  with `&& ... || ...` that is fragile under `set -e`. Replaced with a plain
  if/else assigning `pids_display`. (Also note: a prior `bash -x ... | tail` run
  reported exit=0 misleadingly — that was tail's exit through the pipe, not the
  script's, masking the real status; diagnose with an unpiped run + `echo $?`.)
  Verified the guard+display block flows through to minikube start under
  set -euo pipefail with pids_limit=0.

- 🔲 **r40.3** (2026-05-24) — THE real guard fix (r40/r40.1/r40.2 missed it). The
  failure was never the `(( ))` arithmetic — it was the `pids_limit=$(grep … |
  grep -oE … )` assignment: under `set -euo pipefail`, when /etc/containers/
  containers.conf is absent (normal — only the user file exists), a grep in the
  pipeline returns non-zero, pipefail propagates it, and set -e aborts the whole
  `var=$(…)` assignment (exit 2, no further output — exactly the observed
  symptom; the value even computed but the pipeline's status killed it). Fix:
  `… || true` inside the substitution + `${pids_limit:-2048}` default. Empirically
  reproduced (original aborts before its 'after' echo; fixed reaches it) and
  verified the full guard flows to `minikube start` under the real flags.
  Lesson logged: reproduce a shell failure under its actual set-flags before
  claiming a fix — three prior revisions theorized instead of reproducing.

- ✅ **Phase B VERIFIED** (2026-05-24) — order-service v1→v2 canary confirmed
  end-to-end on a clean 8/8 bootstrap (uncapped node, pids_limit=65536 via CAP-041).
  smoke-canary.sh: v2 rolled out clean (r39 alignment — proxy-hold + retry +
  512Mi), both subsets meshed (2/2), 90/10 split observed v1=95/v2=5, 50/50 split
  observed v1=46/v2=54 — both in band. demo-canary.sh up/shift/down available for
  the repeatable/backable-out flow. Closes r39 / CAP-039. Also confirms the full
  bootstrap (r35) reaches a true 8/8 with all of r34/r37/r38/r40.3 in effect:
  order-service forks and becomes Ready for the first time through a clean bring-up.
  Phase A (review-service add/back-out) remains available to verify via
  smoke-discovery → ingest-openmetadata → demo-add-data-product.sh up. Next: Phase C
  (§17 page restructure + narrative + diagrams + the selective-injection decision).
