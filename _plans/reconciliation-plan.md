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
| unverified              | minikube         | v1.38.x       | §2 install (RPM)      | `minikube version` matches after running §2 install        |
| unverified              | kubectl          | v1.34.x+ (1.35.3 observed) | §2 install (upstream binary; skipped if recent already present) | `kubectl version --client=true` reports 1.34+ |
| unverified              | helm             | 4.1.1         | §2 install (`dnf install helm`) | `helm version --short` reports v4.1.1                   |
| unverified              | httpie           | 3.2.4         | §2 install (`dnf install httpie`) | `http --version` reports 3.2.4                         |
| unverified              | yq (mikefarah)   | 4.47.1        | §2 install (`dnf install yq`) | `yq --version` reports v4.x                                |
| unverified              | krew             | latest        | §2 install (upstream installer) | `kubectl krew version` reports installed                |
| unverified              | stern            | latest (krew) | §2 install (`kubectl krew install stern`) | `kubectl plugin list` shows stern                     |
| unverified              | kubectx / kubens (krew names: ctx, ns) | latest (krew) | §2 install (`kubectl krew install ctx ns`) | `kubectl plugin list` shows ctx and ns |
| unverified              | hey              | latest (Go)   | §2 install (`go install`); pre-existing acceptable | `hey --help` returns help text                |
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
| unverified              | The podman driver works without KVM/qemu/VirtualBox on Fedora 44             | §1, §3  | Promotes when `examples/03-driver-check/demo.sh` passes (r05)               |
| unverified              | No SELinux `:Z` flag needed for minikube hostPath PVs                        | §1, §8  | Resolve in r09 when persistent-volume example lands                         |
| unverified              | `minikube` RPM from `storage.googleapis.com` installs cleanly via `dnf`      | §2      | r04 prose claim; promote once user runs §2 install                          |
| unverified              | `helm 4.1.x` from Fedora repos works against Helm 3-format charts            | §2, §9  | r04 prose claim; promote in r10 when first helm install lands               |
| unverified              | `kubectl 1.35.x` client works against minikube-default 1.35.x cluster        | §2, §3  | Implied by version skew policy; promotes when driver-check demo passes      |
| unverified              | krew installer + `kubectl krew install stern ctx ns` works as documented     | §2      | r04 prose claim; promote once user runs §2 install                          |
| unverified              | mikefarah yq is `dnf install yq` on Fedora 44 (not python-yq)                | §2      | r05 prose correction; promote once user runs §2 install                     |
| unverified              | `minikube start --driver=podman` brings up a healthy cluster                 | §3      | Promotes when driver-check demo passes                                      |
| unverified              | `minikube pause/unpause/stop/delete` cluster-lifecycle commands work         | §3      | Pause/stop not exercised in driver-check; defer or add lifecycle demo later |

## C. Testing matrix

End-to-end tests of each runnable example. This is where the
reconciliation plan earns its keep — a reviewer should see at a
glance which examples are confirmed to actually work, and which
are still aspirational.

| Status     | Example                              | Section | Notes                                                 |
|------------|--------------------------------------|---------|-------------------------------------------------------|
| **in flight** | `examples/03-driver-check/`       | §3      | Shipped in r05; awaiting user run on Fedora 44        |
| unverified | `examples/06-deploy-nginx-kubectl`   | §6      | Deploy UBI nginx via `kubectl apply`, hit NodePort    |
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
  `maybe()` stderr leak). User re-ran audit post-r04;
  surfaced one finding rolled into r05

**In flight:**

- **r05** — `_docs/03-starting-minikube.md` drafted (cluster
  start, layers, status, lifecycle, drivers, in-cluster
  runtime). `examples/03-driver-check/` added — the project's
  first runnable demo. **r04 follow-up fix in §2**: yq is
  packaged in Fedora 44 as mikefarah's yq (4.47.1, confirmed
  via r04-post audit), so §2's install instruction is now
  `sudo dnf install -y yq` rather than the upstream binary
  download; the historical "python-yq" concern doesn't apply
  on Fedora 44

**Open, priority-ordered:**

1. Run §2 install commands (if not already) and §3 happy path
   on Fedora 44; then run `examples/03-driver-check/demo.sh`.
   On `✓ SUCCESS`, the demo's Section C row promotes to
   `verified (Fedora 44)`, along with §1/§3 claims about the
   podman driver, kubectl-against-cluster, and the §2 install
   paths
2. **r06** — draft §4 profiles/multi-node + §5 addons (small
   sections combined)
3. **r07** — draft §6 kubectl + `examples/06-deploy-nginx-kubectl/`
   — first example to deploy a workload, not just verify
   cluster health
4. **r08–r09** — §7 + §8 with examples
5. **r10** — §9 helm + authored small chart; helm 4.x compat
   claim from Section B promotes when first `helm install` lands
6. **r11** — §10 editor/shell/terminal; will request local-setup
   specifics (warp.dev workflows, CLion settings)
7. **r12** — §11 Istio (resource bump pre-flight; expect Section B
   resource claims to surface here)
8. **r13** — §12 KEDA (optional section)
9. **r14–r16** — tail sections, diagrams, editorial pass,
    final reconciliation refresh
