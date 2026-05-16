#!/usr/bin/env bash
# TEMPLATE — copy to scripts/test-<example-name>.sh and edit.
#
# Tests a single runnable example end-to-end:
#   1. builds the container image
#   2. runs it on a host port
#   3. waits for HTTP readiness
#   4. validates the response
#   5. tears down the container (even on failure, via trap)
#
# Returns 0 on success, non-zero on any failure.

set -euo pipefail
source "$(dirname "$0")/lib/_helpers.sh"

# TODO: replace these four values for each new test
EXAMPLE="EXAMPLE_NAME"          # directory name under examples/
IMAGE="test-EXAMPLE_NAME"       # podman image tag (local, no registry)
CONTAINER="test-EXAMPLE_NAME-run"  # running container name
HOST_PORT=18080                 # host-side port (use 1808x range to avoid collisions)
CONTAINER_PORT=8080             # port the app inside the container listens on
EXPECTED_PATTERN='"status":"ok"'  # what the response body should contain

cd "$(repo_root)/examples/$EXAMPLE"
trap "cleanup_container $CONTAINER" EXIT

step "Building $EXAMPLE"
podman build -t "$IMAGE" . >/dev/null || fail "$EXAMPLE: build failed"
pass "$EXAMPLE built"

step "Running $EXAMPLE on :$HOST_PORT"
cleanup_container "$CONTAINER"
podman run -d --name "$CONTAINER" -p "$HOST_PORT:$CONTAINER_PORT" "$IMAGE" >/dev/null

step "Waiting for HTTP response"
if ! wait_for_http "http://127.0.0.1:$HOST_PORT/" 30; then
    info "Container logs:"
    podman logs "$CONTAINER" 2>&1 | tail -20 | sed 's/^/  /'
    fail "$EXAMPLE: never started responding on :$HOST_PORT"
fi

RESP=$(curl -fsS "http://127.0.0.1:$HOST_PORT/")
case "$RESP" in
    *"$EXPECTED_PATTERN"*) pass "$EXAMPLE responds: $RESP" ;;
    *) fail "$EXAMPLE: unexpected response: $RESP" ;;
esac
