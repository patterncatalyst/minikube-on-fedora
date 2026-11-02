# Kubernetes Patterns & CKAD — companion deck

A Red Hat-branded 16:9 deck that works all 32 Kubernetes patterns from the
[Kubernetes patterns & CKAD appendix](../../_appendix/k8s-patterns/) one at a
time, with the appendix's own diagrams and thick speaker notes. Built to double
as CKAD revision, and as the seed for a hands-on workshop.

`kubernetes-patterns-and-ckad-r01.0.pptx` is the deliverable (164 slides). Open
it in PowerPoint, Keynote, or LibreOffice.

## Layout

```
deck.js            # the builder: cover, overview, section loader, closing
deck-helpers.js    # house helpers (Red Hat fonts, colors, slide types)
data/<section>.js  # slide content, one file per pattern family
png/               # the 33 appendix diagrams, rendered from assets/diagrams
assets/            # cover panel, divider panel, logos
```

Each `data/<section>.js` exports `{ divider, slides }`. A slide is one of:
`bullets`, `code` (dark box), `diagram` (embeds `png/<name>.png`), or `table`.
Every slide carries speaker notes; the build fails if one does not.

## Build

```bash
npm install pptxgenjs            # once
export NODE_PATH=$(npm root -g)  # if pptxgenjs is global instead
node deck.js                     # writes the .pptx
```

## Diagrams

The 33 figures are the appendix's own, rendered to PNG from
`../../assets/diagrams/appendix-*.svg`:

```bash
for svg in ../../assets/diagrams/appendix-*.svg; do
  cairosvg "$svg" -o "png/$(basename "$svg" .svg).png" --output-width 1600
done
```

The editable `.excalidraw` sources live next to the SVGs in the repo.

## Sections

Cover, overview, then eight sections: Foundational, Structural, Behavioral,
Configuration, Advanced, Security, the three CKAD gap chapters, and the CKAD
crosswalk that maps all 32 patterns to the five exam domains.
