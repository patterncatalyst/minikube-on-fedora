# r18 — apply instructions

Single source of truth for everything you need to do after
extracting `minikube-on-fedora_r18.tar.gz`. Read this in full
before starting; the steps depend on each other.

## What you'll change

1. New files added (won't conflict with anything):
   - `scripts/sync-example-pages.sh`
   - `_docs/16-examples.md`
   - `onboarding/README.md`
   - `onboarding/LESSONS-LEARNED-r18-additions.md` (will be
     deleted in step 4 below after merging)
   - `_plans/PRD-r18-additions.md` (deleted in step 5)
   - `_plans/reconciliation-plan-r18-addition.md` (deleted in
     step 6)
   - `r18-INSTRUCTIONS.md` (this file — delete or keep as you
     prefer)

2. `README.md` is replaced with the rewritten version.
   `git diff README.md` shows what changed.

3. Manual edits to apply:
   - Move three files into `onboarding/` (step 1)
   - Edit `_config.yml` (step 2)
   - Merge three addenda (steps 3, 4, 5, 6 — well, three of them)
   - Update §15 footer (step 7)
   - Generate example pages (step 8)
   - Audit + push (steps 9–10)

---

## Step 1 — Move onboarding files

```bash
cd ~/Dev/minikube-on-fedora
mv LESSONS-LEARNED.md onboarding/
mv GETTING-STARTED.md onboarding/
mv STARTING-WITH-CLAUDE.md onboarding/
```

`git status` should show these as renames (git auto-detects
move-without-modification).

## Step 2 — Add the `example_pages` collection to `_config.yml`

Open `_config.yml` and add the following block to the
`collections:` section. If you don't have a `collections:`
section yet (only `defaults:`), add the whole block at the top
level:

```yaml
collections:
  docs:
    output: true
    permalink: /docs/:name/
  example_pages:
    output: true
    permalink: /examples/:name/
```

If you already have a `collections:` section with the `docs:`
entry, just add the `example_pages:` lines (keep your existing
`docs:` config — the snippet above shows both for completeness).

Also confirm the `exclude:` list still has `examples/` in it —
that's the source directory we read from, and it should remain
excluded from the published site:

```yaml
exclude:
  - examples/
  - vendor/
  - Gemfile
  - Gemfile.lock
  - r18-INSTRUCTIONS.md
```

(Add `r18-INSTRUCTIONS.md` to exclude or delete the file after
the apply — your call.)

## Step 3 — Merge the LESSONS-LEARNED addendum

Open `onboarding/LESSONS-LEARNED-r18-additions.md`. Review each
item against your existing `onboarding/LESSONS-LEARNED.md`.
Items already covered in your file: skip. Items not yet
covered: copy into your file in an appropriate section (the
addendum is already organized by section).

```bash
# After merging:
rm onboarding/LESSONS-LEARNED-r18-additions.md
```

## Step 4 — Merge the PRD additions

Open `_plans/PRD-r18-additions.md`. The file is a set of
"add to this PRD section" instructions. Open `PRD.md`
alongside and apply each section's additions.

```bash
# After merging:
rm _plans/PRD-r18-additions.md
```

## Step 5 — Splice the reconciliation-plan r18 entry

Open `_plans/reconciliation-plan-r18-addition.md` and follow
its merge instructions:

1. Append the **r18 entry** to Section D of
   `_plans/reconciliation-plan.md`, right after the r17 entry
2. Replace the existing **"Open priorities (after r17):"**
   section with the new **"Project state (post-r18): closed"**
   content

```bash
# After merging:
rm _plans/reconciliation-plan-r18-addition.md
```

## Step 6 — Update §15 footer to link forward to §16

Open `_docs/15-where-to-go-next.md`. Find the bottom of the
file — currently it should end with something like
`[← Back to outline]({{ "/" | relative_url }})`. Add a
forward link to §16:

```markdown
[On to §16: Examples →]({{ "/docs/16-examples/" | relative_url }})
[← Back to outline]({{ "/" | relative_url }})
```

(Keep the back-to-outline link; just add the forward link
above it.)

## Step 7 — Generate the example pages

```bash
./scripts/sync-example-pages.sh
```

This reads every `examples/*/README.md` and generates
`_example_pages/*.md`. It's idempotent — safe to re-run any
time. Review the generated pages:

```bash
ls _example_pages/
git diff _example_pages/  # should be all new files
```

If any example doesn't have a README.md, the script reports
SKIP for that directory; add a README if you want the example
published.

## Step 8 — Run the audit scripts

```bash
./scripts/check-cross-references.sh
./scripts/editorial-audit.sh
```

`check-cross-references.sh` should exit clean (0). Most
likely findings if any:
- The new §15→§16 link, if you forgot step 6
- The §16→§15 back-link
- Per-example links in the §16 hub

`editorial-audit.sh` is advisory and will probably still
show "we" voice findings — those are deliberate per the
PRD reconciliation document.

## Step 9 — Review, commit, push

```bash
git status                  # confirm all the moves and additions
git diff --stat             # confirm the scope
git add -A
git commit -m "feat(r18): examples-as-pages + onboarding folder + README rewrite + PRD/lessons close-out"
git push
sleep 5 && gh run watch
```

## Step 10 — Verify the deployed site

After CI passes, visit:

- `https://patterncatalyst.github.io/minikube-on-fedora/docs/16-examples/`
  — the new hub page; should list every example
- `https://patterncatalyst.github.io/minikube-on-fedora/examples/06-deploy-nginx-kubectl/`
  (or whichever) — should render the example README as a page

If either doesn't render or has navigation issues, that's
worth a follow-up iteration (r18a) for the specific fix.
Common issues at this stage:

- `_config.yml` collection block wrong (jekyll-build-pages logs
  show "unknown collection")
- Permalink wrong (page builds but URL is wrong)
- Layout reference broken (page builds but renders as plain
  markdown without site chrome)

All three are quick fixes once identified.

---

## After applying

Once everything's pushed and deployed:

- `r18-INSTRUCTIONS.md` (this file) can be deleted — the work
  is done and the reconciliation plan records what happened
- The three addendum files are already deleted per the
  individual steps above
- Project state is "closed" — future iterations are
  optional/discretionary

The verified-row count stays at **107**. Audit scripts stay
clean. Onboarding docs are now in `onboarding/`. Per-example
pages are published at `/examples/NN-name/`. The PRD reflects
the shipped reality.

Victory.
