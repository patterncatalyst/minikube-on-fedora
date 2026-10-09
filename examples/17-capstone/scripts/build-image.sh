#!/usr/bin/env bash
#
# build-image.sh — build a service image with Docker Engine and load it into the
# mof-capstone minikube profile's containerd store.
#
# `docker build -f Containerfile` + `minikube -p mof-capstone image load`. There
# is no registry: the chart's image.repository is the bare image name and the
# Deployments use imagePullPolicy: Never, so the kubelet only ever uses what was
# loaded. Loaded images live in the node's containerd store and survive
# `minikube stop/start`; cluster-up.sh re-loads any that are missing.
#
# After loading, an existing Deployment is restarted (`kubectl rollout restart`)
# so its pods pick up the rebuilt :tag (with pullPolicy Never the pod keeps the
# old image until it restarts).
#
# Usage:
#   ./scripts/build-image.sh <context-dir> <image-name> [tag]
# Example:
#   ./scripts/build-image.sh services/order-service order-service v1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

CONTEXT="${1:?usage: build-image.sh <context-dir> <image-name> [tag]}"
NAME="${2:?usage: build-image.sh <context-dir> <image-name> [tag]}"
TAG="${3:-v1}"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$CONTEXT" ]] || fail "context dir $CONTEXT not found"
[[ -f "$CONTEXT/Containerfile" ]] || fail "$CONTEXT/Containerfile not found"
command -v minikube >/dev/null || fail "minikube not in PATH"

require_docker_engine

# ─── Build and load ──────────────────────────────────────────────────────────
step "Building ${NAME}:${TAG} with Docker Engine and loading it into ${PROFILE}"
build_and_load "${NAME}:${TAG}" "$CONTEXT" "$PROFILE" \
    || fail "build or image load failed for ${NAME}:${TAG}"

step "Verifying ${NAME}:${TAG} is in the node"
if minikube -p "$PROFILE" image ls 2>/dev/null | grep -qE "(^|/)${NAME}:${TAG}\$"; then
    printf '    ✓ %s:%s present in %s\n' "$NAME" "$TAG" "$PROFILE"
else
    fail "${NAME}:${TAG} not found in 'minikube -p ${PROFILE} image ls' after load"
fi

# ─── Restart the Deployment so pods use the new image ────────────────────────
if kubectl get deployment "$NAME" -n "$NS" >/dev/null 2>&1; then
    step "Restarting deployment/${NAME} to pick up the new image"
    kubectl rollout restart "deployment/${NAME}" -n "$NS"
fi

printf '\n'
printf '==> Done. Deployments reference: %s:%s (pullPolicy: Never)\n' "$NAME" "$TAG"
