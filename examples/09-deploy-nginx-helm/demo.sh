#!/usr/bin/env bash
#
# examples/09-deploy-nginx-helm/demo.sh
#
# Full helm workflow:
#   1. helm lint (chart sanity check)
#   2. helm template (dry-run render)
#   3. helm install with --set overrides
#   4. wait for rollout; port-forward; curl; verify the installed
#      title appears in the response
#   5. helm upgrade with different --set overrides
#   6. wait for rollout (the ConfigMap checksum annotation makes
#      the upgrade actually roll the Pods)
#   7. re-establish port-forward (Pods got recreated)
#   8. curl; verify the upgraded title appears
#   9. helm history (show both revisions)
#  10. helm uninstall; verify no leftover resources

set -euo pipefail

# ── Resolve repo's shared helpers regardless of cwd ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
RELEASE_NAME="nginx-helm"
CHART_DIR="${SCRIPT_DIR}/chart"
IMAGE_TAG="nginx-custom:v1"
SECTION6_DIR="${REPO_ROOT}/examples/06-deploy-nginx-kubectl"
LOCAL_PORT=18080
WAIT_DEPLOY_SECONDS=180

# Install/upgrade titles — used for the curl assertions
TITLE_INSTALL="First install via helm"
TITLE_UPGRADE="Upgraded title via helm"

# ── State for cleanup ───────────────────────────────────────────────────────
PF_PID=""

cleanup() {
    info "cleanup: stopping port-forward and uninstalling helm release"
    if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
    pkill -f "kubectl port-forward.*${RELEASE_NAME}" 2>/dev/null || true
    # Uninstall whether or not we got past install — idempotent
    helm uninstall "${RELEASE_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Pre-flight: cluster up ──────────────────────────────────────────────────
step "pre-flight: cluster is up and kubectl can reach it"
if ! minikube status >/dev/null 2>&1; then
    info "no cluster; starting"
    minikube start
fi
kubectl get nodes >/dev/null
pass "cluster reachable"

# ── Pre-flight: helm available ──────────────────────────────────────────────
step "pre-flight: helm binary present"
if ! command -v helm >/dev/null 2>&1; then
    fail "helm not in PATH — see §2 for installation"
fi
HELM_VERSION=$(helm version --short)
info "helm version: ${HELM_VERSION}"
pass "helm available"

# ── Pre-flight: image cached ────────────────────────────────────────────────
step "pre-flight: ${IMAGE_TAG} image in cluster cache"
if ! minikube image ls 2>/dev/null | grep -q "${IMAGE_TAG}"; then
    info "image not present; building from §6's Containerfile"
    if [[ ! -f "${SECTION6_DIR}/Containerfile" ]]; then
        fail "${SECTION6_DIR}/Containerfile not found — examples/06 missing?"
    fi
    if ! minikube image build -t "${IMAGE_TAG}" -f Containerfile "${SECTION6_DIR}"; then
        fail "minikube image build failed (see output above)"
    fi
fi
pass "${IMAGE_TAG} available"

# ── Pre-flight: any prior release of nginx-helm ─────────────────────────────
step "pre-flight: remove any prior ${RELEASE_NAME} release"
helm uninstall "${RELEASE_NAME}" >/dev/null 2>&1 || true
pass "no stale ${RELEASE_NAME} release"

# ── helm lint ───────────────────────────────────────────────────────────────
step "running 'helm lint ${CHART_DIR}'"
helm lint "${CHART_DIR}" | sed 's/^/    /'
pass "chart lints clean"

# ── helm template (dry-run) ─────────────────────────────────────────────────
step "running 'helm template ${RELEASE_NAME} ${CHART_DIR}' (dry-run render)"
RENDERED=$(helm template "${RELEASE_NAME}" "${CHART_DIR}" 2>&1)
echo "${RENDERED}" | head -20 | sed 's/^/    /'
echo "    ..."
# Sanity-check: rendered output mentions all three kinds
for kind in "kind: ConfigMap" "kind: Deployment" "kind: Service"; do
    if ! echo "${RENDERED}" | grep -q "${kind}"; then
        fail "rendered output missing ${kind}"
    fi
done
pass "chart renders to ConfigMap + Deployment + Service"

# ── helm install ────────────────────────────────────────────────────────────
step "running 'helm install ${RELEASE_NAME} ${CHART_DIR}' with overrides"
helm install "${RELEASE_NAME}" "${CHART_DIR}" \
    --set content.title="${TITLE_INSTALL}" \
    --set content.customLine="installed at $(date -u +%H:%M:%SZ)" \
    | sed 's/^/    /'
pass "release ${RELEASE_NAME} installed (revision 1)"

# ── Wait for Deployment Available ───────────────────────────────────────────
step "waiting for Deployment Available (up to ${WAIT_DEPLOY_SECONDS}s)"
DEPLOY_NAME="${RELEASE_NAME}"
if ! kubectl wait --for=condition=Available "deployment/${DEPLOY_NAME}" \
        --timeout="${WAIT_DEPLOY_SECONDS}s" >/dev/null; then
    info "Deployment status:"
    kubectl describe "deployment/${DEPLOY_NAME}" | sed 's/^/    /'
    fail "Deployment did not become Available within ${WAIT_DEPLOY_SECONDS}s"
fi
pass "Deployment Available"

# ── Port-forward and curl ───────────────────────────────────────────────────
step "port-forwarding service/${RELEASE_NAME} to 127.0.0.1:${LOCAL_PORT}"
kubectl port-forward "service/${RELEASE_NAME}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
for _ in {1..15}; do
    if curl -fsS --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! kill -0 "${PF_PID}" 2>/dev/null; then
    fail "port-forward died before becoming reachable"
fi
pass "port-forward listening"

# ── Verify install content ──────────────────────────────────────────────────
step "verifying installed title appears in served HTML"
RESP=$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null || true)
case "${RESP}" in
    *"${TITLE_INSTALL}"*)
        pass "served HTML contains '${TITLE_INSTALL}'"
        ;;
    *)
        info "response (first 300 chars):"
        echo "${RESP:0:300}" | sed 's/^/    /'
        fail "served HTML did not contain installed title"
        ;;
esac

# ── helm upgrade ────────────────────────────────────────────────────────────
step "running 'helm upgrade ${RELEASE_NAME} ${CHART_DIR}' with new overrides"
helm upgrade "${RELEASE_NAME}" "${CHART_DIR}" \
    --set content.title="${TITLE_UPGRADE}" \
    --set content.customLine="upgraded at $(date -u +%H:%M:%SZ)" \
    | sed 's/^/    /'
pass "release ${RELEASE_NAME} upgraded (revision 2)"

# ── Wait for rollout ────────────────────────────────────────────────────────
step "waiting for upgrade rollout (configmap checksum triggers Pod recreate)"
# kubectl rollout status will wait for the rollout from the changed
# spec (the checksum annotation in deployment.yaml flipped, so kube
# will recreate the Pods).
if ! kubectl rollout status "deployment/${DEPLOY_NAME}" --timeout=60s >/dev/null; then
    info "rollout status:"
    kubectl describe "deployment/${DEPLOY_NAME}" | sed 's/^/    /'
    fail "upgrade rollout did not complete"
fi
pass "Pods rolled out to new revision"

# ── Re-establish port-forward (old one died with old Pod) ──────────────────
step "re-establishing port-forward to upgraded Pods"
if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
fi
PF_PID=""
kubectl port-forward "service/${RELEASE_NAME}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
for _ in {1..15}; do
    if curl -fsS --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
pass "port-forward reconnected"

# ── Verify upgrade content ──────────────────────────────────────────────────
step "verifying upgraded title appears in served HTML"
RESP=$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null || true)
case "${RESP}" in
    *"${TITLE_UPGRADE}"*)
        pass "served HTML contains '${TITLE_UPGRADE}'"
        ;;
    *)
        info "response (first 300 chars):"
        echo "${RESP:0:300}" | sed 's/^/    /'
        fail "served HTML did not contain upgraded title — rollout may not have completed"
        ;;
esac

# ── helm history ────────────────────────────────────────────────────────────
step "running 'helm history ${RELEASE_NAME}'"
helm history "${RELEASE_NAME}" | sed 's/^/    /'
HISTORY_LINES=$(helm history "${RELEASE_NAME}" | grep -cE '^[0-9]+' || true)
if [[ "${HISTORY_LINES}" -lt 2 ]]; then
    fail "history shows only ${HISTORY_LINES} revisions, expected at least 2"
fi
pass "history shows ${HISTORY_LINES} revisions"

# ── helm uninstall ──────────────────────────────────────────────────────────
step "running 'helm uninstall ${RELEASE_NAME}'"
# Kill port-forward before uninstall (so it doesn't error out trying
# to talk to a vanishing service)
if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
fi
PF_PID=""
helm uninstall "${RELEASE_NAME}" | sed 's/^/    /'
pass "release uninstalled"

# ── Verify no leftover resources (poll — helm uninstall is async) ───────────
step "verifying no chart resources remain (label app.kubernetes.io/instance=${RELEASE_NAME})"
# helm uninstall returns once the release record is deleted and delete
# operations are submitted to the API server. Actual Pod termination is
# async — kubelet runs the preStop hook (none in our case) and waits up to
# terminationGracePeriodSeconds (default 30s) before force-killing. A
# check immediately after uninstall can see Pods still in Terminating
# state. Poll for up to 30s.
LEFTOVERS=0
for i in $(seq 1 30); do
    LEFTOVERS=$(kubectl get all,configmap -l "app.kubernetes.io/instance=${RELEASE_NAME}" \
        --no-headers 2>/dev/null | wc -l)
    if [[ "${LEFTOVERS}" -eq 0 ]]; then
        info "all resources gone after ${i}s"
        break
    fi
    sleep 1
done
if [[ "${LEFTOVERS}" -ne 0 ]]; then
    info "unexpected leftover resources after 30s wait:"
    kubectl get all,configmap -l "app.kubernetes.io/instance=${RELEASE_NAME}" | sed 's/^/    /'
    fail "found ${LEFTOVERS} leftover resources after uninstall"
fi
pass "no leftover resources — helm uninstall cleaned everything"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — helm install + upgrade + history + uninstall all green"
echo
echo "  Same image as §6/§7/§8 (nginx-custom:v1) deployed via a helm"
echo "  chart with templated ConfigMap content. The chart parameterizes"
echo "  replica count, service port, and HTML content — install once,"
echo "  upgrade with different values, see the new content served,"
echo "  uninstall removes everything."
echo
exit 0
