# Lessons learned

What the Hummingbird tutorial campaign taught about three things:
**Podman and containers**, **Jekyll on GitHub Pages**, and
**working with AI assistants on long-running technical projects**.
This document is meant to be readable by you and by an AI assistant
working with you. The opinions here are empirical, not theoretical.

---

## Part 1 — Podman and Podman Compose

### Use Podman, not Docker, when writing container tutorials in 2026

Three reasons:

1. Podman is the default on Fedora and RHEL. Most readers of a
   Red-Hat-ecosystem-adjacent tutorial will have it pre-installed.
2. Podman is rootless by default. Docker requires explicit setup to
   match this security posture.
3. Podman commands and Containerfile syntax are nearly
   indistinguishable from Docker — readers transfer skills both
   directions.

Podman Desktop on macOS provides a GUI and a managed Linux VM that
runs the actual container engine. It works well in 2026; the rough
edges from earlier years are mostly resolved.

### Containerfile vs. Dockerfile

`Containerfile` is the canonical name in the Podman world. `Dockerfile`
also works and is recognized by Podman. Use `Containerfile` in
tutorials targeting Podman; the syntax is otherwise identical.

### `podman` and `docker` are command-compatible

Most `docker <verb>` invocations work as `podman <verb>` — `pull`,
`run`, `build`, `images`, `ps`, `logs`, `exec`, `inspect`, `tag`,
`push`. Behavioral differences exist but are minor for tutorial
purposes. Differences worth knowing:

- Podman has no daemon by default. There's no `podmand` to start.
- Podman pods are a unit between container and Compose stack —
  multiple containers sharing a network namespace. Useful for
  tutorial examples illustrating sidecars.
- Podman builds with **buildah** under the hood, exposed via
  `podman build`. Buildah's `RUN` instruction defaults to
  `/bin/sh -c` — relevant when the runtime image has no shell.

### SELinux and the `:Z` (or `-Z`) flag

On Fedora-family hosts, SELinux blocks containers from accessing
host directories by default. The `:Z` suffix on a volume mount
relabels the host directory so the container can use it:

```bash
podman run -v $(pwd)/data:/data:Z my-image
```

For directly bind-mounted directories (common in podman-compose),
the same applies as `-Z` flag or as `:Z` in the volumes block.

On macOS and non-SELinux Linux distros, `:Z` is a **no-op** — it
doesn't error, it just does nothing useful. Always include it in
tutorial examples; it's correct on Fedora and harmless elsewhere.

### Podman Compose

`podman-compose` is the Docker Compose-compatible CLI for Podman.

- On Fedora 43+: `sudo dnf install -y podman-compose`
- On macOS: ships with Podman Desktop
- On Ubuntu: `pip install podman-compose` or via apt

The compose-file format is the same as Docker Compose. Most
docker-compose.yml files work unmodified, with the exception of
`version: "3.x"` declarations (modern compose ignores them, neither
tool requires them, leave them out).

Caveats:

- **`networks:` is sometimes finicky.** On older podman-compose
  versions, custom networks don't get cleaned up cleanly across
  `up`/`down` cycles. Use `podman-compose down -v` for a full
  reset rather than `podman-compose down`.
- **`depends_on:` doesn't wait for healthchecks** unless you use
  the `condition: service_healthy` syntax. Tutorial examples that
  need a database to be ready before the app starts must define a
  healthcheck on the database and reference it in the dependency.
- **Service-name DNS works the same as Docker Compose.** A service
  named `db` is reachable as `db` from sibling services on the same
  network.

### Distroless runtimes change debugging

If your tutorial uses distroless base images (Hummingbird, Google
distroless, Chainguard), readers cannot `podman exec ... /bin/sh`
into a running container. Cover the **debug sidecar pattern** early:

```bash
podman run -it --rm \
  --pid container:my-running-container \
  --network container:my-running-container \
  registry.access.redhat.com/ubi9/ubi-minimal:latest \
  /bin/bash
```

This attaches a UBI-minimal shell with the same PID and network
namespaces as the running distroless container — same files
accessible via `/proc/1/root/`, same network, full toolchain
available.

### Common test-script gotchas

These came up repeatedly across the Hummingbird examples:

1. **Use `127.0.0.1` not `localhost`.** Modern curl resolves
   `localhost` to `::1` (IPv6) first. Many container runtimes only
   bind to IPv4 by default. Result: "Connection reset by peer" for
   no apparent reason. Always use `127.0.0.1` in test scripts.

2. **Wait for HTTP readiness, don't sleep.** Test scripts that
   `sleep 5 && curl` are fragile. The right pattern:

   ```bash
   for i in $(seq 1 30); do
     if curl -fsS http://127.0.0.1:8080/ >/dev/null 2>&1; then
       break
     fi
     sleep 1
   done
   ```

   This is what `wait_for_http` in `scripts/lib/_helpers.sh` does.

3. **Use distinct ports per test** to avoid collisions when running
   multiple tests in parallel or back-to-back. The 1808x range
   (18080, 18081, …) is rarely used by other tools.

4. **Tear down with `trap` even on failure.** If a test fails
   mid-run, the container is left running. Pattern:

   ```bash
   trap "podman rm -f my-test-container >/dev/null 2>&1 || true" EXIT
   ```

5. **Containerfile RUN in the runtime stage of a multi-stage build
   may fail.** If the runtime image is distroless, there's no
   `/bin/sh` for `RUN` to invoke. Use `COPY` from the builder stage
   to land artifacts in place rather than `RUN` to manipulate them.

### When Hummingbird-style distroless ISN'T the right runtime

Hummingbird (RHHI) is exceptional for compiled-binary or wheel-shipped
workloads. It is **not** the right runtime when:

- The application needs `dnf install` at runtime
- The application is heavy on native dependencies that change
  frequently (large ML stacks beyond NumPy can push this limit)
- The application explicitly requires a shell (some legacy software
  shells out for sub-tasks)

Use UBI for those cases. Mixing UBI builder + Hummingbird runtime
in a multi-stage build is common — the breadth of UBI helps build,
the minimalism of Hummingbird helps deploy.

---

## Part 2 — Jekyll and GitHub Pages

### Use the workflow in `.github/workflows/pages.yml`, not the built-in Pages Jekyll

GitHub Pages has built-in Jekyll support that runs Jekyll 3.10 (very
old). The workflow in this skeleton runs whatever Jekyll version is
pinned in your Gemfile (4.x in 2026) using GitHub's official Pages
deployment actions.

In repo Settings → Pages, set **Source: GitHub Actions**, not
"Deploy from branch."

### Baseurl is the most common deployment bug

The single most common GitHub Pages issue is incorrect `baseurl`.

- For project Pages (`USER.github.io/REPO`): `baseurl: "/REPO"`
- For user/org Pages (`USER.github.io`): `baseurl: ""`
- For local dev: override with `--baseurl ""` so URLs render at the
  root

Internal links must use `{{ "/path" | relative_url }}`,
`{{ "/path" | prepend: site.baseurl }}`, or the `relative_url`
filter — never hard-code `/path/to/file`.

### Collections are powerful and underused

Default Jekyll has `_posts/` for blog posts. Tutorials don't fit that
shape. Define collections in `_config.yml` for any structured
multi-page section:

```yaml
collections:
  docs:
    output: true
    permalink: /docs/:name/
  plans:
    output: true
    permalink: /plans/:name/
```

Combined with `defaults:` you can give every file in a collection a
default layout, eliminating repeated `layout:` front-matter:

```yaml
defaults:
  - scope:
      path: ""
      type: docs
    values:
      layout: tutorial
```

### CSS: Hand-rolled or Tailwind?

Hand-rolled, for tutorial sites.

Tailwind is excellent for application UIs. For documentation, the
combination of long content, code blocks, callouts, tables, and
diagrams works better with hand-rolled CSS using semantic class
names. The skeleton's `site.css` is ~17KB hand-rolled, no build step,
no PostCSS, no toolchain to maintain.

This was the right call on the Hummingbird build and would be again.

### Markdown rendering: kramdown with GFM

Jekyll's default kramdown parser with GFM input gives you tables,
fenced code blocks with language hints, autolinks, strikethrough, and
task lists — basically everything you'd want for a tutorial. Pin
`kramdown-parser-gfm` and `rouge` (for syntax highlighting) in the
Gemfile.

### Code blocks render with rouge automatically

In a fenced code block, the language hint after the backticks
controls syntax highlighting:

    ```bash
    podman run -d quay.io/example/image:latest
    ```

Rouge supports basically every language you'd write a tutorial about.
The CSS in `site.css` styles the `<pre>` and `<code>` tags;
syntax-color tweaks happen in the rouge classes (`.highlight .k`,
`.highlight .s`, etc.).

### The Excalidraw pattern is worth the small overhead

Pairing every diagram as `<name>.svg` (rendered) plus
`<name>.excalidraw` (source) means:

- The site renders fast (inline SVG, no external editor required)
- Anyone — including AI assistants — can edit the diagram by
  re-opening the source in excalidraw.com
- Diff-friendly source files (JSON) live in git alongside the binary
  output

The `_includes/excalidraw.html` snippet renders both with a single
include line.

### Watch for SVG caching aggressively

Browsers cache SVGs more aggressively than HTML. After deploying a
diagram update, a normal page reload may still show the old version.
Hard reload (Ctrl+Shift+R / ⌘+Shift+R) or test in an incognito window
when verifying diagram changes.

GitHub Pages CDN can also hold a stale SVG up to ~10 minutes after
deploy. If a hard reload still shows old content, wait and try again.

### GitHub Actions deprecation warnings are usually GitHub's problem

Periodically GitHub deprecates Node versions used by the Pages
actions. The warnings appear before any breaking change deadline
(usually months in advance). Bump `actions/checkout` to the latest
version when prompted; for the Pages-specific actions
(`configure-pages`, `deploy-pages`, `upload-pages-artifact`), wait for
GitHub to update them — they have strong incentive to do so before
the deadline.

The `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` env var (or its successor)
forces the runner to use a newer Node version, but does **not**
suppress the deprecation warnings themselves — those come from action
manifests, which only the action's maintainer can update.

---

## Part 3 — Working with AI assistants on long technical projects

### The reconciliation plan is the most important file

When AI is helping write technical content, the assistant will
produce plausible-looking claims that may not match reality. The
reconciliation plan tracks every claim's verification status. It's
not bureaucratic overhead — it's the difference between honest
documentation and confident-sounding fiction.

Conventions that worked:

- `verified` — tested end-to-end, by a human, in this session
- `verified (Fedora 43)` — tested on one platform, others pending
- `verified (Fedora 43 + macOS)` — tested cross-platform
- `in flight` — currently being worked on
- `unverified` — claim taken from sources, not tested
- `out of scope` — deliberately not testing in this iteration

Claims default to `unverified` when first written. They get promoted
when a test confirms them. **AI should not promote claims to
`verified` on its own** — that requires a human running the test and
seeing it pass.

### Prefer tarballs over inline pastes for any deliverable longer than ~30 lines

Long inline pastes risk:

- Auto-linkification of URLs (especially Markdown ones)
- Auto-formatting of code blocks (especially YAML)
- Multi-line commands breaking shell autocomplete (especially zsh)
- Newlines getting eaten or duplicated

Tarballs preserve everything exactly. The `present_files` tool
produces clickable downloads for the user. The user extracts and
gets a clean diff to review before committing.

### Single-line shell commands paste better than multi-line

If the deliverable is a script, put it in a tarball. If it's a
command for the user to run inline, write it as one line, even if
that means semicolons and backslash-continuations:

```bash
# Good: single-line paste
cd ~/project && tar -xzf ~/Downloads/update.tar.gz && git add -A && git commit -m "..."

# Risky: multi-line paste in zsh with autocomplete plugins
cd ~/project
tar -xzf ~/Downloads/update.tar.gz
git add -A
git commit -m "..."
```

Some shell configurations mangle multi-line pastes when the user
hits Enter mid-paste, especially with autocomplete or bracketed-
paste mode quirks.

### Use the test-it-on-real-hardware loop

The Hummingbird campaign produced real, working containers because
every claim was tested against running images on the user's actual
machine. The pattern:

1. AI proposes a Containerfile or command
2. User runs it
3. User pastes the output (success or error) back to AI
4. AI debugs based on the actual error, not on what the error
   "should be"

This loop is slow (each cycle is minutes) but produces correct
results. Skipping it produces plausible-looking output that fails in
production.

### Ship working code, then write the prose

For tutorials with runnable examples, get the example working first.
Test it against real services. Fix all the bugs. **Then** write the
tutorial prose explaining it. Writing prose first encourages the AI
to make confident claims about behavior that hasn't been verified —
because the prose has to assert *something*.

### Long sessions need recap moments

A session that runs hours can drift. Periodically ask the assistant
to summarize:

- What's been verified
- What's pending
- What the user agreed to in earlier turns
- What the testing matrix currently says

This catches drift early and gives both the human and the assistant
a fresh shared context.

### Clean up debugging artifacts before declaring done

Every long debugging session produces ad-hoc scripts, cleanup
scripts, throwaway tests. Before declaring the project done, sweep
the repo for these and either move them into the formal
`scripts/` directory with proper structure, or remove them.

The Hummingbird campaign produced `CLEANUP.sh` and
`test-remaining.sh` in the repo root over the course of debugging.
The final cleanup pass deleted them and replaced them with
properly-structured scripts under `scripts/`. The repo looks
intentional now; before that pass it didn't.

### Vendor neutrality is an honest principle worth holding

Even in a tutorial about a specific vendor's product, mentioning
competitors in a "we don't compare to X, Y, Z" line invites the
question of why those particular three are listed. The Hummingbird
build had several "we don't compare to Docker, Chainguard, K8s"
mentions that all got cleaned up to "we don't compare to other
distroless image projects." More honest, less likely to age poorly,
no editorial endorsement of one alternative over another.

The single exception is install URLs for tools that come from a
specific vendor (e.g., `github.com/anchore/syft`). Those are
functional, not promotional, and worth leaving alone.

---

## TL;DR for the next project

If you read nothing else:

1. **Use Podman, write Containerfiles, target Fedora-family.**
2. **Always include `:Z` on volume mounts, always use `127.0.0.1`
   in tests, always wait-for-HTTP not sleep.**
3. **Pin Jekyll in your Gemfile, deploy via the GitHub Actions
   workflow, set baseurl to your repo name.**
4. **Maintain a reconciliation plan from day one. Default new
   claims to unverified.**
5. **Ship via tarballs; paste single-line commands; test against
   real hardware; recap periodically.**
6. **Don't promote claims to verified without a real test.**
7. **Vendor-neutral language ages better than vendor-specific
   complaints.**

Everything else is project-specific detail.

# Lessons learned — additions from r1–r18

> Merge instructions: review against the existing
> `onboarding/LESSONS-LEARNED.md` (formerly at the repo root)
> and integrate the items below that aren't already covered.
> Some may duplicate existing notes; deduplicate as you see fit.
> Once merged, delete this file.

---

## Process

### Ship assets and their referencing prose in the same iteration
r16 shipped 5 SVG diagrams without updating §3/§6/§11/§12 to
reference them. The result was 4 sub-iterations (r16, r16a,
r16b, r16c) of recovery: auto-splice, fix layering, fix more
layering, finally precise ASCII-to-SVG replacement. Visual
content needs its referencing prose at the same moment, or the
assets are orphaned and the next iteration has to clean up.

### Auto-splice is unsafe when destination files already contain related content
r16b's auto-splice heuristic (insert SVG embed before the first
`## ` heading) didn't reason about whether existing ASCII art
at the destination represented the same concept. Result: SVGs
landed at unrelated positions while the original ASCII diagrams
stayed in place inside their proper sections. The correct
operation is *replace ASCII with SVG in place*, which requires
the ASCII source content to be known — and that requires
reading the file, not pattern-matching a heading.

### Cross-reference links don't get updated by section renames
When §13 was renamed Wrap-up → Alternatives in r14a, the
§12→§13 footer link orphaned and pointed at a dead URL for 4
iterations before being caught. `scripts/check-cross-references.sh`
makes this a one-command check; worth running in CI.

### CI build-success is necessary but not sufficient verification
Jekyll built fine for the §14 FAQ kramdown collision; the page
"rendered" but the rendering was wrong (multiple Q&A entries
got swallowed because `<placeholder>` in inline backticks
looked like HTML opening tags). Only a human eyeballing the
deployed preview catches this class of bug. Build CI catches
syntax errors; visual review catches semantic errors. Do both.

### Sub-iteration fix-ups (rNNa, rNNb, rNNc) are normal and OK
Don't try to land a complex change perfectly in one iteration.
Use the rNN.tar.gz pattern with `fix(scope):` commits for
sub-iterations, document each in the reconciliation plan, and
move on. The history is more valuable than the perfection.

## Jekyll / kramdown

### kramdown HTML-collision is a real failure mode
The §14 FAQ shipped initially with `<placeholder>` patterns
inside inline backticks; kramdown interpreted these as HTML
opening tags and the cascade swallowed multiple Q&A entries.
Use `[placeholder]` instead. `scripts/editorial-audit.sh`
catches this pattern, with fence-counting to avoid flagging
matches inside code blocks.

### `{% raw %}` around image URLs breaks them
Wrapping `{{ "/foo" | relative_url }}` in `{% raw %}`
prevents Liquid evaluation, leaving the literal
`{{ ... }}` text as the image URL. Three image embeds in
§11 and §12 had this pattern (the audit script flagged them
in r17 and they were removed). Rule of thumb: use `{% raw %}`
to escape Liquid syntax in *displayed* code samples, never
inside an active image src or attribute.

### Liquid `{{ .Capital }}` collision is real but rare
A specific pattern — `{{ ` followed immediately by a
capital-letter property access — triggers Jekyll's Liquid
parser even inside what looks like fenced code. When in doubt
about a span containing Liquid-looking syntax, wrap in
`{% raw %}{% endraw %}` (the audit script's Liquid-safety
check confirms files don't have this collision pattern outside
existing raw blocks).

### Jekyll permalink slug includes the NN- prefix
For `_docs/12-keda.md`, the published URL is `/docs/12-keda/`
(full filename), not `/docs/keda/`. This caught the
check-cross-references.sh script during initial smoke testing.
If you rename a file you must update every link to it.

## Shell / scripts

### Single-line shell commands for zsh paste safety
zsh's autosuggest can mangle multi-line commands when pasted.
Tutorial code blocks should be single-line where reasonable;
where continuation is needed, use `\` line-continuations
consistently and keep the whole command together.

### `127.0.0.1` not `localhost`
`localhost` can resolve to either IPv4 or IPv6 depending on
the system; some port-forward / proxy stacks bind only IPv4.
`127.0.0.1` is unambiguous. Use it everywhere in commands and
in code examples.

### `trap cleanup EXIT` is mandatory in demo scripts
Every `examples/NN-name/demo.sh` has a cleanup trap that
removes resources on script exit (success, failure, or
Ctrl-C). This makes re-runs idempotent and keeps the cluster
state predictable. The `cleanup.sh` script in each example dir
provides the deeper teardown when you want to actually free
resources rather than just reset for the next run.

### Continuation-aware shell parsing matters in audit scripts
The first version of `scripts/editorial-audit.sh` flagged a
"duplicate --remove-operators flag" as a finding when in fact
the two appearances were in *separate commands* within the
same fenced block. The fix: parse each command independently
(handling `\` line-continuations) rather than concatenating
all lines. Lesson: any "find duplicate X in a block" check has
to know what a "block" actually means in shell.

### Diagnostic dumps on failure
When a demo script fails, it dumps: relevant namespace state
(`kubectl get all,events`), pod logs from any failed
containers, and recent events. This made debugging far faster
during the project — most failures during r4–r12 were diagnosed
from the failure log alone, no re-run needed.

## Kubernetes / minikube

### Image cache doesn't cross profiles
Minikube profiles each have their own image cache. If §11
builds `nginx-custom:v1` on the `istio` profile, that build
isn't visible to the default `minikube` profile. Either build
on both profiles, push to a registry, or keep workloads on
one profile.

### Rootless podman driver puts ingress IPs on the slirp4netns side
Under rootless podman, the ingress gateway's IP isn't
host-routable. Use `kubectl port-forward` (consistent with §6
and §9), or `minikube tunnel -p PROFILE` if you need a stable
external IP. Plan demo scripts around port-forward to keep
things simple.

### `fs.inotify.max_user_instances` matters for multi-cluster
Fedora's default is sized for one minikube cluster. Starting a
second cluster (e.g., `minikube` + `istio` profiles together)
hits the limit and the new cluster's systemd fails at
init with "Too many open files". `/etc/sysctl.d/99-kubernetes.conf`
with `fs.inotify.max_user_instances = 512` and
`fs.inotify.max_user_watches = 524288` solves it persistently.
The §1 prereq script reports the current values and warns if
they're insufficient.

### Native sidecars (KEP-753) change where the sidecar lives
On Kubernetes 1.28+ with Istio 1.29+, the istio-proxy sidecar
is an *init container* with `restartPolicy: Always` (a "native
sidecar"), not a regular container. JSONPath queries against
`.status.containerStatuses[]` won't find it; look at
`.status.initContainerStatuses[]` instead, or check both
`.spec.containers[*].name` and `.spec.initContainers[*].name`.
`kubectl get pods` still shows `2/2` ready (native sidecars
count toward readiness totals).

### Strimzi pins Kafka versions narrowly
Strimzi 0.51 supports ONLY Kafka 4.1.0, 4.1.1, 4.2.0.
Specifying 3.x in the manifest produces a `READY=False` Kafka
CR with an opaque reason; `kubectl describe kafka` is needed
to surface the actual error. We caught this in r13's first run
and pinned 4.1.0 thereafter.

## Image / packaging

### UBI base images for Fedora-adjacent users
We chose `registry.access.redhat.com/ubi9/ubi-minimal` over
Alpine or scratch. Trade-off: ~80 MB larger but no
subscription-manager required on Fedora, production-grade
security posture, and matches what readers see in OpenShift
contexts. Worth it for this audience.

### Multi-stage builds: ubi9 builder → ubi9-minimal runtime
Builder stage has compilers and dev headers; runtime stage is
minimal. `USER 1001:0` in the runtime stage matches
OpenShift's restricted SCC. This pattern appears in every
custom image in the tutorial (nginx in §6, order-processor in
§12 Kafka).

## Tooling

### `gh run watch` is your CI verification, not local `jekyll serve`
The user verifies builds via `git push && sleep 5 && gh run watch`
rather than `bundle exec jekyll serve`. The `sleep 5` is
because the run isn't immediately registered after push;
attaching too early gets "run not found".

### Tarball-per-iteration delivery
Every iteration ships as `minikube-on-fedora_rNN.tar.gz` that
extracts in place over the working copy. Reviewable via
`git diff --stat` before committing, applicable in one
command, easy to roll back if needed. This pattern scales
better than diff-bundles for changes that touch multiple
files.

### Audit scripts catch the regressions a human won't
`check-cross-references.sh` catches dead internal links.
`editorial-audit.sh` catches kramdown collisions, broken
`{% raw %}` patterns, stale section references, "we" voice
creep, stale TODOs, and duplicate shell flags within a single
command. Run both before any release.

## Project management

### Reconciliation plan is the source of truth for "what's done"
The `_plans/reconciliation-plan.md` file tracks every claim in
the tutorial as either `verified (Fedora 44)` or `unverified`,
plus a Section D log of every iteration with what shipped and
what was learned. New readers of the repo should read this
file second (after `README.md`) to understand the actual state.

### PRD reconciliation document closes out the project
`_plans/prd-reconciliation.md` records what shipped vs. what
was planned, with rationale for each divergence (macOS dropped,
UBI instead of Hummingbird, vendor-neutral relaxed for §13,
"we" voice not strictly avoided, Podman not version-pinned).
Worth writing at project close; gives future contributors the
intent vs. reality picture in one document.

### Default status for new claims is `unverified`
Never mark something `verified` without a real test run on the
target platform. If you're temped to mark it verified because
"it should work" or "it works on my similar setup", it's
`unverified`. This discipline kept the 107 verified-row count
honest.

---

## r18 (project close-out additions)

### Examples-as-pages: the README is the source of truth
The published per-example pages at `/examples/NN-name/` are
*generated* from each example's `README.md` via
`scripts/sync-example-pages.sh`. Don't edit the
`_example_pages/*.md` files directly — they'll be overwritten
on the next sync. Edit the README and re-run the sync.

### Onboarding folder centralizes orientation docs
`LESSONS-LEARNED.md`, `GETTING-STARTED.md`, and
`STARTING-WITH-CLAUDE.md` moved into `onboarding/` to keep the
repo root scannable. The top-level README links to the
onboarding folder; new contributors who land on the repo see
the README first, then navigate to `onboarding/` for the
orientation material.

### What "victory" looks like for a tutorial project
Three things needed to be true before this project could be
declared done:
1. Every claim verified or marked unverified — done (107 verified)
2. Every cross-reference resolves — done (audit script clean)
3. The "what shipped vs. what was planned" diff written down —
   done (`_plans/prd-reconciliation.md`)

Not on the list: "every section reads perfectly" (that's
infinite work). The discipline is knowing when to ship.

# PRD additions — r18

> Merge instructions: review the additions below against the
> current `PRD.md` and integrate. Most are clarifications of
> what shipped rather than scope changes; a few items represent
> intentional additions to the planned scope. Once merged,
> delete this file.

## Add to "Deliverables" section

The PRD originally listed deliverables at the level of "tutorial
sections + runnable examples + reconciliation plan". The actual
shipped scope also includes:

- **Per-example Jekyll pages** at `/examples/NN-name/`, generated
  from each example's `README.md` via `scripts/sync-example-pages.sh`.
  Each tutorial section that introduces a runnable workload has
  a corresponding published example page; the §16 hub at
  `/docs/16-examples/` is the navigation index for all of them
- **Audit tooling**: `scripts/check-cross-references.sh` and
  `scripts/editorial-audit.sh` for ongoing documentation quality
- **PRD reconciliation document** at `_plans/prd-reconciliation.md`
  capturing the shipped vs. planned diff with rationale per
  divergence
- **Onboarding folder** at `onboarding/` centralizing
  `GETTING-STARTED.md`, `LESSONS-LEARNED.md`, and
  `STARTING-WITH-CLAUDE.md` (formerly at repo root)

## Add to "Sections" outline

The planned outline had `TODO:` markers for most section titles.
The shipped outline is:

| § | Title | Has Example Page |
|---|---|---|
| §0 | Outline | — |
| §1 | Prerequisites | — |
| §2 | Tooling install | — |
| §3 | Starting minikube | ✓ |
| §4 | Profiles + multi-node | ✓ |
| §5 | Addons + dashboard | — |
| §6 | Deploy via kubectl | ✓ |
| §7 | NodePort | ✓ |
| §8 | Persistent Volumes | ✓ |
| §9 | helm | ✓ |
| §10 | Editor/shell/terminal | — |
| §11 | Istio | ✓ |
| §12 | KEDA (Kafka + HTTP) | ✓ (×2: kafka, http) |
| §13 | Alternatives to minikube | — |
| §14 | FAQ + cleanup recipes | — |
| §15 | Where to go next | — |
| §16 | Examples (hub) | (index of all the above) |

Sections without a "Has Example Page" checkmark are either
conceptual (§1, §2, §13–§15), exploratory without a canonical
demo (§5, §10), or summary navigation (§0, §16).

## Add to "Non-goals" section

- **Maintaining vendor-neutral language** — the PRD's
  vendor-neutral stance was deliberately relaxed for §13
  (Alternatives to minikube), where honest comparison of kind /
  k3s / microk8s / MicroShift is more useful to the reader than
  refusing to take a position. See
  `_plans/prd-reconciliation.md` for the full rationale
- **Eliminating first-person plural ("we") voice** — the audit
  script flags instances but mechanical rewriting introduces
  awkward phrasing. The 7 surviving instances in §11 and §12 are
  contextual (rhetorical "if we had one", quoted upstream text,
  introducing tutorial choices) and judged not worth changing
- **Pinning Podman to a specific version** — the prereq script
  reports the installed version and warns if features used by
  the tutorial are absent; specific version pinning would have
  made the tutorial fragile to Fedora's rebase cadence

## Add to "Audience" section

The shipped audience definition (Fedora 44 developer, basic
Kubernetes literacy, wants local cluster without Docker Desktop
or managed cloud) is more concrete than the PRD's
`TODO:` placeholders. Specifically:

- **Primary**: Fedora 44 desktop/workstation user with basic
  container experience (knows what an image is, can run
  `podman build`)
- **Secondary**: Linux developers on other distributions (most
  material applies; only Fedora 44 is tested) and helm/Istio/KEDA
  learners wanting a low-friction local environment
- **Explicitly not served**: complete Kubernetes beginners,
  Windows users without WSL, anyone needing macOS-tested
  instructions

## Add a "Project state" section near the end

Replace any "Project state: in progress" with the close-out
status:

- **Iteration count**: 17 numbered iterations plus sub-iterations
  (r13a–r13f, r14a, r16a–c, r17), all documented in
  `_plans/reconciliation-plan.md` Section D
- **Verified facts**: 107 rows in Section B of the reconciliation
  plan, each verified on Fedora 44
- **Audit clean**: cross-reference and editorial audit scripts
  both pass; no broken links or known anti-patterns in the
  tutorial body
- **Closed**: project considered feature-complete as of r18.
  Any future work happens as new iterations (r19+) addressing
  specific findings from continued use of the tutorial
