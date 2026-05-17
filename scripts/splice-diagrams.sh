#!/usr/bin/env bash
#
# splice-diagrams.sh — adds SVG embed references to the relevant section
# markdown files. Idempotent: safe to re-run; already-referenced diagrams
# are skipped.
#
# Insertion logic: for each target, find the closing `---` of the front
# matter, then find the first `## ` heading after that, then insert the
# embed in the blank space immediately before that heading. Result: the
# diagram appears after the section's opening prose and before its first
# sub-section.
#
# Usage:
#     ./scripts/splice-diagrams.sh
#     # then:
#     git diff       # review the splices
#     git add -A && git commit -m 'docs(diagrams): embed SVGs into §3, §6, §11, §12'

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Reduce noise by printing only paths once per splice.
splice() {
    local file_glob="$1"
    local diagram="$2"
    local alt_text="$3"
    local anchor_regex="${4:-^## }"

    # Resolve the glob to one file (most specific match)
    local file
    file=$(ls -1 ${file_glob} 2>/dev/null | head -1) || true
    if [[ -z "${file:-}" || ! -f "$file" ]]; then
        printf 'WARN: no file matches %s — skipping\n' "$file_glob" >&2
        return 0
    fi

    if grep -qF "$diagram" "$file"; then
        printf 'SKIP: %s already references %s\n' "$file" "$diagram"
        return 0
    fi

    # Find front matter close (second --- line). 0 if no front matter.
    local fm_close
    fm_close=$(awk '/^---[[:space:]]*$/ {n++; if (n==2) {print NR; exit}}' "$file")
    fm_close=${fm_close:-0}

    # Find first line matching anchor_regex AFTER front matter.
    local anchor_line
    anchor_line=$(awk -v start="$fm_close" -v pat="$anchor_regex" '
        NR > start && $0 ~ pat { print NR; exit }
    ' "$file")

    # Fallback: if no anchor matches, append at EOF with a trailing blank line.
    local append_at_eof=0
    if [[ -z "${anchor_line:-}" ]]; then
        append_at_eof=1
        anchor_line=$(wc -l < "$file")
    fi

    local embed="![${alt_text}]({{ \"/assets/diagrams/${diagram}\" | relative_url }})"

    # awk-based in-place edit (mv-tempfile pattern for portability)
    local tmp="${file}.splice.tmp"
    if (( append_at_eof )); then
        awk -v embed="$embed" '
            { print }
            END { print ""; print embed }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
        printf 'SPLICED: %s ← %s (appended at EOF, no anchor matched)\n' "$file" "$diagram"
    else
        # Insert embed and one blank line BEFORE anchor_line.
        awk -v line="$anchor_line" -v embed="$embed" '
            NR == line { print embed; print ""; }
            { print }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
        printf 'SPLICED: %s ← %s (before line %d: %s)\n' \
            "$file" "$diagram" "$anchor_line" \
            "$(sed -n "${anchor_line}p" "$file" | head -c 60)"
    fi
}

printf '=== Splicing diagram embeds ===\n'

splice "_docs/03-*.md" \
    "03-minikube-topology.svg" \
    "minikube on Fedora 44 topology"

splice "_docs/06-*.md" \
    "06-k8s-primitives.svg" \
    "Kubernetes workload primitives"

splice "_docs/11-*.md" \
    "11-istio-mesh.svg" \
    "Istio service mesh — control plane and data plane"

# §12 has two diagrams. The HPA-vs-KEDA goes near the top (before first ## heading).
splice "_docs/12-*.md" \
    "12-hpa-vs-keda.svg" \
    "HPA vs KEDA scaling models"

# The HTTP add-on goes before the first heading that mentions HTTP.
# If no such heading exists, falls back to EOF append (user can move).
splice "_docs/12-*.md" \
    "12-keda-http-addon.svg" \
    "KEDA HTTP add-on data flow" \
    "^## .*[Hh][Tt][Tt][Pp]"

printf '\nDone. Review with: git diff\n'
printf 'If a diagram landed in the wrong place, just move the embed line — it'\''s plain Markdown.\n'
