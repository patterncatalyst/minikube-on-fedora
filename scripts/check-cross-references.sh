#!/usr/bin/env bash
#
# check-cross-references.sh — verify all internal links resolve to real files.
#
# Two kinds of internal links checked:
#   - /docs/SLUG/  → must correspond to a _docs/NN-SLUG.md file
#   - /assets/PATH → must exist on disk under assets/
#   - /            → always valid (homepage / outline)
#
# External URLs (http://, https://) and anchor-only links (#fragment) are
# not checked.
#
# Catches: stale "On to §N: Old-Title →" links, dead asset references,
# orphaned cross-references after section renames.
#
# Idempotent. Exit 1 if any broken links found, 0 if all clean.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

declare -i broken=0
declare -i checked=0

# Build the set of valid /docs/SLUG/ targets from _docs/NN-slug.md files.
# Slug is the full filename minus .md extension (matching Jekyll's default
# permalink behavior, which produces /docs/12-keda/ from _docs/12-keda.md).
declare -A valid_doc_slugs
for f in _docs/*.md; do
    [[ -f "$f" ]] || continue
    slug=$(basename "$f" .md)
    valid_doc_slugs["/docs/${slug}/"]=1
done
valid_doc_slugs["/"]=1   # homepage is always valid

printf '=== Cross-reference link audit ===\n'
printf 'Known doc targets: %s\n' "$(printf '%s\n' "${!valid_doc_slugs[@]}" | sort | tr '\n' ' ')"
printf '\n'

# Find every Jekyll-style relative_url link in _docs/*.md.
while IFS= read -r match; do
    file="${match%%:*}"
    rest="${match#*:}"
    linenum="${rest%%:*}"
    content="${rest#*:}"

    # Extract every "/..." path inside `{{ "..." | relative_url }}` on this line.
    while read -r path; do
        [[ -z "$path" ]] && continue
        checked+=1

        case "$path" in
            /docs/*/)
                # Validate against _docs/
                if [[ -z "${valid_doc_slugs[$path]:-}" ]]; then
                    printf 'BROKEN docs: %s:%s — %s\n' "$file" "$linenum" "$path" >&2
                    printf '             line: %s\n' "$(printf '%s' "$content" | sed 's/^[[:space:]]*//' | cut -c 1-100)" >&2
                    broken+=1
                fi
                ;;
            /assets/*)
                # Validate against assets/ directory on disk
                local_path=".${path}"
                if [[ ! -e "$local_path" ]]; then
                    printf 'BROKEN asset: %s:%s — %s\n' "$file" "$linenum" "$path" >&2
                    printf '              line: %s\n' "$(printf '%s' "$content" | sed 's/^[[:space:]]*//' | cut -c 1-100)" >&2
                    broken+=1
                fi
                ;;
            /)
                # Homepage — always valid
                :
                ;;
            *)
                # Unrecognized internal link type — warn but don't fail
                printf 'UNKNOWN: %s:%s — %s (skipped)\n' "$file" "$linenum" "$path"
                ;;
        esac
    done < <(printf '%s' "$content" | grep -oE '"(/[^"]*)" \| relative_url' | sed -E 's/^"//; s/" \| relative_url$//')
done < <(grep -nE '\]\(\{\{\s*"[^"]+"\s*\|\s*relative_url\s*\}\}\)' _docs/*.md || true)

printf '\n'
printf 'Checked: %d link(s)\n' "$checked"
if (( broken > 0 )); then
    printf 'BROKEN: %d\n' "$broken" >&2
    exit 1
fi
printf 'All clean.\n'
