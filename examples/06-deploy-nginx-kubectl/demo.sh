#!/usr/bin/env bash
#
# examples/06-deploy-nginx-kubectl/demo.sh
#
# End-to-end smoke test for §6:
#   1. ensure cluster is up; clear any prior nginx Deployment/Service
#   2. build the nginx image with `minikube image build` (multi-stage
#      Containerfile, UBI 9 builder → UBI 9 Minimal runtime)
#   3. apply Deployment + Service manifests
#   4. wait for the Deployment to be Available; on timeout, dump pod
#      logs from current and previous containers for diagnosis
#   5. port-forward the Service to a host port in the 1808x range
#   6. curl the host port; check for the sentinel content baked
#      into the image
#   7. scale the Deployment to 3 replicas; verify all Ready
#   8. clean up port-forward + manifests on exit (success or failure)
#
# Uses the default minikube cluster (NOT a separate profile, unlike
# examples/03-driver-check/) — leaves the cluster running for the
# next demo. The built image stays in the cluster's local image cache
# across runs (cached for fast re-runs); to force a rebuild from
# scratch, run `minikube image rm nginx-custom:v1` before re-running.
#
# Exit codes: 0 on full pass, non-zero on any step failure.

set -euo pipefail

# ── Resolve repo's shared helpers regardless of cwd ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
APP_NAME="nginx"
IMAGE_TAG="nginx-custom:v1"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
HOST_PORT=18080
WAIT_DEPLOY_SECONDS=180
WAIT_SCALE_SECONDS=120
PORT_FORWARD_TIMEOUT=30
PORT_FORWARD_PID=""

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    info "cleanup: stopping port-forward and removing nginx resources"
    if [[ -n "${PORT_FORWARD_PID}" ]]; then
        kill "${PORT_FORWARD_PID}" 2>/dev/null || true
        wait "${PORT_FORWARD_PID}" 2>/dev/null || true
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

# ── Pre-flight: clear any leftover state from previous runs ─────────────────
step "pre-flight: remove any prior ${APP_NAME} Deployment/Service"
kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true >/dev/null 2>&1 || true
# Wait briefly for terminating pods to actually finish, so the next apply
# doesn't race with old pods still going away.
for _ in {1..15}; do
    if ! kubectl get pods -l app="${APP_NAME}" 2>/dev/null | grep -q Terminating; then
        break
    fi
    sleep 1
done
pass "no stale ${APP_NAME} resources"

# ── Build the image inside minikube ─────────────────────────────────────────
step "building ${IMAGE_TAG} via minikube image build (multi-stage UBI 9)"
# `minikube image build` runs the build inside the cluster's runtime so the
# resulting image is immediately available to kubelet without needing a
# registry push. -f specifies the Containerfile (default lookup is Dockerfile).
if ! minikube image build -t "${IMAGE_TAG}" -f Containerfile "${SCRIPT_DIR}"; then
    fail "minikube image build failed (see output above)"
fi
pass "${IMAGE_TAG} built and available in cluster"

# ── Apply manifests ─────────────────────────────────────────────────────────
step "applying nginx Deployment and Service"
kubectl apply -f "${MANIFESTS_DIR}/"
pass "manifests applied"

# ── Wait for Deployment to be Available ─────────────────────────────────────
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

# ── Port-forward to the Service ─────────────────────────────────────────────
step "port-forwarding service/${APP_NAME} to 127.0.0.1:${HOST_PORT}"
kubectl port-forward "service/${APP_NAME}" "${HOST_PORT}:80" >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait for the port to actually be listening before we curl it.
listening=0
for ((i = 0; i < PORT_FORWARD_TIMEOUT; i++)); do
    if curl -fsS "http://127.0.0.1:${HOST_PORT}/" >/dev/null 2>&1; then
        listening=1
        break
    fi
    sleep 1
done
if [[ "${listening}" -ne 1 ]]; then
    if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
        info "(port-forward process is no longer running)"
    fi
    fail "port-forward never started listening within ${PORT_FORWARD_TIMEOUT}s"
fi
pass "port-forward listening on :${HOST_PORT}"

# ── Validate response ───────────────────────────────────────────────────────
step "validating nginx HTTP response (looking for sentinel string)"
RESP=$(curl -fsS "http://127.0.0.1:${HOST_PORT}/")
# Sentinel content from index.html that confirms we're serving our
# baked-in page (not some default upstream nginx welcome).
case "${RESP}" in
    *"Test Page for nginx on UBI 9 Minimal"*)
        pass "nginx served the baked-in index.html"
        ;;
    *)
        info "unexpected response (first 200 chars):"
        echo "${RESP:0:200}" | sed 's/^/    /'
        fail "response did not match the sentinel string"
        ;;
esac

# ── Scale up ────────────────────────────────────────────────────────────────
step "scaling Deployment to 3 replicas"
kubectl scale "deployment/${APP_NAME}" --replicas=3 >/dev/null
if ! kubectl wait --for=condition=Available "deployment/${APP_NAME}" \
        --timeout="${WAIT_SCALE_SECONDS}s" >/dev/null; then
    info "Pod status after scale:"
    kubectl get pods -l "app=${APP_NAME}" | sed 's/^/    /'
    fail "Deployment did not return to Available within ${WAIT_SCALE_SECONDS}s after scale"
fi
pod_count=$(kubectl get pods -l "app=${APP_NAME}" --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
if [[ "${pod_count}" -ne 3 ]]; then
    info "Pod status:"
    kubectl get pods -l "app=${APP_NAME}" | sed 's/^/    /'
    fail "expected 3 Running pods after scale; got ${pod_count}"
fi
kubectl get pods -l "app=${APP_NAME}" | sed 's/^/    /'
pass "scaled to 3 replicas, all Running"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — image built + Deployment + Service + port-forward + scaling all working"
echo
echo "  Cleanup will run automatically on script exit:"
echo "    - kubectl port-forward backgrounded process killed"
echo "    - nginx Deployment and Service deleted"
echo "  Persists across runs:"
echo "    - ${IMAGE_TAG} image stays in the cluster's image cache"
echo "      (force rebuild: minikube image rm ${IMAGE_TAG})"
echo "    - the minikube cluster itself stays up for the next demo"
echo
exit 0
