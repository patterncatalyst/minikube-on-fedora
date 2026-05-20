#!/usr/bin/env bash
# apply-r21.sh — guided apply for the r21 capstone walking skeleton.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

RUN_CLUSTER_TESTS=0
[[ "${1:-}" == "--with-cluster-tests" ]] && RUN_CLUSTER_TESTS=1

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
pause() { printf '   (press Enter when done, or Ctrl-C to abort) '; read -r _; }

step "Pre-flight"
[[ -f examples/17-capstone/demos/smoke-order.sh ]] || { echo "r21 tarball not extracted here"; exit 1; }
git status --short

step "Static checks — shell syntax"
for s in examples/17-capstone/scripts/*.sh examples/17-capstone/demos/*.sh; do
  bash -n "$s" && echo "  ok  $s"
done

step "Static checks — Python compiles"
python3 -m py_compile examples/17-capstone/services/order-service/app/*.py \
  examples/17-capstone/services/order-service/tests/*.py && echo "  ok  python"

step "Static checks — YAML parses (non-template only)"
for y in $(find examples/17-capstone -name '*.yaml' ! -path '*/templates/*'); do
  python3 -c "import yaml,sys; list(yaml.safe_load_all(open('$y')))" && echo "  ok  $y"
done

step "Helm lint (if helm present)"
command -v helm >/dev/null && helm lint examples/17-capstone/charts/capstone/charts/order-service \
  examples/17-capstone/charts/capstone/charts/postgres || echo "  (helm not found; skipping)"

step "MANUAL MERGE 1 — §17 prose"
echo "  Insert _docs/17-capstone-r21-prose-insert.md into _docs/17-capstone.md"
echo "  (before '## What §17 delivers vs what's coming'), then delete the insert file."
[[ -f _docs/17-capstone-r21-prose-insert.md ]] && pause

step "MANUAL MERGE 2 — reconciliation entry"
echo "  Append _plans/reconciliation-plan-r21-addition.md to Section D, then delete it."
[[ -f _plans/reconciliation-plan-r21-addition.md ]] && pause

step "Poetry lock + local unit tests"
if command -v poetry >/dev/null; then
  ( cd examples/17-capstone/services/order-service && poetry lock && poetry install && poetry run pytest -q )
else
  echo "  (poetry not found; skipping — install with: pipx install poetry)"
fi

if (( RUN_CLUSTER_TESTS )); then
  step "Cluster tests — running test-r21.sh"
  ./test-r21.sh
else
  step "Skipping cluster tests"
  echo "  Re-run with: ./apply-r21.sh --with-cluster-tests"
  echo "  Or run them standalone anytime: ./test-r21.sh"
fi

step "Commit + push + watch"
git add -A
git commit -m "feat(r21): capstone walking skeleton — order-service + CloudNativePG + decision log"
git push
sleep 5 && gh run watch
