#!/usr/bin/env bash
#
# sync-example-pages.sh — regenerate Jekyll pages for each example from
# the README.md inside examples/NN-name/.
#
# For each examples/NN-name/ directory containing a README.md, generates
# _example_pages/NN-name.md with proper Jekyll front matter and the
# README body inlined. The first H1 line of the README becomes the page
# title (the H1 itself is stripped from the body since the layout will
# render the title from front matter).
#
# Idempotent — safe to re-run anytime example READMEs change. The
# generated _example_pages/*.md files should be committed to git so
# they're available to GitHub Pages builds.
#
# Run from the repo root: ./scripts/sync-example-pages.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ ! -d examples ]]; then
    printf 'examples/ directory not found — nothing to sync\n' >&2
    exit 1
fi

mkdir -p _example_pages

declare -i generated=0
declare -i skipped=0

for example_dir in examples/*/; do
    [[ -d "$example_dir" ]] || continue
    name=$(basename "$example_dir")
    readme="${example_dir}README.md"

    if [[ ! -f "$readme" ]]; then
        printf 'SKIP %s (no README.md)\n' "$name" >&2
        skipped+=1
        continue
    fi

    # Extract NN prefix for ordering. "06-deploy-nginx-kubectl" → 6
    nn="${name%%-*}"
    if [[ ! "$nn" =~ ^[0-9]+$ ]]; then
        printf 'SKIP %s (directory name does not start with NN-)\n' "$name" >&2
        skipped+=1
        continue
    fi
    order=$((10#$nn))

    # Extract first H1 as title. If none, fall back to a derived title.
    title=$(awk '
        /^#[[:space:]]/ {
            sub(/^#[[:space:]]+/, "")
            print
            exit
        }
    ' "$readme")
    if [[ -z "$title" ]]; then
        # Derive a title from the slug: "06-deploy-nginx-kubectl" → "Example §6: deploy nginx kubectl"
        slug="${name#*-}"
        readable_slug="${slug//-/ }"
        title="Example §${order}: ${readable_slug}"
    fi

    # Extract body — everything after the first H1 (if there was one), else everything.
    body=$(awk '
        BEGIN { skipping_h1 = 0; first_h1_done = 0 }
        /^#[[:space:]]/ && first_h1_done == 0 {
            first_h1_done = 1
            next
        }
        { print }
    ' "$readme")

    # Trim leading blank lines from body
    body=$(printf '%s\n' "$body" | awk 'NF || started { started = 1; print }')

    output="_example_pages/${name}.md"
    {
        printf -- '---\n'
        printf 'title: %s\n' "$(printf '%s' "$title" | sed 's/"/\\"/g; s/^/"/; s/$/"/')"
        printf 'order: %d\n' "$order"
        printf 'example_dir: examples/%s\n' "$name"
        printf 'permalink: /examples/%s/\n' "$name"
        printf 'layout: docs\n'
        printf -- '---\n\n'
        printf '> Source: [`examples/%s/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/%s)\n' "$name" "$name"
        printf '> &nbsp;&nbsp;|&nbsp;&nbsp; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})\n\n'
        printf '%s\n' "$body"
    } > "$output"

    printf 'OK   %s → %s\n' "$readme" "$output"
    generated+=1
done

printf '\nGenerated %d page(s), skipped %d.\n' "$generated" "$skipped"
printf 'Next: review _example_pages/, then git add -A && git commit.\n'
