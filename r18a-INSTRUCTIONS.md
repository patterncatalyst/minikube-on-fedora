# r18a — apply instructions

Two-file fix for §16 hub rendering + example page titles.

## Apply

```bash
cd ~/Dev/minikube-on-fedora && tar -xzf ~/Downloads/minikube-on-fedora_r18a.tar.gz
```

The tarball overwrites:
- `_docs/16-examples.md` (Markdown structure instead of HTML)
- `scripts/sync-example-pages.sh` (smarter title extraction)

And adds:
- `_plans/reconciliation-plan-r18a-addition.md` (splice into the
  main reconciliation plan; details below)

## Regenerate the example pages with the new titles

```bash
./scripts/sync-example-pages.sh
```

The script reports each page's title as it writes it. Watch for
titles that previously looked like `03-driver-check` and now look
like `§3 driver check`. Any descriptive H1s in your READMEs are
preserved as-is.

## Merge the reconciliation entry

Open `_plans/reconciliation-plan-r18a-addition.md` and append its
single r18a entry to Section D of
`_plans/reconciliation-plan.md`, right after the r18 entry. Then:

```bash
rm _plans/reconciliation-plan-r18a-addition.md
```

## Review and push

```bash
git status
git diff _docs/16-examples.md scripts/sync-example-pages.sh
git diff _example_pages/                # see the regenerated titles
git add -A
git commit -m "fix(r18a): §16 hub Markdown rendering + sync-script title fallback"
git push
sleep 5 && gh run watch
```

## Verify the deployed site

After CI passes, visit:

- `https://patterncatalyst.github.io/minikube-on-fedora/docs/16-examples/`

Each example should now appear as a proper H3 section with:

> ### §3 driver check
>
> **Read the walkthrough →**
>
> Source: `examples/03-driver-check/`

If anything still looks unformatted, paste me the rendered text
and we'll iterate (r18b). Otherwise: actually-actual victory.
