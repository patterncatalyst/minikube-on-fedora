#!/usr/bin/env bash
#
# examples/11-istio/cleanup.sh
#
# Deep cleanup for the §11 Istio demo. Goes beyond demo.sh's cleanup
# trap (which removes only the demo's nginx + sidecar deployment).
#
# Removes:
#   - Demo workload (nginx-with-sidecar Deployment + Service + VS/DR)
#   - Bookinfo sample app + its networking (gateway, vs, drs)
#   - Optional addons (Kiali, Prometheus, Grafana, Jaeger, Loki) if
#     installed
#   - With --remove-istio: istiod, ingress/egress gateways, the
#     istio-system namespace, and Istio CRDs
#   - With --remove-istio --remove-profile: also delete the `istio`
#     minikube profile entirely (frees the most resources)
#
# Usage:
#   ./cleanup.sh                                 # demo + Bookinfo + addons
#   ./cleanup.sh --remove-istio                  # plus Istio control plane
#   ./cleanup.sh --remove-istio --remove-profile # also drop the istio profile
#   ./cleanup.sh --help                          # show this

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

REMOVE_ISTIO=false
REMOVE_PROFILE=false
for arg in "$@"; do
    case "${arg}" in
        --remove-istio)   REMOVE_ISTIO=true ;;
        --remove-profile) REMOVE_PROFILE=true ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) fail "unknown argument: ${arg} (try --help)" ;;
    esac
done

if [[ "${REMOVE_PROFILE}" == "true" && "${REMOVE_ISTIO}" != "true" ]]; then
    fail "--remove-profile requires --remove-istio (the profile contains Istio)"
fi

PROFILE_NAME="istio"
ISTIO_DIR="${ISTIO_DIR:-${HOME}/.local/share/istio-current}"

# Check the istio profile exists; if not, there's nothing to clean up
if ! minikube profile list 2>/dev/null | grep -q "${PROFILE_NAME}"; then
    info "no minikube profile named '${PROFILE_NAME}' found — nothing to clean"
    exit 0
fi

kubectl config use-context "${PROFILE_NAME}" >/dev/null 2>&1 || \
    fail "kubectl context '${PROFILE_NAME}' not configured"

# ── Tier 1: demo workload ───────────────────────────────────────────────────
step "removing §11 demo workload (nginx with sidecar)"
kubectl delete -f "${SCRIPT_DIR}/manifests/nginx-with-sidecar.yaml" \
    --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
pass "demo workload removed"

# ── Tier 2: Bookinfo + its networking ──────────────────────────────────────
step "removing Bookinfo sample app + networking"
if [[ -d "${ISTIO_DIR}/samples/bookinfo" ]]; then
    kubectl delete -f "${ISTIO_DIR}/samples/bookinfo/networking/" \
        --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl delete -f "${ISTIO_DIR}/samples/bookinfo/platform/kube/bookinfo.yaml" \
        --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
    pass "Bookinfo removed"
else
    info "Istio dir not found at ${ISTIO_DIR}; skipping Bookinfo (likely already gone)"
fi

# ── Tier 3: Addons (Kiali, Prometheus, Grafana, Jaeger, Loki) ──────────────
if [[ -d "${ISTIO_DIR}/samples/addons" ]]; then
    step "removing observability addons (Kiali / Prometheus / Grafana / Jaeger / Loki)"
    kubectl delete -f "${ISTIO_DIR}/samples/addons/" \
        --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
    pass "addons removed"
fi

if [[ "${REMOVE_ISTIO}" != "true" ]]; then
    echo
    step "DONE (default cleanup)"
    echo
    echo "  Istio control plane (istiod + gateways) is still running."
    echo "  To remove it too:        ./cleanup.sh --remove-istio"
    echo "  To drop the whole profile: ./cleanup.sh --remove-istio --remove-profile"
    echo
    exit 0
fi

# ── Tier 4: Istio control plane ─────────────────────────────────────────────
step "removing Istio control plane"
if command -v istioctl >/dev/null 2>&1; then
    istioctl uninstall --purge -y >/dev/null 2>&1 || true
    pass "istioctl uninstall --purge completed"
else
    info "istioctl not in PATH; falling back to kubectl namespace delete"
fi
if kubectl get namespace istio-system >/dev/null 2>&1; then
    kubectl delete namespace istio-system --wait=true --timeout=120s >/dev/null 2>&1 || true
    pass "istio-system namespace removed"
fi

# Istio installs cluster-scoped CRDs and webhook configurations
info "removing Istio CRDs + webhook configurations"
kubectl get crd -o name | grep -E '\.istio\.io$' \
    | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete mutatingwebhookconfiguration -l app=sidecar-injector \
    --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete validatingwebhookconfiguration -l app=istiod \
    --ignore-not-found=true >/dev/null 2>&1 || true
pass "Istio CRDs + webhooks removed"

if [[ "${REMOVE_PROFILE}" != "true" ]]; then
    echo
    step "DONE (--remove-istio cleanup)"
    echo
    echo "  The istio minikube profile is still running, just empty."
    echo "  To reinstall Istio: ./scripts/setup-istio.sh"
    echo "  To drop the whole profile: ./cleanup.sh --remove-istio --remove-profile"
    echo
    exit 0
fi

# ── Tier 5: Drop the minikube profile entirely ─────────────────────────────
step "deleting the entire istio minikube profile (--remove-profile)"
minikube delete -p "${PROFILE_NAME}" || true
pass "istio profile deleted"

# Switch context back to minikube so the user isn't left on a dangling
# context that no longer exists
if kubectl config get-contexts -o name 2>/dev/null | grep -q '^minikube$'; then
    kubectl config use-context minikube >/dev/null 2>&1 || true
    info "kubectl context switched back to 'minikube'"
fi

echo
step "DONE (full teardown)"
echo
echo "  The istio profile and everything in it are gone."
echo "  To rebuild from scratch:"
echo "    minikube start -p istio --memory=6g --cpus=4 \\"
echo "        --container-runtime=containerd --rootless=true"
echo "    ./scripts/setup-istio.sh"
echo
