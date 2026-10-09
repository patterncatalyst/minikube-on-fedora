# scripts/

Developer-facing scripts. Three patterns live here.

## Per-example test scripts

Each runnable example under `examples/` should have a corresponding
`test-<name>.sh` that builds it, runs it, and validates it responds.

Use `test-template.sh` as a starting point — copy to a new name,
edit the TODO values at the top, done. The template builds and runs
with Docker Engine (`docker build`, `docker run`) and publishes its
port on loopback only: `-p 127.0.0.1:$HOST_PORT:$CONTAINER_PORT`.

The shared helper at `lib/_helpers.sh` provides:

- Color output (`step`, `pass`, `fail`, `info`)
- `repo_root` — finds the repo root regardless of CWD
- `cleanup_container <name>` — idempotent `docker rm -f`
- `wait_for_http <url> [timeout]` — polls until 200 or timeout
- `require_docker_engine` — fails with the exact fix unless the Docker
  Engine is reachable on `unix:///var/run/docker.sock` with the
  `default` context, `DOCKER_HOST` unset, and `podman-docker` absent
- `KUBE_VERSION`, `CORE_PORTS`, `ISTIO_PORTS`, `DRIVER_CHECK_PORTS` —
  the pinned Kubernetes version and the published-NodePort maps
  (`127.0.0.1:<host>:<nodePort>`)
- `ensure_profile <name> <ports> <cpus> <mem_mb>` — creates a profile
  with `--driver=docker --container-runtime=containerd` and
  `--ports=…` (after checking the host ports are free), starts a
  stopped one, and verifies every mapping on an existing one
- `require_published_port <profile> <nodePort> <hostPort>` — fails
  with the delete-and-recreate command when `docker port` does not
  show the mapping; it prints the command and never runs it
- `build_and_load <image> <context-dir> <profile>` — `docker build -f
  <dir>/Containerfile`, then `minikube -p <profile> image load`
- `pin_context <ctx>` — shadows `kubectl`, `helm`, `istioctl` with
  functions that always pass `--context` / `--kube-context`
- `require_free_nodeport <nodePort>` — fails with "delete <ns>/<name>
  first" when another Service holds the nodePort

Conventions for new test scripts:

- Use `set -euo pipefail` at the top
- Source `lib/_helpers.sh`
- Use `127.0.0.1` not `localhost`
- Call `require_docker_engine` before touching Docker
- Use a distinct port in the 1808x range to avoid collisions
  (published as `127.0.0.1:<host>:<container>`)
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

## Audit scripts

`audit-fedora-prereqs.sh` captures the Fedora 44 environment
state this tutorial assumes — hardware, Docker Engine (`docker-ce`
packages, daemon state, context, socket, `docker` group), minikube
profiles, currently-installed tools, what's available in `dnf`
repos, and kernel inotify limits. It warns when `moby-engine` or
`podman-docker` is installed, when the docker context is not
`default`, or when `minikube config` carries a `driver` or `rootless`
key. It modifies nothing, reports instead of failing when Docker is
stopped, and is safe to re-run.

Used before writing a new section to set version pins from real
data rather than guesses, and useful long-term as a "is my
environment still aligned with the tutorial?" check:

```bash
./scripts/audit-fedora-prereqs.sh > /tmp/audit.txt
cat /tmp/audit.txt
```

The output is paste-friendly into iteration discussions where
version pins in the reconciliation plan need resolving.

`editorial-audit.sh` runs eight editorial checks over the docs and
tracked files. Checks 1-7 are advisory. Check 8 covers runtime,
access and OS policy (no tunnels or forwarded ports, no podman
driver or rootless flags, Fedora/RHEL only) plus a version-pin check
for unpinned `latest` references and `stable.txt` lookups. It prints <!-- policy-exempt -->
`file:line` for every finding.

```bash
./scripts/editorial-audit.sh            # advisory, always exits 0
./scripts/editorial-audit.sh --strict   # exits 1 on any policy or pin finding
```

`--strict` runs in CI before the Jekyll build. To keep a deliberate
mention (for example a lesson about why a runtime was dropped),
wrap it in `<!-- policy-exempt:start -->` … `<!-- policy-exempt:end -->`
in Markdown, or end the line with `# policy-exempt` (shell, YAML) or
`<!-- policy-exempt -->` (Markdown).

`check-port-map.sh` cross-checks the published-NodePort maps
(`CORE_PORTS`, `ISTIO_PORTS`, `DRIVER_CHECK_PORTS` in
`lib/_helpers.sh`; `CAPSTONE_PORTS` in
`examples/17-capstone/scripts/lib/env.sh` once it exists). It fails
on duplicate host ports or nodePorts, nodePorts outside 30000-32767,
any `nodePort:` in tracked `examples/` YAML that is in no map, and any
`--ports=` string in `_docs/*.md` or `examples/**/README.md` that is
not a map, a subset of one, or a map variable reference. Read-only.

## Setup scripts

`setup-keda.sh`, `setup-strimzi.sh` and `setup-istio.sh` pin their
Kubernetes context: `KUBE_CONTEXT` (default `minikube`; `istio` for
`setup-istio.sh`) is passed as `--kube-context` to `helm` and
`--context` to `kubectl` and `istioctl`, so the current-context can
never redirect an install.

## Other developer scripts

This directory is also a fine place for non-test developer
scripts (e.g., a "build and push to registry" script for an
artifact pipeline). Add them here, document them in this README.
