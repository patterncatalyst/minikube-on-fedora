# scripts/

Developer-facing scripts. Two patterns live here:

## Per-example test scripts

Each runnable example under `examples/` should have a corresponding
`test-<name>.sh` that builds it, runs it, and validates it responds.

Use `test-template.sh` as a starting point — copy to a new name,
edit the four TODO values at the top, done.

The shared helper at `lib/_helpers.sh` provides:

- Color output (`step`, `pass`, `fail`, `info`)
- `repo_root` — finds the repo root regardless of CWD
- `cleanup_container <name>` — idempotent container removal
- `wait_for_http <url> [timeout]` — polls until 200 or timeout

Conventions for new test scripts:

- Use `set -euo pipefail` at the top
- Source `lib/_helpers.sh`
- Use `127.0.0.1` not `localhost`
- Use a distinct port in the 1808x range to avoid collisions
- Use `trap` to tear down the container even on failure
- Exit 0 on success, non-zero on failure (so the aggregator works)

## Aggregator: test-all-examples.sh

A single script that runs every per-example test and reports a
final summary. Should be added once you have at least two
per-example tests.

Recommended pattern (not included in skeleton — write once you
know your test names):

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/_helpers.sh"

TESTS=(
    test-example-a.sh
    test-example-b.sh
)

declare -a PASSED FAILED
for t in "${TESTS[@]}"; do
    if bash "$(dirname "$0")/$t"; then
        PASSED+=("$t")
    else
        FAILED+=("$t")
    fi
done

# ... print summary ...
```

The aggregator should NOT fail-fast — let every test run, then
report. This is more useful after a refactor when you want to see
all problems at once.

## Other developer scripts

This directory is also a fine place for non-test developer
scripts (e.g., a "build and push to registry" script for an
artifact pipeline). Add them here, document them in this README.
