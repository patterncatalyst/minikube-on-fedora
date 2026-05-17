---
title: Reconciliation plan
description: What in this tutorial is verified, what is in flight, and what still needs validation.
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
| unverified              | No SELinux `:Z` flag needed for minikube hostPath PVs                        | §1, §8  | Resolve in r09 when persistent-volume example lands                         |
| **verified (Fedora 44)** | `minikube` RPM from `storage.googleapis.com` installs cleanly via `dnf`     | §2      | r05 user output: dnf install completed, /usr/bin/minikube present ✓         |
| unverified              | `helm 4.1.x` from Fedora repos works against Helm 3-format charts            | §2, §9  | Install verified; chart-compat promotes in r10 when first `helm install` lands |
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
| unverified              | `minikube image build` builds and caches an image visible to the cluster's kubelet | §6 | r07a demo step; promote when `examples/06-deploy-nginx-kubectl/demo.sh` passes |
| unverified              | A two-stage Containerfile (ubi9 → ubi9-minimal) produces a working nginx image | §6 | r07a Containerfile; promote on demo pass |
| unverified              | `ubi9/ubi-minimal` installs nginx via `microdnf` without subscription-manager | §6 | r07a build step; promote on demo pass |
| unverified              | A two-replica Deployment with the manifest in §6 becomes `Available` within 3 minutes | §6 | r07a manifest claim; promote on demo pass |
| unverified              | `kubectl port-forward service/nginx 18080:80` opens a working tunnel        | §6      | r07 demo claim; promote on demo pass                                        |
| unverified              | `kubectl scale deployment/nginx --replicas=3` brings count to 3 Running pods | §6     | r07 demo claim; promote on demo pass                                        |
| unverified              | Baked-in index.html serves the sentinel string `Test Page for nginx on UBI 9 Minimal` | §6 | r07a demo response check; promote on demo pass                              |
| unverified              | NodePort Service exposes a workload at `<nodeIP>:<nodePort>` on minikube     | §7      | r08 manifest claim; promote when `examples/07-nodeport-service/demo.sh` passes |
| unverified              | `minikube service <name> --url` returns a host-reachable URL                 | §7      | r08 demo claim; promote on demo pass                                        |
| unverified              | NodePort values must be in 30000-32767 range (enforced by kube-apiserver)    | §7      | r08 prose claim; promote on attempt to apply a manifest with an out-of-range nodePort |
| unverified              | A Deployment with a different name + label can coexist with §6's nginx       | §7      | r08 design choice; promote when demos for §6 and §7 can be run back-to-back without interference |

## C. Testing matrix

End-to-end tests of each runnable example. This is where the
reconciliation plan earns its keep — a reviewer should see at a
glance which examples are confirmed to actually work, and which
are still aspirational.

| Status     | Example                              | Section | Notes                                                 |
|------------|--------------------------------------|---------|-------------------------------------------------------|
| **verified (Fedora 44)** | `examples/03-driver-check/`        | §3      | r05c user run: cluster up, all 8 kube-system pods Running, ✓ SUCCESS |
| **in flight** | `examples/06-deploy-nginx-kubectl`   | §6      | r07a pivot (multi-stage build); awaiting user demo run on Fedora 44     |
| **in flight** | `examples/07-nodeport-service`        | §7      | Shipped in r08; awaiting user demo run on Fedora 44                     |
| unverified | `examples/07-nodeport-service`       | §7      | Expose Deployment via NodePort, retrieve URL          |
| unverified | `examples/08-persistent-volume`      | §8      | `hostPath` PV + dynamic PVC                           |
| unverified | `examples/09-deploy-nginx-helm`      | §9      | Same UBI nginx via an authored small helm chart       |
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

- **r07a** (2026-05-17, architectural-pivot) — Demo from r07
  failed: nginx Pods in `CrashLoopBackOff`. Initial diagnosis was
  correct (UBI nginx-124 is an s2i builder, expects content at
  `/opt/app-root/src`), but the first proposed fix (ConfigMap-
  mounted content + `command: ["nginx", "-g", "daemon off;"]`) was
  the wrong architecture. The user redirected to the right
  approach: **build our own image** from a standard UBI base via a
  multi-stage Containerfile (confirmed by LESSONS-LEARNED.md:
  "Mixing UBI builder + minimal runtime in a multi-stage build is
  common — the breadth of UBI helps build, the minimalism of
  Hummingbird helps deploy"). r07a delivers the pivoted approach:
  1. New `examples/06-deploy-nginx-kubectl/Containerfile` — two-
     stage build: `ubi9/ubi` builder stages the index.html, then
     `ubi9/ubi-minimal` runtime installs nginx via `microdnf`,
     reconfigures it for non-root + port 8080 (group-0-writable
     dirs, /tmp pid file, USER 1001 — OpenShift-compatible
     pattern), and copies the staged content. Both base images
     freely redistributable, no subscription-manager required
  2. New `examples/06-deploy-nginx-kubectl/index.html` — the
     baked-in sentinel content
  3. `manifests/deployment.yaml` rewritten — references
     `nginx-custom:v1` with `imagePullPolicy: IfNotPresent`; no
     command override, no volume mount, no ConfigMap dependency
  4. `demo.sh` adds a `minikube image build -t nginx-custom:v1
     -f Containerfile .` step before applying manifests. Also
     enhanced (carried over from the abandoned first r07a draft):
     `kubectl wait` timeout path now dumps logs from current and
     previous containers — so future similar failures
     self-diagnose without a separate log-capture round-trip
  5. §6 prose rewritten — "A small detour: building our own
     image" replaces the s2i-workaround discussion. Walks through
     the multi-stage Containerfile rationale, the three UBI
     variants (ubi / ubi-minimal / ubi-micro) and when to pick
     each, the OpenShift-compatible non-root pattern, and
     `minikube image build`. New "A note on SELinux" subsection
     introduces the `:Z` flag for the §8 PersistentVolume work to
     come — §6 itself doesn't need `:Z` (no host bind mounts) but
     this is where the convention enters the tutorial.
     Reconciliation plan: stale s2i-workaround claim removed;
     new `verified` claim recorded that UBI app images aren't
     directly runnable in plain Kubernetes (learned from the r07
     failure)
- **r08** (2026-05-17) — `_docs/07-services-nodeport.md` drafted
  (20-min section covering Service types comparison, NodePort
  mechanics, three patterns for reaching the NodePort, the
  30000-32767 range constraint, when NodePort isn't the right
  answer). `examples/07-nodeport-service/` shipped with its own
  Deployment + NodePort Service manifests, demo.sh, README.
  Reuses §6's `nginx-custom:v1` image (builds from §6's
  Containerfile automatically if not cached, so the demo is
  runnable without having run §6's first). Distinct resource
  names (`nginx-np`) and label (`app: nginx-np`) so it coexists
  with §6's `nginx` resources without selector confusion. Demo
  gets URL via `minikube service nginx-np --url` and curls it
  directly — no port-forward needed. Reconciliation: four new
  `unverified` §7 rows added; Section C
  `examples/07-nodeport-service/` set to `in flight`

**Open, priority-ordered:**

1. Run `examples/06-deploy-nginx-kubectl/demo.sh` against the
   default minikube cluster. On `✓ SUCCESS`, five §6 Section B
   rows promote plus Section C
2. Run `examples/07-nodeport-service/demo.sh`. On `✓ SUCCESS`,
   four §7 Section B rows promote plus Section C. (Can be run
   independently of §6's demo; will auto-build the image if §6's
   demo hasn't been run yet)
3. **r09** — §8 PVs + `examples/08-persistent-volume/`. First
   section to need `:Z` for SELinux on Fedora hostPath mounts
4. **r10** — §9 helm + authored small chart; helm-4-against-
   helm-3-chart compat claim from Section B promotes here
5. **r11** — §10 editor/shell/terminal; will request local-setup
   specifics
6. **r12** — §11 Istio (resource bump pre-flight; expect Section B
   resource claims to surface here)
7. **r13** — §12 KEDA (optional section)
8. **r14–r16** — tail sections, diagrams, editorial pass, final
   reconciliation refresh
