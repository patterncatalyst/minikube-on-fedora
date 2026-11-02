#!/usr/bin/env bash
# setup-patterns-profile.sh: create (or replace) the mof-patterns minikube
# profile that the Kubernetes-patterns appendix examples run on.
#
# This profile is separate from §3's `minikube` profile and the capstone's
# `mof-capstone`. It is sized for the heaviest appendix needs (Istio + KEDA +
# metrics-server running together), lighter than the full capstone mesh.
#
# Some chapters need extras that must be set at creation time:
#   - NetworkSegmentation needs the Calico CNI. Recreate with --calico for it:
#       ./setup-patterns-profile.sh --replace --calico
#
# Usage:
#   ./setup-patterns-profile.sh              # start (or do nothing if running)
#   ./setup-patterns-profile.sh --replace    # delete mof-patterns first, then start fresh
#   ./setup-patterns-profile.sh --replace --calico   # fresh, with Calico CNI
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib/env.sh"

MEMORY="12g"
CPUS="6"
# No ports published by default; pattern examples use `kubectl port-forward`.
PORTS=""

REPLACE=0
CNI=""
for arg in "$@"; do
    case "$arg" in
        --replace) REPLACE=1 ;;
        --calico)  CNI="calico" ;;
        *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

for tool in minikube kubectl jq; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'missing required tool: %s\n' "$tool" >&2; exit 1; }
done

if (( REPLACE == 1 )); then
    if minikube profile list -o json 2>/dev/null \
        | jq -e --arg n "$PROFILE" '[.valid[]?, .invalid[]?] | any(.Name == $n)' >/dev/null 2>&1; then
        printf '==> Deleting existing %s profile (--replace specified)\n' "$PROFILE"
        minikube delete -p "$PROFILE"
    fi
fi

printf '==> Ensuring the %s profile (%s RAM, %s CPUs, containerd runtime, docker driver%s)\n' \
    "$PROFILE" "$MEMORY" "$CPUS" "${CNI:+, $CNI CNI}"

if [[ -n "$CNI" ]]; then
    # ensure_profile does not take a CNI; start directly when Calico is requested.
    if ! minikube profile list -o json 2>/dev/null \
        | jq -e --arg n "$PROFILE" '.valid[]? | select(.Name == $n and .Status == "Running")' >/dev/null 2>&1; then
        minikube start -p "$PROFILE" --driver=docker --container-runtime=containerd \
            --kubernetes-version="$KUBE_VERSION" --cpus="$CPUS" --memory="$MEMORY" --cni="$CNI"
    fi
else
    ensure_profile "$PROFILE" "$PORTS" "$CPUS" "$MEMORY"
fi

minikube addons enable metrics-server -p "$PROFILE" >/dev/null
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

printf '==> Ready. kubectl and helm in the appendix examples target the %s context.\n' "$PROFILE"
