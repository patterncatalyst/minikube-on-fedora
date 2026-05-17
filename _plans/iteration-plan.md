---
title: Iteration plan
description: Six-phase roadmap from PRD to launch, with verification rhythm and known flex points.
render_with_liquid: false
---

This is the roadmap from approved PRD (`_r01`) to public launch.
Sixteen iterations across six phases; some optional; flexible
about combining or splitting as real-hardware testing reveals
where the work concentrates.

Each iteration ships as `minikube-on-fedora_rNN.tar.gz` per the
cadence in `CONTRIBUTING.md` at the repo root. The
[reconciliation plan]({{ "/plans/reconciliation-plan/" | relative_url }})
tracks verification state for every claim across all iterations.

## Phase 1 — Foundation

| r#  | Deliverables                                                                          | Status     |
|-----|---------------------------------------------------------------------------------------|------------|
| r01 | PRD drafted; decisions logged                                                         | ✅ done    |
| r02 | Skeleton branded: `_config.yml`, README, outline, recon plan, LICENSE, index.html; PRD fix | ✅ done    |

## Phase 2 — Setup and install

| r#  | Deliverables                                                                          | Status     |
|-----|---------------------------------------------------------------------------------------|------------|
| r03 | `_docs/01-prerequisites.md`; iteration plan; `CONTRIBUTING.md`; Fedora 44 audit script | in flight  |
| r04 | `_docs/02-installation.md` with version pins from r03 audit output                    | open       |
| r05 | `_docs/03-starting-minikube.md` + `examples/03-driver-check/`                         | open       |

## Phase 3 — Core minikube operations

| r#  | Deliverables                                                                          | Status     |
|-----|---------------------------------------------------------------------------------------|------------|
| r06 | `_docs/04-profiles-multi-node.md` + `_docs/05-addons-dashboard.md` (small sections combined) | open       |
| r07 | `_docs/06-deploying-with-kubectl.md` + `examples/06-deploy-nginx-kubectl/`             | open       |
| r08 | `_docs/07-services-nodeport.md` + `examples/07-nodeport-service/`                     | open       |
| r09 | `_docs/08-persistent-volumes.md` + `examples/08-persistent-volume/`                   | open       |

## Phase 4 — Helm and developer integration

| r#  | Deliverables                                                                          | Status     |
|-----|---------------------------------------------------------------------------------------|------------|
| r10 | `_docs/09-deploying-with-helm.md` + `examples/09-deploy-nginx-helm/` (authored chart) | open       |
| r11 | `_docs/10-editor-shell-terminal.md` (CLion plugin, Podman Desktop, zsh, warp.dev)     | open       |

## Phase 5 — Service mesh and autoscaling

| r#  | Deliverables                                                                          | Status     |
|-----|---------------------------------------------------------------------------------------|------------|
| r12 | `_docs/11-istio-on-minikube.md` + `examples/11-istio-bookinfo/`                       | open       |
| r13 | `_docs/12-keda-on-minikube.md` + `examples/12-keda-http-scale/` (optional section)    | open       |

## Phase 6 — Polish and launch

| r#  | Deliverables                                                                          | Status     |
|-----|---------------------------------------------------------------------------------------|------------|
| r14 | `_docs/13-alternatives.md` + `_docs/14-faq.md` + `_docs/15-where-next.md`             | open       |
| r15 | All diagrams (paired `.svg` + `.excalidraw`); remaining homepage cards                 | open       |
| r16 | Cross-section editorial pass; final reconciliation refresh; PRD timeline marked complete | open       |

## Within-iteration verification rhythm

For any iteration that ships an example, the pattern is:

1. Tarball delivered with example dir, section prose, and updated
   reconciliation rows marked `in flight`
2. Extract into `~/Dev/minikube-on-fedora/`, push, `gh run watch`
   confirms the site build is green
3. `cd examples/NN-name/ && ./demo.sh`; output shared back
4. **If pass:** next iteration's first move is bumping that row
   to `verified (Fedora 44)` in the reconciliation plan's
   Section C testing matrix
5. **If fail:** diagnose from output, fix in same iteration as
   `_rNNa`, re-run

This honors "tested code first, then prose" from
`LESSONS-LEARNED.md` without doubling the iteration count — the
prose ships alongside the code, but doesn't claim `verified`
status until the test passes on real Fedora 44 hardware.

## Optionality and flex points

The plan above is the **default flow**, not a contract. Known
places where it bends:

### §12 KEDA is genuinely optional

If midway through Phase 4 the decision is to ship without KEDA,
r13 is skipped entirely and Phase 6 reorders around the missing
section. The PRD already flags §12 as optional and the outline
(§0) treats §11 and §12 as skippable.

### r11 editor/shell content depends on actual setup

§10 covers CLion's Kubernetes plugin, Podman Desktop's k8s view,
zsh integration, and warp.dev workflows. Some of these
(especially warp.dev workflows and any non-default CLion settings)
are easier to write from screenshots or terminal snippets of the
actual local setup than from public docs. r11 will request those
when we reach it.

### Iteration grouping is flexible

If a combined iteration (r06 packs profiles + addons; r14 packs
three small sections) turns out too dense in practice, it splits.
If a "single section" iteration turns out lightweight, it merges
with the next. **Phase boundaries are stable; iteration boundaries
inside them are not.**

### Section order is also flexible

If a real-world need elsewhere (a separate project bottlenecked
on §11 Istio reference, for example) makes it sensible to jump
ahead, that's allowed. Phase 2 prereqs are easier to backfill
than the meatier sections; the dependency that matters most is
"you need a running minikube cluster before §6 will work", which
means r03 → r05 must precede the example-heavy iterations
regardless of section ordering.

### When a phase completes

At the end of each phase, the phase table above gets its rows
flipped to ✅, and the reconciliation plan's Section D gets a
`## Phase N done` heading appended with the date. If priorities
shift mid-stream, this document is the one that gets revised; the
PRD's decision log records the rationale.
