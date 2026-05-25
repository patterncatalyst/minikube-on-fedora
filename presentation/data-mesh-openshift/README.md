# Data Mesh on OpenShift — implementation deck

The implementation-focused companion to the **Data Mesh 101** deck (in
`../data-mesh-101/`). Where the 101 deck makes the conceptual case, this deck
shows the four principles realized on enterprise Kubernetes / OpenShift —
principle by principle, with production-shaped code and reference-architecture
diagrams throughout. Target talk length: 1.5–3 hours.

The deck is **diagrams-forward**: infrastructure is shown as architecture
diagrams rather than YAML. Code appears only where the code itself is the lesson
— the Python that implements the APIs (FastAPI/gRPC/Strawberry/aiokafka), the
event contract (Avro), and the canary weights. Every slide carries **speaker
notes**. Gotchas (operational sharp edges) are in **Appendix A**, deliberately
kept out of the main value narrative.

## Theme / branding

This deck is themed to match the **Designing Cloud-Native APIs** deck (Red Hat
brand), so the two read as one family:

- **Title + section dividers** use the Red Hat illustration collage
  (`brand-illustration.png`) — the left portion is the icon collage, the right
  is a dark-red field that carries white title text.
- **Logo** appears on every slide, using the correct variant per background:
  `brand-logo-dark.png` (black wordmark) on white slides, `brand-logo-light.png`
  (white wordmark) on the dark dividers/title/closing.
- **Agenda** slide (slide 2) lists the sections in two columns.
- **Code** slides are full-width rounded dark panels in **Red Hat Mono**, with
  green comments and the explanation in an italic caption below the panel.
- Fonts: **Overpass SemiBold** (headers/eyebrows), **Red Hat Text** (body),
  **Red Hat Mono** (code + section numbers). Palette: Red Hat Red `EE0000`,
  ink `151515`, code panel `1A1A1A`, comment green `8FB98F`.

## Files

```
data-mesh-openshift/
├── Data_Mesh_on_OpenShift.pptx   ← the deck (~59 slides, speaker notes on every slide)
├── build-deck.js                 ← slide content + speaker notes (parametric — edit + rebuild)
├── deck-lib.js                   ← design-system helpers (theme: palette, type, layouts, logo-per-bg)
├── svglib.js                     ← SVG builder in the 101 diagram grammar (dual-emits .excalidraw)
├── makediagrams.js               ← generates the 11 new "17-*" diagrams
├── raster.js / raster2.js        ← SVG → PNG rasterizers for the embedded diagrams
├── brand-illustration.png        ← Red Hat illustration collage (title + dividers background)
├── brand-logo-dark.png           ← Red Hat logo, black wordmark (for white slides)
├── brand-logo-light.png          ← Red Hat logo, white wordmark (for dark slides)
├── dimg/                         ← source diagrams: SVG + hand-editable .excalidraw pairs
└── dpng/                         ← rasterized PNGs the deck embeds (+ dims.json)
```

## Rebuilding

```bash
npm install -g pptxgenjs sharp      # one-time
node raster.js                      # 101 dimg/*.svg → dpng/*.png
node makediagrams.js && node raster2.js   # regenerate the new 17-* diagrams → dpng/
node build-deck.js                  # → Data_Mesh_on_OpenShift.pptx
```

The deck build depends on the three brand assets above being present in this
directory (they are committed alongside the sources).

## Diagrams

The 11 new diagrams are adopted into the tutorial at `assets/diagrams/` as
matching **`.excalidraw` + `.svg` pairs** (same convention as the 101 set).
`svglib.js` + `makediagrams.js` generate all three artifacts (`.excalidraw`,
`.svg`, `.png`) from one source. Edit the `.excalidraw` for one-off hand-tweaks
(then re-export its SVG/PNG), or edit `makediagrams.js` for systematic regen.
