#!/usr/bin/env bash
#
# examples/12-keda-http/cleanup.sh
#
# Deep cleanup for the §12 HTTP demo. Goes beyond demo.sh's cleanup
# trap (which only removes the Deployment + Service + HTTPScaledObject).
#
# Removes:
#   - nginx-http Deployment + Service + HTTPScaledObject (default)
#   - With --remove-operators: KEDA + HTTP add-on + the keda namespace
#
# Usage:
#   ./cleanup.sh                     # demo state only
#   ./cleanup.sh --remove-operators  # plus KEDA itself
#   ./cleanup.sh --help              # show this

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

REMOVE_OPERATORS=false
for arg in "$@"; do
    case "${arg}" in
        --remove-operators) REMOVE_OPERATORS=true ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) fail "unknown argument: ${arg} (try --help)" ;;
    esac
done

PROFILE_NAME="minikube"
kubectl config use-context "${PROFILE_NAME}" >/dev/null 2>&1 || \
    fail "kubectl context '${PROFILE_NAME}' not configured"

# ── Tier 1: demo workload ───────────────────────────────────────────────────
step "removing demo workload (nginx Deployment + Service + HTTPScaledObject)"
kubectl delete httpscaledobject nginx-http-scaler -n default \
    --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
kubectl delete service nginx-http -n default \
    --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
kubectl delete deployment nginx-http -n default \
    --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
# Kill any stray port-forwards from previous demo runs
pkill -f "kubectl port-forward.*keda-add-ons-http-interceptor" 2>/dev/null || true
pass "demo workload removed"

if [[ "${REMOVE_OPERATORS}" != "true" ]]; then
    echo
    step "DONE (default cleanup)"
    echo
    echo "  KEDA + HTTP add-on are still installed."
    echo "  To remove them too: ./cleanup.sh --remove-operators"
    echo
    exit 0
fi

# ── Tier 2: operators ───────────────────────────────────────────────────────
# Note: this also affects §12 Kafka demo if you run it later — it
# depends on KEDA too. If you want to keep KEDA core but remove only
# the HTTP add-on:
#   helm uninstall keda-add-ons-http -n keda
step "removing KEDA + HTTP add-on (this affects §12 Kafka demo too)"
if helm status keda-add-ons-http -n keda >/dev/null 2>&1; then
    helm uninstall keda-add-ons-http -n keda --wait >/dev/null 2>&1 || true
    pass "KEDA HTTP add-on helm release uninstalled"
fi
if helm status keda -n keda >/dev/null 2>&1; then
    helm uninstall keda -n keda --wait >/dev/null 2>&1 || true
    pass "KEDA helm release uninstalled"
fi
if kubectl get namespace keda >/dev/null 2>&1; then
    kubectl delete namespace keda --wait=true --timeout=60s >/dev/null 2>&1 || true
    pass "keda namespace removed"
fi

info "removing KEDA CRDs"
kubectl get crd -o name | grep -E '\.keda\.sh$|\.http\.keda\.sh$' \
    | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
pass "KEDA CRDs removed"

echo
step "DONE (deep cleanup, --remove-operators)"
echo
echo "  KEDA + HTTP add-on fully removed."
echo "  To reinstall: ./scripts/setup-keda.sh"
echo
