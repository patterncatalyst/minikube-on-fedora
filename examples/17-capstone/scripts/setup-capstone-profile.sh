#!/usr/bin/env bash
#
# setup-capstone-profile.sh — create (or replace) the mof-capstone minikube
# profile sized for the full §17 stack.
#
# The profile is intentionally separate from §3's `minikube` profile and §11's
# `istio` profile so the larger resource footprint doesn't disturb earlier
# sections' state. It is named `mof-capstone` (not `capstone`) because the name
# `capstone` belongs to another repository's cluster on the same host; the
# Kubernetes namespace stays `capstone`. Idempotent: safe to re-run.
#
# Runs on Docker Engine (docker driver, containerd runtime) and publishes every
# host-facing NodePort at creation (CAPSTONE_PORTS in scripts/lib/env.sh).
# Published ports are fixed when the profile is created, which is why a
# profile created without them has to be deleted and recreated.
#
# Usage:
#   ./setup-capstone-profile.sh             # start (or do nothing if running)
#   ./setup-capstone-profile.sh --replace   # delete mof-capstone first, then start fresh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

MEMORY="24g"
CPUS="16"

REPLACE=0
if [[ "${1:-}" == "--replace" ]]; then
    REPLACE=1
fi

# ─── Pre-flight ──────────────────────────────────────────────────────────────

for tool in minikube kubectl jq; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool not in PATH. See §1/§2 for installation."
done

require_docker_engine

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
    | jq -r --arg p "$PROFILE" '.valid[]? | select(.Name != $p and .Status == "Running") | .Name' 2>/dev/null || true)

if [[ -n "$running_profiles" ]]; then
    printf 'WARNING: other minikube profiles are running and will compete for RAM:\n' >&2
    printf '%s\n' "$running_profiles" | sed 's/^/  - /' >&2
    printf 'Recommended: stop them with `minikube stop -p <name>` before continuing.\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── Profile setup ───────────────────────────────────────────────────────────

if (( REPLACE )); then
    if minikube profile list -o json 2>/dev/null \
        | jq -e --arg n "$PROFILE" '[.valid[]?, .invalid[]?] | any(.Name == $n)' >/dev/null 2>&1; then
        printf '==> Deleting existing %s profile (--replace specified)\n' "$PROFILE"
        minikube delete -p "$PROFILE"
    fi
fi

printf '==> Ensuring the %s profile (%s RAM, %s CPUs, containerd runtime, docker driver)\n' \
    "$PROFILE" "$MEMORY" "$CPUS"
ensure_profile "$PROFILE" "$CAPSTONE_PORTS" "$CPUS" "$MEMORY"

printf '==> Enabling metrics-server\n'
minikube addons enable metrics-server -p "$PROFILE" >/dev/null

printf '==> Creating capstone namespace\n'
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

printf '==> Verifying cluster health\n'
kubectl get nodes
kubectl get pods -n kube-system

# The node is a container; its PID limit caps TOTAL processes across all pods.
# The full meshed capstone (CNPG, Kafka, KEDA, OpenMetadata + OpenSearch JVMs,
# observability, services and their Envoy sidecars) runs ~2000+ tasks (CAP-040).
# Docker Engine's default is unlimited (0 / -1); report the value, and fail only
# when a daemon-level default clearly caps it.
pids_limit=$(docker inspect -f '{{.HostConfig.PidsLimit}}' "$PROFILE" 2>/dev/null || echo unknown)
case "$pids_limit" in
    0|-1|"<nil>"|"") pids_display="unlimited" ;;
    unknown)         pids_display="unknown" ;;
    *)               pids_display="$pids_limit" ;;
esac
printf '==> Node PidsLimit: %s\n' "$pids_display"
if [[ "$pids_limit" =~ ^[0-9]+$ ]] && (( pids_limit > 0 && pids_limit < 4096 )); then
    printf 'ERROR: the node container is capped at %s PIDs; the full stack needs more.\n' "$pids_limit" >&2
    printf 'The Docker daemon applies a default pids limit. Remove "default-pids-limit" from\n' >&2
    printf '/etc/docker/daemon.json (or raise it), restart docker, then recreate the profile:\n' >&2
    printf '  ./scripts/setup-capstone-profile.sh --replace\n' >&2
    exit 1
fi

printf '\n'
printf '==> Capstone profile is ready.\n'
printf '\n'
printf 'Next steps:\n'
printf '  1. The platform stack (Strimzi, KEDA, Istio, Apicurio, OpenMetadata,\n'
printf '     observability, Postgres) installs with ./scripts/bootstrap-capstone.sh.\n'
printf '  2. To free the profile when done with §17:\n'
printf '       ./scripts/teardown.sh\n'
printf '  3. kubectl and helm in this repo always target the %s context;\n' "$PROFILE"
printf '     your current-context is never changed by these scripts.\n'
