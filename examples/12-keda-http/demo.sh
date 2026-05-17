#!/usr/bin/env bash
#
# examples/12-keda-http/demo.sh
#
# Demonstrates KEDA scale-from-zero on HTTP traffic via the KEDA
# HTTP add-on (BETA at v0.12.2 — see §12 prose).
#
# Phases:
#   1.  Pre-flight: minikube up, KEDA + HTTP add-on installed
#   2.  Build nginx-custom:v1 if not cached (reuses §6's Containerfile)
#   3.  Apply nginx Deployment (replicas: 0) + Service + HTTPScaledObject
#   4.  Assert nginx is at 0 replicas
#   5.  Port-forward the HTTP add-on interceptor to 127.0.0.1:18080
#   6.  Fire one request (Host: nginx.local) — interceptor buffers
#       until the Pod is up. First request takes a few seconds
#       (cold-start)
#   7.  Run `hey -n 500 -c 50` to drive sustained load
#   8.  Watch replicas climb (assert >= 1)
#   9.  Wait for load to finish + scaledownPeriod for scale-down
#   10. Assert replicas = 0
#
# Idempotent — image cache + KEDA install survive cleanup.

set -euo pipefail

# ── Repo helpers ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
PROFILE_NAME="minikube"
IMAGE_TAG="nginx-custom:v1"
SECTION6_DIR="${REPO_ROOT}/examples/06-deploy-nginx-kubectl"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
INTERCEPTOR_PORT=18080
HOST_HEADER="nginx.local"
LOAD_REQUESTS=500
LOAD_CONCURRENCY=50
SCALEUP_TIMEOUT=120
SCALEDOWN_TIMEOUT=120

# ── State for cleanup ───────────────────────────────────────────────────────
PF_PID=""

cleanup() {
    info "cleanup: stopping port-forward + removing nginx + HTTPScaledObject"
    if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
    pkill -f "kubectl port-forward.*keda-add-ons-http-interceptor" 2>/dev/null || true
    kubectl delete -f "${MANIFESTS_DIR}/http-scaled-object.yaml" \
        --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl delete -f "${MANIFESTS_DIR}/nginx-deployment.yaml" \
        --ignore-not-found=true >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Phase 1: Pre-flight ─────────────────────────────────────────────────────
step "pre-flight: minikube up, KEDA + HTTP add-on installed"
kubectl config use-context "${PROFILE_NAME}" >/dev/null 2>&1 || \
    fail "kubectl context '${PROFILE_NAME}' not configured"
kubectl get nodes >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
pass "minikube cluster reachable"

if ! kubectl get deployment keda-operator -n keda >/dev/null 2>&1; then
    fail "KEDA core not found — run ./scripts/setup-keda.sh first"
fi
if ! kubectl get deployment keda-add-ons-http-interceptor -n keda >/dev/null 2>&1; then
    fail "KEDA HTTP add-on not found — run ./scripts/setup-keda.sh first"
fi
pass "KEDA + HTTP add-on present in 'keda' namespace"

command -v hey >/dev/null 2>&1 || fail "hey not in PATH — see §2 (go install)"

# ── Phase 2: Ensure nginx-custom image is cached ────────────────────────────
step "ensuring ${IMAGE_TAG} is in the minikube profile's image cache"
if ! minikube image ls -p "${PROFILE_NAME}" 2>/dev/null | grep -q "${IMAGE_TAG}"; then
    info "image not present; building from §6's Containerfile"
    if [[ ! -f "${SECTION6_DIR}/Containerfile" ]]; then
        fail "${SECTION6_DIR}/Containerfile not found — examples/06 missing?"
    fi
    minikube -p "${PROFILE_NAME}" image build -t "${IMAGE_TAG}" \
        -f Containerfile "${SECTION6_DIR}"
fi
pass "${IMAGE_TAG} available"

# ── Phase 3: Apply Deployment + Service + HTTPScaledObject ──────────────────
step "applying nginx Deployment + Service + HTTPScaledObject"
kubectl apply -f "${MANIFESTS_DIR}/nginx-deployment.yaml"
kubectl apply -f "${MANIFESTS_DIR}/http-scaled-object.yaml"
sleep 3
pass "manifests applied"

# ── Phase 4: Assert initial replicas = 0 ────────────────────────────────────
step "asserting nginx is at 0 replicas (no traffic yet)"
INITIAL_REPLICAS=$(kubectl get deployment nginx-http -o jsonpath='{.spec.replicas}')
info "current replicas: ${INITIAL_REPLICAS}"
if [[ "${INITIAL_REPLICAS}" != "0" ]]; then
    fail "expected 0 replicas before HTTP traffic, got ${INITIAL_REPLICAS}"
fi
pass "nginx at 0 replicas"

# ── Phase 5: Port-forward the HTTP interceptor ──────────────────────────────
step "port-forwarding HTTP add-on interceptor to 127.0.0.1:${INTERCEPTOR_PORT}"
kubectl port-forward -n keda service/keda-add-ons-http-interceptor-proxy \
    "${INTERCEPTOR_PORT}:8080" >/dev/null 2>&1 &
PF_PID=$!
for _ in {1..30}; do
    if curl -fsS --max-time 2 "http://127.0.0.1:${INTERCEPTOR_PORT}/" \
            -H "Host: ${HOST_HEADER}" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! kill -0 "${PF_PID}" 2>/dev/null; then
    fail "port-forward died before becoming reachable"
fi
pass "interceptor reachable"

# ── Phase 6: Cold-start request ─────────────────────────────────────────────
step "firing single cold-start request — interceptor will buffer until Pod is ready"
COLD_START_BEGIN=$(date +%s)
RESP=$(curl -fsS --max-time 60 "http://127.0.0.1:${INTERCEPTOR_PORT}/" \
    -H "Host: ${HOST_HEADER}" 2>/dev/null || echo "")
COLD_START_S=$(( $(date +%s) - COLD_START_BEGIN ))
info "cold-start request took ${COLD_START_S}s"
case "${RESP}" in
    *"Test Page"*|*"<html"*|*"<!doctype"*)
        pass "cold-start succeeded (HTML response received after ${COLD_START_S}s)"
        ;;
    *)
        info "response (first 200 chars):"
        echo "${RESP:0:200}" | sed 's/^/    /'
        fail "cold-start did not return expected response"
        ;;
esac

# ── Phase 7: Drive load with hey ────────────────────────────────────────────
step "driving load: hey -n ${LOAD_REQUESTS} -c ${LOAD_CONCURRENCY}"
# Run hey in background so we can watch replicas during the load
hey -n "${LOAD_REQUESTS}" -c "${LOAD_CONCURRENCY}" \
    -H "Host: ${HOST_HEADER}" \
    "http://127.0.0.1:${INTERCEPTOR_PORT}/" > /tmp/hey-output.txt 2>&1 &
HEY_PID=$!
info "hey running as PID ${HEY_PID}; watching replicas..."

# ── Phase 8: Watch replicas climb ───────────────────────────────────────────
PEAK_REPLICAS=0
SCALED_UP=""
for i in $(seq 1 "${SCALEUP_TIMEOUT}"); do
    if ! kill -0 "${HEY_PID}" 2>/dev/null; then
        info "[${i}s] hey finished; final replica check"
        break
    fi
    R=$(kubectl get deployment nginx-http -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [[ "${R}" -gt "${PEAK_REPLICAS}" ]]; then
        PEAK_REPLICAS="${R}"
        info "[${i}s] replicas climbed to ${R}"
    fi
    if [[ "${R}" -ge 1 && -z "${SCALED_UP}" ]]; then
        SCALED_UP="yes"
    fi
    sleep 1
done

wait "${HEY_PID}" 2>/dev/null || true
HEY_SUMMARY=$(tail -20 /tmp/hey-output.txt | grep -E "Summary|Total:|Requests/sec:|Status code distribution" -A 5 || tail -10 /tmp/hey-output.txt)
info "hey summary:"
echo "${HEY_SUMMARY}" | sed 's/^/    /'

if [[ -z "${SCALED_UP}" ]]; then
    info "nginx never scaled up. HTTPScaledObject status:"
    kubectl describe httpscaledobject nginx-http-scaler 2>/dev/null | sed 's/^/    /' || true
    info "HTTP add-on operator logs:"
    kubectl logs -n keda deployment/keda-add-ons-http-controller-manager --tail=30 \
        2>/dev/null | sed 's/^/    /' || true
    fail "KEDA HTTP add-on did not scale nginx up"
fi
pass "nginx scaled up — peak replicas: ${PEAK_REPLICAS}"

# ── Phase 9: Wait for scale-down ────────────────────────────────────────────
step "waiting for KEDA to scale down to 0 (scaledownPeriod=30s, allow up to ${SCALEDOWN_TIMEOUT}s)"
FINAL_REPLICAS=""
for i in $(seq 1 "${SCALEDOWN_TIMEOUT}"); do
    R=$(kubectl get deployment nginx-http -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
    if [[ "${R}" == "0" ]]; then
        FINAL_REPLICAS="${R}"
        info "[${i}s] scaled back to 0 replicas"
        break
    fi
    if [[ $((i % 10)) -eq 0 ]]; then
        info "[${i}s] replicas = ${R}, waiting..."
    fi
    sleep 1
done
if [[ "${FINAL_REPLICAS}" != "0" ]]; then
    fail "nginx did not scale back to 0 within ${SCALEDOWN_TIMEOUT}s"
fi
pass "nginx back at 0 replicas"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — KEDA scale-from-zero on HTTP traffic verified"
echo
echo "  Workload:        nginx-http (nginx-custom:v1)"
echo "  Trigger:         HTTP request concurrency"
echo "  Cold-start:      ${COLD_START_S}s (interceptor buffered until Pod ready)"
echo "  Lifecycle:       0 → ${PEAK_REPLICAS} → 0 replicas"
echo "  Load test:       ${LOAD_REQUESTS} requests at concurrency ${LOAD_CONCURRENCY}"
echo
echo "  Cleanup on exit removes nginx Deployment + Service +"
echo "  HTTPScaledObject. KEDA + HTTP add-on stay installed."
echo
exit 0
