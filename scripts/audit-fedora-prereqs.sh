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
maybe()   { "$@" 2>&1 || echo "(command failed or tool not present)"; }

section "platform"
cat /etc/fedora-release 2>&1 || echo "(not a Fedora system?)"
uname -srm

section "hardware"
echo "CPUs: $(nproc)"
free -h
df -h ~ /

section "container engine: podman"
maybe podman --version
maybe podman info --format \
  '{{.Host.OS}} {{.Host.Arch}} rootless={{.Host.Security.Rootless}} cgroupVersion={{.Host.CgroupVersion}}'

section "container engine: docker CLI (optional)"
maybe docker --version

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
maybe istioctl version --remote=false 2>/dev/null

section "what's in Fedora 44 dnf repos"
for pkg in minikube kubectl kubernetes-client helm stern kubectx; do
    printf '\n--- dnf info %s ---\n' "$pkg"
    dnf info "$pkg" 2>&1 \
      | awk '/^Name|^Version|^Release|^Repository|^Summary/{print}' \
      | head -10
    if ! dnf info "$pkg" >/dev/null 2>&1; then
        echo "(no package named $pkg in current repos)"
    fi
done

section "done"
echo "Paste the entire output above (from === platform === down) into"
echo "the iteration thread so version pins can be set from real data."
