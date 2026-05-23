---
title: Capstone roadmap (phases A–E)
description: The post-observability plan — feature demos, narrative restructure, presentation, and a replayable walkthrough.
render_with_liquid: false
---

This is the working roadmap for finishing the §17 capstone after the
observability arc (through r30). Each phase is its own iteration set with its
own decision-log entries and verification. Sequencing is driven by dependencies:
features first, then the narrative that documents them, then the deck, then the
replayable walkthrough.

## Phase A — New API as a demonstration (temporary)

Add a new REST endpoint to one service (likely order-service, the template),
**as a demonstration of the add-a-data-product workflow**, not a permanent
feature. Walk it end to end: write the endpoint → publish its contract to
Apicurio → ingest into OpenMetadata so it appears in the catalog and lineage →
then **back it out** so the baseline is clean for the next demo run. The value is
showing the *process and the mesh affordances*, repeatably.

A companion thread: walk the **various ways to retrieve the data and to discover
metadata** about the data and its schemas (GraphQL, REST, gRPC; Apicurio for
contracts; OpenMetadata for lineage/discovery). Together with Phase B this is the
data-mesh value proposition *from the API/consumer perspective*.

## Phase B — v1→v2 canary as a repeatable walkthrough

Finish the v1→v2 story already started (`order-service-v2`, `smoke-canary.sh`):
a genuinely different v2 (the new field from Phase A is a natural differentiator),
the weighted Istio VirtualService, and verification that traffic splits. Framed
as a **repeatable, backable-out walkthrough** so it can be demoed live and reset.

## Phase C — Narrative restructure: one page → a section set

The capstone has outgrown a single page. Restructure into a set of sections (the
existing `_docs/17-capstone.md` becomes an overview/landing plus dedicated
sections), each pairing prose with diagrams from `presentation/`. Planned topics:

- What a data mesh is, and the four principles
- The value proposition of Kubernetes as the substrate
- Contracts and the registry (Apicurio)
- The catalog and discovery (OpenMetadata) — why it's a mesh requirement
- Why autoscaling (KEDA), including scale-to-zero for elastic data products
- Why Istio for progressive delivery (canary) and mTLS
- How Kafka enables async data requests and serves as the backbone
- How Kubernetes provides cloud-native recoverability from failure
- Observability: traces/spans, metrics for performance, and correlation of
  logs/metrics/traces; Kiali for live vs after-the-fact views of the flows

Diagrams for most of these already exist in `presentation/data-mesh-101/diagrams/`
(see that README's mapping table). Adopted diagrams get copied into
`assets/diagrams/` under the `NN-name` convention as each section is written.

## Phase D — Implementation deck (~1.5–3 h)

A new pptx in `presentation/` demonstrating the implementation as a reference
architecture: walk → explain → demo, step by step. It reuses the **Data Mesh 101
design system** (Red Hat brand palette/type/layout — documented in
`presentation/README.md`), draws narrative from Phase C, borrows framing from the
101 deck, and uses the existing diagrams plus additional diagrams the user will
upload when Phase D starts (each as SVG + Excalidraw). The 101 deck itself is
already copied into `presentation/data-mesh-101/` as the design source of truth.

## Phase E — Replayable step-by-step walkthrough

Walk the entire capstone step by step, then the demos, paced for a presenter and
keyed to the new deck. Likely a guided `demos/walkthrough.sh` layered over the
existing smokes.

**Acceptance criteria (the demo vision):** a presenter can replay the example
with CLI narration *and* graphically show what's happening — open Grafana/Tempo
to watch a live trace's spans, inspect OpenMetadata lineage, observe the Istio
canary split (Kiali live vs after-the-fact), and see metrics correlate with the
flow — each beat explained so a consumer or presenter sees the whole system in
perspective, not just commands scrolling by.

## Sequencing

A → B (features; B's version delta depends on A) → C (documents A/B) → D (deck
from C's narrative + diagrams) → E (walkthrough over everything). Phases A and B
are designed to be backed out and replayed, so they double as demo scripts.
