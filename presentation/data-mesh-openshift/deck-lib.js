// Data Mesh on OpenShift — implementation deck (Phase D)
// Reuses the Data Mesh 101 design system (Red Hat brand).
const pptxgen = require("pptxgenjs");
const fs = require("fs");

const DIMS = JSON.parse(fs.readFileSync("dpng/dims.json", "utf8"));
const IMG = (name) => `dpng/${name}.png`;

// ---- Design system (extracted from the 101 deck) ----
const C = {
  red:   "EE0000",  // Red Hat Red — title/divider panels, eyebrows
  dkred: "8A0000",  // dark red accent
  ink:   "151515",  // near-black text
  gray:  "5A5A5A",  // muted captions/secondary
  white: "FFFFFF",
  offwhite: "FBFAF7",
  warm:  "E6E0D6",
  paleR: "FFB3B3",
  paleR2:"FFD9D9",
  navy:  "1A3A6A",
  codebg:"1B1B1B",  // code panel background
  codefg:"E6E6E6",  // code text
  codekey:"FF8B8B", // code keyword (pale red)
  codemut:"9AA0A6", // code comment
};
const F = {
  head: "Overpass SemiBold",   // headers/eyebrows
  body: "Red Hat Text",        // body
  bodyM:"Red Hat Text Medium", // emphasis
  mono: "Consolas",            // code (Red Hat Mono not guaranteed; Consolas is safe mono)
};

const pres = new pptxgen();
pres.defineLayout({ name: "W", width: 13.333, height: 7.5 });
pres.layout = "W";
pres.author = "Robert Sedor";
pres.title = "Data Mesh on OpenShift";
const PW = 13.333, PH = 7.5;

// fresh shadow object each call (pptxgenjs mutates in place)
const shadow = () => ({ type: "outer", color: "000000", blur: 7, offset: 3, angle: 135, opacity: 0.13 });

// ---- footer motif (every content slide): page number left, brand mark right ----
let PAGENO = 0;
function footer(slide, { dark = false } = {}) {
  PAGENO += 1;
  const fg = dark ? "FFFFFF" : C.gray;
  slide.addText(String(PAGENO), { x: 0.5, y: PH - 0.5, w: 1, h: 0.3, fontSize: 9, color: fg, fontFace: F.body, align: "left", margin: 0 });
  slide.addText([
    { text: "Red Hat", options: { bold: true, color: dark ? "FFFFFF" : C.red } },
    { text: "  ·  Data Mesh", options: { color: fg } },
  ], { x: PW - 3.0, y: PH - 0.5, w: 2.5, h: 0.3, fontSize: 9, fontFace: F.head, align: "right", margin: 0 });
}

// ---- TITLE slide: red left panel + geometric line motif ----
function titleSlide({ eyebrow, title, subtitle, author, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  const panelW = PW * 0.42;
  s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: panelW, h: PH, fill: { color: C.red } });
  // geometric line motif on the panel
  for (let i = 0; i < 7; i++) {
    s.addShape(pres.shapes.LINE, { x: 0.0, y: 0.7 + i * 0.9, w: panelW - 0.8 - i * 0.15, h: 0, line: { color: "FFFFFF", width: 1, transparency: 62 } });
  }
  s.addText("THE DATA MESH", { x: 0.7, y: 0.7, w: panelW - 1.2, h: 0.4, fontSize: 14, color: "FFFFFF", fontFace: F.head, charSpacing: 3, bold: true, margin: 0 });
  s.addText("IMPLEMENTATION", { x: 0.7, y: 1.05, w: panelW - 1.2, h: 0.4, fontSize: 14, color: "FFD9D9", fontFace: F.head, charSpacing: 3, bold: true, margin: 0 });
  // right side: title block
  const rx = panelW + 0.7;
  s.addText(title, { x: rx, y: 2.2, w: PW - rx - 0.6, h: 1.8, fontSize: 44, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText(subtitle, { x: rx, y: 3.95, w: PW - rx - 0.6, h: 1.0, fontSize: 18, color: C.gray, fontFace: F.body, valign: "top", margin: 0 });
  s.addText(author, { x: rx, y: 5.0, w: PW - rx - 0.6, h: 0.4, fontSize: 14, color: C.red, fontFace: F.bodyM, valign: "top", margin: 0 });
  if (notes) s.addNotes(notes);
  return s;
}

// ---- SECTION DIVIDER: full red, two-digit number eyebrow + white title ----
function divider({ num, title, sub, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.red };
  s.addText(num, { x: 0.9, y: 1.5, w: 4, h: 2.2, fontSize: 150, color: "FFFFFF", fontFace: F.head, bold: true, transparency: 18, margin: 0 });
  s.addText(title, { x: 0.95, y: 3.8, w: PW - 2, h: 1.6, fontSize: 40, color: "FFFFFF", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  if (sub) s.addText(sub, { x: 1.0, y: 5.3, w: PW - 2.2, h: 1.0, fontSize: 16, color: "FFD9D9", fontFace: F.body, valign: "top", margin: 0 });
  PAGENO += 1;
  s.addText(String(PAGENO), { x: 0.5, y: PH - 0.5, w: 1, h: 0.3, fontSize: 9, color: "FFFFFF", fontFace: F.body, transparency: 30, margin: 0 });
  if (notes) s.addNotes(notes);
  return s;
}

// ---- eyebrow + title block for a content slide ----
function head(s, eyebrow, title, { titleH = 0.9 } = {}) {
  s.addText(eyebrow.toUpperCase(), { x: 0.7, y: 0.45, w: PW - 1.4, h: 0.32, fontSize: 12, color: C.red, fontFace: F.head, bold: true, charSpacing: 2, margin: 0 });
  s.addText(title, { x: 0.7, y: 0.78, w: PW - 1.4, h: titleH, fontSize: 30, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0 });
}

// ---- CONTENT slide: eyebrow + title + left bullets (+ optional right visual handled by caller) ----
function contentSlide({ eyebrow, title, bullets, bulletsX = 0.7, bulletsW = PW - 1.4, bulletsY = 1.95, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title);
  if (bullets) addBullets(s, bullets, { x: bulletsX, y: bulletsY, w: bulletsW });
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

function addBullets(s, bullets, { x, y, w, h = 4.6, fontSize = 16 }) {
  const runs = [];
  bullets.forEach((b, i) => {
    const lvl = b.lvl || 0;
    const isLast = i === bullets.length - 1;
    if (b.head) {
      runs.push({ text: b.text, options: { bold: true, color: C.ink, fontFace: F.bodyM, fontSize: fontSize + 1, bullet: false, breakLine: true, paraSpaceBefore: i ? 8 : 0, paraSpaceAfter: 3 } });
    } else {
      runs.push({ text: b.text, options: { color: b.color || (lvl ? C.gray : C.ink), fontFace: F.body, fontSize: lvl ? fontSize - 1 : fontSize, bullet: { indent: 18 }, indentLevel: lvl, breakLine: true, paraSpaceAfter: 6 } });
    }
  });
  s.addText(runs, { x, y, w, h, valign: "top", margin: 0 });
}

// ---- DIAGRAM slide: eyebrow + title + centered diagram + caption ----
function diagramSlide({ eyebrow, title, image, caption, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title);
  const d = DIMS[image];
  const maxH = 4.4, maxW = PW - 1.6;
  let w = maxW, h = w * (d.h / d.w);
  if (h > maxH) { h = maxH; w = h * (d.w / d.h); }
  const x = (PW - w) / 2, y = 1.85 + (maxH - h) / 2;
  s.addImage({ path: IMG(image), x, y, w, h });
  if (caption) s.addText(caption, { x: 0.8, y: PH - 1.0, w: PW - 1.6, h: 0.4, fontSize: 12, color: C.gray, fontFace: F.body, italic: true, align: "center", margin: 0 });
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// ---- CODE slide: eyebrow + title + dark code panel + optional note ----
function codeSlide({ eyebrow, title, lang, code, note, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title);
  const px = 0.7, py = 1.9, pw = note ? 8.4 : PW - 1.4, ph = 4.7;
  s.addShape(pres.shapes.RECTANGLE, { x: px, y: py, w: pw, h: ph, fill: { color: C.codebg }, line: { type: "none" }, shadow: shadow() });
  if (lang) s.addText(lang, { x: px + 0.15, y: py + 0.12, w: pw - 0.3, h: 0.28, fontSize: 10, color: C.codemut, fontFace: F.mono, bold: true, charSpacing: 1, margin: 0, wrap: false });
  // auto-size font so the snippet fits the panel height (avoid overflow)
  const lines = code.split("\n").length;
  const avail = ph - 0.85;                // inches of vertical room for code (below lang label)
  let fs = 12.5;
  const lineIn = (f) => (f * 1.16) / 72;  // approx line height in inches
  while (lines * lineIn(fs) > avail && fs > 8) fs -= 0.5;
  s.addText(code, { x: px + 0.25, y: py + 0.5, w: pw - 0.5, h: ph - 0.7, fontSize: fs, color: C.codefg, fontFace: F.mono, valign: "top", margin: 0, lineSpacingMultiple: 1.1 });
  if (note) {
    s.addText(note, { x: px + pw + 0.3, y: py + 0.1, w: PW - (px + pw + 0.3) - 0.6, h: ph, fontSize: 14, color: C.ink, fontFace: F.body, valign: "top", margin: 0 });
  }
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

// code with simple keyword coloring via rich-text runs
function codeRuns(lines) {
  // lines: array of {t, c?} where c is color override; default code fg
  const runs = [];
  lines.forEach((ln, i) => {
    const isLast = i === lines.length - 1;
    if (typeof ln === "string") {
      runs.push({ text: ln, options: { color: C.codefg, fontFace: F.mono, fontSize: 12.5, breakLine: true } });
    } else {
      runs.push({ text: ln.t, options: { color: ln.c || C.codefg, fontFace: F.mono, fontSize: 12.5, breakLine: true } });
    }
  });
  return runs;
}

// add just the page number (for custom full-color slides)
function pageNum(slide, { dark = false } = {}) {
  PAGENO += 1;
  slide.addText(String(PAGENO), { x: 0.5, y: PH - 0.5, w: 1, h: 0.3, fontSize: 9, color: dark ? "FFFFFF" : C.gray, fontFace: F.body, transparency: dark ? 30 : 0, margin: 0 });
}

module.exports = { pres, C, F, PW, PH, titleSlide, divider, contentSlide, diagramSlide, codeSlide, head, addBullets, footer, pageNum, DIMS, IMG, codeRuns };
