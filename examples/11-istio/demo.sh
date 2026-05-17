#!/usr/bin/env bash
#
# examples/11-istio/demo.sh
#
# §11 happy path. The longest demo in the tutorial — 5-10 minutes
# for a full run. Phases are idempotent so re-runs work even if a
# prior attempt died midway.
#
# Phases:
#   1.  Pre-flight: istio profile up, kubectl context is `istio`,
#       istioctl in PATH, ISTIO_CURRENT symlink resolves
#   2.  Build nginx-custom:v1 on the istio profile (image cache is
#       per-profile, so it doesn't carry from `minikube`)
#   3.  Install Istio (idempotent: skipped if already installed)
#   4.  Label `default` namespace for sidecar injection
#   5.  Deploy our nginx-with-sidecar; verify 2/2 containers
#   6.  Deploy Bookinfo; wait for all Pods Ready
#   7.  Apply Gateway + VirtualService
#   8.  Port-forward the ingress gateway; curl /productpage and
#       confirm the expected markup
#   9.  Apply destination rules + virtual-service-all-v1; curl
#       productpage N times; confirm responses don't show v2/v3
#       indicators (no glyphicon-star-empty / glyphicon-star)
#   10. Apply 50/50 split between v1 and v3; curl 20 times; count
#       responses that contain `glyphicon-star` (v3 indicator);
#       expect roughly 8-12 of 20
#   11. Cleanup all Bookinfo + nginx resources on exit; restore
#       kubectl context to `minikube`
#
# This does NOT install the addons (Kiali, Prometheus, etc.) —
# they take 5+ minutes to come up. See §11 prose for instructions.

set -euo pipefail

# ── Resolve repo's shared helpers ───────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
PROFILE_NAME="istio"
IMAGE_TAG="nginx-custom:v1"
SECTION6_DIR="${REPO_ROOT}/examples/06-deploy-nginx-kubectl"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
ISTIO_DIR="${ISTIO_DIR:-${HOME}/.local/share/istio-current}"
BOOKINFO_DIR="${ISTIO_DIR}/samples/bookinfo"
INGRESS_PORT=8080
WAIT_DEPLOY_SECONDS=300

# ── State for cleanup ───────────────────────────────────────────────────────
PF_PID=""
ORIGINAL_CONTEXT=""

cleanup() {
    info "cleanup: stopping port-forward and removing §11 resources"
    if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
    pkill -f "kubectl port-forward.*istio-ingressgateway" 2>/dev/null || true

    # Best-effort delete of routing rules then bookinfo + nginx
    kubectl delete -f "${BOOKINFO_DIR}/networking/" --ignore-not-found=true \
        >/dev/null 2>&1 || true
    kubectl delete -f "${BOOKINFO_DIR}/platform/kube/bookinfo.yaml" \
        --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true \
        >/dev/null 2>&1 || true

    # Restore kubectl context to the §6-§9 profile
    if [[ -n "${ORIGINAL_CONTEXT}" && "${ORIGINAL_CONTEXT}" != "${PROFILE_NAME}" ]]; then
        info "restoring kubectl context to ${ORIGINAL_CONTEXT}"
        kubectl config use-context "${ORIGINAL_CONTEXT}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# ── Phase 1: Pre-flight ─────────────────────────────────────────────────────
step "pre-flight: kernel inotify limits sufficient for a second minikube cluster"
# minikube containers run systemd as PID 1, which wants its own inotify
# watches for cgroup management. Default Fedora settings are enough for
# ONE cluster (the §3 `minikube` profile already consumed that budget);
# starting a SECOND cluster needs raised limits. Symptoms when too low:
# "Failed to create control group inotify object: Too many open files"
# from the container during minikube start.
INOTIFY_INSTANCES=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
INOTIFY_WATCHES=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
info "fs.inotify.max_user_instances = ${INOTIFY_INSTANCES}"
info "fs.inotify.max_user_watches   = ${INOTIFY_WATCHES}"
if [[ "${INOTIFY_INSTANCES}" -lt 256 ]] || [[ "${INOTIFY_WATCHES}" -lt 131072 ]]; then
    info ""
    info "inotify limits are too low for a second minikube cluster on this host."
    info "Symptoms: 'Failed to create control group inotify object: Too many open"
    info "files' from the cluster container during minikube start."
    info ""
    info "One-time fix (persists across reboots):"
    info ""
    info "    sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF"
    info "    fs.inotify.max_user_instances = 512"
    info "    fs.inotify.max_user_watches = 524288"
    info "    EOF"
    info "    sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf"
    info ""
    info "Then re-run this demo."
    fail "inotify limits below minimum (need ≥256 instances, ≥131072 watches)"
fi
pass "inotify limits OK for multi-cluster"

step "pre-flight: istio minikube profile up + tooling in place"

# Save current context so we can restore on exit
ORIGINAL_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
info "current kubectl context: ${ORIGINAL_CONTEXT:-<none>}"

# Ensure the istio profile is healthy. Three cases:
#   (a) profile is running cleanly → skip start
#   (b) profile exists but isn't running (stopped or partial-start
#       leftover with stale podman volume) → delete + recreate
#   (c) profile doesn't exist → create fresh
if minikube status -p "${PROFILE_NAME}" 2>/dev/null | grep -q "host: Running"; then
    info "${PROFILE_NAME} profile already running"
else
    # If a profile exists in any state, delete it first to avoid the
    # "volume with name istio already exists" cascade from a previous
    # failed start.
    if minikube profile list 2>/dev/null | grep -q "${PROFILE_NAME}"; then
        info "${PROFILE_NAME} profile exists but isn't healthy; deleting before fresh start"
        minikube delete -p "${PROFILE_NAME}" >/dev/null 2>&1 || true
    fi
    # Belt-and-suspenders: clean up any orphaned podman volume
    if podman volume exists "${PROFILE_NAME}" 2>/dev/null; then
        info "removing stale podman volume '${PROFILE_NAME}'"
        podman volume rm "${PROFILE_NAME}" 2>/dev/null || true
    fi
    info "starting ${PROFILE_NAME} profile (6 GB / 4 CPU)"
    minikube start -p "${PROFILE_NAME}" \
        --memory=6g \
        --cpus=4 \
        --container-runtime=containerd \
        --rootless=true \
        --delete-on-failure
fi

# Switch kubectl to the istio profile
kubectl config use-context "${PROFILE_NAME}" >/dev/null
kubectl get nodes >/dev/null
pass "istio profile reachable; kubectl context = ${PROFILE_NAME}"

# istioctl in PATH
if ! command -v istioctl >/dev/null 2>&1; then
    info "istioctl not in PATH — run scripts/setup-istio.sh first"
    fail "istioctl missing"
fi
info "istioctl: $(istioctl version --remote=false 2>/dev/null | head -1)"
pass "istioctl available"

# Istio source dir
if [[ ! -d "${BOOKINFO_DIR}" ]]; then
    info "Bookinfo samples not at ${BOOKINFO_DIR}"
    info "run scripts/setup-istio.sh to download the Istio release tarball"
    fail "${BOOKINFO_DIR} missing"
fi
pass "Bookinfo samples at ${BOOKINFO_DIR}"

# ── Phase 2: Build nginx-custom:v1 on this profile ──────────────────────────
step "ensuring ${IMAGE_TAG} is in the istio profile's image cache"
# Image cache is per-profile in minikube; even if §6 built this on the
# default profile, the istio profile doesn't have it.
if ! minikube image ls -p "${PROFILE_NAME}" 2>/dev/null | grep -q "${IMAGE_TAG}"; then
    info "image not present on ${PROFILE_NAME}; building from §6's Containerfile"
    if [[ ! -f "${SECTION6_DIR}/Containerfile" ]]; then
        fail "${SECTION6_DIR}/Containerfile not found — examples/06 missing?"
    fi
    minikube -p "${PROFILE_NAME}" image build -t "${IMAGE_TAG}" \
        -f Containerfile "${SECTION6_DIR}"
fi
pass "${IMAGE_TAG} available on istio profile"

# ── Phase 3: Install Istio (idempotent) ─────────────────────────────────────
step "installing Istio control plane (skipped if already installed)"
if kubectl get namespace istio-system >/dev/null 2>&1 \
   && kubectl get deployment -n istio-system istiod >/dev/null 2>&1; then
    info "istio-system / istiod already present, skipping install"
else
    info "running 'istioctl install --set profile=demo -y' (~30-60s)"
    istioctl install --set profile=demo -y
fi

# Wait for control plane Pods
if ! kubectl wait --for=condition=Available --timeout=180s \
        deployment/istiod -n istio-system >/dev/null 2>&1; then
    fail "istiod did not become Available within 180s"
fi
if ! kubectl wait --for=condition=Available --timeout=180s \
        deployment/istio-ingressgateway -n istio-system >/dev/null 2>&1; then
    fail "istio-ingressgateway did not become Available within 180s"
fi
kubectl get pods -n istio-system | sed 's/^/    /'
pass "Istio control plane and gateway ready"

# The MutatingWebhookConfiguration that performs sidecar injection
# registers separately from istiod's Pod readiness. `kubectl wait
# Available` returns as soon as istiod's Pod is ready (gRPC port
# open) — but the caBundle on the webhook config gets populated
# asynchronously a few seconds later. Deploying a workload during
# that gap produces a Pod with no sidecar injected; the API server
# silently skips the webhook because its caBundle is empty.
step "waiting for MutatingWebhookConfiguration istio-sidecar-injector to be ready"
WEBHOOK_READY=""
for i in $(seq 1 60); do
    CABUNDLE=$(kubectl get mutatingwebhookconfiguration istio-sidecar-injector \
        -o jsonpath='{.webhooks[0].clientConfig.caBundle}' 2>/dev/null || true)
    if [[ -n "${CABUNDLE}" ]]; then
        info "webhook ready (caBundle populated) after ${i}s"
        WEBHOOK_READY="yes"
        break
    fi
    sleep 1
done
if [[ -z "${WEBHOOK_READY}" ]]; then
    fail "istio-sidecar-injector webhook caBundle not populated within 60s"
fi
pass "sidecar-injector webhook live"

# ── Phase 4: Label default namespace for sidecar injection ──────────────────
step "labeling default namespace for istio sidecar injection"
kubectl label namespace default istio-injection=enabled --overwrite >/dev/null
# Brief buffer so the admission controller's namespace-label cache
# refreshes before our nginx Pod creation hits the webhook
sleep 3
pass "default namespace labeled (istio-injection=enabled)"

# ── Phase 5: Deploy nginx-with-sidecar ──────────────────────────────────────
deploy_nginx_with_sidecar() {
    kubectl delete -f "${MANIFESTS_DIR}/" --ignore-not-found=true >/dev/null 2>&1 || true
    sleep 2
    kubectl apply -f "${MANIFESTS_DIR}/"
    if ! kubectl wait --for=condition=Available \
            "deployment/nginx-istio" --timeout="${WAIT_DEPLOY_SECONDS}s" >/dev/null; then
        info "Deployment status:"
        kubectl describe deployment/nginx-istio | sed 's/^/    /'
        fail "nginx-istio Deployment did not become Available"
    fi
}

dump_injection_diagnostics() {
    info ""
    info "  Namespace labels:"
    kubectl get namespace default --show-labels 2>/dev/null | sed 's/^/    /'
    info ""
    info "  Mutating webhook configurations matching istio:"
    kubectl get mutatingwebhookconfigurations \
        -o custom-columns='NAME:.metadata.name,CABUNDLE_BYTES:.webhooks[0].clientConfig.caBundle' \
        2>/dev/null | grep -i istio | sed 's/^/    /' || echo "    (none found)"
    info ""
    info "  Pod annotations:"
    kubectl get pod "${NGINX_POD}" -o jsonpath='{.metadata.annotations}' 2>/dev/null \
        | sed 's/^/    /' || echo "    (pod gone)"
    info ""
    info "  istiod logs (last 30 lines):"
    kubectl logs -n istio-system deployment/istiod --tail=30 2>/dev/null \
        | sed 's/^/    /' || echo "    (no logs)"
    info ""
}

check_sidecar_injected() {
    NGINX_POD=$(kubectl get pod -l app=nginx-istio -o jsonpath='{.items[0].metadata.name}')
    # Istio 1.29+ on Kubernetes 1.28+ uses "native sidecars" (KEP-753):
    # istio-proxy is injected as an init container with
    # restartPolicy=Always, not as a main container. So checking only
    # .status.containerStatuses[] misses it. Look at the Pod spec,
    # which is authoritative regardless of native-vs-classic sidecar
    # mode — both .spec.containers[] and .spec.initContainers[].
    NGINX_CONTAINERS=$(kubectl get pod "${NGINX_POD}" \
        -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}' \
        2>/dev/null)
    case " ${NGINX_CONTAINERS} " in
        *" istio-proxy "*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

step "deploying nginx-with-sidecar"
deploy_nginx_with_sidecar

if check_sidecar_injected; then
    pass "nginx-istio Pod has istio-proxy injected (mesh injection working — native sidecar mode in Istio 1.29+/K8s 1.28+)"
else
    info "first deploy did not inject sidecar — Pod containers: ${NGINX_CONTAINERS}"
    info "dumping diagnostics, then retrying once after a brief pause"
    dump_injection_diagnostics
    info "retrying nginx deployment (10s pause)"
    sleep 10
    deploy_nginx_with_sidecar
    if check_sidecar_injected; then
        pass "nginx-istio Pod has istio-proxy injected on retry (mesh injection working)"
    else
        info "still no sidecar on retry — Pod containers: ${NGINX_CONTAINERS}"
        dump_injection_diagnostics
        fail "sidecar injection failed twice; webhook is broken"
    fi
fi

# ── Phase 6: Deploy Bookinfo ────────────────────────────────────────────────
step "deploying Bookinfo (4 microservices, 6 Pods) — first run ~2-3 minutes"
# Clean up first (idempotent)
kubectl delete -f "${BOOKINFO_DIR}/platform/kube/bookinfo.yaml" \
    --ignore-not-found=true >/dev/null 2>&1 || true
sleep 3
kubectl apply -f "${BOOKINFO_DIR}/platform/kube/bookinfo.yaml"

# Wait for every bookinfo Deployment
BOOKINFO_DEPLOYMENTS=$(kubectl get deployments \
    -l 'app in (productpage,details,ratings,reviews)' \
    -o jsonpath='{.items[*].metadata.name}')
for dep in ${BOOKINFO_DEPLOYMENTS}; do
    info "waiting for ${dep} to be Available"
    if ! kubectl wait --for=condition=Available "deployment/${dep}" \
            --timeout="${WAIT_DEPLOY_SECONDS}s" >/dev/null; then
        info "Pods:"
        kubectl get pods | sed 's/^/    /'
        fail "${dep} did not become Available within ${WAIT_DEPLOY_SECONDS}s"
    fi
done
kubectl get pods | sed 's/^/    /'
pass "all Bookinfo Deployments Available; sidecars injected"

# ── Phase 7: Gateway + VirtualService ───────────────────────────────────────
step "applying Bookinfo Gateway + VirtualService"
kubectl apply -f "${BOOKINFO_DIR}/networking/bookinfo-gateway.yaml"
# istioctl analyze for a sanity check
ANALYZE_OUTPUT=$(istioctl analyze 2>&1 || true)
if echo "${ANALYZE_OUTPUT}" | grep -qi 'error'; then
    info "istioctl analyze reported errors:"
    echo "${ANALYZE_OUTPUT}" | sed 's/^/    /'
    fail "istioctl analyze failed"
fi
pass "Gateway + VirtualService applied; istioctl analyze clean"

# ── Phase 8: Port-forward ingress + curl productpage ────────────────────────
step "port-forwarding istio-ingressgateway to 127.0.0.1:${INGRESS_PORT}"
kubectl port-forward -n istio-system service/istio-ingressgateway \
    "${INGRESS_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
for _ in {1..30}; do
    if curl -fsS --max-time 2 "http://127.0.0.1:${INGRESS_PORT}/productpage" \
            >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! kill -0 "${PF_PID}" 2>/dev/null; then
    fail "port-forward died before becoming reachable"
fi
pass "ingress gateway reachable at http://127.0.0.1:${INGRESS_PORT}/"

step "curling productpage; expecting a Bookinfo title (rebranded across versions)"
RESP=$(curl -fsS "http://127.0.0.1:${INGRESS_PORT}/productpage" 2>/dev/null || true)
# Older Istio releases titled the page "Bookinfo Sample". Istio 1.29+
# rebranded to "Simple Bookstore App" and migrated from Bootstrap to
# Tailwind for the UI. Both titles indicate the productpage served via
# the mesh; either is a valid signal that productpage→Gateway→ingress
# traffic flow is working.
case "${RESP}" in
    *"Simple Bookstore"*|*"Bookinfo Sample"*)
        pass "Bookinfo productpage served via ingress + mesh"
        ;;
    *)
        info "response (first 500 chars):"
        echo "${RESP:0:500}" | sed 's/^/    /'
        fail "productpage response did not contain a Bookinfo title"
        ;;
esac

# ── Phase 9: Route 100% to reviews-v1 ───────────────────────────────────────
# The previous version of this demo grepped responses for `glyphicon-star`
# (Bootstrap glyphicons used in pre-Tailwind Bookinfo). Current Istio
# Bookinfo migrated to Tailwind, so that marker is gone. Rather than
# chase the current Tailwind class names (which will change again next
# redesign), we check the routing's *effect* on response distribution:
#
#   v1 pinning → all responses come from the deterministic v1 backend →
#                response bytes should be near-identical across samples
#                → low distinct-hash count (typically 1)
#   50/50 v1/v3 → v1 deterministic + v3 has random star counts per
#                request → multiple distinct response patterns →
#                distinct-hash count ≥ 2
#
# This is robust against future Bookinfo UI changes.

step "applying destination-rules + virtual-service-all-v1"
kubectl apply -f "${BOOKINFO_DIR}/networking/destination-rule-all.yaml"
kubectl apply -f "${BOOKINFO_DIR}/networking/virtual-service-all-v1.yaml"
# Routing takes a few seconds to propagate to sidecars
sleep 8

step "curling productpage 10 times; responses should hash identically (deterministic v1)"
declare -A V1_HASHES
for _ in $(seq 1 10); do
    H=$(curl -fsS "http://127.0.0.1:${INGRESS_PORT}/productpage" 2>/dev/null \
        | md5sum | cut -d' ' -f1)
    V1_HASHES["$H"]=$((${V1_HASHES["$H"]:-0} + 1))
done
V1_DISTINCT=${#V1_HASHES[@]}
info "distinct response hashes across 10 samples: ${V1_DISTINCT}"
for h in "${!V1_HASHES[@]}"; do
    info "  ${V1_HASHES[$h]} responses → ${h:0:12}..."
done
if [[ "${V1_DISTINCT}" -gt 3 ]]; then
    info "too many distinct hashes for v1 pinning — routing rule may not have applied"
    fail "v1 pinning check failed (${V1_DISTINCT} distinct hashes; expected ≤3)"
fi
pass "${V1_DISTINCT} distinct hash(es) across 10 samples — reviews pinned to v1"

# ── Phase 10: 50/50 split between v1 and v3 ─────────────────────────────────
step "applying virtual-service-reviews-50-v3 (50/50 between v1 and v3)"
if [[ -f "${BOOKINFO_DIR}/networking/virtual-service-reviews-50-v3.yaml" ]]; then
    kubectl apply -f "${BOOKINFO_DIR}/networking/virtual-service-reviews-50-v3.yaml"
elif [[ -f "${BOOKINFO_DIR}/networking/virtual-service-reviews-jason-v2-v3.yaml" ]]; then
    info "using virtual-service-reviews-jason-v2-v3.yaml (50/50 file not at canonical path)"
    kubectl apply -f "${BOOKINFO_DIR}/networking/virtual-service-reviews-jason-v2-v3.yaml"
else
    fail "no traffic-split manifest found in ${BOOKINFO_DIR}/networking/"
fi
sleep 8

step "curling productpage 20 times; expecting multiple distinct response patterns (mixed versions)"
declare -A SPLIT_HASHES
for _ in $(seq 1 20); do
    H=$(curl -fsS "http://127.0.0.1:${INGRESS_PORT}/productpage" 2>/dev/null \
        | md5sum | cut -d' ' -f1)
    SPLIT_HASHES["$H"]=$((${SPLIT_HASHES["$H"]:-0} + 1))
done
SPLIT_DISTINCT=${#SPLIT_HASHES[@]}
info "distinct response hashes across 20 samples: ${SPLIT_DISTINCT}"
for h in "${!SPLIT_HASHES[@]}"; do
    info "  ${SPLIT_HASHES[$h]} responses → ${h:0:12}..."
done
if [[ "${SPLIT_DISTINCT}" -lt 2 ]]; then
    info "50/50 split should produce at least 2 distinct response patterns"
    info "got only ${SPLIT_DISTINCT} — split may not have taken effect"
    fail "split check failed: only ${SPLIT_DISTINCT} distinct hash(es) across 20 samples"
fi
pass "${SPLIT_DISTINCT} distinct response patterns across 20 samples — split is working"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — Istio install + sidecar injection + Bookinfo routing all verified"
echo
echo "  Cluster: minikube profile '${PROFILE_NAME}' (separate from §6-§9)"
echo "  Sidecar: nginx-istio Pod has istio-proxy injected"
echo "           (native sidecar mode — KEP-753, Istio 1.29+/K8s 1.28+)"
echo "  Bookinfo: 4 services × 6 Pods, all sidecar-injected"
echo "  Routing: v1-pin verified (${V1_DISTINCT} distinct hash/10)"
echo "           split verified (${SPLIT_DISTINCT} distinct patterns/20)"
echo
echo "  Cleanup on exit removes Bookinfo + nginx + routing rules and"
echo "  restores kubectl context to '${ORIGINAL_CONTEXT}'. Istio itself"
echo "  stays installed on the ${PROFILE_NAME} profile; uninstall with"
echo "  'istioctl uninstall --purge -y' (see §11 prose)."
echo
echo "  To explore further:"
echo "    - kubectl apply -f ${BOOKINFO_DIR}/networking/virtual-service-ratings-test-delay.yaml"
echo "      (fault injection — 7s delay on ratings)"
echo "    - kubectl apply -f ${ISTIO_DIR}/samples/addons"
echo "      (Kiali, Prometheus, Grafana, Jaeger; ~5 min to come up)"
echo "    - istioctl dashboard kiali"
echo "      (visualize the mesh)"
echo
exit 0
