#!/usr/bin/env bash
#
# examples/07-nodeport-service/demo.sh
#
# End-to-end smoke test for §7:
#   1. ensure the Docker Engine, the default profile and its published
#      ports are in place (nodePort 30808 -> 127.0.0.1:18081)
#   2. ensure nginx-custom:v1 is loaded in the cluster; if not,
#      build it from §6's Containerfile and load it automatically
#   3. clear any prior nginx-np Deployment/Service
#   4. apply manifests
#   5. wait for Deployment Available (with log-dump-on-timeout)
#   6. confirm the node publishes nodePort 30808 on 127.0.0.1:18081
#   7. curl http://127.0.0.1:18081/, check for the sentinel string
#   8. clean up Deployment + Service on exit
#
# Uses your default minikube cluster. The image nginx-custom:v1
# stays cached across runs; cluster stays running for next demo.

set -euo pipefail

# ── Resolve repo's shared helpers regardless of cwd ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
APP_NAME="nginx-np"
IMAGE_TAG="nginx-custom:v1"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
SECTION6_DIR="${REPO_ROOT}/examples/06-deploy-nginx-kubectl"
WAIT_DEPLOY_SECONDS=180
NODE_PORT=30808
HOST_PORT=18081
URL="http://127.0.0.1:${HOST_PORT}"
PROFILE="minikube"
CPUS=6
MEMORY_MB=16384

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    info "cleanup: removing ${APP_NAME} resources"
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
pass "${IMAGE_TAG} available in cluster"

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
step "applying ${APP_NAME} Deployment and NodePort Service"
kubectl apply -f "${MANIFESTS_DIR}/"
pass "manifests applied"

# ── Wait for Deployment ─────────────────────────────────────────────────────
step "waiting for Deployment to be Available (up to ${WAIT_DEPLOY_SECONDS}s)"
if ! kubectl wait --for=condition=Available "deployment/${APP_NAME}" \
        --timeout="${WAIT_DEPLOY_SECONDS}s" >/dev/null; then
    info "Deployment status:"
    kubectl describe "deployment/${APP_NAME}" | sed 's/^/    /'
    info "Pod status:"
    kubectl get pods -l "app=${APP_NAME}" | sed 's/^/    /'
    info "Pod logs (current and previous container if restarted):"
    for pod in $(kubectl get pods -l "app=${APP_NAME}" \
                   -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        echo "    ----- ${pod} (current container) -----"
        kubectl logs "${pod}" --tail=30 2>&1 | sed 's/^/    /' || true
        echo "    ----- ${pod} (previous container, if restarted) -----"
        kubectl logs "${pod}" --tail=30 --previous 2>&1 | sed 's/^/    /' || true
    done
    fail "Deployment did not become Available within ${WAIT_DEPLOY_SECONDS}s"
fi
kubectl get deployment,pods -l "app=${APP_NAME}" | sed 's/^/    /'
pass "Deployment Available"

# ── Published NodePort ──────────────────────────────────────────────────────
# The mapping 127.0.0.1:18081 -> nodePort 30808 was fixed when the profile
# was created (--ports in CORE_PORTS); nothing runs in the foreground here.
step "checking nodePort ${NODE_PORT} is published on 127.0.0.1:${HOST_PORT}"
require_published_port "${PROFILE}" "${NODE_PORT}" "${HOST_PORT}"
info "kubectl get svc ${APP_NAME}:"
kubectl get svc "${APP_NAME}" | sed 's/^/    /'
pass "nodePort ${NODE_PORT} published on 127.0.0.1:${HOST_PORT}"

# ── Curl the URL ────────────────────────────────────────────────────────────
step "curling NodePort URL ${URL}/"
RESP=""
for _ in {1..30}; do
    if RESP=$(curl -fsS --max-time 3 "${URL}/" 2>/dev/null); then
        break
    fi
    sleep 1
done
if [[ -z "${RESP}" ]]; then
    info "Service and endpoints:"
    kubectl get svc,endpoints "${APP_NAME}" | sed 's/^/    /'
    fail "curl never got a response from ${URL}/"
fi
case "${RESP}" in
    *"Test Page for nginx on UBI 10 Minimal"*)
        pass "nginx served the baked-in index.html via the published NodePort"
        ;;
    *)
        info "unexpected response (first 200 chars):"
        echo "${RESP:0:200}" | sed 's/^/    /'
        fail "response did not match the sentinel string"
        ;;
esac

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — NodePort Service for ${APP_NAME} reachable at ${URL}"
echo
echo "  The NodePort was published when the profile was created:"
echo "    --ports=127.0.0.1:${HOST_PORT}:${NODE_PORT}  (host :${HOST_PORT} -> node :${NODE_PORT})"
echo "  Nothing runs in the foreground. Cleanup on exit removes"
echo "  Deployment/Service; the image stays loaded for the next demo."
echo
exit 0
