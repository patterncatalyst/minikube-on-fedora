#!/usr/bin/env bash
#
# build-image.sh — build a service image and push it to the capstone
# minikube profile's in-cluster registry.
#
# WHY THE REGISTRY (CAP-007, revised in r21c): under the rootless-podman
# driver with the containerd runtime, neither `minikube image build` nor
# `minikube image load` reliably places an image where the kubelet can pull
# it. We hit this hard in r21/r21a/r21b: builds succeeded but images never
# landed in the profile's containerd store, leaving pods in ErrImagePull.
# The robust, scalable answer is minikube's built-in registry addon: build
# on the host with podman, push to the registry, and have deployments pull
# from it like any normal image.
#
# THE PORT ASYMMETRY (CAP-009) — the single most important detail:
#   - From the HOST (podman push):   127.0.0.1:<host-port>   (e.g. 41685)
#   - From INSIDE the cluster (pull): localhost:5000
# Same registry, two addresses. The host port is assigned by minikube for
# the podman driver (NOT 5000); we discover it dynamically below. The chart's
# image.repository uses the in-cluster address (localhost:5000/<name>).
#
# Requires MINIKUBE_ROOTLESS=true (CAP-010) — exported here defensively so
# the script works even in a shell that forgot to set it.
#
# Usage:
#   ./scripts/build-image.sh <context-dir> <image-name> [tag]
# Example:
#   ./scripts/build-image.sh services/order-service order-service v1

set -euo pipefail
export MINIKUBE_ROOTLESS=true

PROFILE="capstone"
CONTEXT="${1:?usage: build-image.sh <context-dir> <image-name> [tag]}"
NAME="${2:?usage: build-image.sh <context-dir> <image-name> [tag]}"
TAG="${3:-v1}"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d "$CONTEXT" ]] || fail "context dir $CONTEXT not found"
[[ -f "$CONTEXT/Containerfile" ]] || fail "$CONTEXT/Containerfile not found"
command -v podman >/dev/null   || fail "podman not in PATH"
command -v minikube >/dev/null || fail "minikube not in PATH"

# ─── Discover the host-side registry port ────────────────────────────────────
# minikube maps the registry's :5000 to a host port (e.g. 127.0.0.1:41685).
# Read it from the profile container's port mappings rather than hardcoding.
step "Discovering the host registry port"
HOST_PORT=$(podman port "$PROFILE" 2>/dev/null | awk -F'[:]' '/5000\/tcp/ {print $NF; exit}')
[[ -n "$HOST_PORT" ]] || fail "could not find the host port mapped to registry :5000 — is the registry addon enabled? (minikube addons enable registry -p $PROFILE)"
HOST_REG="127.0.0.1:${HOST_PORT}"
printf '    host registry: %s  (cluster pulls from localhost:5000)\n' "$HOST_REG"

# ─── Build, tag, push ────────────────────────────────────────────────────────
step "Building ${NAME}:${TAG} on the host with podman"
podman build -t "${NAME}:${TAG}" "$CONTEXT"

step "Tagging for the host registry"
podman tag "${NAME}:${TAG}" "${HOST_REG}/${NAME}:${TAG}"

step "Pushing to ${HOST_REG} (plain HTTP registry; --tls-verify=false)"
podman push --tls-verify=false "${HOST_REG}/${NAME}:${TAG}"

step "Verifying ${NAME} is in the registry catalog"
if curl -fsS "http://${HOST_REG}/v2/_catalog" | grep -q "\"${NAME}\""; then
    printf '    ✓ %s present in registry\n' "$NAME"
else
    fail "${NAME} not found in registry catalog after push"
fi

printf '\n'
printf '==> Done. Deployments should reference: localhost:5000/%s:%s\n' "$NAME" "$TAG"
