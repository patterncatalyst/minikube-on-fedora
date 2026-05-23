# Presentation assets

This directory holds the presentation materials for the capstone: the existing
**Data Mesh 101** deck (the conceptual intro) and, in time, a new
implementation-focused deck that walks the §17 reference architecture and demos
it step by step.

```
presentation/
├── data-mesh-101/
│   ├── The_Data_Mesh_Updated.pptx     ← source/reference deck (design source of truth)
│   └── diagrams/                       ← 15 paired SVG + Excalidraw diagrams
└── README.md                           ← this file
```

The 101 deck is concept-only (no live demo). The new deck (Phase D) reuses its
visual language and tells the implementation story.

## Design system (extracted from the 101 deck — match this in the new deck)

This is a **Red Hat brand** deck. The new deck should reuse the same palette,
type, and layout grammar so the two read as one family.

### Palette

| Role | Hex | Usage in the deck |
|------|-----|-------------------|
| Primary accent (Red Hat Red) | `EE0000` | Title-slide panel, section-divider background, eyebrow labels |
| Dark red | `8A0000` | Diagram accents, hover/secondary red |
| Near-black (text) | `151515` | Titles and body text on light slides |
| Muted gray | `5A5A5A` | Captions, secondary text |
| White | `FFFFFF` | Content-slide background |
| Off-white | `FBFAF7` | Alternate/section background |
| Warm light | `E6E0D6` | Diagram fills, light panels |
| Pale reds | `FFB3B3`, `FFD9D9` | Diagram highlights |
| Navy (secondary) | `1A3A6A` | Occasional diagram accent |

Red dominates the title and divider slides; content slides are predominantly
white with red used sparingly as the accent (eyebrow labels, key marks).

### Typography

- **Headers / eyebrows:** Overpass SemiBold
- **Body:** Red Hat Text (and Red Hat Text Medium for emphasis)
- The theme's `majorFont`/`minorFont` nominally say Calibri Light / Calibri, but
  every slide overrides to the Red Hat faces. If the build environment lacks the
  Red Hat fonts, expect LibreOffice to substitute — keep Calibri/Calibri Light
  as the documented fallback so substitution degrades gracefully.

### Layout grammar

- **Title slide:** red left panel (~40% width) carrying a geometric line motif
  and a white "THE DATA MESH" eyebrow; title + subtitle + author on the right.
- **Section divider:** full red background, large two-digit number eyebrow
  (`01`, `02`, …) above a large white section title.
- **Content slide:** white background; a small red ALL-CAPS eyebrow naming the
  section; a bold near-black title; left-aligned bullets in Red Hat Text.
- **Diagram slide:** white background; eyebrow + title; the diagram centered;
  a single muted caption line at the bottom restating the takeaway.
- **Footer motif (every slide):** Red Hat logo bottom-right, page number
  bottom-left. (This is an intentional brand element, not decorative chrome.)

## Diagram inventory and where each belongs

Each diagram is a paired `.svg` (for embedding/rendering) and `.excalidraw`
(editable source), matching the tutorial's diagram convention. The mapping below
is the working plan for Phase C (which sections reference which diagram) and
Phase D (which slide uses which); refine as the sections are written.

| Diagram | Conceptual home (Phase C section) | Deck use |
|---------|-----------------------------------|----------|
| `data-mesh-overview` | What is a data mesh | "at a glance" |
| `four-principles` | The four principles | principles overview |
| `operational-vs-analytical` | Operational vs analytical data | the two planes |
| `central-team-bottleneck` | Why centralized platforms stall | bottleneck |
| `monolith-to-mesh` | The shift to domain ownership | before/after |
| `decentralization-checklist` | Decentralized everything except data | checklist |
| `analytical-data-composition` | Data as a product | analytical composition |
| `data-product-anatomy` | Data as a product | product anatomy |
| `federated-governance-model` | Federated computational governance | governance |
| `platform-planes` | Self-serve data platform | platform planes |
| `logical-mesh-architecture` | Why this maps to Kubernetes | logical architecture |
| `contract-flow` | Contracts, registry, catalog | runtime vs discovery path |
| `contracts-registry-catalog` | Apicurio + OpenMetadata | contract → registry → catalog |
| `ingestion-streaming-sourcing` | The async spine (Kafka) | ingestion/streaming |
| `reference-data-mesh-architecture` | The capstone as reference architecture | centerpiece / Phase E |

When a Phase C section adopts a diagram, copy it into `assets/diagrams/` under
the tutorial's `NN-name.svg` + `.excalidraw` convention (so the doc can embed it
via the site's `relative_url` include, the same way §17 embeds its existing
diagrams) and keep this directory as the curated presentation source.

## Phase D plan (build later; ~1.5–3 h)

The new deck demonstrates the implementation as a **reference architecture**:
walk the content, explain it, and demo it step by step. It draws narrative from
the Phase C sections, borrows framing from the 101 deck, and uses the diagrams
above plus any additional diagrams uploaded alongside this deck. The user will
provide additional diagrams (SVG + Excalidraw) when Phase D begins. Reuse the
design system documented above so the implementation deck and the 101 deck are
visually one family.
