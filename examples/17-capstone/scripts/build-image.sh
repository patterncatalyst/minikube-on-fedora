#!/usr/bin/env bash
#
# build-image.sh — build a service image and load it into the capstone
# minikube profile's containerd image store.
#
# WHY THIS EXISTS: under the rootless-podman driver with the containerd
# runtime, `minikube image build` does not reliably place the built image
# where the containerd-backed kubelet looks for it. The build appears to
# succeed, but the image isn't in the profile's store, so pods land in
# ErrImagePull (the kubelet falls back to docker.io/library/<name>, which
# 404s). The robust pattern is: build on the host with podman, then
# explicitly `minikube image load` into the profile.
#
# Usage:
#   ./scripts/build-image.sh <context-dir> <image:tag>
# Example:
#   ./scripts/build-image.sh services/order-service order-service:v1

set -euo pipefail

PROFILE="capstone"
CONTEXT="${1:?usage: build-image.sh <context-dir> <image:tag>}"
IMAGE="${2:?usage: build-image.sh <context-dir> <image:tag>}"

step() { printf '\n==> %s\n' "$1"; }

[[ -d "$CONTEXT" ]] || { printf 'ERROR: context dir %s not found\n' "$CONTEXT" >&2; exit 1; }
[[ -f "$CONTEXT/Containerfile" ]] || { printf 'ERROR: %s/Containerfile not found\n' "$CONTEXT" >&2; exit 1; }

command -v podman >/dev/null   || { printf 'ERROR: podman not in PATH\n' >&2; exit 1; }
command -v minikube >/dev/null || { printf 'ERROR: minikube not in PATH\n' >&2; exit 1; }

step "Building $IMAGE on the host with podman"
podman build -t "$IMAGE" "$CONTEXT"

step "Loading $IMAGE into the $PROFILE profile (containerd store)"
minikube image load "$IMAGE" -p "$PROFILE"

step "Confirming $IMAGE is present in the profile"
if minikube image ls -p "$PROFILE" | grep -q "${IMAGE%%:*}"; then
    printf '    ✓ %s is in the %s image store\n' "$IMAGE" "$PROFILE"
else
    printf 'ERROR: %s did NOT land in the %s store after load\n' "$IMAGE" "$PROFILE" >&2
    printf 'Try: minikube image ls -p %s   to inspect what is there\n' "$PROFILE" >&2
    exit 1
fi
