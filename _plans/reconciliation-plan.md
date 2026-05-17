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

| Status | Tool          | Version | Where pinned          | How to verify                                       |
|--------|---------------|---------|-----------------------|-----------------------------------------------------|
| unverified | minikube  | TBD     | §2 install commands   | `minikube version` matches the documented version   |
| unverified | kubectl   | TBD     | §2 install commands   | `kubectl version --client` matches                  |
| unverified | helm      | TBD     | §2 install commands   | `helm version` matches                              |
| unverified | istioctl  | TBD     | §11 install commands  | `istioctl version` matches                          |
| unverified | KEDA      | TBD     | §12 helm install args | `helm list -n keda` shows the documented chart ver  |
| unverified | KEDA HTTP add-on | TBD | §12 helm install args | `helm list -n keda` shows the add-on chart version  |
| unverified | Fedora    | 44      | §1 platform statement | `cat /etc/fedora-release` reports Fedora 44         |
| unverified | Podman    | TBD     | §1 prereq check       | `podman --version` matches the documented version   |

## B. Per-section claims

Claims made in prose that are not yet end-to-end verified. New
rows added as sections get drafted.

| Status     | Claim                                                                | Section | Notes                                                                                |
|------------|----------------------------------------------------------------------|---------|--------------------------------------------------------------------------------------|
| unverified | 4 CPU / 8 GB RAM / 20 GB free disk is sufficient for §1–§10           | §1      | Tutorial floor; promote after walking §1–§10 on hardware near this floor             |
| unverified | 6 CPU / 16 GB RAM / 50 GB free disk is comfortable for §1–§12         | §1      | "Comfortable for all" recommendation; verify when §11 + §12 are complete             |
| unverified | Podman runs rootless on Fedora 44 with the §1 UBI test command       | §1      | `podman run --rm ubi9/ubi-minimal id` returns successful exit                        |
| unverified | The podman driver works without KVM/qemu/VirtualBox on Fedora 44      | §1, §3  | Resolve in r05 when §3 + driver-check example land                                   |
| unverified | No SELinux `:Z` flag needed for minikube hostPath PVs                 | §1, §8  | Resolve in r09 when persistent-volume example lands                                  |
| unverified | UBI images at `registry.access.redhat.com` are pullable without subscription | §1      | Implicitly tested by the §1 verification block; promote when that's run cleanly      |

## C. Testing matrix

End-to-end tests of each runnable example. This is where the
reconciliation plan earns its keep — a reviewer should see at a
glance which examples are confirmed to actually work, and which
are still aspirational.

| Status     | Example                              | Section | Notes                                                 |
|------------|--------------------------------------|---------|-------------------------------------------------------|
| unverified | `examples/03-driver-check/`          | §3      | Sanity: podman driver starts a cluster, status green  |
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

**In flight:**

- **r03** — `_docs/01-prerequisites.md` drafted; iteration plan
  codified at `_plans/iteration-plan.md`; `CONTRIBUTING.md`
  added at repo root; `scripts/audit-fedora-prereqs.sh` added
  for capturing Fedora 44 environment state. Awaiting first-run
  audit output to resolve Section A version pins for r04

**Open, priority-ordered:**

1. Run `scripts/audit-fedora-prereqs.sh` on Fedora 44 and paste
   the output back to the iteration thread; that data resolves
   Section A version rows
2. **r04** — draft §2 installation with version pins set from
   the audit output; promote Section A rows from `unverified` to
   `verified (Fedora 44)` as each tool's install is confirmed
3. **r05** — draft §3 starting minikube + `examples/03-driver-check/`;
   resolves the "podman driver works without KVM" claim in §3
4. **r06** — draft §4 profiles/multi-node + §5 addons
5. **r07** — draft §6 kubectl + `examples/06-deploy-nginx-kubectl/`
   — the first example that the Section C testing matrix can
   meaningfully validate
6. **r08–r09** — drafts §7–§8 with examples
7. **r10** — §9 helm + authored small chart
8. **r11** — §10 editor/shell/terminal; will request local-setup
   specifics (warp.dev workflows, CLion settings)
9. **r12** — §11 Istio (resource-bump pre-flight; expect Section B
   claims around resource usage to surface here)
10. **r13** — §12 KEDA (optional)
11. **r14–r16** — tail sections, diagrams, editorial pass,
    final reconciliation refresh
