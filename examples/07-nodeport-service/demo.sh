#!/usr/bin/env bash
#
# examples/07-nodeport-service/demo.sh
#
# End-to-end smoke test for §7:
#   1. ensure cluster is up
#   2. ensure nginx-custom:v1 is in the cluster's image cache; if
#      not, build it automatically from §6's Containerfile (so this
#      demo is runnable without having run §6's demo first)
#   3. clear any prior nginx-np Deployment/Service
#   4. apply manifests
#   5. wait for Deployment Available (with log-dump-on-timeout)
#   6. retrieve URL via `minikube service nginx-np --url`
#   7. curl the URL, check for the sentinel string
#   8. clean up Deployment + Service on exit (success or failure)
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

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    info "cleanup: removing ${APP_NAME} Deployment and Service"
    kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true \
        >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Pre-flight: cluster up ──────────────────────────────────────────────────
step "pre-flight: cluster is up and kubectl can reach it"
if ! minikube status >/dev/null 2>&1; then
    info "no cluster running; starting default profile"
    minikube start
fi
kubectl get nodes >/dev/null
pass "cluster reachable"

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

# ── Retrieve URL via minikube service ───────────────────────────────────────
step "retrieving NodePort URL via 'minikube service ${APP_NAME} --url'"
# minikube service can take a few seconds to find the endpoint right
# after the Deployment becomes Available; poll a few times.
URL=""
for _ in {1..10}; do
    URL=$(minikube service "${APP_NAME}" --url 2>/dev/null | head -1 || true)
    if [[ -n "${URL}" ]]; then
        break
    fi
    sleep 1
done
if [[ -z "${URL}" ]]; then
    info "minikube service output (full):"
    minikube service "${APP_NAME}" --url 2>&1 | sed 's/^/    /' || true
    fail "minikube service did not return a URL within 10 attempts"
fi
info "NodePort URL: ${URL}"
pass "URL retrieved"

# ── Curl the URL ────────────────────────────────────────────────────────────
step "curling NodePort URL ${URL}/"
# Poll briefly — kube-proxy can take a moment to wire up after Deployment Available
RESP=""
for _ in {1..15}; do
    if RESP=$(curl -fsS --max-time 3 "${URL}/" 2>/dev/null); then
        break
    fi
    sleep 1
done
if [[ -z "${RESP}" ]]; then
    fail "curl never got a response from ${URL}/"
fi
case "${RESP}" in
    *"Test Page for nginx on UBI 9 Minimal"*)
        pass "nginx served the baked-in index.html via NodePort"
        ;;
    *)
        info "unexpected response (first 200 chars):"
        echo "${RESP:0:200}" | sed 's/^/    /'
        fail "response did not match the sentinel string"
        ;;
esac

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — NodePort Service exposes ${APP_NAME} at ${URL}"
echo
echo "  This URL is host-reachable directly (no kubectl port-forward)."
echo "  Cleanup on exit removes the Deployment and Service; the image"
echo "  stays cached for the next demo."
echo
exit 0
