#!/usr/bin/env bash
#
# scripts/setup-strimzi.sh
#
# One-time install of the Strimzi Cluster Operator into the `kafka`
# namespace on the pinned kube context (KUBE_CONTEXT, default `minikube`).
# Idempotent — safe to re-run.
#
# Pinned versions:
#   Strimzi:  1.2.0   (kafka.strimzi.io/v1 CRDs only; Kafka 4.3.1 supported)
#
# After this script returns, examples/12-keda-kafka/demo.sh can run.
# The demo creates a Kafka cluster custom resource — the operator
# reconciles it into actual Pods.
#
# Known issues:
# - Strimzi 1.x accepts ONLY the kafka.strimzi.io/v1 API; v1beta2
#   custom resources are rejected. Kafka 3.x and ZooKeeper are gone, so
#   examples/12-keda-kafka pins Kafka 4.3.1 (KRaft, KafkaNodePool)
# - Strimzi 1.2 needs a recent Kubernetes; the pinned cluster runs
#   v1.36.5, so we're fine
# - The Cluster Operator can occasionally get stuck in a NotReady state
#   on first install — if `helm install --wait` times out, check
#   `kubectl logs -n kafka deployment/strimzi-cluster-operator` and
#   try `helm uninstall strimzi -n kafka` + re-run

set -euo pipefail

STRIMZI_VERSION="${STRIMZI_VERSION:-1.2.0}"
NAMESPACE="${NAMESPACE:-kafka}"
KUBE_CONTEXT="${KUBE_CONTEXT:-minikube}"

# Color helpers
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; NC=''
fi
info()  { echo -e "  ${YELLOW}→${NC} $*"; }
pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*" >&2; exit 1; }
step()  { echo -e "${YELLOW}━━${NC} $*"; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
step "pre-flight"
command -v helm >/dev/null 2>&1 || fail "helm not in PATH — see §2"
command -v kubectl >/dev/null 2>&1 || fail "kubectl not in PATH — see §2"
kubectl --context "${KUBE_CONTEXT}" get nodes >/dev/null 2>&1 || fail "kubectl cannot reach context ${KUBE_CONTEXT} — start the profile first (§4)"
info "kube context (pinned): ${KUBE_CONTEXT}"
info "to target another profile: KUBE_CONTEXT=<profile> ./scripts/setup-strimzi.sh"
pass "tooling available"

# ── Step 1: Add the Strimzi helm repository ─────────────────────────────────
step "ensuring strimzi helm repository is registered"
if helm repo list 2>/dev/null | grep -q '^strimzi'; then
    info "strimzi helm repo already registered"
else
    helm repo add strimzi https://strimzi.io/charts/
    info "added strimzi helm repo"
fi
helm repo update strimzi >/dev/null
pass "strimzi helm repo ready"

# ── Step 2: Install the Cluster Operator ────────────────────────────────────
step "installing Strimzi Cluster Operator ${STRIMZI_VERSION} into namespace ${NAMESPACE}"
if helm status --kube-context "${KUBE_CONTEXT}" strimzi -n "${NAMESPACE}" >/dev/null 2>&1; then
    INSTALLED=$(helm status --kube-context "${KUBE_CONTEXT}" strimzi -n "${NAMESPACE}" -o json | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["chart"]["metadata"]["version"])' 2>/dev/null || echo "unknown")
    info "Strimzi already installed (version ${INSTALLED}); upgrading if needed"
    helm upgrade --kube-context "${KUBE_CONTEXT}" strimzi strimzi/strimzi-kafka-operator \
        --version "${STRIMZI_VERSION}" \
        -n "${NAMESPACE}" \
        --wait \
        --timeout 5m
else
    helm install --kube-context "${KUBE_CONTEXT}" strimzi strimzi/strimzi-kafka-operator \
        --version "${STRIMZI_VERSION}" \
        -n "${NAMESPACE}" \
        --create-namespace \
        --set watchAnyNamespace=false \
        --wait \
        --timeout 5m
fi
pass "Strimzi Cluster Operator ${STRIMZI_VERSION} installed"

# ── Step 3: Verify operator Pod is Running ──────────────────────────────────
step "verifying Strimzi Cluster Operator Pod is Running"
if ! kubectl --context "${KUBE_CONTEXT}" wait --for=condition=Available --timeout=120s \
        deployment/strimzi-cluster-operator -n "${NAMESPACE}" >/dev/null 2>&1; then
    info "Cluster Operator did not become Available within 120s; diagnostics:"
    kubectl --context "${KUBE_CONTEXT}" get pods -n "${NAMESPACE}" | sed 's/^/    /'
    info "operator logs (last 30 lines):"
    kubectl --context "${KUBE_CONTEXT}" logs -n "${NAMESPACE}" deployment/strimzi-cluster-operator --tail=30 \
        2>/dev/null | sed 's/^/    /' || true
    fail "Strimzi Cluster Operator not Available"
fi
kubectl --context "${KUBE_CONTEXT}" get pods -n "${NAMESPACE}" | sed 's/^/    /'
pass "Strimzi Cluster Operator Available"

echo
step "SUCCESS — Strimzi ready"
echo
echo "  Cluster Operator: ${STRIMZI_VERSION}"
echo "  Namespace:        ${NAMESPACE}"
echo
echo "  The operator now watches for Kafka, KafkaTopic, and KafkaUser"
echo "  custom resources in the ${NAMESPACE} namespace and reconciles"
echo "  them into actual Kubernetes resources (StatefulSets, Services,"
echo "  Secrets) under the hood."
echo
echo "  Next: run the Kafka scaling demo:"
echo
echo "    cd examples/12-keda-kafka && ./demo.sh"
echo
exit 0
