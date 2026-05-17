#!/usr/bin/env bash
#
# examples/07-nodeport-service/demo.sh
#
# End-to-end smoke test for §7:
#   1. ensure cluster is up
#   2. ensure nginx-custom:v1 is in the cluster's image cache; if
#      not, build it from §6's Containerfile automatically
#   3. clear any prior nginx-np Deployment/Service
#   4. apply manifests
#   5. wait for Deployment Available (with log-dump-on-timeout)
#   6. start `minikube service --url` in the background and watch
#      its output for the tunnel URL — under rootless podman the
#      cluster IP isn't host-routable, so minikube auto-tunnels and
#      prints a 127.0.0.1:<random-port> URL once the tunnel is up
#   7. curl the URL, check for the sentinel string
#   8. clean up Deployment + Service + tunnel on exit
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
TUNNEL_WAIT_SECONDS=90

# ── State that cleanup() needs to see (declared globally) ───────────────────
TUNNEL_PID=""
TUNNEL_LOG=""

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    info "cleanup: stopping tunnel and removing ${APP_NAME} resources"
    if [[ -n "${TUNNEL_PID}" ]] && kill -0 "${TUNNEL_PID}" 2>/dev/null; then
        kill "${TUNNEL_PID}" 2>/dev/null || true
        wait "${TUNNEL_PID}" 2>/dev/null || true
    fi
    # Some `minikube service` builds spawn children (kubectl
    # port-forward under the hood); sweep any lingering ones.
    pkill -f "minikube service ${APP_NAME}" 2>/dev/null || true
    if [[ -n "${TUNNEL_LOG}" && -f "${TUNNEL_LOG}" ]]; then
        rm -f "${TUNNEL_LOG}"
    fi
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

# ── Start tunnel via 'minikube service --url' (background) ──────────────────
# Under rootless podman, the cluster's node IP (192.168.49.2) lives
# in a user network namespace and isn't host-routable, so minikube
# auto-starts a tunnel via kubectl port-forward equivalent and
# prints http://127.0.0.1:<random-port>. We run it in the background
# and watch the log file for the URL line, then kill on cleanup.
step "starting tunnel via 'minikube service ${APP_NAME} --url' (background)"
TUNNEL_LOG="$(mktemp)"
minikube service "${APP_NAME}" --url > "${TUNNEL_LOG}" 2>&1 &
TUNNEL_PID=$!
info "tunnel PID: ${TUNNEL_PID}, log: ${TUNNEL_LOG}"

# Poll the log file for an http:// line. Tunnel setup typically
# takes 20-30s on rootless podman the first time.
URL=""
for i in $(seq 1 "${TUNNEL_WAIT_SECONDS}"); do
    # Check if the tunnel process died unexpectedly
    if ! kill -0 "${TUNNEL_PID}" 2>/dev/null; then
        info "tunnel process exited unexpectedly; output:"
        sed 's/^/    /' "${TUNNEL_LOG}"
        fail "minikube service exited before printing a URL"
    fi
    URL=$(grep -m1 '^http://' "${TUNNEL_LOG}" 2>/dev/null || true)
    if [[ -n "${URL}" ]]; then
        info "tunnel ready after ${i}s"
        break
    fi
    sleep 1
done

if [[ -z "${URL}" ]]; then
    info "tunnel still establishing after ${TUNNEL_WAIT_SECONDS}s; log so far:"
    sed 's/^/    /' "${TUNNEL_LOG}"
    fail "minikube service did not print a URL within ${TUNNEL_WAIT_SECONDS}s"
fi

info "NodePort URL (via auto-tunnel): ${URL}"
pass "tunnel established"

# ── Curl the URL ────────────────────────────────────────────────────────────
step "curling NodePort URL ${URL}/"
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
        pass "nginx served the baked-in index.html via NodePort tunnel"
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
echo "  Under rootless podman, minikube auto-tunneled the NodePort to"
echo "  a localhost port (the cluster IP isn't host-routable from the"
echo "  user network namespace). With rootful podman or kvm2 the URL"
echo "  would be http://<minikube ip>:30808 directly — no tunnel."
echo "  Cleanup on exit kills the tunnel and removes Deployment/Service;"
echo "  the image stays cached for the next demo."
echo
exit 0
