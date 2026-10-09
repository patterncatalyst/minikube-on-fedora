#!/usr/bin/env bash
#
# editorial-audit.sh — surface common editorial issues across _docs/*.md.
# Checks 1-7 are advisory (warnings, not errors). Check 8 (runtime / access /
# OS policy) and the version-pin check are advisory by default and fail the
# run under --strict. Output ends with a summary count of findings per
# category.
#
# Run from the repo root:
#   ./scripts/editorial-audit.sh            # advisory, exit 0
#   ./scripts/editorial-audit.sh --strict   # exit 1 on any policy / pin finding
#
# Policy exemptions (check 8 and the pin check):
#   - Markdown: lines between <!-- policy-exempt:start --> and
#     <!-- policy-exempt:end -->, or a line ending in <!-- policy-exempt -->
#   - Shell / YAML / any file: a line ending in "# policy-exempt"

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

STRICT=0
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg (usage: $0 [--strict])" >&2; exit 2 ;;
    esac
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ANSI-light formatting (only used to make sections scannable in terminal)
hdr() { printf '\n=== %s ===\n' "$1"; }

declare -A counts=()

# 1. Stale §13 "Wrap-up" references (§13 was renamed to "Alternatives to minikube" in r14a)
hdr "Stale §13 Wrap-up references"
if grep -rn -E '13-wrap-up|Wrap-up' _docs/ 2>/dev/null; then
    counts[wrap-up]=$(grep -rn -E '13-wrap-up|Wrap-up' _docs/ 2>/dev/null | wc -l)
else
    printf '  (none)\n'
fi

# 2. Bare <placeholder> patterns inside inline backticks (kramdown HTML-collision)
# Looks for: backtick, then any non-backtick chars including <word>, then closing backtick
hdr "Bare <placeholder> inside inline backticks (kramdown collision risk)"
matches=$(grep -nE '`[^`]*<[a-z][a-z-]+>[^`]*`' _docs/*.md 2>/dev/null || true)
# Filter out fenced code blocks by inspecting context
if [[ -n "$matches" ]]; then
    # Simple heuristic: check if line falls inside ``` ... ``` block
    while IFS= read -r match; do
        file="${match%%:*}"
        rest="${match#*:}"
        line="${rest%%:*}"
        # Count ``` fences before this line; even = outside, odd = inside
        fence_count=$(awk -v target="$line" 'NR < target && /^[[:space:]]*```/ {c++} END {print c+0}' "$file")
        if (( fence_count % 2 == 0 )); then
            printf '%s\n' "$match"
            counts[angle-brackets]=$((${counts[angle-brackets]:-0} + 1))
        fi
    done <<< "$matches"
    [[ -z "${counts[angle-brackets]:-}" ]] && printf '  (all matches were inside fenced code blocks — safe)\n'
else
    printf '  (none)\n'
fi

# 3. "minikube VM" — with the docker driver the node is a container, not a VM
hdr "minikube VM references (should be 'minikube node')"
if grep -rn 'minikube VM' _docs/ 2>/dev/null; then
    counts[minikube-vm]=$(grep -rn 'minikube VM' _docs/ 2>/dev/null | wc -l)
else
    printf '  (none)\n'
fi

# 4. "we" / "we'll" / "we're" voice — PRD says use 'you' for reader, passive/third-person otherwise
hdr "First-person plural ('we', 'we'll', 'we're') — PRD says avoid"
matches=$(grep -nE "\bwe('ll|'ve|'re| ([a-z]+ ){0,3}(use|did|chose|need|run|skip|deploy|build|install|go|want|set|add|put|leave|cover|see|saw|got|have))?\b" _docs/*.md 2>/dev/null || true)
if [[ -n "$matches" ]]; then
    # Filter fenced code blocks same way
    while IFS= read -r match; do
        file="${match%%:*}"
        rest="${match#*:}"
        line="${rest%%:*}"
        fence_count=$(awk -v target="$line" 'NR < target && /^[[:space:]]*```/ {c++} END {print c+0}' "$file")
        if (( fence_count % 2 == 0 )); then
            printf '%s\n' "$match"
            counts[we-voice]=$((${counts[we-voice]:-0} + 1))
        fi
    done <<< "$matches"
    [[ -z "${counts[we-voice]:-}" ]] && printf '  (all matches were inside fenced code blocks)\n'
else
    printf '  (none)\n'
fi

# 5. {% raw %}{{ ... | relative_url }}{% endraw %} — broken URL pattern
# The {% raw %} prevents Liquid from evaluating the relative_url filter, leaving the
# literal {{ ... }} string as the image src. The image will not load.
hdr "{% raw %}-wrapped relative_url URLs (renders broken image src)"
if grep -rnE '\{% raw %\}\{\{[^}]*relative_url[^}]*\}\}\{% endraw %\}' _docs/ 2>/dev/null; then
    counts[raw-url]=$(grep -rnE '\{% raw %\}\{\{[^}]*relative_url[^}]*\}\}\{% endraw %\}' _docs/ 2>/dev/null | wc -l)
else
    printf '  (none)\n'
fi

# 6. Stale TODO/FIXME/XXX markers in body content
hdr "Stale TODO / FIXME / XXX markers"
matches=$(grep -rnE '\b(TODO|FIXME|XXX)\b' _docs/ scripts/ examples/*/README.md examples/*/demo.sh 2>/dev/null || true)
if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches"
    counts[todos]=$(printf '%s' "$matches" | wc -l)
else
    printf '  (none)\n'
fi

# 7. Duplicate flags in shell command examples (e.g. --container-runtime=containerd twice)
hdr "Duplicate flags in single command (continuation-aware)"
# Process each fenced bash block, group lines into commands by handling \ continuations,
# then check each command independently for repeated flags. Avoids the false positive
# where two separate commands in one block both use --foo.
for f in _docs/*.md; do
    [[ -f "$f" ]] || continue
    awk '
        /^[[:space:]]*```bash/ { in_block = 1; cmd = ""; cmd_start = NR; next }
        /^[[:space:]]*```/     { in_block = 0; next }
        !in_block { next }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line ~ /\\$/) {
                # Continuation: strip trailing \, accumulate
                sub(/\\$/, "", line)
                cmd = cmd " " line
                next
            }
            # End of command
            cmd = cmd " " line
            # Skip blank or comment-only commands
            if (cmd !~ /[^[:space:]#]/) { cmd = ""; cmd_start = NR + 1; next }
            # Find --flag tokens in this command and count duplicates
            delete flag_count
            tmp = cmd
            while (match(tmp, /--[a-z][a-z-]*(=[^[:space:]]*)?/)) {
                flag = substr(tmp, RSTART, RLENGTH)
                flag_count[flag]++
                tmp = substr(tmp, RSTART + RLENGTH)
            }
            for (flag in flag_count) {
                if (flag_count[flag] > 1) {
                    printf "%s:%d: duplicate flag %s (×%d) in single command\n",
                        FILENAME, cmd_start, flag, flag_count[flag]
                }
            }
            cmd = ""
            cmd_start = NR + 1
        }
    ' "$f"
done | tee "$WORK/dup-flags.out"
if [[ -s "$WORK/dup-flags.out" ]]; then
    counts[dup-flags]=$(wc -l < "$WORK/dup-flags.out")
else
    printf '  (none)\n'
fi

# 8. Runtime / access / OS policy, plus version pins.
# Scope: every tracked text file except presentation/, _plans/, lockfiles,
# screenshots, this script, and .github/workflows/pages.yml (its
# `runs-on: ubuntu-latest` is CI infrastructure, not tutorial content).
hdr "Runtime / access / OS policy (check 8)"
git ls-files -z \
    | grep -zvE '^(presentation/|_plans/|assets/screenshots/)|\.lock$|^\.github/workflows/pages\.yml$|^scripts/editorial-audit\.sh$' \
    | while IFS= read -r -d '' f; do
        [[ -f "$f" ]] && grep -Iq . "$f" 2>/dev/null && printf '%s\n' "$f"
    done > "$WORK/files.txt" || true

# Build text.txt (line text) and meta.txt (file:line), skipping exempt lines.
: > "$WORK/text.txt"; : > "$WORK/meta.txt"
while IFS= read -r f; do
    awk -v F="$f" -v T="$WORK/text.txt" -v M="$WORK/meta.txt" '
        /<!-- policy-exempt:start -->/ { skip = 1 }
        {
            exempt = skip \
                  || $0 ~ /#[[:space:]]*policy-exempt[[:space:]]*$/ \
                  || $0 ~ /<!-- policy-exempt -->[[:space:]]*$/
            if (!exempt) { print $0 >> T; printf "%s:%d\n", F, FNR >> M }
        }
        /<!-- policy-exempt:end -->/ { skip = 0 }
    ' "$f"
done < "$WORK/files.txt"
paste -d'\t' "$WORK/meta.txt" "$WORK/text.txt" > "$WORK/all.tsv" 2>/dev/null || true
printf '  scanned %d files, %d non-exempt lines\n' "$(wc -l < "$WORK/files.txt")" "$(wc -l < "$WORK/text.txt")"

# scan_pattern LABEL REGEX KIND   (KIND is "policy" or "pin")
scan_pattern() {
    local label="$1" re="$2" kind="$3" idx n
    idx=$(grep -niE -e "$re" "$WORK/text.txt" 2>/dev/null | cut -d: -f1 || true)
    [[ -z "$idx" ]] && return 0
    printf '%s\n' "$idx" > "$WORK/idx.txt"
    n=$(wc -l < "$WORK/idx.txt")
    counts["$kind:$label"]=$n
    printf '\n  [%s] %s (%d)\n' "$kind" "$label" "$n"
    awk -F'\t' 'NR==FNR { want[$1] = 1; next } (FNR in want) { t = $2; for (i = 3; i <= NF; i++) t = t "\t" $i
                  gsub(/^[[:space:]]+/, "", t); printf "    %s: %s\n", $1, substr(t, 1, 140) }' \
        "$WORK/idx.txt" "$WORK/all.tsv"
}

POLICY_PATTERNS=(
    'port-forward'
    'minikube tunnel'
    'minikube service'
    'kubectl proxy'
    'istioctl dashboard'
    'minikube dashboard'
    'ssh -L'
    '--driver=podman'
    'driver podman'
    '--rootless'
    'rootless true'
    'MINIKUBE_ROOTLESS'
    'podman (build|run|push|port|volume|tag|info|image)'
    'slirp4netns'
    'podman-compose'
    'Podman Desktop'
    '\bcrun\b'
    'cri-o'
    'macOS'
    'Windows'
    'WSL'
    'Ubuntu'
    'Debian'
    'Homebrew'
    'brew install'
    'Colima'
    'Rancher Desktop'
    'Apple Silicon'
    '\bLima\b'
    'Docker Desktop'
    'Hyper-V'
    'VirtualBox'
    'apt(-get)? install'
)
for pat in "${POLICY_PATTERNS[@]}"; do
    scan_pattern "$pat" "$pat" policy
done
(( ${#counts[@]} == 0 )) && printf '  (none)\n'

hdr "Unpinned versions (check 8b)"
before=${#counts[@]}
for pat in ':latest\b' 'releases/latest' '@latest' 'stable\.txt'; do
    scan_pattern "$pat" "$pat" pin
done
[[ ${#counts[@]} -eq $before ]] && printf '  (none)\n'

# Summary
hdr "Summary"
total=0
policy_total=0
for k in "${!counts[@]}"; do
    n="${counts[$k]}"
    total=$((total + n))
    case "$k" in policy:*|pin:*) policy_total=$((policy_total + n)) ;; esac
done
while IFS= read -r k; do
    printf '  %-48s %d\n' "$k" "${counts[$k]}"
done < <(printf '%s\n' "${!counts[@]}" | sort)
if (( total == 0 )); then
    printf '  No issues found. Editorial pass clean.\n'
else
    printf '\nTotal findings: %d (advisory — not all are bugs)\n' "$total"
    printf 'Policy + pin findings: %d\n' "$policy_total"
fi
if (( STRICT == 1 && policy_total > 0 )); then
    printf 'FAIL (--strict): %d policy/pin finding(s)\n' "$policy_total" >&2
    exit 1
fi
