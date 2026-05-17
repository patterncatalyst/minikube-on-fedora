#!/usr/bin/env bash
#
# scripts/setup-keda.sh
#
# One-time install of KEDA core + the KEDA HTTP add-on into the
# `keda` namespace on the current kubectl context. Idempotent —
# safe to re-run.
#
# Pinned versions:
#   KEDA core:        2.19.0    (latest stable, Feb 2026)
#   KEDA HTTP add-on: 0.12.2    (latest, Feb 2026 — note: BETA)
#
# After this script returns successfully, both `examples/12-keda-kafka`
# and `examples/12-keda-http` demos can run. The HTTP add-on is only
# needed for the HTTP demo; remove it via
#   helm uninstall keda-add-ons-http -n keda
# if you want a leaner install (saves ~200 MB).

set -euo pipefail

KEDA_VERSION="${KEDA_VERSION:-2.19.0}"
KEDA_HTTP_VERSION="${KEDA_HTTP_VERSION:-0.12.2}"
NAMESPACE="${NAMESPACE:-keda}"

# Color helpers
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; NC=''
fi
info()  { echo -e "  ${YELLOW}→${NC} $*"; }
pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*" >&2; exit 1; }
step()  { echo -e "${YELLOW}━━${NC} $*"; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
step "pre-flight"
command -v helm >/dev/null 2>&1 || fail "helm not in PATH — see §2"
command -v kubectl >/dev/null 2>&1 || fail "kubectl not in PATH — see §2"
kubectl get nodes >/dev/null 2>&1 || fail "kubectl cannot reach a cluster"
CURRENT_CONTEXT=$(kubectl config current-context)
info "kubectl context: ${CURRENT_CONTEXT}"
info "helm: $(helm version --short)"
pass "tooling available"

# ── Step 1: Add the kedacore helm repository ────────────────────────────────
step "ensuring kedacore helm repository is registered"
if helm repo list 2>/dev/null | grep -q '^kedacore'; then
    info "kedacore helm repo already registered"
else
    helm repo add kedacore https://kedacore.github.io/charts
    info "added kedacore helm repo"
fi
helm repo update kedacore >/dev/null
pass "kedacore helm repo ready"

# ── Step 2: Install KEDA core ───────────────────────────────────────────────
step "installing KEDA core ${KEDA_VERSION} into namespace ${NAMESPACE}"
if helm status keda -n "${NAMESPACE}" >/dev/null 2>&1; then
    INSTALLED=$(helm status keda -n "${NAMESPACE}" -o json | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["chart"]["metadata"]["version"])' 2>/dev/null || echo "unknown")
    info "KEDA core already installed (version ${INSTALLED}); upgrading if needed"
    helm upgrade keda kedacore/keda \
        --version "${KEDA_VERSION}" \
        -n "${NAMESPACE}" \
        --wait \
        --timeout 5m
else
    helm install keda kedacore/keda \
        --version "${KEDA_VERSION}" \
        -n "${NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout 5m
fi
pass "KEDA core ${KEDA_VERSION} installed"

# ── Step 3: Install KEDA HTTP add-on ────────────────────────────────────────
step "installing KEDA HTTP add-on ${KEDA_HTTP_VERSION} into namespace ${NAMESPACE}"
info "(beta — official upstream notes this is not yet recommended for production)"
if helm status keda-add-ons-http -n "${NAMESPACE}" >/dev/null 2>&1; then
    INSTALLED=$(helm status keda-add-ons-http -n "${NAMESPACE}" -o json | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["chart"]["metadata"]["version"])' 2>/dev/null || echo "unknown")
    info "HTTP add-on already installed (version ${INSTALLED}); upgrading if needed"
    helm upgrade keda-add-ons-http kedacore/keda-add-ons-http \
        --version "${KEDA_HTTP_VERSION}" \
        -n "${NAMESPACE}" \
        --wait \
        --timeout 5m
else
    helm install keda-add-ons-http kedacore/keda-add-ons-http \
        --version "${KEDA_HTTP_VERSION}" \
        -n "${NAMESPACE}" \
        --wait \
        --timeout 5m
fi
pass "KEDA HTTP add-on ${KEDA_HTTP_VERSION} installed"

# ── Step 4: Verify Pods are Running ─────────────────────────────────────────
step "verifying KEDA Pods are Running"
sleep 3
kubectl get pods -n "${NAMESPACE}" | sed 's/^/    /'
NOT_READY=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null \
    | awk '$2 != "1/1" && $2 != "2/2" {print $1}' | wc -l)
if [[ "${NOT_READY}" -ne 0 ]]; then
    info "some Pods aren't fully ready yet; this may be transient — re-run if it persists"
fi
pass "KEDA installation complete"

echo
step "SUCCESS — KEDA ready"
echo
echo "  KEDA core:        ${KEDA_VERSION}  (operator + metrics-apiserver + admission webhook)"
echo "  HTTP add-on:      ${KEDA_HTTP_VERSION}  (interceptor + scaler + operator) — BETA"
echo "  Namespace:        ${NAMESPACE}"
echo
echo "  Next: install Strimzi for Pattern A (Kafka), then run the demos."
echo
echo "    ./scripts/setup-strimzi.sh"
echo "    cd examples/12-keda-kafka && ./demo.sh"
echo
echo "  Or skip Strimzi and run Pattern B (HTTP) directly:"
echo
echo "    cd examples/12-keda-http && ./demo.sh"
echo
exit 0
