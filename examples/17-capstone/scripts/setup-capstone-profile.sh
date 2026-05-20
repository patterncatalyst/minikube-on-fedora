#!/usr/bin/env bash
#
# setup-capstone-profile.sh — create (or replace) the capstone minikube
# profile sized for the full §17 stack.
#
# The capstone profile is intentionally separate from §3's `minikube`
# profile and §11's `istio` profile so the larger resource footprint
# doesn't disturb earlier sections' state. Idempotent: safe to re-run.
#
# Usage:
#   ./setup-capstone-profile.sh             # start (or do nothing if running)
#   ./setup-capstone-profile.sh --replace   # delete first, then start fresh

set -euo pipefail

PROFILE_NAME="capstone"
MEMORY="24g"
CPUS="16"
DISK="80g"
RUNTIME="containerd"
DRIVER="podman"

REPLACE=0
if [[ "${1:-}" == "--replace" ]]; then
    REPLACE=1
fi

# ─── Pre-flight ──────────────────────────────────────────────────────────────

if ! command -v minikube >/dev/null 2>&1; then
    printf 'ERROR: minikube not in PATH. See §2 for installation.\n' >&2
    exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
    printf 'ERROR: podman not in PATH. See §1 for installation.\n' >&2
    exit 1
fi

# Confirm inotify limits (§1's tweak). Capstone runs many controllers; the
# Fedora default fs.inotify.max_user_instances=128 is insufficient.
inotify_instances=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
if (( inotify_instances < 256 )); then
    printf 'ERROR: fs.inotify.max_user_instances is %d (need ≥ 256).\n' "$inotify_instances" >&2
    printf 'Apply the §1 kernel-limits tweak before continuing:\n' >&2
    printf '  sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF\n' >&2
    printf '  fs.inotify.max_user_instances = 512\n' >&2
    printf '  fs.inotify.max_user_watches = 524288\n' >&2
    printf '  EOF\n' >&2
    printf '  sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf\n' >&2
    exit 1
fi

# Warn (don't fail) if other minikube profiles are running. Capstone wants
# the headroom.
running_profiles=$(minikube profile list -o json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for p in data.get("valid", []):
        if p["Name"] != "'"$PROFILE_NAME"'" and p.get("Status") == "Running":
            print(p["Name"])
except Exception:
    pass
' 2>/dev/null || true)

if [[ -n "$running_profiles" ]]; then
    printf 'WARNING: other minikube profiles are running and will compete for RAM:\n' >&2
    printf '%s\n' "$running_profiles" | sed 's/^/  - /' >&2
    printf 'Recommended: stop them with `minikube stop -p <name>` before continuing.\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── Profile setup ───────────────────────────────────────────────────────────

if minikube status -p "$PROFILE_NAME" >/dev/null 2>&1; then
    if (( REPLACE )); then
        printf '==> Deleting existing %s profile (--replace specified)\n' "$PROFILE_NAME"
        minikube delete -p "$PROFILE_NAME"
    else
        printf '==> Profile %s already exists and is running. Pass --replace to recreate.\n' "$PROFILE_NAME"
        printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
        kubectl config use-context "$PROFILE_NAME"
        printf '==> Done. Current nodes:\n'
        kubectl get nodes
        exit 0
    fi
fi

printf '==> Starting %s profile (%s RAM, %s CPUs, %s disk, %s runtime)\n' \
    "$PROFILE_NAME" "$MEMORY" "$CPUS" "$DISK" "$RUNTIME"

minikube start -p "$PROFILE_NAME" \
    --memory="$MEMORY" \
    --cpus="$CPUS" \
    --disk-size="$DISK" \
    --container-runtime="$RUNTIME" \
    --driver="$DRIVER" \
    --rootless=true \
    --addons=metrics-server

printf '==> Switching kubectl context to %s\n' "$PROFILE_NAME"
kubectl config use-context "$PROFILE_NAME"

printf '==> Creating capstone namespace\n'
kubectl create namespace capstone --dry-run=client -o yaml | kubectl apply -f -

printf '==> Verifying cluster health\n'
kubectl get nodes
kubectl get pods -n kube-system

printf '\n'
printf '==> Capstone profile is ready.\n'
printf '\n'
printf 'Next steps (per r20):\n'
printf '  1. The platform stack (Strimzi, KEDA, Istio, Apicurio, OpenMetadata,\n'
printf '     observability, Prefect, Postgres) installs in iterations r21-r27.\n'
printf '  2. To free the profile when done with §17:\n'
printf '       ./scripts/teardown.sh\n'
printf '  3. To switch back to a different profile:\n'
printf '       kubectl config use-context minikube  # (or istio, etc.)\n'
