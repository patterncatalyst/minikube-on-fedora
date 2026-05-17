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

| Status | Claim | Section | Notes |
|--------|-------|---------|-------|
| (no rows yet — sections are not drafted) | | | |

## C. Testing matrix

End-to-end tests of each runnable example. This is where the
reconciliation plan earns its keep — a reviewer should see at a
glance which examples are confirmed to actually work, and which
are still aspirational.

| Status     | Example                              | Section | Notes                                                 |
|------------|--------------------------------------|---------|-------------------------------------------------------|
| unverified | `examples/06-deploy-nginx-kubectl`   | §6      | Deploy UBI nginx via `kubectl apply`, hit NodePort    |
| unverified | `examples/07-nodeport-service`       | §7      | Expose Deployment via NodePort, retrieve URL          |
| unverified | `examples/08-persistent-volume`      | §8      | `hostPath` PV + dynamic PVC                           |
| unverified | `examples/09-deploy-nginx-helm`      | §9      | Same UBI nginx via an authored small helm chart       |
| unverified | `examples/11-istio-bookinfo`         | §11     | Istio sample app with sidecar + Gateway + VS          |
| unverified | `examples/12-keda-http-scale`        | §12     | KEDA HTTP add-on + `hey` load test                    |

**Aggregator status:** `scripts/test-all-examples.sh` does not
yet exist; will be added once the first example's `demo.sh`
passes on its own.

## D. Open priorities

Roughly priority-ordered list of what to do next. Updated each
time the project moves forward.

**Done:**

- ✅ PRD drafted and approved (r01)
- ✅ Skeleton scaffolded with project branding (r02 — this iteration)

**Open, priority-ordered:**

1. Verify `minikube`, `kubectl`, and `helm` install paths on
   Fedora 44 — are they in standard repos or via upstream
   installers? (Resolves three rows in Section A above)
2. Draft §1 prerequisites against a fresh Fedora 44 install
3. Draft §2 installation; pin tool versions in Section A
4. Draft §3 starting minikube with the podman driver; resolve
   any rootless-podman gotchas in the same pass
5. Build `examples/06-deploy-nginx-kubectl/` end-to-end before
   drafting §6 prose (test code first, then prose — per
   `LESSONS-LEARNED.md`)
6. Draft §4–§5 (profiles, multi-node, addons)
7. Draft §6–§7 prose now that the example works
8. Author the small helm chart for §9; verify against the same
   UBI nginx workload
9. Draft §9 helm; refresh §10 editor/shell/terminal integration
10. Tackle §11 Istio: bump minikube resources, install
    `istioctl`, get bookinfo demo running, draft prose
11. Tackle §12 KEDA + HTTP add-on (optional section)
12. Draft §13–§15, cross-section editorial pass, diagrams
