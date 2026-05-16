# assets/diagrams/

Each diagram lives as a **pair** of files with the same base name:

- `<name>.svg` — the rendered diagram, what appears on the site
- `<name>.excalidraw` — the editable JSON source

## Naming convention

`<section-number>-<topic>-<thing>.svg` for tutorial diagrams.

Examples:

- `01-prerequisites-toolchain.svg`
- `04-multi-stage-builds-pattern.svg`
- `07-compose-stack.svg`

This makes diagrams findable by section number and keeps related
diagrams sorted next to each other in the directory listing.

## Including a diagram in tutorial prose

Use the include:

```liquid
{% raw %}{% include excalidraw.html
   file="04-multi-stage-builds-pattern"
   alt="Diagram showing a builder stage producing artifacts that the runtime stage copies"
   caption="Figure 4.1 — The multi-stage build pattern" %}{% endraw %}
```

The include automatically:

- Renders the SVG inline (fast, accessible, scales with CSS)
- Adds an `alt` attribute for screen readers
- Adds the caption below the figure
- Includes a "Download Excalidraw source" link pointing at the
  matching `.excalidraw` file

## Editing a diagram

1. Open https://excalidraw.com
2. Drag the `<name>.excalidraw` file in
3. Edit
4. **Export → SVG** (NOT PNG) — overwrites `<name>.svg`
5. **File → Save to file** — overwrites `<name>.excalidraw`

Always update both files; they should stay in sync.

## Hand-coded SVGs

Sometimes a hand-coded SVG is faster than Excalidraw — especially
for grids, sequence diagrams, and anything heavy on math. You can
hand-code an SVG and ship a minimal `.excalidraw` source as
documentation, or omit the `.excalidraw` entirely and adjust the
`excalidraw.html` include to handle missing sources.

## SVG sizing

Use `viewBox="0 0 W H"` without explicit `width` or `height`
attributes. The site CSS will scale the SVG responsively to fit
its container. Hard-coded pixel dimensions break responsive
rendering.
