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
| unverified              | KEDA             | TBD           | §12 helm install args | `helm list -n keda` shows the documented chart version     |
| unverified              | KEDA HTTP add-on | TBD           | §12 helm install args | `helm list -n keda` shows the add-on chart version         |

## B. Per-section claims

Claims made in prose that are not yet end-to-end verified. New
rows added as sections get drafted; rows are promoted to
`verified` when their underlying claim has been exercised on
Fedora 44.

| Status                  | Claim                                                                       | Section | Notes                                                                       |
|-------------------------|-----------------------------------------------------------------------------|---------|-----------------------------------------------------------------------------|
| unverified              | 4 CPU / 8 GB RAM / 20 GB free disk is sufficient for §1–§10                  | §1      | Promote after running §1–§10 on hardware near the floor (not the dev box)    |
| unverified              | 6 CPU / 16 GB RAM / 50 GB free disk is comfortable for §1–§12                | §1      | "Comfortable for all" recommendation; verify once §11 + §12 are complete    |
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
| unverified              | `helm uninstall` removes all chart-created resources within 30s (async deletion) | §9 | r10 user run: leftover Pod in `Terminating` state caught the demo's one-shot check (failed); r10d demo polls for 30s; promote on demo re-run pass |
| **verified (Fedora 44)** | Helm 4 reads charts authored against the Helm 3 chart format (`apiVersion: v2`) | §2, §9 | r10 user run with helm `v4.1.1+g5caf004` cleanly handled the v2-format chart through lint, template, install, upgrade, history, uninstall |
| **verified (Fedora 44)** | `helm uninstall` is asynchronous — returns success once delete operations are submitted; actual Pod termination follows `terminationGracePeriodSeconds` (default 30s) | §9 | Learned in r10 user run: leftover check ran 0ms after uninstall returned, caught a Pod still `Terminating` (3s old). r10d's demo polls for 30s after uninstall to account for the async behavior |

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
| **in flight** | `examples/09-deploy-nginx-helm`        | §9      | r10 user run passed every substantive check; failed only on a one-shot leftover query that raced a `Terminating` Pod. r10d demo polls for 30s; awaiting re-run |
| unverified | `examples/11-istio-bookinfo`         | §11     | Istio sample app with sidecar + Gateway + VS          |
| unverified | `examples/12-keda-http-scale`        | §12     | KEDA HTTP add-on + `hey` load test                    |

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

**Open, priority-ordered:**

1. Re-run `examples/09-deploy-nginx-helm/demo.sh` after applying
   r10d. On `✓ SUCCESS`, the final §9 row (no-leftovers-within-30s)
   promotes plus Section C `examples/09-deploy-nginx-helm/`. The
   "8 §9 Section B rows promote" framing from r10's open list is
   now: 7 already promoted in r10d's plan, 1 pending re-run
2. Optional: verify §8 PV auto-delete by running the demo,
   exiting before cleanup, manually `kubectl delete pvc/nginx-content`,
   then `kubectl get pv` — should show the PV cleaned up. Low
   priority
3. Optional: §7 leftovers (range enforcement, coexist) — low
   priority, can stay `unverified` indefinitely
4. **r11** — §10 editor/shell/terminal; will request local-setup
   specifics (your CLion / warp.dev / shell-of-choice details)
5. **r12** — §11 Istio (resource bump pre-flight; expect Section B
   resource claims to surface here)
6. **r13** — §12 KEDA (optional section)
7. **r14–r16** — tail sections, diagrams, editorial pass, final
   reconciliation refresh
