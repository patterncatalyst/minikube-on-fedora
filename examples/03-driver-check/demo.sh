#!/usr/bin/env bash
#
# examples/03-driver-check/demo.sh
#
# Smoke test for the §3 happy path:
#   1. start minikube on the `driver-check` profile (docker driver, containerd)
#   2. verify the driver, runtime and published port, and that minikube
#      status reports all components Running
#   3. verify kubectl can list nodes and system pods
#   4. tear down on exit (success or failure)
#
# Idempotent: deletes any existing driver-check profile before
# starting, so re-running from a half-dead state works cleanly.
#
# Exit codes: 0 on full pass, non-zero on any step failure.

set -euo pipefail

# ── Resolve the repo's shared helpers regardless of cwd ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
PROFILE="driver-check"
# KUBE_VERSION and DRIVER_CHECK_PORTS come from scripts/lib/_helpers.sh
CPUS="${CPUS:-4}"
MEMORY_MB="${MEMORY_MB:-8192}"
NODE_WAIT_SECONDS=120
POD_WAIT_SECONDS=180

# ── Cleanup trap ────────────────────────────────────────────────────────────
cleanup() {
    info "cleanup: deleting profile ${PROFILE}"
    minikube delete -p "${PROFILE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Pre-flight ──────────────────────────────────────────────────────────────
step "pre-flight: required tools on PATH"
command -v minikube >/dev/null 2>&1 || fail "minikube not on PATH — see §2"
command -v kubectl  >/dev/null 2>&1 || fail "kubectl not on PATH — see §2"
command -v jq       >/dev/null 2>&1 || fail "jq not on PATH — see §1"
pass "minikube, kubectl, jq present"

step "pre-flight: Docker Engine"
require_docker_engine

step "pre-flight: clear any pre-existing ${PROFILE} profile"
minikube delete -p "${PROFILE}" >/dev/null 2>&1 || true
pass "no stale ${PROFILE} profile"

# ── Start ───────────────────────────────────────────────────────────────────
step "starting cluster (profile=${PROFILE}, driver=docker, runtime=containerd, k8s=${KUBE_VERSION})"
minikube start \
    --profile "${PROFILE}" \
    --driver=docker \
    --container-runtime=containerd \
    --delete-on-failure \
    --cpus="${CPUS}" \
    --memory="${MEMORY_MB}" \
    --kubernetes-version="${KUBE_VERSION}" \
    --ports="${DRIVER_CHECK_PORTS}" \
    --wait=all

pass "minikube start completed"

# ── Verify ──────────────────────────────────────────────────────────────────
step "checking driver, container runtime and published port"
driver=$(minikube profile list -o json \
    | jq -r --arg n "${PROFILE}" '.valid[] | select(.Name == $n) | .Config.Driver')
runtime=$(minikube profile list -o json \
    | jq -r --arg n "${PROFILE}" '.valid[] | select(.Name == $n) | .Config.KubernetesConfig.ContainerRuntime')
[[ "${driver}" == "docker" ]] || fail "driver is '${driver}', expected docker"
[[ "${runtime}" == "containerd" ]] || fail "container runtime is '${runtime}', expected containerd"
require_published_port "${PROFILE}" 30079 18079
published=$(docker port "${PROFILE}" 30079/tcp)
echo "    docker port ${PROFILE} 30079/tcp -> ${published}"
node_rt=$(kubectl --context "${PROFILE}" get nodes \
    -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')
[[ "${node_rt}" == containerd://* ]] || fail "node containerRuntimeVersion is '${node_rt}', expected containerd://..."
pass "driver=docker, runtime=${node_rt}, 127.0.0.1:18079 -> nodePort 30079"

step "checking minikube status"
status_out=$(minikube status -p "${PROFILE}" || true)
echo "${status_out}" | sed 's/^/    /'
# All four lines should report Running / Configured
for component in host kubelet apiserver; do
    case "${status_out}" in
        *"${component}: Running"*) ;;
        *) fail "${component} is not Running in minikube status" ;;
    esac
done
case "${status_out}" in
    *"kubeconfig: Configured"*) ;;
    *) fail "kubeconfig is not Configured in minikube status" ;;
esac
pass "minikube status: host/kubelet/apiserver Running, kubeconfig Configured"

step "waiting for node to report Ready"
if ! kubectl --context "${PROFILE}" wait --for=condition=Ready node --all \
       --timeout="${NODE_WAIT_SECONDS}s" >/dev/null; then
    fail "node did not reach Ready within ${NODE_WAIT_SECONDS}s"
fi
kubectl --context "${PROFILE}" get nodes -o wide | sed 's/^/    /'
pass "node Ready"

step "waiting for kube-system pods to be Running/Completed"
if ! kubectl --context "${PROFILE}" wait --for=condition=Ready pod \
       -n kube-system --all --timeout="${POD_WAIT_SECONDS}s" >/dev/null; then
    info "kube-system pod state at timeout:"
    kubectl --context "${PROFILE}" get pods -n kube-system | sed 's/^/    /'
    fail "kube-system pods did not all become Ready within ${POD_WAIT_SECONDS}s"
fi
kubectl --context "${PROFILE}" get pods -n kube-system | sed 's/^/    /'
pass "all kube-system pods Ready"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — minikube + kubectl + docker driver + containerd + published port all working"
echo
echo "  The driver-check profile will be torn down momentarily."
echo "  To work with minikube interactively, create the default profile with"
echo "  its published ports (§3):"
echo "    minikube start -p minikube --driver=docker --container-runtime=containerd \\"
echo "      --kubernetes-version=$KUBE_VERSION --cpus=6 --memory=16384 \\"
echo "      --ports=$CORE_PORTS"
echo
exit 0
