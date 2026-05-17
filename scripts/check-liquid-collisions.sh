#!/usr/bin/env bash
#
# scripts/check-liquid-collisions.sh
#
# Static check for Jekyll Liquid vs Go-template collisions.
#
# Two failure modes we've actually hit:
#   1. Go template syntax (e.g. {{ .Values.foo }} from helm charts)
#      inside _docs/*.md code blocks without {% raw %} wrappers.
#      Jekyll's Liquid parser tries to evaluate them and either
#      warns loudly (best case) or crashes the build (worst case
#      — `replace` filter arity mismatch).
#   2. Any {{ }} content in _plans/*.md files that don't have
#      `render_with_liquid: false` in front matter. The plan
#      files describe templating in prose; Liquid eats it.
#
# This check runs in seconds with just bash + awk. No Ruby, no
# Bundler, no Jekyll. Run before `git push` if you want to catch
# issues before CI; or rely on CI if you're feeling lucky.
#
# Returns 0 if clean, 1 if any collisions found.
#
# Usage:
#   ./scripts/check-liquid-collisions.sh         # run from anywhere in the repo
#   bash scripts/check-liquid-collisions.sh

set -euo pipefail

# Find repo root (handles being run from any subdir)
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "${REPO_ROOT}"

FAIL=0

# ── Color helpers (no-op if not a TTY) ──────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

# ────────────────────────────────────────────────────────────────────────────
# Check 1: _docs/*.md — Go template syntax outside {% raw %} wrappers
# ────────────────────────────────────────────────────────────────────────────
#
# Strategy: scan each file line by line tracking whether we're inside a
# `{% raw %}` ... `{% endraw %}` block. When NOT inside raw, flag any line
# that looks like Go template syntax.
#
# We use a deliberately conservative pattern that catches the most common
# Go template signatures without false-positiving on legitimate Liquid:
#   - {{ .UpperCase }}     (Go variable access — Liquid is conventionally lowercase)
#   - {{ printf  }}        (Go-only function — Liquid has no printf)
#   - {{ define / range / with }} (Go-only control flow)
#   - {{/* ... */}}        (Go template comment syntax)
#   - {{ include "..." . }} (Go's include uses dot at end; Liquid's include is a tag)
#
# Liquid syntax we deliberately don't flag:
#   - {{ "/path" | relative_url }}  (string literal + filter — common in nav links)
#   - {{ site.title }} or {{ page.url }}  (lowercase property access)

echo "─── Checking _docs/*.md for Go template collisions outside {% raw %} ───"

if compgen -G "_docs/*.md" >/dev/null; then
    DOCS_COLLISIONS=$(awk '
        BEGIN { in_raw = 0 }
        /\{%[[:space:]]*raw[[:space:]]*%\}/  { in_raw = 1 }
        /\{%[[:space:]]*endraw[[:space:]]*%\}/ { in_raw = 0; next }
        in_raw == 0 {
            # Pattern 1: {{ .UpperCase ... }} (Go variable access)
            if (match($0, /\{\{[^}]*\.[A-Z][A-Za-z_.]*/)) {
                printf "%s:%d: Go-template variable outside {%% raw %%}: %s\n", FILENAME, NR, $0
                seen = 1
            }
            # Pattern 2: {{ printf ... }} or {{ define / range / with / include }}
            else if (match($0, /\{\{[^}]*(printf|define|range|with|include)[[:space:]]/)) {
                printf "%s:%d: Go-template control/function outside {%% raw %%}: %s\n", FILENAME, NR, $0
                seen = 1
            }
            # Pattern 3: {{/* ... */}} Go template comment
            else if (match($0, /\{\{\//)) {
                printf "%s:%d: Go-template comment outside {%% raw %%}: %s\n", FILENAME, NR, $0
                seen = 1
            }
        }
        END { exit (seen ? 1 : 0) }
    ' _docs/*.md 2>&1 || true)

    if [[ -n "${DOCS_COLLISIONS}" ]]; then
        echo -e "${RED}✗${NC} found collisions in _docs/:"
        echo "${DOCS_COLLISIONS}" | sed 's/^/    /'
        FAIL=1
    else
        echo -e "${GREEN}✓${NC} _docs/ clean"
    fi
else
    echo -e "${YELLOW}!${NC} no _docs/*.md files found (run from repo root?)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Check 2: _plans/*.md — any {{ }} content requires render_with_liquid: false
# ────────────────────────────────────────────────────────────────────────────
#
# Plan files describe project state in prose, including occasional references
# to templating syntax. Rather than wrap every {{ }} in raw tags inside table
# cells (ugly + can break tables), disable Liquid for the file wholesale via
# `render_with_liquid: false` in front matter.

echo
echo "─── Checking _plans/*.md for unguarded {{ }} content ───"

if compgen -G "_plans/*.md" >/dev/null; then
    PLANS_FAIL=0
    for f in _plans/*.md; do
        # Skip if file has no {{ }} content at all
        if ! grep -qE '\{\{[^}]*\}\}' "$f"; then
            continue
        fi
        # File has {{ }} — must have render_with_liquid: false in front matter
        # (front matter is the first --- block at top of file)
        FRONT_MATTER=$(awk '
            /^---$/ { count++; if (count == 2) exit; next }
            count == 1 { print }
        ' "$f")
        if ! echo "${FRONT_MATTER}" | grep -q 'render_with_liquid:[[:space:]]*false'; then
            echo -e "    ${RED}✗${NC} $f: has {{ }} content but missing 'render_with_liquid: false' in front matter"
            PLANS_FAIL=1
            FAIL=1
        fi
    done
    if [[ $PLANS_FAIL -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} _plans/ clean"
    fi
else
    echo -e "${YELLOW}!${NC} no _plans/*.md files found"
fi

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────

echo
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ no Liquid collisions found — safe to push${NC}"
    exit 0
else
    echo -e "${RED}✗ Liquid collisions detected — fix before push${NC}"
    echo
    echo "Conventions:"
    echo "  _docs/*.md   : wrap each code block containing {{ }} Go templates"
    echo "                 with {% raw %} ... {% endraw %} tags"
    echo "  _plans/*.md  : add 'render_with_liquid: false' to front matter"
    echo "                 when describing templates in prose"
    echo
    echo "See CONTRIBUTING.md → 'Site authoring conventions' for details."
    exit 1
fi
