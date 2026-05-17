# Contributing

Short version: this project uses **Conventional Commits** with a small
fixed set of types listed below. PRs should match the convention; CI
doesn't enforce it (yet) but reviewers will ask you to amend if not.

## Commit-message format

```
<type>(<scope>): <short summary>

<optional body, wrap at 72 chars>

<optional trailers, e.g. Fixes: #123>
```

- `<type>` from the table below.
- `<scope>` is **optional** but expected on `docs:` and `demo:` commits.
  Use `§0`...`§15` for section work matching the `_docs/NN-*.md` files,
  `demo-NN` for example work matching `examples/NN-*/` directories,
  or omit when the change spans many areas.
- `<short summary>` is one line, **imperative mood**, ≤ 72 chars,
  no trailing period.
- The body is optional but encouraged for anything beyond a typo fix.
  Wrap at 72 chars.

### Types

| Type        | When to use                                                                                |
|-------------|--------------------------------------------------------------------------------------------|
| `docs:`     | Tutorial prose under `_docs/`, README, PRD, plan updates                                    |
| `site:`     | Jekyll layouts, includes, CSS, page structure under `_layouts/` `_includes/` `assets/`      |
| `demo:`     | Anything inside `examples/NN-*/` (manifests, helm values, demo.sh)                          |
| `ci:`       | `.github/workflows/`, helper scripts and test scripts under `scripts/`                      |
| `chore:`    | Routine maintenance (dependency bumps, `.gitignore`, file moves, iteration archive housekeeping) |
| `fix:`      | Bug fix in any of the above; **always** pair with the scope of the bug                      |
| `feat:`     | New capability; **always** pair with the scope where it lands                               |
| `refactor:` | Reorganization without behaviour change                                                     |
| `style:`    | Formatting only, no logic change                                                            |

### Examples

```
docs(§6): expand kubectl section with imperative dry-run patterns
```

```
fix(demo-06): NodePort service-type missing in deployment manifest
```

```
site: align card grid to three columns on viewports >= 1024px
```

```
chore: archive r03 — §1 prerequisites + iteration plan
```

```
feat(demo-12): KEDA HTTP add-on demo with hey-driven scaling
```

### Subject-line cheat sheet

- "Add", "Drop", "Rename", "Move" — imperative verbs are right
- "Added", "Dropped" — past tense is wrong; reword
- "Updates docs" — vague; say *what* about the docs
- "WIP" — fine on a feature branch, but squash before merge

## When to split a commit

Each commit should leave the tree in a working state. If a single
change touches **multiple types** (e.g. you fixed a demo bug *and*
expanded the prose around it), prefer two commits:

```
fix(demo-09): chart values missing serviceAccount block
docs(§9): explain why minikube needs the serviceAccount override
```

over a single mixed-type commit. The exception: when the doc change
*explains* the fix and they share rationale; then bundle them and
say so in the body.

## Container image policy

This tutorial intentionally pulls **only public, UBI-based images**
from registries that do not require Red Hat subscription
registration. The goal is friction-free: no `subscription-manager
register`, no Docker Hub anonymous rate limits, no licensing
ambiguity for readers.

### Preferred image sources (in priority order)

1. `registry.access.redhat.com/ubi9/...` — UBI 9 images. Stable,
   supported, publicly pullable
2. `quay.io/...` — when the project ships only to Quay
3. `ghcr.io/...` — when the project ships only to GHCR
4. `docker.io/...` — last resort. Document inline why no UBI,
   Quay, or GHCR equivalent exists

### Documented exceptions

The following non-UBI images are knowingly used. New exceptions
require updating this table:

| Image                                            | Where       | Why                                                  |
|--------------------------------------------------|-------------|------------------------------------------------------|
| `docker.io/istio/proxyv2`                        | §11 demos   | Istio's official sidecar image; no UBI variant       |
| `docker.io/istio/pilot`                          | §11 install | Istio control plane; no UBI variant                  |
| `ghcr.io/kedacore/keda`                          | §12 install | KEDA operator; published only to GHCR                |
| `ghcr.io/kedacore/keda-add-ons-http-interceptor` | §12 demo    | KEDA HTTP add-on; published only to GHCR             |

For the application workloads the tutorial deploys (the actual
demo apps, not the platform images),
`registry.access.redhat.com/ubi9/nginx-124` is the default.

### UBI without a Red Hat subscription

If a future iteration adds a custom `Containerfile` using `FROM
registry.access.redhat.com/ubi9/ubi:9.x` (the "full" UBI base,
which uses `dnf` rather than `microdnf`), include this fragment
right after the `FROM` line to silence subscription-manager:

```dockerfile
# UBI w/o entitlement: silence subscription-manager.
# Free UBI repos in ubi.repo are unaffected — dnf install works normally.
RUN rm -f /etc/yum.repos.d/redhat.repo && \
    sed -i 's/^enabled=1/enabled=0/' \
        /etc/dnf/plugins/subscription-manager.conf 2>/dev/null || true
```

**Why**: UBI ships with `/etc/yum.repos.d/redhat.repo` configured to
fetch entitlement-only RHEL repos. Without a Red Hat subscription
registered inside the container (which we don't, and shouldn't),
every `dnf install` triggers the `subscription-manager` plugin to
refresh those repos. The refresh fails with `Unable to read
consumer identity` and on some configurations exits non-zero,
killing the build. The `redhat.repo` removal stops the refresh
attempt; the plugin disable silences any residual warnings.

**Free UBI content is unaffected** — the open `ubi-*-rpms` repos
in `/etc/yum.repos.d/ubi.repo` work without entitlement and
provide everything a tutorial-scale build would need. UBI without
subscription is a documented, supported Red Hat configuration;
this is just the one-line opt-out of the entitlement plumbing
that's installed by default.

This applies only to **`ubi9/ubi`** stages. **`ubi9/ubi-minimal`**
uses `microdnf`, which has no subscription-manager plugin and no
`redhat.repo`; runtime stages on `ubi-minimal` need no fix.

The bulk of this tutorial does *not* build images — it pulls
pre-built UBI ones. The fragment above is only relevant if a
future iteration adds a Containerfile under `examples/`.

### Adding a new exception

Don't, unless:

- You've checked `registry.access.redhat.com`, Quay.io, and the
  project's GHCR namespace and confirmed the upstream image isn't
  available there
- The exception is documented inline (a `# Note:` comment above
  the relevant `image:` or `FROM` line stating *why* this image
  isn't UBI)
- The rationale is added to the exceptions table above

## Reconciliation plan

Every substantive change should leave a corresponding entry in
[`_plans/reconciliation-plan.md`](./_plans/reconciliation-plan.md).
This is **not** a changelog — it tracks verification state, not
the list of commits. The rule of thumb:

- A code or docs change that you've personally walked through on
  Fedora 44 → flip the matrix row from `unverified` to
  `verified (Fedora 44)`, add a dated entry to Section D
- A code or docs change you haven't run end-to-end → leave the
  row as `unverified` and **say so** in Section D if the surface
  area changed

The reconciliation plan is the honest source of truth for what's
real vs. what's drafted-but-untested. Keep it honest.

## Site authoring conventions

Jekyll's Liquid templating uses `{{ }}` and `{% %}` syntax. Several
things this tutorial discusses also use `{{ }}` — Go templates in
helm charts, kustomize templated YAML, `podman info --format`
strings, future Istio config patterns. When Liquid encounters
these in markdown, it tries to evaluate them. Best case: noisy
warnings during build. Worst case: the build crashes because
Liquid's parser tries to run the foreign template as a Liquid
pipeline and hits an arity mismatch (the kind that exits the
build with code 1).

Two conventions handle this cleanly. Different file types use
different mechanisms because the trade-offs differ.

### `_docs/*.md` — wrap individual blocks

The section pages mix intentional Liquid (`{{ "/docs/foo/" |
relative_url }}` in nav links, `{% seo %}` in the layout) with
content that *describes* templates from other tools (helm, podman
format strings, etc.). The right granularity is per-block.

For any markdown code block containing `{{ }}` syntax that isn't
Liquid:

```markdown
{% raw %}
``yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "nginx-helm.fullname" . }}-content
``
{% endraw %}
```

(Triple-backticks shown as double here so this markdown file
itself doesn't break. Use real triple-backticks in your actual
content.)

The `{% raw %}` / `{% endraw %}` tags sit outside the code fence;
the markdown renderer still treats the fenced block as code, and
Liquid passes its contents through verbatim.

Inline mentions in prose work the same way — wrap the paragraph:

```markdown
{% raw %}**Go templating + Sprig functions** — `{{ .Values.foo }}`
inserts a value …{% endraw %}
```

### `_plans/*.md` — disable Liquid wholesale

The plan files (`reconciliation-plan.md`, `iteration-plan.md`)
describe project state in prose, including frequent references to
templating syntax inside markdown table cells. Wrapping every
mention in `{% raw %}` works but breaks table rendering in some
edge cases — table cells don't always play nicely with embedded
Liquid tags.

These files don't actually use any Liquid features. Disable
Liquid for the entire file via front matter:

```yaml
---
title: Reconciliation plan
description: …
render_with_liquid: false
---
```

The `render_with_liquid: false` directive (Jekyll 3.0+) tells the
build to skip Liquid processing for this page. Markdown rendering
still happens. No raw tags needed anywhere in the body.

### Catching collisions before push

`scripts/check-liquid-collisions.sh` runs a static check for both
conventions. It's bash + awk, runs in well under a second, doesn't
need Ruby/Bundler/Jekyll installed:

```bash
./scripts/check-liquid-collisions.sh
```

What it catches in `_docs/`:

- `{{ .UpperCase }}` patterns (Go template variable access; Liquid
  uses lowercase by convention)
- `{{ printf }}`, `{{ define }}`, `{{ range }}`, `{{ with }}`,
  `{{ include "..." . }}` (Go-only constructs)
- `{{/* ... */}}` Go template comments

What it catches in `_plans/`:

- Any `{{ }}` content in a file missing
  `render_with_liquid: false` in front matter

Run it whenever a section adds template-heavy content. CI also
catches the same issues via the actual Jekyll build — this is an
optional pre-flight that gives faster feedback than push-then-wait.

## Branching and PRs

- Default branch: `main`
- Branches: `feat/<thing>`, `fix/<thing>`, `docs/<scope>`. Anything
  short-lived
- One commit per logical change is preferred; squash-merge is fine
  if review surfaced fixups
- Force-pushing your own feature branch is fine; force-pushing
  `main` is not

## Iteration cadence

This project ships in **iterations** named `_rNN`. Each iteration:

1. Drops as a tarball (`minikube-on-fedora_rNN.tar.gz`)
2. Extracts in-place over `~/Dev/minikube-on-fedora/`
3. Gets committed with a `chore: archive rNN — <summary>` message
4. Pushes to `main`; `gh run watch` confirms the Pages deploy

The iteration plan in
[`_plans/iteration-plan.md`](./_plans/iteration-plan.md)
describes the six-phase roadmap and what each iteration ships.
