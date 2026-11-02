# Presentation assets

This directory holds the companion decks for the project. All three share one
Red Hat visual language so they read as a family.

```
presentation/
├── data-mesh-101/          ← concept deck: the four principles, no live demo
│   ├── The_Data_Mesh_Updated.pptx   ← design source of truth
│   └── diagrams/                     ← 15 paired SVG + Excalidraw diagrams
├── data-mesh-minikube/     ← implementation deck for the capstone, built and demoed on minikube
│   ├── Data_Mesh_on_Minikube.pptx   ← ~59 slides, speaker notes on every slide
│   ├── build-deck.js                 ← slide content + notes (parametric: edit + rebuild)
│   ├── add-glossary.js               ← glossary slides
│   ├── makediagrams.js / svglib.js   ← diagram generators (SVG + Excalidraw)
│   ├── raster.js / raster2.js        ← SVG → PNG rasterizers for embedded diagrams
│   └── dimg/ · dpng/                 ← generated diagrams and their rasterized PNGs
├── k8s-patterns-appendix/  ← companion deck for the Kubernetes-patterns & CKAD appendix
│   ├── kubernetes-patterns-and-ckad-r01.0.pptx   ← 164 slides
│   ├── deck.js · deck-helpers.js     ← builder + house helpers
│   └── data/                         ← one module per pattern family
└── README.md               ← this file
```

- **data-mesh-101** is concept-only. Its `.pptx` is the design source of truth
  the other decks match; it has no programmatic builder here.
- **data-mesh-minikube** is the implementation companion to the 101 deck. It
  walks the capstone reference architecture principle by principle and demos it
  on a minikube profile. The OpenShift variant lives in its own separate project.
- **k8s-patterns-appendix** works the 32 Kubernetes patterns from the appendix,
  each mapped to its CKAD objective.

## Building the decks

```bash
# data-mesh-minikube (needs pptxgenjs + sharp)
cd data-mesh-minikube
node raster.js && node makediagrams.js && node raster2.js && node build-deck.js

# k8s-patterns-appendix (needs pptxgenjs)
cd k8s-patterns-appendix
npm install && node deck.js
```

## Design system

A **Red Hat brand** palette, type, and layout grammar, shared across all decks.

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
  Red Hat fonts, expect LibreOffice to substitute: keep Calibri/Calibri Light
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
  bottom-left, a brand element on every slide.

## Diagram index

Each diagram is a paired `.svg` (for embedding) and `.excalidraw` (editable
source), matching the tutorial's diagram convention.

| Diagram | Concept | Deck use |
|---------|---------|----------|
| `data-mesh-overview` | What is a data mesh | "at a glance" |
| `four-principles` | The four principles | principles overview |
| `operational-vs-analytical` | Operational vs analytical data | the two planes |
| `central-team-bottleneck` | Why centralized platforms stall | bottleneck |
| `monolith-to-mesh` | The shift to domain ownership | before/after |
| `decentralization-checklist` | Decentralized everything except data | checklist |
| `analytical-data-composition` | Data as a product | analytical composition |
| `data-product-anatomy` | Data as a product | product anatomy |
| `federated-governance-model` | Federated computational governance | governance |
| `logical-mesh-architecture` | Why this maps to Kubernetes | logical architecture |
| `contract-flow` | Contracts, registry, catalog | runtime vs discovery path |
| `contracts-registry-catalog` | Apicurio + OpenMetadata | contract to registry to catalog |
| `ingestion-streaming-sourcing` | The async spine (Kafka) | ingestion/streaming |
| `reference-data-mesh-architecture` | The capstone as reference architecture | centerpiece |

To reuse a diagram in the tutorial site, copy its pair into `assets/diagrams/`
under the `NN-name.svg` + `.excalidraw` convention, the same way the capstone
chapter embeds its diagrams.
