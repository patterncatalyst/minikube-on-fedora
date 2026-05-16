# Jekyll Tutorial Skeleton

A reusable starting point for technical tutorial sites with runnable
examples, built on Jekyll, deployed to GitHub Pages, and designed to be
extended interactively with Claude or another AI assistant.

This skeleton was extracted from the [Project Hummingbird tutorial](https://patterncatalyst.github.io/hummingbird-tutorial/)
after a long collaborative build-out — it captures the structure,
conventions, and tooling that worked well in that build, with the
project-specific content stripped.

> **Quick start:** see [GETTING-STARTED.md](GETTING-STARTED.md) for the
> step-by-step setup. This README explains what's here and why.

---

## What this skeleton gives you

A working Jekyll project that, once configured, produces a site with:

- **A landing page** with hero, "what you'll learn" section, and card grid
  pointing into the tutorial sections
- **A tutorial section structure** organized as numbered Markdown files in
  `_docs/` that Jekyll renders with consistent layout, navigation, and
  duration estimates
- **A reconciliation plan** in `_plans/` that tracks what's been verified
  vs. what hasn't — critical for honest documentation when using AI
  assistants who may produce plausible-looking but unverified content
- **A diagrams directory** with paired `.svg` (rendered) and `.excalidraw`
  (editable source) files, included via a single Liquid include
- **A runnable examples directory** structured to live alongside the
  tutorial without being included in the published site
- **A scripts directory** with a tested pattern for end-to-end
  build-and-test scripts and an aggregator
- **A GitHub Actions workflow** that builds and deploys to GitHub Pages
  with a working Ruby/Jekyll setup
- **CSS** with a clean, opinionated, accessible design — nav, cards,
  body type, code blocks, callouts, tables

The total file count of the skeleton is ~25 files. Most are short.

## Directory tour

```
.
├── _config.yml              ← Jekyll config; edit branding here
├── Gemfile                  ← Ruby deps; pinned to Pages-compatible versions
├── README.md                ← This file (replace with your project's README)
├── PRD.md                   ← Product requirements doc — fill in before writing
├── GETTING-STARTED.md       ← Step-by-step setup instructions
├── STARTING-WITH-CLAUDE.md  ← How to use this skeleton with Claude on new projects
├── LESSONS-LEARNED.md       ← Empirical wisdom about Podman, Jekyll, AI workflows
├── LICENSE                  ← Apache 2.0 (replace with your license)
│
├── .github/
│   └── workflows/
│       └── pages.yml        ← Build-and-deploy workflow for GitHub Pages
│
├── _layouts/                ← Wrapper HTML around content
│   ├── default.html         ← Base shell with header/footer
│   ├── tutorial.html        ← Tutorial sections (with section nav, duration)
│   └── plan.html            ← Reconciliation/planning docs
│
├── _includes/               ← Reusable HTML fragments
│   ├── header.html          ← Top nav (uses _config.yml values)
│   ├── footer.html          ← Bottom of every page
│   └── excalidraw.html      ← <figure> with SVG + .excalidraw download link
│
├── _data/                   ← YAML data accessible as `site.data.*`
│   └── (empty, expand as needed)
│
├── _docs/                   ← Tutorial content (Markdown collection)
│   ├── 00-outline.md        ← Stub with table of contents
│   └── 01-prerequisites.md  ← Stub with structure guidance
│
├── _plans/                  ← Planning/reconciliation docs (Markdown collection)
│   └── reconciliation-plan.md ← The audit-trail document
│
├── assets/
│   ├── css/
│   │   └── site.css         ← All site styles in one file
│   ├── diagrams/            ← Paired .svg + .excalidraw files
│   │   └── README.md        ← Conventions for adding diagrams
│   └── images/              ← Photos, screenshots, hero images
│
├── examples/                ← Runnable code that lives alongside the tutorial
│   └── README.md            ← Conventions for adding examples
│
├── scripts/                 ← Developer-facing scripts
│   ├── README.md            ← Index of what each script does
│   ├── lib/
│   │   └── _helpers.sh      ← Sourced by every test script
│   └── test-template.sh     ← Copy-and-edit template for new test scripts
│
├── index.html               ← Homepage with hero + cards
├── examples.html            ← Optional listing page for the examples/
└── diagrams.html            ← Optional gallery page for the diagrams/
```

## Conventions worth knowing

These were learned the expensive way during the Hummingbird build. They
apply to most projects you'd build on this skeleton.

### Numbered tutorial files

Tutorial sections live in `_docs/` and are numbered: `00-outline.md`,
`01-prerequisites.md`, `02-introduction.md`, etc. The number prefix:

- Sorts files in editor and on disk in reading order
- Becomes part of the URL slug (`/docs/01-prerequisites/`)
- Lets you reorganize by renaming numbers (with care for cross-links)

Front-matter on each section follows this pattern:

```yaml
---
title: Prerequisites
order: 1
description: One-sentence description for cards and meta tags.
duration: 15 minutes
---
```

The `order` field controls the prev/next nav; the `duration` is
displayed in the layout to set reader expectations.

### `_docs/` and `_plans/` are Jekyll collections

These are **not** Jekyll defaults — they're configured as collections in
`_config.yml`. The `defaults:` block gives every file in `_docs/` the
`tutorial` layout automatically, so you don't repeat `layout: tutorial`
in every front-matter block.

If you rename either, update `_config.yml`'s `collections:` and
`defaults:` sections to match.

### Examples directory is excluded from the build

The `examples/` directory holds runnable Containerfiles, source code,
and configurations the tutorial references — but it is **not** part of
the published site. This is enforced by `exclude: examples/` (with the
trailing slash; without it the rule doesn't fire) in `_config.yml`.

The pattern: write the tutorial section, write a corresponding
`examples/<name>/` directory with a working Containerfile, write a test
script that builds and runs it. The tutorial references commands the
reader can copy-paste; the examples directory holds the same code in
runnable form.

### Diagram pairing

Every diagram lives in `assets/diagrams/` as **two files** with the same
base name:

- `<name>.svg` — the rendered diagram, what appears on the site
- `<name>.excalidraw` — the editable JSON source

The `excalidraw.html` include renders the SVG inline as a `<figure>` and
adds a "Download Excalidraw source" link below it, so anyone can edit
the diagram in [excalidraw.com](https://excalidraw.com) and re-export.

Diagram naming convention: `<section-number>-<topic>-<thing>.svg`. So
the multi-stage build pattern diagram from section 4 is
`04-multi-stage-builds-pattern.svg`. This lets you find diagrams from
the section number alone.

### The reconciliation plan is honest about what's verified

`_plans/reconciliation-plan.md` is the **audit trail**. As you write
tutorial content, you'll inevitably make claims you haven't tested. The
reconciliation plan tracks each one as `verified`, `verified (Fedora 43)`,
`in flight`, `unverified`, or `out of scope`.

This is most valuable when AI is helping write content — AI is excellent
at producing plausible-looking technical claims, and the reconciliation
plan is where those claims get either promoted to verified or flagged
for testing.

The header banner at the top of the testing matrix (G.2 in the
Hummingbird version) gives a clear at-a-glance status. This is the first
thing a reviewer or future you should look at.

### Test script naming and structure

Every `examples/<name>/` should have a corresponding
`scripts/test-<name>.sh` that builds, runs, validates response, and
tears down — even if all six examples share 90% of the script content.
The aggregator `scripts/test-all-examples.sh` runs them all and reports
pass/fail per script.

Test scripts:

- Source `scripts/lib/_helpers.sh` for color output, `repo_root`,
  `wait_for_http`
- Use `set -euo pipefail` so failures surface
- Use `trap "cleanup_container ..." EXIT` to tear down even on failure
- Use `127.0.0.1` not `localhost` (avoids IPv4/IPv6 dual-stack issues)
- Use distinct ports per test (1808x range works) so they don't collide
- Exit non-zero on failure so the aggregator can tally

### The aggregator does not fail-fast

`test-all-examples.sh` runs every test even if earlier ones fail, then
prints a final summary. Useful when you want to see all problems at
once after a refactor instead of fixing them one re-run at a time.

## What's NOT in the skeleton

Deliberately omitted, because they're project-specific:

- The actual tutorial content (you'll write your own)
- The actual examples (project-dependent)
- The actual diagrams (project-dependent)
- A specific color scheme branded to one project (the CSS is neutral)
- A specific test runtime — the helper supports any HTTP-serving
  container; non-HTTP examples need their own validators

## When to use this skeleton

Good fit:

- Multi-section technical tutorials with running code
- Documentation projects where examples need to be verifiable
- Projects where you'll be working with AI assistants and want a clear
  "verified vs. claimed" boundary
- Project Pages on GitHub (`USERNAME.github.io/PROJECT`)

Not a great fit (better tools exist):

- API reference documentation (use OpenAPI/Swagger or similar)
- Single-page reference cards (overkill — just write a Markdown gist)
- Marketing sites (the design is technical, not promotional)

## License

The skeleton itself is Apache 2.0; replace with whatever license your
project uses. The `LICENSE` file should be updated to match your
project before first commit.
