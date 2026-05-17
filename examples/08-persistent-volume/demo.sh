#!/usr/bin/env bash
#
# examples/08-persistent-volume/demo.sh
#
# End-to-end smoke test for §8 with persistence verification:
#   1. cluster up; image cached (auto-build if not); standard SC present
#   2. clear any prior nginx-pv resources
#   3. apply PVC + Deployment + Service
#   4. wait for PVC Bound + Deployment Available
#   5. port-forward and curl; capture the initContainer-written timestamp
#   6. delete the Pod; wait for Deployment to redeploy
#   7. re-establish port-forward (old one died with the Pod)
#   8. curl again; verify timestamp matches → PV persisted across Pod
#      lifecycle
#   9. cleanup tunnel + manifests on exit

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
LOCAL_PORT=18080
WAIT_DEPLOY_SECONDS=180
WAIT_REPLACEMENT_SECONDS=90

# ── State for cleanup ───────────────────────────────────────────────────────
PF_PID=""

cleanup() {
    info "cleanup: stopping port-forward and removing ${APP_NAME} resources"
    if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
    pkill -f "kubectl port-forward service/${APP_NAME}" 2>/dev/null || true
    kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true \
        >/dev/null 2>&1 || true
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

# ── Port-forward ────────────────────────────────────────────────────────────
step "port-forwarding service/${APP_NAME} to 127.0.0.1:${LOCAL_PORT}"
kubectl port-forward "service/${APP_NAME}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
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
pass "port-forward listening on :${LOCAL_PORT}"

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

# The port-forward typically dies with the old Pod (kubectl
# port-forward attaches to a specific Pod, not the Service). Kill
# it now so we don't leak the process.
if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
fi
PF_PID=""

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

# ── Re-establish port-forward to the new Pod and re-curl ────────────────────
step "re-establishing port-forward to the new Pod"
kubectl port-forward "service/${APP_NAME}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
for _ in {1..15}; do
    if curl -fsS --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! kill -0 "${PF_PID}" 2>/dev/null; then
    fail "port-forward did not re-attach to new Pod"
fi
pass "port-forward reconnected to ${NEW_POD}"

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
