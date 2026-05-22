#!/usr/bin/env python3
"""render-split.py — emit a tiny SVG bar chart of an observed canary split.

The "make the traffic split visible" stretch from the r26 design intent, kept
to stdlib so it runs anywhere. Given the v1 and v2 request counts the smoke
measured, it writes a two-bar SVG showing each subset's share.

Usage:
  render-split.py <v1_count> <v2_count> <out.svg>
"""
import sys


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write("usage: render-split.py <v1_count> <v2_count> <out.svg>\n")
        return 2
    v1, v2 = int(sys.argv[1]), int(sys.argv[2])
    out = sys.argv[3]
    total = max(v1 + v2, 1)
    p1 = round(100 * v1 / total)
    p2 = 100 - p1

    # Layout: a 480-wide track; v1 (blue) then v2 (amber), widths by share.
    track = 460
    w1 = round(track * v1 / total)
    w2 = track - w1
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="500" height="120" viewBox="0 0 500 120">
  <style> text {{ font-family: sans-serif; }} </style>
  <text x="10" y="24" font-size="16" font-weight="bold">order-service canary split</text>
  <rect x="10" y="40" width="{w1}" height="40" fill="#2563eb"/>
  <rect x="{10 + w1}" y="40" width="{w2}" height="40" fill="#f59e0b"/>
  <text x="14" y="65" font-size="13" fill="#fff">v1 {p1}%</text>
  <text x="{14 + w1}" y="65" font-size="13" fill="#fff">v2 {p2}%</text>
  <text x="10" y="104" font-size="12" fill="#555">v1={v1} requests &#183; v2={v2} requests &#183; n={total}</text>
</svg>
"""
    with open(out, "w") as fh:
        fh.write(svg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
