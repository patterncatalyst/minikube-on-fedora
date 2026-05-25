---
title: Phase C plan — narrative restructure (one page → a section set)
description: Working skeleton for restructuring §17 into a navigable section set. A plan to react to, NOT final prose. Read the current page against this before writing.
render_with_liquid: false
---

> **Status: DRAFT skeleton for review.** Drafted while the author was away, from
> the current `_docs/17-capstone.md` (1241 lines), the 15 diagrams in
> `presentation/data-mesh-101/diagrams/`, the roadmap's Phase C topics, and the
> full decision log. The first thing to do on resuming is read the current page
> top-to-bottom against this skeleton and correct the mapping — the existing prose
> is substantial and good; this is a reorganization, not a rewrite.

## The core finding

§17 is **not a blank page** — it's a 1241-line single page that already contains
most of Phase C's content, just laid out linearly. So the restructure is mostly
**reorganization + gap-filling**, not new writing:

- The **operational/how-to prose already exists** and is solid (services, images,
  Postgres operator, GraphQL, Kafka, contracts/registry/catalog, canary, KEDA,
  observability, troubleshooting). It mostly needs *relocating* into dedicated
  sections, not rewriting.
- The **conceptual "why" sections are comparatively thin** ("What is a data mesh?",
  "The four principles", "Why this maps to Kubernetes" are ~15-30 lines each) and
  are where the 15 concept diagrams + new narrative add the most value.
- **One topic is entirely unwritten and now owed: the selective-injection
  decision** (see §"New section to write" below). Tonight's saga is the material.

## Decision to make first (blocks the section layout)

**How to physically split the page.** Two options — need the author's call:

- **(A) Landing + child pages.** `17-capstone.md` becomes a short overview/landing
  that links to dedicated pages (`17a-…`, `17b-…` or a subdirectory). Cleanest
  navigation; matches the roadmap's "overview/landing plus dedicated sections."
  Cost: Jekyll nav/ordering wiring, cross-link updates, and the cross-reference
  linter (`check-cross-references.sh`) must stay green across the new files.
- **(B) One long page, restructured in place.** Keep a single page but reorder into
  the clean section sequence with a table-of-contents jump-list at top. Lower
  tooling risk (no new files/nav), preserves all existing anchors. Cost: still a
  very long page.

Recommendation: **(A)** matches the roadmap intent and the "outgrown a single page"
premise — but it's the bigger tooling change, so confirm before splitting. The
section *content/sequence* below is identical either way; only the file boundaries
differ.

## Proposed section sequence (the narrative spine)

Ordered concept → substrate → the mesh affordances in build order → operate →
observe. Each row: target section, where its prose comes from in the current page,
and the diagram to pair.

| # | Section | Prose source (current page) | Diagram (presentation/.../diagrams/) |
|---|---------|------------------------------|--------------------------------------|
| 0 | Overview / landing | intro (lines 9-24) + "Architecture overview" (108) | `data-mesh-overview.svg` |
| 1 | What a data mesh is | "What is a data mesh?" (25) | `monolith-to-mesh.svg`, `operational-vs-analytical.svg` |
| 2 | The four principles | "The four principles" (43) | `four-principles.svg`, `federated-governance-model.svg` |
| 3 | Why Kubernetes is the substrate | "Why this maps to Kubernetes" (78) | `platform-planes.svg`, `logical-mesh-architecture.svg` |
| 4 | The services & data products | "The five services" (130), "order-service" (293) | `data-product-anatomy.svg` |
| 5 | Contracts & the registry (Apicurio) | "Contracts, the registry, and the catalog" (689) | `contract-flow.svg`, `contracts-registry-catalog.svg` |
| 6 | The catalog & discovery (OpenMetadata) | "catalog as a mesh requirement" (765), "Deploying the catalog" (819), "Pointing ingestion… lineage" (891) | `contracts-registry-catalog.svg` (shared) |
| 7 | The async backbone (Kafka) | "The async spine: events with Kafka" (541) | `ingestion-streaming-sourcing.svg` |
| 8 | The read layer (GraphQL/REST/gRPC) | "The read layer: GraphQL federation" (495) | `analytical-data-composition.svg` |
| 9 | Progressive delivery & mTLS (Istio) | "Evolving a contract… canary" (938) + **NEW selective-injection** | `reference-data-mesh-architecture.svg` (mesh portion) |
| 10 | Elastic data products (KEDA) | "Scaling to demand, and to zero" (978) | (no dedicated 101 diagram — may need a new one in Phase D) |
| 11 | Recoverability (cloud-native) | "Operating the cluster: bring-up and troubleshooting" (1111) + the failure-cascade lessons | `decentralization-checklist.svg`? (weak fit — candidate for a new diagram) |
| 12 | Observability | "Seeing it: metrics with Prometheus and Grafana" (1042) + tracing arc | `reference-data-mesh-architecture.svg` (obs portion) |
| 13 | Where to go next | "What the capstone builds… ahead" (1176), "References" (1199), "directory" (1214) | — |

Diagrams not yet placed: `central-team-bottleneck.svg` (fits §1 or §2 as the
"problem" framing), `analytical-data-composition.svg` (could anchor §8),
`reference-data-mesh-architecture.svg` (the big one — likely the overview or §9/§12).
Two topics (KEDA §10, recoverability §11) have **no strong existing diagram** — flag
as candidates for new diagrams the author may add in Phase D.

## New section to write (not in the current page): selective Istio injection

This is the one genuinely new piece of prose, and Phase C is its home. It belongs
in §9 (Istio) as a decision/lesson callout. The material is first-hand from the
build saga (decision log CAP-034, CAP-038, CAP-040, CAP-041):

**The claim:** mesh *selectively* (only the workloads that need the mesh — here,
order-service for the canary), not namespace-wide. Namespace-wide
`istio-injection=enabled` is convenient but couples the whole namespace to the mesh
in ways that bite.

**The evidence (lived, not theoretical):**
- **Batch Jobs can't complete when meshed** — the OpenMetadata ingestion Jobs got
  an istio-proxy that never exits, so the Job hung `0/2` forever (CAP-034). Jobs
  had to opt out explicitly.
- **Operator-managed infra with its own TLS collides with Envoy** — CloudNativePG
  runs TLS on its instance-manager/replication ports; an injected sidecar
  re-wrapped those connections and crash-looped Postgres (exit 2, "HTTP
  communication issue"). Excluding Postgres from the mesh fixed it (CAP-038).
- **istiod becomes a fail-closed dependency for *every* pod-create** — when the
  injection webhook was briefly unreachable, *no* pod in the namespace could be
  created (not just mesh pods). With selective injection, an istiod blip only
  affects the meshed workloads (CAP-040 context).

**The guidance:** label namespaces for injection only when most workloads belong in
the mesh; otherwise opt specific workloads in (`sidecar.istio.io/inject: "true"` on
the pod template) and keep operator-managed infra (databases, Kafka, registries,
catalog) and short-lived Jobs out. State the trade-off honestly: namespace-wide is
simpler to reason about and gives blanket mTLS; selective is more resilient and
avoids the three failure classes above.

I can draft this section's prose in full now (it's the part I have authoritative
material for) — left as a stub here pending the (A)/(B) file-layout decision so it
lands in the right place.

## Editorial constraints to preserve (from the existing page's voice)

- Prose, not bullet-dumps; "you" for the reader; explains *why* alongside *how*.
- Vendor-neutral; no competitor comparisons.
- Diagrams are SVG (scale on hi-DPI), adopted into `assets/diagrams/` under the
  `NN-name` convention as each section is written (per roadmap line 53).
- `_plans/*` and any new `_docs/*` must keep `render_with_liquid: false` where they
  contain `{{ }}`/`{% %}`, and pass `check-liquid-collisions.sh` +
  `check-cross-references.sh` before push.

## Suggested work order for the writing sessions

1. **Decide (A) vs (B)** file layout — unblocks everything.
2. Adopt diagrams into `assets/diagrams/` (`NN-name.svg`) per the mapping table.
3. Move existing prose into the section sequence (mechanical; preserve anchors).
4. Write the thin conceptual sections (§1-3) up to the depth the diagrams support.
5. Write the **selective-injection** section (§9) — the one net-new piece.
6. Thread the narrative: short connective intros/outros so sections flow as a set.
7. Re-run both linters; update reconciliation (Phase C rows) + a CAP entry for the
   restructure decision.

## Resolved facts (checked from the sandbox)

- **`assets/diagrams/` already exists** and uses the `NN-name` convention — and
  **three §17 diagrams are already adopted**: `17-capstone-data-mesh.svg`,
  `17-capstone-contracts.svg`, `17-capstone-contract-flow.svg` (plus
  `03-minikube-topology`, `06-k8s-primitives`, `11-istio-mesh`, `12-hpa-vs-keda`,
  `12-keda-http-addon` for earlier sections). So the adoption pattern is set; new
  Phase C diagrams continue as `17-<topic>.svg`. NB: the current page already
  references some of these, so when reorganizing, **preserve existing image refs**
  and only add the unadopted 101 diagrams (e.g. `four-principles`,
  `monolith-to-mesh`, `operational-vs-analytical`, `platform-planes`) as their
  sections get written.
- **Pages order by a front-matter `order:` integer** (capstone is `order: 17`,
  examples `order: 16`). This shapes option (A): child pages would need
  `order: 17.1, 17.2…` or a sub-collection — confirm Jekyll accepts fractional
  ordering, or use a `17-capstone/` subdirectory with its own index. Option (B)
  (one page, in place) sidesteps this entirely. **This nudges the recommendation
  toward (B) for lower risk**, unless the author wants true separate pages.
- **No other `_docs/*` page links into §17** by name — so option (A)'s
  cross-reference blast radius is small (mainly the outline/landing and any
  in-page anchors). That lowers (A)'s risk somewhat.

Net: the (A)/(B) call is now better informed — (B) is lowest-risk and the `order:`
integer scheme mildly favors it; (A) is viable since nothing external links in.
Still the author's call, but I'd lead with (B) unless separate pages are wanted.
