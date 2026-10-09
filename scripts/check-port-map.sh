#!/usr/bin/env bash
#
# check-port-map.sh — cross-check the published-NodePort maps against the
# YAML and the docs.
#
# Maps (single source of truth):
#   CORE_PORTS, ISTIO_PORTS, DRIVER_CHECK_PORTS  scripts/lib/_helpers.sh
#   CAPSTONE_PORTS                               examples/17-capstone/scripts/lib/env.sh
#                                                (skipped with a note if absent)
#
# Checks:
#   1. each map is well formed, has no duplicate host ports or nodePorts,
#      and every nodePort is in 30000-32767
#   2. every `nodePort: NNNNN` in tracked YAML under examples/ appears in
#      some map's nodePort set
#   3. every `--ports=` string in _docs/*.md and examples/**/README.md equals
#      a map, is a subset of one map's entries, or is a reference to a map
#      variable such as "$CORE_PORTS"
#
# Read-only. Exit 1 on any mismatch.
#
# Run from anywhere: ./scripts/check-port-map.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ERRORS=0
err() { printf '  MISMATCH: %s\n' "$*" >&2; ERRORS=$((ERRORS + 1)); }
hdr() { printf '\n=== %s ===\n' "$1"; }

declare -A MAPS=()      # name -> comma-separated entries
declare -A NODEPORTS=() # nodePort -> map names

# Read NAME="value" from a file without sourcing it.
read_map() {
    local name="$1" file="$2"
    sed -n -E "s/^[[:space:]]*(export )?${name}=\"([^\"]*)\".*/\2/p" "$file" | head -1
}

hdr "Loading maps"
for name in CORE_PORTS ISTIO_PORTS DRIVER_CHECK_PORTS; do
    v=$(read_map "$name" scripts/lib/_helpers.sh)
    if [[ -z "$v" ]]; then
        err "$name not found in scripts/lib/_helpers.sh"
    else
        MAPS[$name]="$v"
    fi
done
ENV_SH=examples/17-capstone/scripts/lib/env.sh
if [[ -f "$ENV_SH" ]]; then
    v=$(read_map CAPSTONE_PORTS "$ENV_SH")
    if [[ -z "$v" ]]; then
        err "CAPSTONE_PORTS not found (as a single-line quoted string) in $ENV_SH"
    else
        MAPS[CAPSTONE_PORTS]="$v"
    fi
else
    echo "  note: $ENV_SH does not exist yet; CAPSTONE_PORTS skipped"
fi
for name in "${!MAPS[@]}"; do
    printf '  %-20s %s entries\n' "$name" "$(tr ',' '\n' <<<"${MAPS[$name]}" | wc -l)"
done

# ── 1. Map integrity ────────────────────────────────────────────────────────
hdr "Map integrity (duplicates, range, format)"
for name in "${!MAPS[@]}"; do
    declare -A seen_host=() seen_node=()
    IFS=',' read -ra entries <<<"${MAPS[$name]}"
    for e in "${entries[@]}"; do
        if [[ ! "$e" =~ ^127\.0\.0\.1:([0-9]+):([0-9]+)$ ]]; then
            err "$name: malformed entry '$e' (want 127.0.0.1:<host>:<nodePort>)"
            continue
        fi
        h="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
        [[ -n "${seen_host[$h]:-}" ]] && err "$name: duplicate host port $h"
        [[ -n "${seen_node[$n]:-}" ]] && err "$name: duplicate nodePort $n"
        seen_host[$h]=1; seen_node[$n]=1
        if (( n < 30000 || n > 32767 )); then
            err "$name: nodePort $n outside 30000-32767"
        fi
        NODEPORTS[$n]="${NODEPORTS[$n]:-} $name"
    done
    unset seen_host seen_node
done
(( ERRORS == 0 )) && echo "  ok"

# ── 2. nodePort values in YAML ──────────────────────────────────────────────
hdr "nodePort values in tracked YAML under examples/"
checked=0
while IFS=: read -r file line value; do
    checked=$((checked + 1))
    if [[ -z "${NODEPORTS[$value]:-}" ]]; then
        err "$file:$line: nodePort $value is not in any map"
    fi
done < <(git ls-files 'examples/*.yaml' 'examples/*.yml' 'examples/*.tpl' \
    | xargs -r grep -nHE '^[[:space:]]*-?[[:space:]]*nodePort:[[:space:]]*"?[0-9]+' \
    | sed -E 's/^([^:]+):([0-9]+):.*nodePort:[[:space:]]*"?([0-9]+).*/\1:\2:\3/')
echo "  $checked nodePort declaration(s) checked"

# ── 3. --ports= strings in docs ─────────────────────────────────────────────
hdr "--ports= strings in _docs/*.md and examples/**/README.md"
in_map_subset() {  # in_map_subset "e1,e2,..." -> 0 if subset of a single map
    local want="$1" name ok e
    for name in "${!MAPS[@]}"; do
        ok=1
        IFS=',' read -ra es <<<"$want"
        for e in "${es[@]}"; do
            [[ ",${MAPS[$name]}," == *",$e,"* ]] || { ok=0; break; }
        done
        (( ok )) && return 0
    done
    return 1
}
checked=0
while IFS= read -r hit; do
    file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; text="${rest#*:}"
    # one --ports= per match; a line may hold several
    while IFS= read -r tok; do
        [[ -n "$tok" ]] || continue
        checked=$((checked + 1))
        tok="${tok#\"}"; tok="${tok%\"}"
        if [[ "$tok" =~ ^\$\{?([A-Z_]+)\}?$ ]]; then
            if [[ -z "${MAPS[${BASH_REMATCH[1]}]:-}" ]]; then
                var="${BASH_REMATCH[1]}"
                case "$var" in
                    CAPSTONE_PORTS) [[ -f "$ENV_SH" ]] || continue ;;
                esac
                err "$file:$line: --ports=\$$var references an unknown map"
            fi
        elif ! in_map_subset "$tok"; then
            err "$file:$line: --ports=$tok matches no map and is not a subset of one"
        fi
    done < <(grep -oE -e '--ports=[^[:space:]\\`'"'"')]+' <<<"$text" | sed 's/^--ports=//')
done < <(
    { git ls-files '_docs/*.md'; git ls-files 'examples/*README.md'; } \
        | xargs -r grep -nH -e '--ports=' || true
)
echo "  $checked --ports= string(s) checked"

# ── Summary ─────────────────────────────────────────────────────────────────
hdr "Summary"
if (( ERRORS > 0 )); then
    printf '  %d mismatch(es)\n' "$ERRORS"
    exit 1
fi
echo "  Port maps, YAML nodePorts and docs agree."
