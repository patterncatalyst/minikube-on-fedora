# Data Mesh on OpenShift — implementation deck

The implementation-focused companion to the **Data Mesh 101** deck (in
`../data-mesh-101/`). Where the 101 deck makes the conceptual case, this deck
shows the four principles realized on enterprise Kubernetes / OpenShift —
principle by principle, with production-shaped code and the reference-architecture
diagrams throughout. Target talk length: 1.5–3 hours.

Gotchas (operational sharp edges) are in **Appendix A**, deliberately kept out of
the main value narrative.

## Files

```
data-mesh-openshift/
├── Data_Mesh_on_OpenShift.pptx   ← the deck (60 slides)
├── build-deck.js                 ← slide content (parametric — edit + rebuild)
├── deck-lib.js                   ← the design-system helpers (101 brand: palette, type, layouts)
├── raster.js                     ← SVG → PNG rasterizer for the embedded diagrams
├── dimg/                         ← source SVG diagrams (from data-mesh-101/diagrams)
└── dpng/                         ← rasterized PNGs the deck embeds (+ dims.json)
```

## Rebuilding

```bash
npm install -g pptxgenjs sharp      # one-time
node raster.js                      # dimg/*.svg → dpng/*.png (+ dims.json)
node build-deck.js                  # → Data_Mesh_on_OpenShift.pptx
```

The design system (Red Hat palette, Overpass SemiBold / Red Hat Text, the
title/divider/content/code/diagram layout grammar) is documented in
`../README.md` and encoded in `deck-lib.js`, so this deck and the 101 deck read
as one visual family.
