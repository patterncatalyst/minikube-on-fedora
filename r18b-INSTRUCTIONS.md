# r18b — apply instructions

Single-file fix: sync script writes `layout: tutorial` (not the
non-existent `layout: docs`) and uses a middot separator instead
of pipes (which kramdown was parsing as a table inside the
blockquote).

## Apply

```bash
cd ~/Dev/minikube-on-fedora && tar -xzf ~/Downloads/minikube-on-fedora_r18b.tar.gz
```

Overwrites: `scripts/sync-example-pages.sh`
Adds: `_plans/reconciliation-plan-r18b-addition.md`,
      `r18b-INSTRUCTIONS.md` (this file)

## Regenerate the example pages

```bash
./scripts/sync-example-pages.sh
```

The script reports each title as it writes. Output should look
the same as r18a (titles preserved) — the change is invisible
in the script's stdout. What's different is *inside* each
generated page:

```bash
head -7 _example_pages/03-driver-check.md
```

Should show `layout: tutorial` (not `layout: docs`).

```bash
grep -A1 '^---' _example_pages/03-driver-check.md | head -10
```

The meta line should start with `**Source:**` and use `&middot;`
as separator — no `|` pipes (outside Liquid expressions).

## Merge reconciliation entry

```bash
$EDITOR _plans/reconciliation-plan-r18b-addition.md _plans/reconciliation-plan.md
# splice the r18b entry into Section D, then:
rm _plans/reconciliation-plan-r18b-addition.md
```

## Review and push

```bash
git status
git diff scripts/sync-example-pages.sh
git diff _example_pages/                # should show layout: docs → tutorial across the board
git add -A
git commit -m "fix(r18b): example pages use correct layout: tutorial + no pipes in meta line"
git push
sleep 5 && gh run watch
```

## Verify the deployed site

After CI passes, revisit
`https://patterncatalyst.github.io/minikube-on-fedora/examples/03-driver-check/`.

Expected:
- Site header with "☸️ Minikube Tutorial on Fedora" link
- Top nav row: Tutorial / Prerequisites / Plan / GitHub ↗
- Breadcrumbs: Home / Tutorial / §3 driver check (or similar)
- Section number "3" badge before the page title
- Title "§3 driver check"
- Meta paragraph with bold "Source:" link and middot-separated
  back-link to /docs/16-examples/
- Body content rendered with site prose styling
- Footer with the standard site links

If any of those are missing, paste the rendered page output and
we'll iterate. Most likely candidates if something's still off:

- A page with no front matter at all (raw README dump) → fix
  the source README to have proper Markdown structure
- Layout broken in a different way → likely needs a layout
  change, not a sync-script change
