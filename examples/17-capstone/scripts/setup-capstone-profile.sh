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
export MINIKUBE_ROOTLESS=true   # CAP-010: required so minikube uses rootless podman
                                # for host ops (status/ssh/registry), not sudo podman

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

# Confirm podman's default pids_limit is raised (CAP-040). The podman driver
# creates the minikube node as a container whose ROOT cgroup pids.max is
# podman's default (--pids-limit=2048) — a cap on TOTAL processes across ALL
# pods on the node. The full meshed capstone (CNPG, Kafka, KEDA, OpenMetadata +
# OpenSearch JVMs, observability, six services, and six Envoy sidecars under
# namespace-wide injection) runs ~2000+ tasks and saturates 2048 — so the
# kubelet can't fork the last pod's init (order-service: EAGAIN, runc exit 128,
# "fork/exec ...: resource temporarily unavailable", CrashLoopBackOff/StartError).
# The node-container cgroup pids.max is NOT writable live on a rootless node
# (Operation not permitted), so the only durable fix is at CREATION time: raise
# podman's default via containers.conf before the node is built.
# Parse the effective podman default pids_limit from containers.conf (user first,
# then system). The trailing `|| true` is ESSENTIAL: under `set -e` + `pipefail`,
# a `var=$(...)` assignment aborts the whole script if the inner pipeline returns
# non-zero — and this grep chain legitimately returns non-zero when a file is
# absent or contains no match. That abort (not the arithmetic) was the real bug.
pids_limit=$(
    grep -hsE '^[[:space:]]*pids_limit[[:space:]]*=' \
        "${HOME}/.config/containers/containers.conf" \
        /etc/containers/containers.conf 2>/dev/null \
        | tail -1 | grep -oE '[0-9]+' | tail -1 || true
)
pids_limit="${pids_limit:-2048}"
pids_too_low=0
# Use `(( ))` only as an if-condition (set-e-exempt position) and only on a
# verified-numeric value.
if [[ "$pids_limit" != "0" ]] && [[ "$pids_limit" =~ ^[0-9]+$ ]]; then
    if (( pids_limit < 8192 )); then pids_too_low=1; fi
fi
if [[ "$pids_too_low" == "1" ]]; then
    printf 'ERROR: podman default pids_limit is %s (need 0=unlimited or ≥ 8192).\n' "$pids_limit" >&2
    printf 'The capstone node would be capped at %s total PIDs and the last pod\n' "$pids_limit" >&2
    printf 'would fail to fork (EAGAIN / runc exit 128). Raise it before creating the node:\n' >&2
    printf '  mkdir -p ~/.config/containers\n' >&2
    printf '  printf '\''[containers]\\npids_limit = 0\\n'\'' >> ~/.config/containers/containers.conf\n' >&2
    printf 'Then re-run this script (a node recreate is needed to pick it up).\n' >&2
    exit 1
fi
if [[ "$pids_limit" == "0" ]]; then
    pids_display="unlimited"
else
    pids_display="$pids_limit"
fi
printf '==> podman pids_limit OK (%s) — node will have PID headroom (CAP-040)\n' "$pids_display"

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

printf '==> Persisting rootless mode in minikube config (CAP-010)\n'
minikube config set rootless true >/dev/null 2>&1 || true

printf '==> Enabling the in-cluster registry addon (CAP-009)\n'
minikube addons enable registry -p "$PROFILE_NAME"
printf '    Host pushes to 127.0.0.1:<port> (see: podman port %s | grep 5000)\n' "$PROFILE_NAME"
printf '    Cluster pulls from localhost:5000 — build-image.sh handles both.\n'

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
