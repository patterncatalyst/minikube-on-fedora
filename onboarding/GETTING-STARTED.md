# Getting started

Two paths: do the setup by hand (about 30 minutes), or hand it to an
AI assistant with the prompt at the bottom of this file (about 5
minutes of your time, the assistant does the typing).

The end state is the same: a buildable Jekyll site with your
project's name and branding, deployed to GitHub Pages, ready for you
to start writing tutorial content.

---

## Path A: Manual setup

### 1. Copy the skeleton

```bash
# From wherever you keep the skeleton:
cp -r jekyll-tutorial-skeleton/ my-new-tutorial/
cd my-new-tutorial/

# Strip the skeleton's git history if it has any
rm -rf .git

# Initialize as a fresh repo
git init
git branch -M main
```

### 2. Configure for your project

Open `_config.yml` and replace every value marked `TODO`:

```yaml
title: "My Awesome Tutorial"          # Was: "TODO: Your Tutorial Title"
description: "Teaching X to people who already know Y."
brand_emoji: "🚀"                     # One emoji for the header brand mark
github_username: "your-github-handle"
github_repo: "my-new-tutorial"
baseurl: "/my-new-tutorial"           # Match the repo name exactly
```

The baseurl matters: if your site lives at `https://USER.github.io/REPO`,
`baseurl` must be `/REPO`. If your site lives at `https://USER.github.io`
(a user/org Pages site), `baseurl` must be `""`.

Then update the LICENSE file with your project's license, and replace
the README.md with one specific to your project.

### 3. Install Ruby and Jekyll dependencies

If you don't have Ruby installed:

- **Fedora**: `sudo dnf install -y ruby ruby-devel @development-tools`
- **macOS**: `brew install ruby` (then add Homebrew Ruby to PATH)
- **Ubuntu**: `sudo apt install -y ruby-full build-essential`

Then in the project directory:

```bash
bundle install
```

This reads the Gemfile and installs the pinned Jekyll version locally
into `vendor/bundle/`. First run takes a minute or two; subsequent
runs are instant.

### 4. Run the dev server

```bash
bundle exec jekyll serve --baseurl ""
```

Open http://localhost:4000/ in a browser. You should see the
landing page with your project's title and emoji in the header.
Edit any file in `_docs/`, `_includes/`, `_layouts/`, `assets/css/`,
or the top-level pages and the site rebuilds automatically.

The `--baseurl ""` flag overrides the production baseurl for local
dev, so URLs render as `/docs/01-prerequisites/` instead of
`/my-new-tutorial/docs/01-prerequisites/`.

### 5. Push to GitHub

```bash
git add .
git commit -m "Initial commit from Jekyll tutorial skeleton"

# Create the repo on GitHub first (any way: web UI, gh CLI, etc.)
git remote add origin git@github.com:YOUR-USERNAME/my-new-tutorial.git
git push -u origin main
```

### 6. Enable GitHub Pages

In the repo on GitHub:

1. **Settings → Pages**
2. **Build and deployment → Source: GitHub Actions**

That's all. The workflow in `.github/workflows/pages.yml` triggers on
push to main, builds the site with the Gemfile-pinned Jekyll, and
deploys to Pages. First deploy takes ~1 minute. Watch progress in the
**Actions** tab.

After the first successful deploy, your site is at
`https://YOUR-USERNAME.github.io/my-new-tutorial/`.

### 7. Start writing

The skeleton ships two stub tutorial files:

- `_docs/00-outline.md` — your table of contents
- `_docs/01-prerequisites.md` — what readers need installed before
  they can follow along

Edit those, add more files (`02-something.md`, `03-something.md`,
…), and the section nav in the tutorial layout fills in
automatically based on the `order:` field.

For runnable code examples, add directories under `examples/` and
matching test scripts under `scripts/`. The `scripts/test-template.sh`
is a copy-and-edit starting point.

---

## Path B: Hand it to an AI assistant

If you have access to Claude or another capable AI assistant, this
workflow is faster. Open a fresh chat session and paste the prompt
below as your first message, with the bracketed values filled in.

You'll need to upload the skeleton tarball or have the assistant
work in a project where it has filesystem access.

### The starter prompt

> I'm starting a new technical tutorial site using the
> jekyll-tutorial-skeleton I've attached. The skeleton's README.md
> and LESSONS-LEARNED.md explain the conventions; please read them
> before generating any code.
>
> Project specifics:
> - **Project title:** [your title]
> - **One-line description:** [your description]
> - **Brand emoji:** [single emoji]
> - **GitHub username:** [your-github-handle]
> - **Repo name:** [your-repo-name]
> - **Topic:** [what is this tutorial teaching, and who is it for?]
> - **Estimated tutorial sections:** [rough number, e.g. 8-12]
> - **Will you have runnable examples?** [yes / no — and if yes, what
>   languages or tools?]
>
> Please:
>
> 1. Apply the configuration values above to `_config.yml`,
>    `LICENSE`, and any other project-specific places. Do not modify
>    the skeleton files unless that file needs project-specific
>    changes.
>
> 2. Replace the skeleton's README.md with one for my project.
>    Replace the stub `_docs/00-outline.md` with an outline that
>    matches the section count and topic. Leave `_docs/01-prerequisites.md`
>    as a stub I'll fill in.
>
> 3. Initialize `_plans/reconciliation-plan.md` with a project-
>    appropriate header (state-key conventions, not yet any
>    `verified` rows since nothing has been built).
>
> 4. Pause before writing any tutorial content. After I review the
>    scaffolding, I'll tell you what section to draft first.
>
> Please follow these rules from LESSONS-LEARNED.md throughout our
> work together:
>
> - When making claims about technical behavior, mark them
>   `unverified` in the reconciliation plan unless we have actually
>   tested them in this session
> - When suggesting commands, prefer single-line commands inline OR
>   commands inside a script in a tarball — multi-line for-loops in
>   chat-pasted commands break my zsh autocomplete
> - When delivering files, use a tarball via the present_files tool;
>   long inline pastes risk being mangled by the chat client
> - Default to Podman, not Docker, for any container examples
> - Use `127.0.0.1` not `localhost` in test scripts
> - Use the `-Z` flag (or `:Z` on volumes) for SELinux when on
>   Fedora-family hosts; note in the prose that this is a no-op on
>   non-SELinux platforms but harmless

This prompt is calibrated for the patterns that worked on the
Hummingbird build — feel free to edit it for your project's specifics.
The most important parts are the "pause before writing tutorial
content" instruction and the lessons-learned rules at the bottom.

---

## Common issues

**`bundle install` fails with native extension errors.** You need
build tools. Re-run the OS-specific install command from step 3
which includes the `-devel` and build-tools packages.

**Site builds locally but pages 404 in production.** Almost always a
`baseurl` mismatch. Check that `_config.yml`'s `baseurl` exactly
matches your repo name with a leading slash (e.g. `/my-tutorial`).

**Header emoji doesn't show in the browser.** Some emoji require
specific font support. Try a different one, or replace the emoji
with an inline SVG by editing `_includes/header.html`.

**GitHub Pages workflow runs but says "no Pages site found".** You
forgot step 6. Settings → Pages → Source: GitHub Actions.

**Examples directory shows up at /examples/ on the live site.**
Check that `_config.yml`'s `exclude:` block has `examples/` with the
**trailing slash**. Without it, Jekyll will silently include the
directory.

**Diagrams render at the wrong size in production but right
locally.** SVG sizing follows the `viewBox` attribute, not pixel
dimensions. Edit the SVG to use `viewBox="0 0 W H"` without `width`
or `height` attributes, and the CSS in `site.css` will scale it
responsively.
