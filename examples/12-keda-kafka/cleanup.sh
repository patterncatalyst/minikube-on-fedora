#!/usr/bin/env bash
#
# examples/12-keda-kafka/cleanup.sh
#
# Deep cleanup for the §12 Kafka demo. Goes beyond what demo.sh's
# cleanup trap does (which only removes the consumer + ScaledObject).
#
# Removes:
#   - Consumer Deployment + ScaledObject (default, demo's normal cleanup)
#   - Kafka cluster CR + KafkaNodePool + KafkaTopic (the heavyweight
#     state demo.sh's trap intentionally LEAVES for re-run speed)
#   - With --remove-operators: Strimzi Cluster Operator + the kafka
#     namespace, and KEDA + HTTP add-on + the keda namespace
#
# Usage:
#   ./cleanup.sh                     # demo state + Kafka cluster
#   ./cleanup.sh --remove-operators  # plus Strimzi + KEDA themselves
#   ./cleanup.sh --help              # show this

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

REMOVE_OPERATORS=false
for arg in "$@"; do
    case "${arg}" in
        --remove-operators) REMOVE_OPERATORS=true ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) fail "unknown argument: ${arg} (try --help)" ;;
    esac
done

PROFILE_NAME="minikube"
kubectl config use-context "${PROFILE_NAME}" >/dev/null 2>&1 || \
    fail "kubectl context '${PROFILE_NAME}' not configured"

# ── Tier 1: demo workload ───────────────────────────────────────────────────
step "removing demo workload (consumer + ScaledObject)"
kubectl delete scaledobject order-processor-scaler -n default \
    --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
kubectl delete deployment order-processor -n default \
    --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
pass "demo workload removed"

# ── Tier 2: Kafka cluster + topics ──────────────────────────────────────────
step "removing Kafka cluster + topics (this is what demo.sh's trap leaves)"
# Topics first (Topic Operator cleans up its referenced Kafka resources)
kubectl delete kafkatopic --all -n kafka \
    --ignore-not-found=true --wait=true --timeout=60s >/dev/null 2>&1 || true
# Then the Kafka cluster itself
kubectl delete kafka my-kafka -n kafka \
    --ignore-not-found=true --wait=true --timeout=120s >/dev/null 2>&1 || true
# Then the KafkaNodePool (Strimzi should cascade, but be explicit)
kubectl delete kafkanodepool dual-role -n kafka \
    --ignore-not-found=true --wait=true --timeout=60s >/dev/null 2>&1 || true
# PVCs the cluster created (Strimzi sets deleteClaim: false intentionally)
kubectl delete pvc -n kafka -l strimzi.io/cluster=my-kafka \
    --ignore-not-found=true >/dev/null 2>&1 || true
pass "Kafka cluster + topics + PVCs removed"

if [[ "${REMOVE_OPERATORS}" != "true" ]]; then
    echo
    step "DONE (default cleanup)"
    echo
    echo "  Strimzi Cluster Operator + KEDA are still installed."
    echo "  To remove them too: ./cleanup.sh --remove-operators"
    echo
    exit 0
fi

# ── Tier 3: operators ───────────────────────────────────────────────────────
step "removing Strimzi Cluster Operator (helm uninstall + namespace)"
if helm status strimzi -n kafka >/dev/null 2>&1; then
    helm uninstall strimzi -n kafka --wait >/dev/null 2>&1 || true
    pass "Strimzi helm release uninstalled"
fi
if kubectl get namespace kafka >/dev/null 2>&1; then
    kubectl delete namespace kafka --wait=true --timeout=60s >/dev/null 2>&1 || true
    pass "kafka namespace removed"
fi

# Strimzi installs cluster-scoped CRDs. Remove them so a fresh install
# doesn't pick up stale schemas.
info "removing Strimzi CRDs"
kubectl get crd -o name | grep -E '\.kafka\.strimzi\.io$' \
    | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
pass "Strimzi CRDs removed"

step "removing KEDA + HTTP add-on (helm uninstall + namespace)"
if helm status keda-add-ons-http -n keda >/dev/null 2>&1; then
    helm uninstall keda-add-ons-http -n keda --wait >/dev/null 2>&1 || true
    pass "KEDA HTTP add-on helm release uninstalled"
fi
if helm status keda -n keda >/dev/null 2>&1; then
    helm uninstall keda -n keda --wait >/dev/null 2>&1 || true
    pass "KEDA helm release uninstalled"
fi
if kubectl get namespace keda >/dev/null 2>&1; then
    kubectl delete namespace keda --wait=true --timeout=60s >/dev/null 2>&1 || true
    pass "keda namespace removed"
fi

info "removing KEDA CRDs"
kubectl get crd -o name | grep -E '\.keda\.sh$|\.http\.keda\.sh$' \
    | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
pass "KEDA CRDs removed"

echo
step "DONE (deep cleanup, --remove-operators)"
echo
echo "  Strimzi + KEDA + HTTP add-on fully removed."
echo "  The minikube profile is otherwise untouched."
echo "  To reinstall: ./scripts/setup-keda.sh && ./scripts/setup-strimzi.sh"
echo
