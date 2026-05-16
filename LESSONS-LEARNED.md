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
