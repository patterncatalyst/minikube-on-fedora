#!/usr/bin/env bash
#
# editorial-audit.sh — surface common editorial issues across _docs/*.md.
# All checks are advisory (warnings, not errors). Run output ends with a
# summary count of findings per category.
#
# Run from the repo root: ./scripts/editorial-audit.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

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

# 3. "minikube VM" — with the podman driver it's actually a container, not a VM
hdr "minikube VM references (should be 'minikube node container' under podman driver)"
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
done | tee /tmp/dup-flags.out
if [[ -s /tmp/dup-flags.out ]]; then
    counts[dup-flags]=$(wc -l < /tmp/dup-flags.out)
else
    printf '  (none)\n'
fi
rm -f /tmp/dup-flags.out

# Summary
hdr "Summary"
total=0
for k in "${!counts[@]}"; do
    n="${counts[$k]}"
    printf '  %-20s %d\n' "$k" "$n"
    total=$((total + n))
done
if (( total == 0 )); then
    printf '  No issues found. Editorial pass clean.\n'
else
    printf '\nTotal findings: %d (advisory — not all are bugs)\n' "$total"
fi
