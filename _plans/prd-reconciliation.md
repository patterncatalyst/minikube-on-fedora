---
title: PRD reconciliation
description: What we set out to build per the original PRD, what shipped, and where intent and delivery diverged.
render_with_liquid: false
---

> Counterpart to `reconciliation-plan.md`, focused on the high-level
> question: what did we set out to build (per the original PRD),
> what did we actually ship, and where did intent and delivery diverge?
>
> This document is the "intended" vs "what we shipped" diff the PRD
> template itself anticipated would be instructive at project close.

---

## Summary

A 15-section, ~5–7 hour hands-on Kubernetes tutorial targeting Fedora 44
users running rootless Podman. Twelve technical sections (§1–§12) all
verified end-to-end on Fedora 44; three tail sections (§13–§15) provide
alternatives comparison, FAQ + cleanup recipes, and forward pointers.
Five paired SVG + Excalidraw diagrams; per-example `cleanup.sh` scripts
at three tiers; reconciliation plan tracking **107 verified facts**.

The original PRD was a template with many `TODO:` markers; some of those
were filled in by behavior (decisions made while writing), some were
elided (decisions deferred or reconsidered). This document captures the
deltas explicitly.

---

## Goals — planned vs shipped

| PRD goal (paraphrased) | Status | Notes |
|---|---|---|
| Reader can do TODO without consulting other resources | ✓ (concretized) | Reader can stand up minikube on Fedora 44 (rootless Podman), build images, deploy via kubectl + helm, install Istio for service mesh, and install KEDA for event-driven autoscaling — all without consulting other resources |
| Reader understands *why* the patterns work, not just commands | ✓ | Every section explains the mental model alongside the commands. The "Sidebar: native sidecars" callout in §11 and the HPA-vs-KEDA conceptual section in §12 are concrete examples of why-over-how |
| Examples build and run end-to-end on TODO platforms with no manual fixups | ⚠ (Fedora 44 only) | Originally planned for Fedora 43+ and macOS; shipped Fedora 44 only. macOS support was descoped early — see "Divergences" below |

## Non-goals — planned vs shipped

| PRD non-goal | Status |
|---|---|
| Does NOT teach container basics (assumed prereq) | ✓ As planned |
| Does NOT cover production hardening (cert rotation at scale, multi-region, etc.) | ✓ As planned; §15 ("Where to go next") points at production-like upgrades |
| Does NOT compare specific vendor products | ⚠ §13 ("Alternatives to minikube") deliberately *does* compare kind, k3s, microk8s, MicroShift, and minikube. The PRD's vendor-neutral stance was relaxed when the question "should I use minikube or one of these?" turned out to be exactly the kind of practical comparison a Fedora reader needs at the end. The comparison is honest (microk8s gets criticized for Fedora compatibility, MicroShift for being RHEL-only) rather than promotional |

## Audience — planned vs shipped

The PRD audience section was almost entirely `TODO:`. The shipped
tutorial concretized this as:

- **Primary audience**: Fedora 44 desktop/workstation users with basic
  container experience (knows what an image is, can run `podman build`)
  who want Kubernetes on their machine without Docker Desktop or a
  managed cloud cluster
- **Secondary audience**: Linux developers on other distributions —
  most material applies, but examples are tested on Fedora 44 only
- **Not served**: Beginners who haven't used containers; Windows users
  without WSL; anyone needing macOS instructions

---

## Sections — planned outline vs shipped outline

The PRD had a "first cut" sections table with mostly `TODO:` titles
and durations. Shipped outline:

| § | Title | Verified |
|---|---|---|
| §1 | Prerequisites | ✓ Fedora 44 |
| §2 | Tooling install (kubectl, helm, yq, hey, krew) | ✓ |
| §3 | Starting minikube (rootless Podman + containerd) | ✓ |
| §4 | Profiles + multi-node | ✓ |
| §5 | Addons + dashboard | ✓ |
| §6 | Deploy via kubectl (custom UBI image) | ✓ |
| §7 | NodePort (with slirp4netns tunnel) | ✓ |
| §8 | Persistent Volumes (initContainer-seeds-PV) | ✓ |
| §9 | helm (with checksum-annotation rollout) | ✓ |
| §10 | Editor/shell/terminal (k9s, kubectx, etc.) | mostly ✓ |
| §11 | Istio (Bookinfo + native sidecars + Kiali) | ✓ |
| §12 | KEDA (Strimzi Kafka 4.1.0 + HTTP add-on) | ✓ |
| §13 | Alternatives to minikube | prose only (no demo) |
| §14 | FAQ + cleanup recipes | prose only |
| §15 | Where to go next | prose only |

Total reader duration: ~5–7 hours for the complete walkthrough,
~3–4 hours if §11 (Istio) is skipped (it's the longest single section
and is explicitly marked as a reference section).

---

## Divergences (and why)

### macOS support dropped
**Planned**: Fedora 43+ and current macOS as primary platforms.
**Shipped**: Fedora 44 only.

Reason: macOS has a fundamentally different container story (Podman
Machine wraps Linux in a VM, which adds another layer to the topology;
minikube's resource accounting also differs). Supporting macOS would
have required either parallel sections or an awkward "Linux readers
skip this" structure. The compromise was to acknowledge macOS users
in §13 (the Alternatives section mentions CRC as the Fedora→macOS
path via OpenShift Local) and keep the technical content focused.

### UBI base images instead of Hummingbird
**Planned**: Hummingbird image catalog at quay.io/hummingbird.
**Shipped**: Red Hat UBI 9 (`registry.access.redhat.com/ubi9/ubi-minimal`).

Reason: Hummingbird was speculative when the PRD was written; UBI is
production-grade, freely distributable without subscription-manager
on Fedora, and matches what Fedora-adjacent users already encounter
in OpenShift contexts. The trade-off is image size (UBI is ~80 MB
larger than Alpine) but the layering benefits and Fedora-ecosystem
familiarity were worth it.

### Vendor-neutral language relaxed for §13
**Planned**: Vendor-neutral; readers can compare for themselves.
**Shipped**: §13 explicitly compares kind / k3s / microk8s / MicroShift,
with honest assessments about Fedora compatibility specifically.

Reason: After ~10 hours of writing the tutorial, the practical question
"should I have used kind instead of minikube?" was clearly something a
careful reader would ask. Refusing to answer would have left them
hunting for fragmented opinions elsewhere. The Fedora-centric framing
made the comparison defensible — it's not "kind is bad" but "kind has
specific strengths for CI work; here's when to pick it on Fedora".

### "We" voice not strictly avoided
**Planned**: PRD said "no 'we' voice (use 'you' for the reader and either
passive or third-person otherwise)".
**Shipped**: ~7 instances of "we'll" / "we" remain across §11 and §12.

Reason: Mechanical voice-conversion would have produced awkward phrasing
in places. The instances are contextual ("if we had one"; quoted upstream
text like KEDA's README; "we go with Strimzi" introducing a tutorial
choice). The audit script (`scripts/editorial-audit.sh`) flags these so
they can be reviewed section-by-section later if desired.

### Specific Podman version not pinned
**Planned**: PRD listed "Specific Podman version with feature X" as a
dependency.
**Shipped**: No specific Podman version pinned. The §1 prerequisites
script reports the installed Podman version; the tutorial was tested
on Fedora 44's default Podman 5.8.2.

Reason: Pinning a specific version would have made the tutorial
fragile to Podman's release cadence (Fedora rebases regularly). The
features we use (rootless, user-namespaced, no daemon) have been
stable since Podman 4.x. Better to fail loudly via the prereq script
if something genuinely breaks than to require an exact version.

---

## Process observations worth recording

Things learned during ~17 iterations that are likely to apply to
future tutorial projects:

1. **Ship assets and their referencing prose in the same iteration.**
   r16 shipped 5 SVG files without updating §3/§6/§11/§12 to reference
   them. The result was 4 iterations (r16, r16a, r16b, r16c) of
   recovery: auto-splice, fix layering, fix more layering, finally
   precise ASCII-to-SVG replacement. Lesson: visual content needs its
   referencing prose at the same moment, or the assets are orphaned.

2. **kramdown HTML-collision is a real failure mode.** The §14 FAQ
   shipped initially with `<placeholder>` patterns inside inline
   backticks; kramdown interpreted these as HTML opening tags and
   the cascade swallowed multiple Q&A entries. Use `[placeholder]`
   instead. The audit script catches this pattern.

3. **`{% raw %}` doesn't do what you might expect inside image src.**
   Wrapping `{{ "/foo" | relative_url }}` in `{% raw %}` prevents
   Liquid evaluation, leaving the literal `{{ ... }}` text as the
   image URL. Three image embeds in §11 and §12 had this pattern;
   r17 removed the wraps.

4. **Auto-splice is unsafe when destination files already contain
   related content.** A heuristic that finds the first `## ` heading
   and inserts a new embed has no way to know whether existing ASCII
   art at that location represents the same concept. r16b's
   auto-splice ran *alongside* existing ASCII; r16c had to do precise
   `str_replace` on the original content to clean up. Lesson: replace
   ASCII with SVG in place via known-content matching, not
   heuristic insertion.

5. **Cross-reference links don't get updated by section renames.**
   When §13 was renamed Wrap-up → Alternatives in r14a, the §12→§13
   footer link orphaned and pointed at a dead URL for 4 iterations
   before being caught. The `check-cross-references.sh` script makes
   this a one-command check, runnable in CI.

6. **CI build-success is necessary but not sufficient verification.**
   Jekyll built fine for the §14 FAQ kramdown collision; the page
   "rendered" but the rendering was wrong. Only a human eyeballing
   the deployed preview catches this class of bug. Lesson: build CI
   catches syntax errors; visual review catches semantic errors. Do
   both.

---

## Reconciliation plan integration

The detailed iteration-by-iteration history is in
`reconciliation-plan.md`. That document tracks:

- **107 verified facts** (rows in Section B) — each demo, each
  command, each pre-flight check verified on real Fedora 44
- **17 iterations** documented in Section D — what each iteration
  shipped, why, what was learned
- **Open priorities** at end of plan — remaining low-value cleanup
  items if anyone wants to push further

When new contributors arrive: read the PRD first (intent), then this
document (intent vs shipped), then the reconciliation plan (every
specific decision and why). That's the recommended order.

---

## Addendum: project reopened (§16 examples hub + §17 capstone)

The summary above describes the original 15-section project at its
first close (**107 verified facts**). The project subsequently
reopened to add two things, so this document's "shipped" picture has
moved on:

- **§16 — Examples hub** (r18 family): a generated index of the
  per-example pages, with a `sync-example-pages.sh` script that
  renders `examples/*/README.md` into browsable pages. Onboarding
  docs moved under `onboarding/`.
- **§17 — Capstone: a data mesh on minikube** (r19 onward, in
  progress): a five-service data mesh (order / inventory / payment /
  shipping / notification) demonstrating REST + gRPC + GraphQL +
  Kafka, deployed via a helm umbrella chart to a dedicated `capstone`
  profile, with Postgres (CloudNativePG), Apicurio, OpenMetadata,
  observability, and Prefect. Architectural choices are tracked
  separately in `_plans/capstone-decisions.md` (CAP-001 … CAP-010).

**Current verified count: 112** (was 107). The five new facts come
from r21c — the order-service walking skeleton, verified end-to-end
on Fedora 44 (image build → in-cluster registry → operator-managed
Postgres → REST round-trip → row persisted).

**A divergence worth recording, in the spirit of this document:** the
capstone took six iterations (r21 → r21c) to stand up its *first*
service, almost entirely due to image-distribution friction on the
rootless-podman + containerd driver — not the application code, the
helm charts, or the operators, all of which worked on first or second
try. The lasting fix (minikube's in-cluster registry, plus
`MINIKUBE_ROOTLESS=true` as mandatory) is documented as CAP-007/009/010
and called out for readers in §17's "known friction" section. The
genuinely scary pre-identified risk — CloudNativePG on rootless-podman
minikube — did **not** materialize; the operator provisioned a Ready
primary in seconds. A reminder that the risks you plan for and the
risks that bite are often different ones.

The §13 vendor-neutrality divergence noted above also deepened in the
capstone: §17 names specific tools throughout (Strimzi, KEDA, Istio,
CloudNativePG, Apicurio, OpenMetadata, Prefect, Strawberry) because a
working data mesh requires concrete choices. These are presented as
"a defensible set of choices for this stack," not endorsements, with
rationale in the decision log.
