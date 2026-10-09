#!/usr/bin/env bash
#
# audit-fedora-prereqs.sh — capture the Fedora 44 environment state
# this tutorial assumes. Run once before writing each new section;
# paste the output into the iteration thread so version pins in the
# reconciliation plan can be set from real data, not guesses.
#
# Safe to re-run any number of times. Modifies nothing; reads only.
#
# Usage:
#   ./scripts/audit-fedora-prereqs.sh                  # print to stdout
#   ./scripts/audit-fedora-prereqs.sh > /tmp/audit.txt # capture to file

section() { printf '\n=== %s ===\n' "$*"; }

# Run a command if its first argument is on PATH; otherwise report
# cleanly. Avoids bash's "command not found" stderr noise that the
# r03 version of this script let through.
maybe() {
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1 || echo "  (command failed)"
    else
        echo "  ($1 not present)"
    fi
}

section "platform"
cat /etc/fedora-release 2>&1 || echo "(not a Fedora system?)"
uname -srm

section "hardware"
echo "CPUs: $(nproc)"
free -h
df -h ~ /

section "container engine: Docker Engine (docker-ce)"
# Audit only: every probe below tolerates a stopped daemon and reports.
if command -v rpm >/dev/null 2>&1; then
    rpm -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin 2>&1 | sed 's/^/  /' || true
fi
maybe docker --version
printf '  systemctl is-active docker: %s\n' "$(systemctl is-active docker 2>&1 || true)"
CTX=$(docker context show 2>/dev/null || true)
echo "  docker context: ${CTX:-(none)}"
if [[ -S /var/run/docker.sock ]]; then
    echo "  socket: /var/run/docker.sock present"
else
    echo "  socket: /var/run/docker.sock MISSING"
fi
if id -nG | tr ' ' '\n' | grep -qx docker; then
    echo "  group: $(id -un) is in the docker group"
else
    echo "  group: $(id -un) is NOT in the docker group (sudo usermod -aG docker \$USER, then re-login)"
fi
docker info --format '  server={{.ServerVersion}} cgroup={{.CgroupVersion}} root={{.DockerRootDir}}' 2>/dev/null \
    || echo "  (docker daemon not reachable)"

section "container engine: warnings"
WARNED=0
warn() { echo "  WARN: $*"; WARNED=1; }
if rpm -q moby-engine >/dev/null 2>&1; then
    warn "moby-engine is installed; the tutorial uses docker-ce (sudo dnf remove moby-engine)"
fi
if rpm -q podman-docker >/dev/null 2>&1; then
    warn "podman-docker is installed and shadows the docker CLI (sudo dnf remove podman-docker)"
fi
if [[ -n "${CTX}" && "${CTX}" != "default" ]]; then
    warn "docker context is '${CTX}', expected 'default' (docker context use default)"
fi
if [[ -n "${DOCKER_HOST:-}" ]]; then
    warn "DOCKER_HOST is set to '${DOCKER_HOST}' (unset it)"
fi
MK_CFG=$(minikube config view 2>/dev/null || true)
if grep -Eiq 'driver|rootless' <<<"${MK_CFG}"; then
    warn "minikube config sets driver/rootless; the tutorial passes flags per profile:"
    sed 's/^/        /' <<<"${MK_CFG}" | grep -Ei 'driver|rootless' || true
    echo "        clear with: minikube config unset <key>"
fi
(( WARNED == 0 )) && echo "  (none)"

section "minikube profiles"
minikube profile list 2>/dev/null || echo "  (minikube not present, or the docker daemon is stopped)"

section "currently installed tutorial tools (PATH)"
for tool in minikube kubectl helm istioctl stern kubectx kubens yq krew httpie hey gh; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  %-12s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf '  %-12s (not installed)\n' "$tool"
    fi
done

section "current versions (where installed)"
maybe minikube version
maybe kubectl version --client=true
maybe helm version --short
maybe istioctl version --remote=false

section "what's in Fedora 44 dnf repos"
for pkg in minikube kubectl kubernetes-client helm stern kubectx httpie yq; do
    printf '\n--- dnf info %s ---\n' "$pkg"
    if dnf info "$pkg" >/dev/null 2>&1; then
        dnf info "$pkg" 2>&1 \
          | awk '/^Name|^Version|^Release|^Repository|^Summary/{print}' \
          | head -10
    else
        echo "(no package named $pkg in current repos)"
    fi
done

section "kernel limits (matters for §11 multi-cluster)"
INSTANCES=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
WATCHES=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
echo "  fs.inotify.max_user_instances = ${INSTANCES}"
echo "  fs.inotify.max_user_watches   = ${WATCHES}"
if [[ "${INSTANCES}" -ge 256 ]] && [[ "${WATCHES}" -ge 131072 ]]; then
    echo "  STATUS: ✓ OK for running a second minikube profile (§11)"
else
    echo "  STATUS: ⚠ defaults — fine for §3-§10 (one cluster) but"
    echo "          NOT for §11 (two clusters: minikube + istio)."
    echo "          Fix from §1 prereqs 'Kernel limits' subsection:"
    echo ""
    echo "          sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF"
    echo "          fs.inotify.max_user_instances = 512"
    echo "          fs.inotify.max_user_watches = 524288"
    echo "          EOF"
    echo "          sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf"
fi

section "done"
echo "Paste the entire output above (from === platform === down) into"
echo "the iteration thread so version pins can be set from real data."
