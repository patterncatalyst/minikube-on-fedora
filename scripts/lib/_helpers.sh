#!/usr/bin/env bash
# Shared helpers for the example-test scripts and the minikube profile
# scripts. Source this from each scripts/test-*.sh — handles colors,
# repo-root resolution, container cleanup, the Docker Engine preflight,
# the published-NodePort maps, and profile creation. Not intended to be
# executed directly.

# ── Colors (auto-disabled when stdout isn't a tty) ──────────────────────────
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

step()  { echo -e "${CYAN}━━ $*${NC}"; }
pass()  { echo -e "${GREEN}✓ $*${NC}"; }
fail()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }
info()  { echo -e "${YELLOW}  $*${NC}"; }

# ── Repo-root resolution ────────────────────────────────────────────────────
# Falls back to the script's grandparent dir if we're outside a git checkout.
repo_root() {
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        # scripts/lib/_helpers.sh -> scripts/ -> repo
        cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
    fi
}

# ── Cluster constants ───────────────────────────────────────────────────────
# Single source of truth for the Kubernetes version and the host-to-nodePort
# maps. scripts/check-port-map.sh cross-checks these against the YAML and
# the docs. Format: 127.0.0.1:<hostPort>:<nodePort>[,...]
KUBE_VERSION=v1.35.1
CORE_PORTS="127.0.0.1:18080:30080,127.0.0.1:18081:30808,127.0.0.1:18090:30900"
ISTIO_PORTS="127.0.0.1:8080:30880,127.0.0.1:20001:30201,127.0.0.1:3000:30300,127.0.0.1:9090:30990,127.0.0.1:16686:31686"
DRIVER_CHECK_PORTS="127.0.0.1:18079:30079"

# ── Container cleanup ───────────────────────────────────────────────────────
# Idempotent: removes a container if it exists, silent if not.
cleanup_container() {
    local name="$1"
    docker rm -f "$name" >/dev/null 2>&1 || true
}

# Wait up to N seconds for an HTTP endpoint to start responding.
# Returns 0 if it does, 1 if it doesn't. Use 127.0.0.1 (not localhost)
# to avoid IPv4/IPv6 dual-stack mismatch issues.
wait_for_http() {
    local url="$1"
    local timeout="${2:-30}"
    local i
    for ((i = 0; i < timeout; i++)); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# ── Docker Engine preflight ─────────────────────────────────────────────────
# minikube follows the active docker context, so the tutorial requires the
# Docker Engine (docker-ce) on its default socket. Each failure prints the fix.
require_docker_engine() {
    local sock="unix:///var/run/docker.sock" ctx endpoint

    command -v docker >/dev/null 2>&1 \
        || fail "docker CLI not found. Install Docker Engine (docker-ce) per §1, then: sudo systemctl enable --now docker"

    if rpm -q podman-docker >/dev/null 2>&1; then
        fail "podman-docker is installed and shadows the docker CLI. Fix: sudo dnf remove podman-docker"
    fi

    ctx=$(docker context show 2>/dev/null || true)
    if [[ "$ctx" != "default" ]]; then
        fail "docker context is '${ctx:-unknown}', expected 'default'. Fix: docker context use default"
    fi

    endpoint=$(docker context inspect default --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
    if [[ "$endpoint" != "$sock" ]]; then
        fail "docker context 'default' points at '${endpoint:-unknown}', expected $sock. Fix: docker context use default; unset DOCKER_HOST; and remove any Docker Desktop context override"  # policy-exempt
    fi

    if [[ -n "${DOCKER_HOST:-}" && "$DOCKER_HOST" != "$sock" ]]; then
        fail "DOCKER_HOST is set to '$DOCKER_HOST', expected $sock or unset. Fix: unset DOCKER_HOST (and remove it from ~/.bashrc / ~/.zshrc)"
    fi

    docker info >/dev/null 2>&1 \
        || fail "cannot reach the Docker daemon on /var/run/docker.sock. Fix: sudo systemctl enable --now docker; sudo usermod -aG docker \$USER (then log out and back in)"

    pass "Docker Engine reachable (context default, $sock)"
}

# ── Published NodePorts ─────────────────────────────────────────────────────
# Set by ensure_profile so require_published_port can print the exact
# recreate command. Never executed here.
_RECREATE_HINT=""

# require_published_port PROFILE NODEPORT HOSTPORT
# The minikube node container must publish NODEPORT on 127.0.0.1:HOSTPORT.
require_published_port() {
    local profile="$1" nodeport="$2" hostport="$3" published
    published=$(docker port "$profile" "${nodeport}/tcp" 2>/dev/null || true)
    if ! grep -qF "127.0.0.1:${hostport}" <<<"$published"; then
        echo -e "${RED}✗ profile '$profile' does not publish nodePort ${nodeport} on 127.0.0.1:${hostport}${NC}" >&2
        echo "  Ports are fixed when the profile is created. Delete and recreate it:" >&2
        if [[ -n "$_RECREATE_HINT" ]]; then
            echo "    $_RECREATE_HINT" >&2
        else
            echo "    minikube delete -p $profile && minikube start -p $profile --driver=docker --container-runtime=containerd --kubernetes-version=$KUBE_VERSION --ports=<map from scripts/lib/_helpers.sh>" >&2
        fi
        exit 1
    fi
}

# ── Profile creation ────────────────────────────────────────────────────────
# ensure_profile NAME PORTS CPUS MEM_MB
# Creates the profile with published NodePorts if absent, starts it if
# stopped, and verifies every mapping if it already exists.
ensure_profile() {
    local name="$1" ports="$2" cpus="$3" mem="$4" entry p exists=0

    _RECREATE_HINT="minikube delete -p $name && minikube start -p $name --driver=docker --container-runtime=containerd --kubernetes-version=$KUBE_VERSION --cpus=$cpus --memory=$mem --ports=$ports"

    if minikube profile list -o json 2>/dev/null \
        | jq -e --arg n "$name" '[.valid[]?, .invalid[]?] | any(.Name == $n)' >/dev/null 2>&1; then
        exists=1
    fi

    if (( exists == 0 )); then
        step "Creating minikube profile '$name'"
        local -a conflicts=()
        IFS=',' read -ra entries <<<"$ports"
        for entry in "${entries[@]}"; do
            p=$(cut -d: -f2 <<<"$entry")
            if [[ -n "$(ss -ltnH "sport = :$p" 2>/dev/null)" ]]; then
                conflicts+=("host port $p (in use: $(ss -ltnpH "sport = :$p" 2>/dev/null | awk '{print $4, $6}' | head -1))")
            fi
        done
        if (( ${#conflicts[@]} > 0 )); then
            printf '  conflict: %s\n' "${conflicts[@]}" >&2
            fail "cannot publish ports for profile '$name'; free the host ports above and re-run"
        fi
        minikube start -p "$name" \
            --driver=docker --container-runtime=containerd \
            --kubernetes-version="$KUBE_VERSION" \
            --cpus="$cpus" --memory="$mem" \
            --ports="$ports" \
            || fail "minikube start -p $name failed"
        pass "profile '$name' created"
    elif ! minikube status -p "$name" >/dev/null 2>&1; then
        step "Starting stopped profile '$name' (published ports persist)"
        minikube start -p "$name" || fail "minikube start -p $name failed"
    fi

    IFS=',' read -ra entries <<<"$ports"
    for entry in "${entries[@]}"; do
        require_published_port "$name" "$(cut -d: -f3 <<<"$entry")" "$(cut -d: -f2 <<<"$entry")"
    done
    pass "profile '$name' publishes all expected ports"
}

# ── Images ──────────────────────────────────────────────────────────────────
# build_and_load IMAGE CONTEXT_DIR PROFILE
# Builds with Docker Engine, then loads the image into the profile's
# containerd. Use the bare image name with imagePullPolicy: Never.
build_and_load() {
    local image="$1" ctxdir="$2" profile="$3"
    docker build -f "$ctxdir/Containerfile" -t "$image" "$ctxdir" \
        && minikube -p "$profile" image load "$image"
}

# ── Context pinning ─────────────────────────────────────────────────────────
# pin_context CTX
# Shadows kubectl / helm / istioctl with functions that always target CTX,
# so a changed current-context can never redirect a script.
PINNED_CONTEXT=""
pin_context() {
    PINNED_CONTEXT="$1"
    kubectl()  { command kubectl --context "$PINNED_CONTEXT" "$@"; }
    helm()     { command helm --kube-context "$PINNED_CONTEXT" "$@"; }
    istioctl() { command istioctl --context "$PINNED_CONTEXT" "$@"; }
}

# require_free_nodeport NODEPORT
# Fails when any Service in any namespace already holds NODEPORT.
require_free_nodeport() {
    local np="$1" holders
    holders=$(kubectl get svc -A -o json 2>/dev/null \
        | jq -r --argjson np "$np" '.items[] | select(any(.spec.ports[]?; .nodePort == $np)) | "\(.metadata.namespace)/\(.metadata.name)"') \
        || fail "could not list Services to check nodePort $np"
    if [[ -n "$holders" ]]; then
        while IFS= read -r h; do
            echo -e "${RED}✗ nodePort $np is held by Service $h${NC}" >&2
            echo "  Fix: kubectl delete svc -n ${h%%/*} ${h##*/}   (delete ${h} first)" >&2
        done <<<"$holders"
        exit 1
    fi
}
