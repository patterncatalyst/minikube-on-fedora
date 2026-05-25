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

## LOCKED structure (author-confirmed)

**Format:** short §17 landing (scenario-setting prose) + **9 grouped concept pages**
as dedicated child pages. Grouped (not one-per-section) for two reasons the author
gave: (1) easier to find by concept, (2) each grouped page doubles as a Phase D
slide-cluster. Naming/numbering still to confirm, but the page set is locked:

1. **Concepts & principles** — what a data mesh is, operational vs. analytical, the
   four principles. (Grounding; mirrors 101 deck slides 1-31, condensed. Decide:
   recap briefly vs. link to the 101 deck and dive into implementation.)
2. **Kubernetes as the substrate** — why k8s; four principles → k8s primitives;
   architecture overview.
3. **Services & data products** — the services, order-service template, data-product
   anatomy, build/image story.
4. **Contracts & the catalog** — Apicurio (registry) + OpenMetadata (catalog,
   lineage, discovery); why the catalog is a mesh requirement.
5. **The data planes** — async backbone (Kafka) + read layer (GraphQL/REST/gRPC).
6. **Progressive delivery & mTLS** — Istio canary v1→v2 + the selective-injection
   decision (design-decision framing; the cautionary version lives in Gotchas).
7. **Elastic & resilient** — KEDA scale-to-zero + cloud-native recoverability.
8. **Observability** — metrics/traces/logs correlation + Kiali (live vs after).
9. **Anti-patterns** — conceptual/organizational data-mesh failure modes from the
   literature (vendor-neutral, reusable). NOT our build's incidents — those are
   "Gotchas" (below). Sources synthesized (paraphrase, never reproduce):
     - **Tool ≠ transformation.** Data mesh is socio-technical; buying a catalog or
       relabeling a lake doesn't make a mesh. (Globant #5; Moronta; Nextdata.)
     - **Recreating centralization under a new name** — central team stays the
       proxy, or "governance" re-centralizes approvals; shadow data teams.
       (Nextdata "proxy data mesh"; Moronta "over-centralizing for coordination".)
     - **"Dumb" data products** — products reduced to renamed tables / catalog rows
       instead of *autonomous* units that serve, govern, and describe themselves.
       (Nextdata's central thesis; Globant #1 lifecycle neglect.)
     - **Governance as afterthought or as bureaucracy** — either bolted on outside
       the product, or so heavy it bottlenecks. Federated *computational* governance
       is the target. (Globant #4; Moronta; the federated-governance principle.)
     - **Ownership vacuum / fuzzy domains** — no clear owner; overlapping domains;
       conflicting versions. (Globant #10; Moronta; ThoughtWorks "fuzzy boundaries".)
     - **Open loop / no feedback** — static downstream products, no operational↔
       analytical loop, no consumer feedback. (Nextdata "open loop"; Globant #3.)
     - **Hype-driven / wrong-fit adoption** — mesh isn't for every org; analysis
       paralysis; more products ≠ better. (Globant #2/#8/#9; takt.dev "unsuitable
       for small orgs / no governance culture".)
   Framing (author to confirm): state each anti-pattern generally, then — where we
   have one — a one-line nod to how our build's lessons are the operational analogue,
   with a pointer to Gotchas. Keep page 9 conceptual. LinkedIn source (gugulla post)
   could not be fetched (auth wall) — author to paste if its points should be added.

## SEPARATE: "Gotchas" section → deck Appendix A

Distinct from page 9. **Gotchas = the implementation/operational potholes WE hit
building the demo**, mined from the CAP decision log — war-story framing, "here's
what bit us and the fix." Maps to **Appendix A** in the Phase D deck. Candidates:
  - Namespace-wide mesh injection broke batch Jobs (CAP-034) and crash-looped CNPG
    via TLS-vs-Envoy (CAP-038); istiod became a fail-closed dependency for every
    pod-create (CAP-040). → "mesh selectively."
  - Under-sizing a stateful workload like a stateless one — Postgres OOM at 512Mi in
    WAL recovery (CAP-038). → "size stateful workloads for their worst moment."
  - App exits on first dependency failure at startup — order-service crash-loop; fix
    = retry + holdApplicationUntilProxyStarts (CAP-037). → "deps aren't ready at boot."
  - Long-lived single-node cluster treated as durable — idle-node /dev decay wedging
    kube-proxy (CAP-040). → "cycle on resume; don't debug symptoms."
  - Node PID ceiling (podman pids_limit default 2048) starving pod forks (CAP-041).
  - Shell footguns under `set -euo pipefail` — the guard saga. → maybe a scripting
    sidebar; author's call whether it earns a spot.
Whether Gotchas also appears as a §17 page (vs. only the deck appendix) — author to
decide. Likely: a short "Operating notes / gotchas" page or fold into page 7, with
the full enumerated list reserved for the deck appendix.

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

## FINAL decisions (author-confirmed, resume-ready)

- **Numbering: `17.N` fractional.** Child pages `17.1`–`17.9`, descriptive names
  (`17.1-concepts-and-principles.md` … `17.9-anti-patterns.md`). Verified: YAML
  parses `order: 17.1` as float; the layout's `sort: "order"` is numeric, so the
  nav/prev-next chain is `17 (landing) → 17.1 → … → 17.9 → 18` with no wiring.
  Permalink `:name` gives `/docs/17.1-concepts-and-principles/` etc.
- **Page 1 framing:** brief 101 recap, then dive into implementation (don't
  re-teach the 101 deck — link to it and move on).
- **Selective-injection appears twice by design (confirmed good):** design-decision
  framing on page 6 (Istio), cautionary-gotcha framing in deck Appendix A. The
  repetition reinforces from both directions.
- **Front-matter fields the layout uses:** `title`, `description`, `duration`
  (renders as ⏱ chip), `order` (renders as "Section N.N"). Child pages set all four.

## Scaffold built (this session)

The landing page rewrite + nine child-page skeletons are generated as
`minikube-on-fedora-phase-c-scaffold` (separate tar). Each child page has: correct
front matter, a one-line "what this page covers," a **prose-source pointer** (the
line range in the OLD 17-capstone.md to relocate), the **diagram(s)** to embed, and
a stub body marked `<!-- DRAFT: ... -->`. Nothing is deleted from the old page yet —
the scaffold is additive so the relocation can be checked section-by-section before
removing the originals. Writing order suggestion: 17.9 (anti-patterns; source
synthesis already done) → 17.6 (Istio + selective-injection; we have the material) →
then 17.1→17.8 in order.

## How to activate the scaffold (on resume — explicit, reversible)

The scaffold is ADDITIVE. The nine `_docs/17.N-*.md` child pages are live Jekyll
pages immediately (they'll appear in the nav as Sections 17.1-17.9, each a DRAFT
stub). The landing rewrite is staged as `_docs/17-capstone.md.NEW` and does NOT
render (Jekyll ignores non-.md extensions), so the current long `17-capstone.md`
stays live until you swap:

    # when ready to make the short landing live (after sanity-checking it):
    cd _docs
    cp 17-capstone.md 17-capstone.md.OLD     # keep the full original as backup
    mv 17-capstone.md.NEW 17-capstone.md      # activate the short landing
    # the OLD content's prose is the source for the child pages; once all nine are
    # written and verified, delete 17-capstone.md.OLD.

Until that swap, the site shows BOTH the full old §17 AND the nine new stub pages —
fine for drafting, but don't push to the live site in that half-state (or do, since
it's a personal tutorial — author's call). Suggested: keep the swap until at least
17.9 and 17.6 are drafted, so the landing links don't point at empty stubs.

**Writing order (recap):** 17.9 (anti-patterns — synthesis done) → 17.6 (Istio +
selective-injection — material in hand) → 17.1-17.8 in sequence, relocating prose
from 17-capstone.md.OLD per each page's PROSE SOURCE pointer.

## STRUCTURE CORRECTED (mirrors the skeleton's reference/compendium pattern)

The earlier `17.1`–`17.9`-in-_docs approach was WRONG — it injected pages into the
main tutorial chain. Corrected to mirror the cpp-tutorial's Statelessness Compendium
(`_reference/statelessness/` collection): the capstone is now its OWN collection.

**What was built:**
- `_config.yml`: new `capstone` collection (`output: true`, `permalink: /capstone/:path/`)
  + a default scope giving it `layout: tutorial`, `sectionid: capstone`. Modeled on
  the skeleton's `reference` collection (`:path` preserves the subdirectory).
- `_layouts/tutorial.html`: prev/next now branches on `page.sectionid` — capstone
  pages thread among `site.capstone` (their own internal chain), everything else
  threads `site.docs` as before. This is the one layout change needed; verified
  if/else/endif balanced.
- `_capstone/data-mesh/`: `00-index.md` (set landing, "The set" list) + `01-concepts`
  … `09-anti-patterns` (internally numbered 0-9). URLs: `/capstone/data-mesh/00-index/`,
  `/capstone/data-mesh/01-concepts/`, … `/capstone/data-mesh/09-anti-patterns/`.
- `_docs/17-capstone.md.NEW`: short hand-off page (stays in the main chain as §17,
  links into the set). Staged as .NEW — the full original 17-capstone.md remains the
  prose source until the set is written, then swap (see activation note above).

**Content carried over unchanged:** the 9-section grouping, prose-source line-range
pointers, diagram mapping, anti-patterns synthesis (7 themes, sourced), gotchas split.
Only the housing changed: a self-contained collection with internal 00-09 numbering
and its own landing + prev/next, instead of 17.N pages in the docs chain.

**Resume:** extract, commit, sanity-check with a local Jekyll build if possible
(the collection + layout branch are the only structural risk — verify
/capstone/data-mesh/00-index/ renders and its prev/next chains within the set).
Then write: 09-anti-patterns (synthesis done) → 06-progressive-delivery-mtls
(material in hand) → 01-08 in order, relocating prose from 17-capstone.md (the OLD
full page) per each doc's PROSE SOURCE note. Swap 17-capstone.md.NEW → live once
06 and 09 are drafted.
