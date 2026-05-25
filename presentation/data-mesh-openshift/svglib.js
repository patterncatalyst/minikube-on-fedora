// svglib.js — build diagrams in the Data Mesh 101 visual grammar.
// White bg, Helvetica, color-paneled rounded rects, marker arrows, titled cards.

const FONT = "Helvetica, -apple-system, 'Segoe UI', Roboto, sans-serif";

// palette families (fill, stroke, heading)
const FAM = {
  blue:   { fill: "#e8eef7", stroke: "#2c5aa0", head: "#1a3a6a" },
  orange: { fill: "#fbe8d8", stroke: "#c97a3a", head: "#7a3a0a" },
  tan:    { fill: "#f5edd6", stroke: "#c19a6b", head: "#5a3a0a" },
  green:  { fill: "#e8f0e0", stroke: "#5a8a3a", head: "#2a5a1a" },
  red:    { fill: "#fdf0ec", stroke: "#c14a3a", head: "#a8331f" },
  gray:   { fill: "#f4f3f0", stroke: "#9a9a9a", head: "#4a4a4a" },
  white:  { fill: "#ffffff", stroke: "#c19a6b", head: "#5a3a0a" },
};
const INK = "#3a3a3a", MUT = "#666666", SUB = "#8a7a5a", TITLE = "#2a2a2a";

function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

class SVG {
  constructor(w, h) { this.w = w; this.h = h; this.parts = []; }
  // wrapped multi-line text helper
  lines(x, y, arr, { size = 11, fill = INK, anchor = "start", weight = null, lh = 17, italic = false } = {}) {
    arr.forEach((t, i) => {
      this.parts.push(`<text x="${x}" y="${y + i * lh}" font-size="${size}" fill="${fill}" text-anchor="${anchor}"${weight ? ` font-weight="${weight}"` : ""}${italic ? ` font-style="italic"` : ""}>${esc(t)}</text>`);
    });
  }
  text(x, y, t, opt = {}) { this.lines(x, y, [t], opt); }
  title(t, sub) {
    this.text(this.w / 2, 32, t, { size: 18, fill: TITLE, anchor: "middle", weight: 700 });
    if (sub) this.text(this.w / 2, 51, sub, { size: 12, fill: MUT, anchor: "middle", italic: true });
  }
  rect(x, y, w, h, fam, { rx = 6, sw = 1.5, dash = null } = {}) {
    const f = FAM[fam] || fam;
    this.parts.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${f.fill}" stroke="${f.stroke}" stroke-width="${sw}" rx="${rx}"${dash ? ` stroke-dasharray="${dash}"` : ""}/>`);
  }
  plainRect(x, y, w, h, fill, stroke, { rx = 6, sw = 1.5, dash = null } = {}) {
    this.parts.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" rx="${rx}"${dash ? ` stroke-dasharray="${dash}"` : ""}/>`);
  }
  // a titled card with heading + optional body lines + optional sublabel block
  card(x, y, w, h, fam, heading, body = [], { sublabel = null, subitems = [], hsize = 13.5 } = {}) {
    const f = FAM[fam];
    this.rect(x, y, w, h, fam);
    this.text(x + 16, y + 26, heading, { size: hsize, fill: f.head, weight: 700 });
    if (body.length) this.lines(x + 16, y + 50, body, { size: 11, fill: INK, lh: 16 });
    if (sublabel) {
      const sy = y + 50 + body.length * 16 + 14;
      this.text(x + 16, sy, sublabel, { size: 9, fill: SUB, weight: 600 });
      this.lines(x + 16, sy + 20, subitems, { size: 10.5, fill: f.head, lh: 21 });
    }
  }
  defs() {
    return `<defs>
<marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#5a5a5a"/></marker>
<marker id="arrR" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#c14a3a"/></marker>
<marker id="arrB" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#2c5aa0"/></marker>
<marker id="arrG" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#5a8a3a"/></marker>
</defs>`;
  }
  arrow(x1, y1, x2, y2, { color = "#5a5a5a", marker = "arr", w = 1.6, dash = null } = {}) {
    this.parts.push(`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${color}" stroke-width="${w}" marker-end="url(#${marker})"${dash ? ` stroke-dasharray="${dash}"` : ""}/>`);
  }
  label(x, y, t, { size = 10, fill = MUT, anchor = "middle", italic = true } = {}) {
    this.text(x, y, t, { size, fill, anchor, italic });
  }
  // a small rounded "pill" callout (for highlighting implementing pieces)
  pill(x, y, w, t, fam, { h = 26 } = {}) {
    const f = FAM[fam] || fam;
    this.parts.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${f.fill}" stroke="${f.stroke}" stroke-width="1.5" rx="13"/>`);
    this.text(x + w / 2, y + h / 2 + 4, t, { size: 11, fill: f.head, anchor: "middle", weight: 700 });
  }
  footer(t) { this.text(this.w / 2, this.h - 16, t, { size: 12, fill: "#6a5a3a", anchor: "middle", italic: true }); }
  render() {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${this.w} ${this.h}" font-family="${FONT}"><rect x="0" y="0" width="${this.w}" height="${this.h}" fill="#ffffff"/>${this.defs()}${this.parts.join("")}</svg>`;
  }
}

module.exports = { SVG, FAM, INK, MUT, SUB, TITLE };
