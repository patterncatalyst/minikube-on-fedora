// deck.js: Kubernetes Patterns & CKAD appendix deck (data-driven renderer).
//
// Content lives in data/<section>.js, one file per pattern family, each
// exporting { divider: {...}, slides: [...] }. This file renders the cover,
// the overview, every section in order, and the closing, then asserts that
// every slide carries speaker notes.
//
// Build:  export NODE_PATH=$(npm root -g) && node deck.js

"use strict";

const H = require("./deck-helpers.js");
const {
  COLOR, FONT, W, ASSETS,
  newDeck, addFooter, addContentTitle, addBullets, addTwoColBullets,
  addStatusTable, addCaption, addCodeSlide, addDiagramSlide, addSectionDivider, addNotes,
} = H;

const OUT = "kubernetes-patterns-and-ckad-r01.0.pptx";
const REV = "r01.0";

const pres = newDeck();
pres.title = "Kubernetes Patterns & CKAD, worked on minikube";
let pageNum = 0;
let notesCount = 0;

function S() { const s = pres.addSlide(); pageNum += 1; addFooter(s, pageNum); return s; }

function note(s, text) {
  if (!text || !text.trim()) throw new Error(`slide ${pageNum} has no speaker notes`);
  addNotes(s, text); notesCount += 1;
}

function divider(code, title, subtitle, notes) {
  const s = pres.addSlide(); pageNum += 1;
  addSectionDivider(s, code, title, subtitle); note(s, notes);
}

// ---- inline **bold** support for bullets ---------------------------------
function mdRuns(text) {
  // Split on **bold**; odd segments are the bold spans.
  return text.split(/\*\*(.+?)\*\*/g)
    .map((p, i) => ({ text: p, bold: i % 2 === 1 }))
    .filter((p) => p.text.length > 0);
}

// A bulleted list that honors **bold** inside each line.
function richBullets(slide, lines, opts = {}) {
  const fontSize = opts.fontSize || 16;
  const items = [];
  lines.forEach((ln) => {
    const runs = mdRuns(ln);
    runs.forEach((r, ri) => {
      const last = ri === runs.length - 1;
      items.push({
        text: r.text,
        options: {
          bold: r.bold,
          // pptxgenjs reads the paragraph bullet from the run that ends the
          // line (breakLine), so set both on the last run.
          bullet: last ? { code: "25CF" } : false,
          breakLine: last,
          paraSpaceAfter: last ? 8 : 0,
        },
      });
    });
  });
  slide.addText(items, {
    x: opts.x || 0.62, y: opts.y || 1.85, w: opts.w || 12.09, h: opts.h || 4.85,
    fontFace: FONT.body, fontSize, color: COLOR.body,
    align: "left", valign: "top", lineSpacingMultiple: 1.15,
  });
}

function richTwoCol(slide, left, right, opts = {}) {
  const fontSize = opts.fontSize || 15;
  richBullets(slide, left, { fontSize, x: 0.62, w: 6.0 });
  richBullets(slide, right, { fontSize, x: 7.02, w: 6.0 });
}

// ---- render one content slide from a spec --------------------------------
function render(spec) {
  const s = S();
  if (spec.t === "bullets") {
    addContentTitle(s, spec.eyebrow, spec.title);
    richBullets(s, spec.bullets, { fontSize: spec.fontSize || 16 });
    if (spec.caption) addCaption(s, spec.caption);
  } else if (spec.t === "two") {
    addContentTitle(s, spec.eyebrow, spec.title);
    richTwoCol(s, spec.left, spec.right, { fontSize: spec.fontSize || 15 });
    if (spec.caption) addCaption(s, spec.caption);
  } else if (spec.t === "code") {
    addCodeSlide(s, spec.eyebrow, spec.title, spec.lang, spec.code, spec.caption,
      { fontSize: spec.fontSize || 11 });
  } else if (spec.t === "diagram") {
    addDiagramSlide(s, spec.eyebrow, spec.title, spec.png, spec.caption);
  } else if (spec.t === "table") {
    addContentTitle(s, spec.eyebrow, spec.title);
    addStatusTable(s, spec.rows, { colW: spec.colW, rowH: spec.rowH });
    if (spec.caption) addCaption(s, spec.caption);
  } else {
    throw new Error(`unknown slide type: ${spec.t}`);
  }
  note(s, spec.notes);
}

function section(data) {
  divider(data.divider.code, data.divider.title, data.divider.subtitle, data.divider.notes);
  data.slides.forEach(render);
}

// ==== Cover ================================================================
{
  const s = pres.addSlide(); pageNum += 1;
  s.background = { color: COLOR.white };
  try { s.addImage({ path: `${ASSETS}/cover-panel.png`, x: 0, y: 0, w: W, h: 7.5 }); } catch (e) {}
  s.addText("KUBERNETES PATTERNS · CKAD COMPANION", { x: 6.00, y: 1.98, w: 6.90, h: 0.34,
    fontFace: FONT.title, fontSize: 13, bold: true, color: COLOR.red, charSpacing: 5, align: "left", valign: "middle" });
  s.addText([{ text: "Kubernetes", options: { breakLine: true } },
             { text: "patterns,", options: { breakLine: true } },
             { text: "worked live" }], {
    x: 5.95, y: 2.42, w: 6.95, h: 2.60, fontFace: FONT.title, fontSize: 50, bold: true, color: COLOR.ink, align: "left", valign: "top" });
  s.addText("Thirty-two cloud-native patterns on one minikube cluster, each tagged to the CKAD exam.", {
    x: 6.00, y: 4.95, w: 6.70, h: 0.90, fontFace: FONT.body, fontSize: 17, italic: true, color: COLOR.caption, align: "left", valign: "top" });
  s.addText(REV, { x: 11.85, y: 5.95, w: 0.95, h: 0.30, fontFace: FONT.mono, fontSize: 11, color: COLOR.caption, align: "right", valign: "middle" });
  try { s.addImage({ path: `${ASSETS}/logo-candidate-2.png`, x: 11.10, y: 6.80, w: 1.55, h: 0.37 }); } catch (e) {}
  note(s, "This deck works the Kubernetes design patterns one at a time against the shipping services from the data-mesh project, and runs every one on a single minikube profile on Fedora. It doubles as CKAD revision: each pattern is tagged to its exam domain and a closing crosswalk maps the whole set to the five domains. What to show: the title, then jump to the overview. Fallback: the whole set also reads as a reference site at the project's Pages URL.");
}

// ==== Overview ============================================================
{
  const s = S();
  addContentTitle(s, "OVERVIEW", "A pattern per chapter, on a real system");
  richBullets(s, [
    "Thirty-two patterns, each worked against the same order, inventory, payment, shipping, and notification services the data-mesh project runs.",
    "Every pattern runs on one minikube profile, mof-patterns, on Fedora: docker driver, containerd runtime, no managed cloud.",
    "Each pattern is tagged to its CKAD exam domain; a closing crosswalk maps the set to all five domains with a timed self-test.",
    "Six pattern families plus three chapters for the CKAD topics the patterns don't already cover.",
  ], { fontSize: 16 });
  note(s, "The appendix grounds every pattern in a system you can place an order against, rather than a throwaway nginx demo. What to show: name the five shipping services and the single profile. The point is that the same cluster carries all thirty-two patterns. Fallback: the reference site has the same chapters if the deck runs long.");
}
{
  const s = S();
  addContentTitle(s, "OVERVIEW", "The six families");
  richTwoCol(s,
    [
      "Foundational: the contracts every container honors to be scheduled and run well.",
      "Structural: how containers compose inside one Pod.",
      "Behavioral: how workloads behave over time, from Jobs to StatefulSets.",
    ],
    [
      "Configuration: how configuration reaches the application.",
      "Advanced: extending the platform with controllers and an operator.",
      "Security: running with least privilege at the Pod and network layers.",
    ], { fontSize: 15 });
  addCaption(s, "Three closing chapters cover the CKAD topics the patterns leave out: observability, packaging, and namespace governance.");
  note(s, "This is the map. Read a family at a time; within a family the patterns stand alone. What to show: point out that the families run from least to most involved, foundational first because everything else assumes it. Fallback: the crosswalk at the end lists every pattern by family and exam domain.");
}
{
  const s = S();
  addContentTitle(s, "OVERVIEW", "How each pattern is worked");
  richBullets(s, [
    "The problem: what breaks without the pattern, stated against the shipping services.",
    "The manifest: the Kubernetes objects that express the pattern, shown as the YAML that matters.",
    "Run it: what you apply, what you observe on the cluster, and how failure looks when a dependency is missing.",
    "The CKAD lens: the exam domain, the competency, and a one-line drill you can run from memory.",
  ], { fontSize: 16 });
  note(s, "Every pattern chapter follows the same shape, so the deck stays predictable once the audience sees the first one. What to show: tell the audience the CKAD drill on each pattern slide is runnable as-is against mof-patterns. Fallback: skip the drills on a first pass and return to them for exam prep.");
}

// ==== Sections (data-driven) ==============================================
const SECTIONS = [
  "foundational",
  "structural",
  "behavioral",
  "configuration",
  "advanced",
  "security",
  "ckad-gaps",
  "crosswalk",
];
for (const name of SECTIONS) {
  // eslint-disable-next-line import/no-dynamic-require, global-require
  section(require(`./data/${name}.js`));
}

// ==== Closing =============================================================
{
  const s = S();
  addContentTitle(s, "CLOSING", "From reference to workshop");
  richBullets(s, [
    "Every pattern here is runnable: the manifests, the build scripts, and the exact kubectl sequence ship in the project's examples directory.",
    "The CKAD crosswalk turns the set into timed revision against the five exam domains.",
    "The same content extends into a hands-on workshop: one cluster, one pattern per lab, building on the shipping services already deployed.",
  ], { fontSize: 16 });
  addCaption(s, "Chapters, runnable examples, and the editable diagrams live on the project's Pages site and GitHub repository.");
  note(s, "Close by pointing people at the runnable examples and the crosswalk. What to show: the examples directory layout, one folder per pattern, each with its own README and manifests. Fallback: if time is short, end on the crosswalk slide and leave the workshop framing for the follow-up.");
}

pres.writeFile({ fileName: OUT })
  .then((p) => console.log(`WROTE ${p}: ${pageNum} slides, ${notesCount} with notes`))
  .catch((e) => { console.error(e); process.exit(1); });
