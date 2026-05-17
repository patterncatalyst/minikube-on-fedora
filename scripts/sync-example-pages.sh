#!/usr/bin/env bash
#
# sync-example-pages.sh — regenerate Jekyll pages for each example from
# the README.md inside examples/NN-name/.
#
# For each examples/NN-name/ directory containing a README.md, generates
# _example_pages/NN-name.md with proper Jekyll front matter and the
# README body inlined.
#
# Title extraction:
#   1. Use the first H1 from the README, if present AND it's not just
#      the directory name (e.g. "# 03-driver-check" is too slug-like
#      to make a good page title).
#   2. Otherwise, derive a readable title from the slug:
#      "03-driver-check" → "§3 driver check"
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

# Normalize a string for comparison: lowercase, collapse whitespace,
# strip leading/trailing whitespace.
normalize() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //; s/ $//'
}

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

    # Build the readable-slug fallback title.
    # "06-deploy-nginx-kubectl" → slug "deploy-nginx-kubectl" → "deploy nginx kubectl"
    slug="${name#*-}"
    readable_slug="${slug//-/ }"
    fallback_title="§${order} ${readable_slug}"

    # Extract first H1 from README.
    h1_title=$(awk '
        /^#[[:space:]]/ {
            sub(/^#[[:space:]]+/, "")
            print
            exit
        }
    ' "$readme")

    # Decide which title to use.
    # If H1 is missing → fallback.
    # If H1 normalizes to the same string as the directory name or its
    # readable form → it's too slug-like to be a good title, use the
    # fallback.
    # Otherwise → use the H1 as-is.
    if [[ -z "$h1_title" ]]; then
        title="$fallback_title"
    else
        norm_h1=$(normalize "$h1_title")
        norm_dirname=$(normalize "$name")
        norm_readable=$(normalize "$readable_slug")
        if [[ "$norm_h1" == "$norm_dirname" || "$norm_h1" == "$norm_readable" ]]; then
            title="$fallback_title"
        else
            title="$h1_title"
        fi
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

    # Trim leading blank lines from body.
    body=$(printf '%s\n' "$body" | awk 'NF || started { started = 1; print }')

    output="_example_pages/${name}.md"
    {
        printf -- '---\n'
        printf 'title: %s\n' "$(printf '%s' "$title" | sed 's/"/\\"/g; s/^/"/; s/$/"/')"
        printf 'order: %d\n' "$order"
        printf 'example_dir: examples/%s\n' "$name"
        printf 'permalink: /examples/%s/\n' "$name"
        printf 'layout: tutorial\n'
        printf -- '---\n\n'
        # Meta line: NO pipes (kramdown's GFM mode parses them as table separators
        # inside blockquotes). Use a middot · separator instead.
        printf '**Source:** [`examples/%s/`](https://github.com/patterncatalyst/minikube-on-fedora/tree/main/examples/%s) &middot; [← Back to examples index]({{ "/docs/16-examples/" | relative_url }})\n\n' "$name" "$name"
        printf '%s\n' "$body"
    } > "$output"

    printf 'OK   %s → %s (title: %s)\n' "$readme" "$output" "$title"
    generated+=1
done

printf '\nGenerated %d page(s), skipped %d.\n' "$generated" "$skipped"
printf 'Next: review _example_pages/, then git add -A && git commit.\n'
