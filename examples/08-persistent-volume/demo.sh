#!/usr/bin/env bash
#
# examples/08-persistent-volume/demo.sh
#
# End-to-end smoke test for §8 with persistence verification:
#   1. Docker Engine + default profile with published ports; image
#      loaded (auto-build if not); standard SC present
#   2. clear any prior nginx-pv resources; check nodePort 30080 is free
#   3. apply PVC + Deployment + NodePort Service
#   4. wait for PVC Bound + Deployment Available
#   5. curl 127.0.0.1:18080; capture the initContainer-written timestamp
#   6. delete the Pod; wait for Deployment to redeploy
#   7. poll 127.0.0.1:18080 until the page returns (the NodePort routes
#      to the replacement Pod; no connection to re-establish)
#   8. verify timestamp matches → PV persisted across Pod lifecycle
#   9. cleanup manifests on exit
#

set -euo pipefail

# ── Resolve repo's shared helpers regardless of cwd ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
APP_NAME="nginx-pv"
PVC_NAME="nginx-content"
IMAGE_TAG="nginx-custom:v1"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
SECTION6_DIR="${REPO_ROOT}/examples/06-deploy-nginx-kubectl"
NODE_PORT=30080
LOCAL_PORT=18080
PROFILE="minikube"
CPUS=6
MEMORY_MB=16384
WAIT_DEPLOY_SECONDS=180
WAIT_REPLACEMENT_SECONDS=90

cleanup() {
    info "cleanup: removing ${APP_NAME} resources (frees nodePort ${NODE_PORT})"
    # Skip until pin_context has run, so an early failure never touches
    # whatever cluster happens to be current.
    [[ -n "${PINNED_CONTEXT}" ]] || return 0
    kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true \
        >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Pre-flight: cluster up ──────────────────────────────────────────────────
step "pre-flight: Docker Engine, profile and kubectl context"
require_docker_engine
ensure_profile "${PROFILE}" "${CORE_PORTS}" "${CPUS}" "${MEMORY_MB}"
pin_context "${PROFILE}"
kubectl get nodes >/dev/null
pass "cluster reachable (context ${PROFILE})"

# ── Pre-flight: standard StorageClass present ───────────────────────────────
step "pre-flight: 'standard' StorageClass present and default"
if ! kubectl get storageclass standard >/dev/null 2>&1; then
    info "Available storage classes:"
    kubectl get storageclass 2>&1 | sed 's/^/    /'
    fail "'standard' StorageClass not found — run 'minikube addons enable default-storageclass storage-provisioner'"
fi
pass "'standard' StorageClass available"

# ── Pre-flight: image cached ────────────────────────────────────────────────
step "pre-flight: ${IMAGE_TAG} image in cluster cache"
if ! minikube -p "${PROFILE}" image ls 2>/dev/null | grep -q "${IMAGE_TAG}"; then
    info "image not present; building from §6's Containerfile"
    if [[ ! -f "${SECTION6_DIR}/Containerfile" ]]; then
        fail "${SECTION6_DIR}/Containerfile not found — examples/06 missing?"
    fi
    if ! build_and_load "${IMAGE_TAG}" "${SECTION6_DIR}" "${PROFILE}"; then
        fail "image build/load failed (see output above)"
    fi
fi
pass "${IMAGE_TAG} available"

# ── Pre-flight: clear stale ─────────────────────────────────────────────────
step "pre-flight: remove any prior ${APP_NAME} resources"
kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true >/dev/null 2>&1 || true
for _ in {1..15}; do
    if ! kubectl get pods -l "app=${APP_NAME}" 2>/dev/null | grep -q Terminating; then
        break
    fi
    sleep 1
done
pass "no stale ${APP_NAME} resources"

step "pre-flight: nodePort ${NODE_PORT} is free"
require_free_nodeport "${NODE_PORT}"
pass "nodePort ${NODE_PORT} free"

# ── Apply manifests ─────────────────────────────────────────────────────────
step "applying PVC, Deployment, and Service"
kubectl apply -f "${MANIFESTS_DIR}/"
pass "manifests applied"

# ── Wait for Deployment ─────────────────────────────────────────────────────
step "waiting for Deployment Available (up to ${WAIT_DEPLOY_SECONDS}s)"
if ! kubectl wait --for=condition=Available "deployment/${APP_NAME}" \
        --timeout="${WAIT_DEPLOY_SECONDS}s" >/dev/null; then
    info "Deployment status:"
    kubectl describe "deployment/${APP_NAME}" | sed 's/^/    /'
    info "Pod status:"
    kubectl get pods -l "app=${APP_NAME}" | sed 's/^/    /'
    info "PVC status:"
    kubectl get pvc "${PVC_NAME}" -o wide | sed 's/^/    /'
    info "initContainer logs (if available):"
    for pod in $(kubectl get pods -l "app=${APP_NAME}" \
                   -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        echo "    ----- ${pod} seed-content -----"
        kubectl logs "${pod}" -c seed-content --tail=30 2>&1 | sed 's/^/    /' || true
        echo "    ----- ${pod} nginx -----"
        kubectl logs "${pod}" -c nginx --tail=30 2>&1 | sed 's/^/    /' || true
    done
    fail "Deployment did not become Available within ${WAIT_DEPLOY_SECONDS}s"
fi
kubectl get deployment,pods,pvc -l "app=${APP_NAME}" | sed 's/^/    /'
pass "Deployment Available, PVC bound"

# ── Published NodePort ──────────────────────────────────────────────────────
step "checking nodePort ${NODE_PORT} is published on 127.0.0.1:${LOCAL_PORT}"
require_published_port "${PROFILE}" "${NODE_PORT}" "${LOCAL_PORT}"
if ! wait_for_http "http://127.0.0.1:${LOCAL_PORT}/" 30; then
    info "Service and endpoints:"
    kubectl get svc,endpoints "${APP_NAME}" | sed 's/^/    /'
    fail "http://127.0.0.1:${LOCAL_PORT}/ did not respond within 30s"
fi
pass "nginx reachable on 127.0.0.1:${LOCAL_PORT} (nodePort ${NODE_PORT})"

# ── Capture initial timestamp ───────────────────────────────────────────────
step "capturing initial content from PV"
INITIAL_RESP=$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null || true)
INITIAL_TIMESTAMP=$(echo "${INITIAL_RESP}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' | head -1 || true)
if [[ -z "${INITIAL_TIMESTAMP}" ]]; then
    info "response (first 300 chars):"
    echo "${INITIAL_RESP:0:300}" | sed 's/^/    /'
    fail "could not extract timestamp from initial response"
fi
info "initial timestamp from PV: ${INITIAL_TIMESTAMP}"
pass "content seeded by initContainer, served by nginx"

# ── Capture old pod name(s), delete, wait for replacement ───────────────────
step "deleting Pod to test persistence across Pod lifecycle"
OLD_POD=$(kubectl get pods -l "app=${APP_NAME}" -o jsonpath='{.items[0].metadata.name}')
info "old Pod: ${OLD_POD}"
kubectl delete pod "${OLD_POD}" --wait=false >/dev/null
info "waiting for replacement Pod (up to ${WAIT_REPLACEMENT_SECONDS}s)"

# Wait for the new Pod to be Ready
if ! kubectl wait --for=condition=Available "deployment/${APP_NAME}" \
        --timeout="${WAIT_REPLACEMENT_SECONDS}s" >/dev/null; then
    info "Deployment status after deletion:"
    kubectl describe "deployment/${APP_NAME}" | sed 's/^/    /'
    fail "replacement Deployment did not become Available within ${WAIT_REPLACEMENT_SECONDS}s"
fi
NEW_POD=$(kubectl get pods -l "app=${APP_NAME}" -o jsonpath='{.items[0].metadata.name}')
if [[ "${NEW_POD}" == "${OLD_POD}" ]]; then
    fail "Pod name didn't change — replacement did not happen"
fi
info "new Pod: ${NEW_POD}"
pass "Pod replaced; Deployment Available again"

# ── Show initContainer log from new Pod (should say "already exists") ───────
step "checking new Pod's initContainer log (should report existing content)"
SEED_LOG=$(kubectl logs "${NEW_POD}" -c seed-content 2>&1 || true)
echo "${SEED_LOG}" | sed 's/^/    /'
case "${SEED_LOG}" in
    *"already exists"*)
        pass "initContainer found existing content → PV persisted"
        ;;
    *"seeding fresh content"*)
        info "initContainer seeded fresh content — the PV should have persisted but didn't"
        fail "PV did not persist across Pod restart"
        ;;
    *)
        info "unexpected initContainer log; continuing to timestamp check"
        ;;
esac

# ── Poll the NodePort until the replacement Pod serves it ───────────────────
# Nothing to reconnect: the NodePort routes to whichever Pod is Ready.
step "polling 127.0.0.1:${LOCAL_PORT} until the replacement Pod answers"
if ! wait_for_http "http://127.0.0.1:${LOCAL_PORT}/" 30; then
    info "Service and endpoints:"
    kubectl get svc,endpoints "${APP_NAME}" | sed 's/^/    /'
    fail "NodePort did not route to the replacement Pod within 30s"
fi
pass "NodePort routes to ${NEW_POD}"

# ── Capture new timestamp, assert match ─────────────────────────────────────
step "verifying content persisted across Pod restart"
NEW_RESP=$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null || true)
NEW_TIMESTAMP=$(echo "${NEW_RESP}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' | head -1 || true)
if [[ -z "${NEW_TIMESTAMP}" ]]; then
    info "response (first 300 chars):"
    echo "${NEW_RESP:0:300}" | sed 's/^/    /'
    fail "could not extract timestamp from new response"
fi
echo "    before Pod restart: ${INITIAL_TIMESTAMP}"
echo "    after Pod restart:  ${NEW_TIMESTAMP}"
if [[ "${NEW_TIMESTAMP}" != "${INITIAL_TIMESTAMP}" ]]; then
    fail "timestamps differ — content did NOT persist (PV not working as designed)"
fi
pass "timestamps match — PV did its job across Pod lifecycle"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — Deployment + PVC + persistence all verified"
echo
echo "  Same image as §6/§7 (nginx-custom:v1), different content via"
echo "  PV mount. initContainer seeded the PV on first run; the new"
echo "  Pod's initContainer found existing content and skipped the"
echo "  seed step. Cleanup on exit removes Deployment + Service + PVC"
echo "  (the PV is auto-deleted by the 'standard' StorageClass's"
echo "  Delete reclaim policy)."
echo
exit 0
