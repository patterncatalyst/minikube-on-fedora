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
# cleanly. Avoids bash's "command not found" stderr noise.
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

section "container engine: podman"
maybe podman --version
# Note: CgroupVersion field was removed from podman info template in
# podman 5.x; dropped to keep output clean.
maybe podman info --format \
  '{{.Host.OS}} {{.Host.Arch}} rootless={{.Host.Security.Rootless}}'

section "container engine: docker CLI (optional)"
maybe docker --version

section "currently installed tutorial tools"

# Top-level binaries on PATH (installed via dnf, RPM, or upstream)
for tool in minikube kubectl helm istioctl yq httpie hey gh; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  %-16s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf '  %-16s (not installed)\n' "$tool"
    fi
done

# krew + its plugins are kubectl subcommands, not standalone binaries.
# They install as ~/.krew/bin/kubectl-<name> and are invoked as
# `kubectl <name>`. command -v won't find them by their plain name.
krew_dir="${KREW_ROOT:-$HOME/.krew}/bin"
if [[ -x "${krew_dir}/kubectl-krew" ]]; then
    printf '  %-16s %s\n' "kubectl krew" "${krew_dir}/kubectl-krew"
    for plugin in stern ctx ns; do
        if [[ -x "${krew_dir}/kubectl-${plugin}" ]]; then
            printf '  %-16s %s\n' "kubectl ${plugin}" "${krew_dir}/kubectl-${plugin}"
        else
            printf '  %-16s (krew plugin not installed)\n' "kubectl ${plugin}"
        fi
    done
else
    printf '  %-16s (not installed; install via §2 krew bootstrap)\n' "kubectl krew"
fi

section "current versions (where installed)"
maybe minikube version --short
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

section "done"
echo "Paste the entire output above (from === platform === down) into"
echo "the iteration thread so version pins can be set from real data."
