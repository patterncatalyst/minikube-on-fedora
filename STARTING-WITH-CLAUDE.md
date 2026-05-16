# Starting a new project with Claude

This document is the practical playbook for using this skeleton as
the starting point for a new tutorial project, with Claude as your
collaborator. The PRD template (`PRD.md`) and the skeleton's
templated files together give Claude enough context to be useful
quickly.

The pattern below was refined over a long collaborative build — it
front-loads the work that has the highest payoff and defers what
can wait.

---

## The four-stage plan

### Stage 1 — Set up locally (you, ~5 minutes)

Before opening Claude, get the skeleton into a fresh project on
disk:

```bash
# Spawn a new repo from the skeleton template on GitHub, or:
gh repo create my-new-tutorial --template patterncatalyst/skeleton-tutorial --public --clone
cd my-new-tutorial

# Or if you already have the tarball:
tar -xzf jekyll-tutorial-skeleton.tar.gz
mv jekyll-tutorial-skeleton my-new-tutorial
cd my-new-tutorial
rm -rf .git
git init && git branch -M main
```

Don't edit anything yet. Don't fill in the PRD yet. Just have the
skeleton on disk so you have something to reference when talking
to Claude.

### Stage 2 — Open Claude and do the kickoff (you + Claude, ~30 min)

Open a fresh Claude conversation. Attach (drag-and-drop or upload
button):

- The skeleton tarball **OR** a representative subset of files —
  at minimum `README.md`, `LESSONS-LEARNED.md`, `GETTING-STARTED.md`,
  `PRD.md`, and `_config.yml`
- Any source materials you have for the new project (a paper,
  reference docs, your own notes, screenshots)

Then paste the kickoff prompt from the bottom of this file.

Claude will read the lessons-learned doc, understand the
conventions, and begin a Q&A to fill in the PRD. **Resist the
urge to start writing tutorial content here.** The whole point
of this stage is producing a complete, decided PRD before
any prose gets written.

The PRD work usually takes 20-30 minutes of conversation. By the
end, every `TODO` in `PRD.md` should be replaced with a real
answer, and `_config.yml` should have your project's branding
filled in.

### Stage 3 — Configure the skeleton (Claude, with your review, ~15 min)

Once the PRD is complete, ask Claude to do the mechanical
configuration work using the PRD as the source of truth:

> Now using the PRD we just wrote, please:
> 1. Update `_config.yml` with the title, description, github_username, github_repo, and brand_emoji
> 2. Replace `README.md` with one specific to this project, keeping the directory tour and conventions
> 3. Replace `_docs/00-outline.md` with an outline matching our PRD's section list
> 4. Initialize `_plans/reconciliation-plan.md` with the conventions header and an empty G.2 testing matrix
> 5. Update `LICENSE` with my name and current year if I'm using Apache 2.0
> 6. Pause before writing any tutorial content beyond the outline

Claude will produce these as a tarball. Extract, review, commit.
At this point you have a buildable, branded site with no actual
content yet — and that's the right state to be in.

### Stage 4 — Iterative content writing (you + Claude, hours-to-weeks)

Now write tutorial content one section at a time. The pattern
that worked on the Hummingbird build:

1. Pick a section. Tell Claude which one. Reference the PRD.
2. Claude drafts the section based on source materials and PRD
3. You review for accuracy and tone
4. If the section involves runnable code, **build the code first**, test it, fix it, then write the prose to match
5. Update the reconciliation plan: claims default to `unverified`,
   they get promoted to `verified` only when a real test confirms them
6. Commit, push, watch the deploy succeed
7. Repeat for the next section

The key discipline: **tested code first, then prose**. Writing
prose first encourages Claude to make plausible-but-untested
claims, which compound into a tutorial that looks correct but
doesn't actually work.

---

## What to attach to a new Claude conversation

In rough order of importance:

1. **The skeleton itself** (tarball or key files). This gives Claude
   the project structure, the conventions, and the lessons-learned
   doc which contains all the hard-won wisdom.

2. **PRD.md** with the project's specifics filled in. This is the
   single biggest force multiplier — Claude with a complete PRD
   produces dramatically better content than Claude without one.

3. **Source materials** for whatever you're documenting. Official
   docs, your own notes, papers, slides, transcripts of meetings.
   The more grounded Claude is in real source material, the less
   it makes up.

4. **Examples from similar tutorials** if you want to match a style
   or tone. ("Write this in the tone of the Quarkus guides" tells
   Claude something concrete about voice.)

You can attach everything at once or share progressively. For long
projects, attach the PRD + skeleton at the start, then attach
source materials as you reach the sections that need them.

---

## When to start a new Claude conversation

Long conversations drift, eat context, and start to feel sluggish.
Start a fresh conversation when:

- You're moving from "scaffolding" to "writing first section" — the
  work changes shape, a fresh context helps
- You've written 3-5 sections and are starting a new major area
- You hit a natural break (finishing all of part 1, before
  starting part 2)
- The conversation has visibly slowed down or you're getting more
  recap-y responses

When you start a fresh conversation, the kickoff prompt looks
slightly different — see "Resuming a project in a new
conversation" below.

---

## The kickoff prompt for a NEW project

Copy this, fill in the bracketed values, paste as your first
message in a fresh Claude conversation.

> I'm starting a new technical tutorial site using the skeleton
> I've attached. The skeleton's README.md, GETTING-STARTED.md,
> and especially LESSONS-LEARNED.md explain the conventions I
> want to follow. Please read them before generating any code or
> prose.
>
> Project specifics so far:
>
> - **Working title:** [your title — can change later]
> - **Topic:** [what is this tutorial teaching, in 1-2 sentences]
> - **Audience:** [who is this for — be specific]
> - **My background:** [your experience level with the topic, so
>   Claude can calibrate its explanations]
> - **Source material I have:** [list, or "none yet"]
> - **Estimated section count:** [rough number]
> - **Will there be runnable code examples?** [yes / no / maybe]
> - **Target platforms:** [Fedora 43 / macOS / Windows-via-WSL /
>   etc.]
> - **Deadline pressure:** [hard deadline / soft target / no
>   deadline]
>
> Please:
>
> 1. Read the skeleton's documentation, especially LESSONS-LEARNED.md
> 2. Open `PRD.md` and walk me through filling it in section by
>    section. Ask me one question at a time. Don't move to the
>    next section until I've answered the current one. Don't
>    start writing tutorial content yet.
> 3. When the PRD is complete, summarize back to me what we
>    decided so I can confirm before we start configuring the
>    skeleton.
>
> Also follow these rules from LESSONS-LEARNED.md throughout our
> work together:
>
> - When making technical claims, default to `unverified` in the
>   reconciliation plan unless we've actually tested in this
>   session
> - When suggesting commands for me to run, prefer single-line
>   inline commands OR scripts in tarballs — multi-line for-loops
>   in chat-pasted commands break my zsh autocomplete
> - When delivering files, use a tarball via the present_files
>   tool; long inline pastes risk being mangled by the chat client
> - Default to Podman not Docker for any container examples
> - Use `127.0.0.1` not `localhost` in test scripts
> - Remind me to `git add` and commit changes after each
>   meaningful unit of work — not at the end of the session

---

## The kickoff prompt for RESUMING a project in a new Claude conversation

When you start a fresh conversation mid-project, you need to
re-establish context. Copy this, fill in the bracketed values:

> I'm continuing work on a tutorial project. Please read the
> attached files in this order:
>
> 1. `LESSONS-LEARNED.md` — the conventions I want to follow
> 2. `PRD.md` — what we're building and why
> 3. `_plans/reconciliation-plan.md` — current state of what's
>    verified vs. unverified
> 4. The current state of `_docs/` — what's been written so far
>
> Project status:
>
> - **Sections drafted:** [list, e.g. "00-outline, 01-prerequisites, 02-introduction"]
> - **Sections tested end-to-end:** [list]
> - **Currently working on:** [what you stopped on]
> - **Next planned section:** [what's next]
> - **Open questions or stuck points:** [anything unresolved]
>
> Please summarize back to me:
>
> 1. Your understanding of what this tutorial is about
> 2. What's been done and what's pending, based on the
>    reconciliation plan
> 3. The next reasonable piece of work
>
> Don't start writing yet — let me confirm your summary first so
> we have shared context.

This pattern catches drift early. If Claude's summary is off in
some important way, you fix it before any work happens.

---

## Anti-patterns to avoid

These all came up during the Hummingbird build and cost real time:

**Skipping the PRD.** Writing tutorial sections without a clear
PRD means every section is its own decision point, and every
session re-litigates audience and scope. The PRD is upfront cost
that pays back many times over.

**Writing prose before testing the code.** The single most common
source of bugs in the Hummingbird tutorial. Prose first encourages
plausible-sounding fiction; code first forces honesty.

**Auto-promoting unverified claims.** When Claude offers a
"verified ✅" status without you having actually run the test,
push back. Claude should mark it `unverified` until a human runs
the verification. This is non-negotiable for the reconciliation
plan to be meaningful.

**Ignoring vendor-neutral language warnings.** Phrases like "we
don't compare to Docker, Chainguard, Kubernetes" age poorly —
why those three? Why not others? Generic phrasing is more honest
and ages better. Lessons-learned doc covers this.

**Not committing per section.** Long sessions accumulate changes;
forgetting to commit means a single bad merge or lost laptop
costs a day of work. Commit per meaningful unit (per section,
per fix, per cleanup).

**Trusting AI-generated diagrams without checking.** The
Hummingbird build hit this twice — diagrams that looked plausible
in chat but had alignment issues, overlapping text, or
floating disconnected elements when actually rendered. Always
visually verify diagrams in the deployed site, hard-refresh
the browser cache after any update.

---

## TL;DR for the next project

1. Spawn from template: `gh repo create my-new-tutorial --template patterncatalyst/skeleton-tutorial --public --clone`
2. Open Claude, attach the skeleton + your source materials
3. Paste the kickoff prompt from this file with your project's specifics
4. Fill in the PRD first, configure the skeleton second, write content third
5. Test code before writing prose
6. Default new claims to `unverified` in the reconciliation plan
7. Commit per section, push, verify the deploy
