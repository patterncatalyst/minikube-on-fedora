#!/usr/bin/env bash
#
# build-service.sh: build one of the capstone's shipping services with
# Docker Engine and load it into the mof-patterns minikube profile's
# containerd store.
#
# Modeled on examples/17-capstone/scripts/build-image.sh, parameterized to the
# appendix's own profile (mof-patterns, via scripts/lib/env.sh) instead of
# mof-capstone. `docker build -f Containerfile` + `minikube -p mof-patterns
# image load`. There is no registry: every example's Deployment uses the bare
# image name with imagePullPolicy: Never, so the kubelet only ever uses what
# was loaded here.
#
# The capstone's service source under examples/17-capstone/services/ is never
# modified; this script only builds and loads it.
#
# After loading, an existing Deployment of the same name in the `patterns`
# namespace is restarted (`kubectl rollout restart`) so its pods pick up the
# rebuilt :tag (with pullPolicy Never the pod keeps the old image until it
# restarts).
#
# Usage:
#   ./scripts/build-service.sh <service-name> [tag]
# Example:
#   ./scripts/build-service.sh shipping-service v1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

SERVICE="${1:?usage: build-service.sh <service-name> [tag]}"
TAG="${2:-v1}"

CONTEXT="$SCRIPT_DIR/../../17-capstone/services/$SERVICE"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$CONTEXT" ]] || fail "service $SERVICE not found under examples/17-capstone/services/"
[[ -f "$CONTEXT/Containerfile" ]] || fail "$CONTEXT/Containerfile not found"
command -v minikube >/dev/null || fail "minikube not in PATH"

require_docker_engine

# ─── Build and load ──────────────────────────────────────────────────────────
step "Building ${SERVICE}:${TAG} with Docker Engine and loading it into ${PROFILE}"
build_and_load "${SERVICE}:${TAG}" "$CONTEXT" "$PROFILE" \
    || fail "build or image load failed for ${SERVICE}:${TAG}"

step "Verifying ${SERVICE}:${TAG} is in the node"
if minikube -p "$PROFILE" image ls 2>/dev/null | grep -qE "(^|/)${SERVICE}:${TAG}\$"; then
    printf '    ok: %s:%s present in %s\n' "$SERVICE" "$TAG" "$PROFILE"
else
    fail "${SERVICE}:${TAG} not found in 'minikube -p ${PROFILE} image ls' after load"
fi

# ─── Restart the Deployment so pods use the new image ────────────────────────
if kubectl get deployment "$SERVICE" -n "$NS" >/dev/null 2>&1; then
    step "Restarting deployment/${SERVICE} to pick up the new image"
    kubectl rollout restart "deployment/${SERVICE}" -n "$NS"
fi

printf '\n'
printf '==> Done. Deployments reference: %s:%s (pullPolicy: Never) in namespace %s\n' "$SERVICE" "$TAG" "$NS"
