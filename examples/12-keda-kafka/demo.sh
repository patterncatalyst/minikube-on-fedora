#!/usr/bin/env bash
#
# examples/12-keda-kafka/demo.sh
#
# Demonstrates KEDA scale-from-zero on Kafka consumer lag.
#
# Phases:
#   1.  Pre-flight: minikube up, Strimzi installed, KEDA installed
#   2.  Apply Kafka cluster + topic CRs, wait for Ready
#   3.  Build order-processor:v1 image on the minikube profile
#   4.  Apply consumer Deployment (replicas: 0) + KEDA ScaledObject
#   5.  Assert consumer is at 0 replicas
#   6.  Produce 200 messages to the orders topic
#   7.  Watch replica count climb from 0 (assert it reaches >=1)
#   8.  Wait for topic to drain (consumer eats messages)
#   9.  Wait cooldownPeriod + buffer for KEDA to scale back to 0
#   10. Assert final state: replicas = 0
#
# Idempotent — re-runs reuse the existing Kafka cluster + image cache.
# First run is slow (~3-5 min for Kafka cluster bring-up + image build).
# Re-runs are fast (~2 min, mostly the produce-and-drain cycle).

set -euo pipefail

# ── Repo helpers ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../scripts/lib/_helpers.sh
source "${REPO_ROOT}/scripts/lib/_helpers.sh"

# ── Config ──────────────────────────────────────────────────────────────────
PROFILE_NAME="minikube"
KAFKA_NS="kafka"
CONSUMER_NS="default"
KAFKA_CLUSTER="my-kafka"
TOPIC="orders"
CONSUMER_GROUP="order-processor-group"
IMAGE_TAG="order-processor:v1"
MSG_COUNT=200
SCALEUP_TIMEOUT=120
SCALEDOWN_TIMEOUT=120
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
CONSUMER_DIR="${SCRIPT_DIR}/consumer"
KAFKA_READY_TIMEOUT=300

cleanup() {
    info "cleanup: removing consumer + ScaledObject"
    kubectl delete -n "${CONSUMER_NS}" -f "${MANIFESTS_DIR}/scaled-object.yaml" \
        --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl delete -n "${CONSUMER_NS}" -f "${MANIFESTS_DIR}/consumer-deployment.yaml" \
        --ignore-not-found=true >/dev/null 2>&1 || true
    # Kafka cluster + topic stay — they're slow to recreate and idempotent
}
trap cleanup EXIT

# ── Phase 1: Pre-flight ─────────────────────────────────────────────────────
step "pre-flight: minikube up, Strimzi + KEDA installed"
kubectl config use-context "${PROFILE_NAME}" >/dev/null 2>&1 || \
    fail "kubectl context '${PROFILE_NAME}' not configured — run minikube start -p ${PROFILE_NAME}"
kubectl get nodes >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
pass "minikube cluster reachable"

if ! kubectl get namespace "${KAFKA_NS}" >/dev/null 2>&1; then
    fail "kafka namespace not present — run ./scripts/setup-strimzi.sh first"
fi
if ! kubectl get deployment strimzi-cluster-operator -n "${KAFKA_NS}" >/dev/null 2>&1; then
    fail "Strimzi Cluster Operator not found — run ./scripts/setup-strimzi.sh first"
fi
pass "Strimzi operator present in '${KAFKA_NS}' namespace"

if ! kubectl get deployment keda-operator -n keda >/dev/null 2>&1; then
    fail "KEDA operator not found — run ./scripts/setup-keda.sh first"
fi
pass "KEDA operator present in 'keda' namespace"

# ── Phase 2: Apply Kafka cluster + topic, wait for Ready ────────────────────
step "applying Kafka cluster + topic CRs"
kubectl apply -f "${MANIFESTS_DIR}/kafka-cluster.yaml"
kubectl apply -f "${MANIFESTS_DIR}/kafka-topic.yaml"

# Wait for Kafka cluster Ready. This is THE flaky step — first install
# can take 60-90s, sometimes more. Use Strimzi's Ready condition (not
# the underlying StatefulSet) since the Cluster Operator owns the
# top-level lifecycle logic.
step "waiting for Kafka cluster '${KAFKA_CLUSTER}' to be Ready (up to ${KAFKA_READY_TIMEOUT}s — first-time install can take ~90s)"
if ! kubectl wait --for=condition=Ready --timeout="${KAFKA_READY_TIMEOUT}s" \
        kafka/${KAFKA_CLUSTER} -n "${KAFKA_NS}" >/dev/null 2>&1; then
    info "Kafka cluster did not reach Ready. Diagnostics:"
    info ""
    info "  Cluster Operator logs (last 30 lines):"
    kubectl logs -n "${KAFKA_NS}" deployment/strimzi-cluster-operator --tail=30 \
        2>/dev/null | sed 's/^/    /' || true
    info ""
    info "  Kafka CR status:"
    kubectl get kafka/${KAFKA_CLUSTER} -n "${KAFKA_NS}" -o yaml 2>/dev/null \
        | grep -A 20 "^  conditions:" | sed 's/^/    /' || true
    info ""
    info "  Pods in ${KAFKA_NS} namespace:"
    kubectl get pods -n "${KAFKA_NS}" | sed 's/^/    /'
    info ""
    info "  Recent events:"
    kubectl get events -n "${KAFKA_NS}" --sort-by='.lastTimestamp' \
        2>/dev/null | tail -15 | sed 's/^/    /'
    fail "Kafka cluster '${KAFKA_CLUSTER}' did not reach Ready within ${KAFKA_READY_TIMEOUT}s"
fi
pass "Kafka cluster Ready"

step "waiting for topic '${TOPIC}' to be Ready"
if ! kubectl wait --for=condition=Ready --timeout=60s \
        kafkatopic/${TOPIC} -n "${KAFKA_NS}" >/dev/null 2>&1; then
    info "Topic CR status:"
    kubectl get kafkatopic/${TOPIC} -n "${KAFKA_NS}" -o yaml \
        | grep -A 10 "^status:" | sed 's/^/    /' || true
    fail "topic '${TOPIC}' did not reach Ready within 60s"
fi
pass "Topic '${TOPIC}' Ready"

# Show the Kafka broker Pod to confirm it's up
kubectl get pods -n "${KAFKA_NS}" -l strimzi.io/cluster=${KAFKA_CLUSTER} | sed 's/^/    /'

# ── Phase 3: Build consumer image ───────────────────────────────────────────
step "ensuring ${IMAGE_TAG} is in the minikube profile's image cache"
if ! minikube image ls -p "${PROFILE_NAME}" 2>/dev/null | grep -q "${IMAGE_TAG}"; then
    info "building consumer image from ${CONSUMER_DIR}/Containerfile (~30s first time)"
    minikube -p "${PROFILE_NAME}" image build -t "${IMAGE_TAG}" \
        -f Containerfile "${CONSUMER_DIR}"
fi
pass "${IMAGE_TAG} available"

# ── Phase 4: Apply consumer + ScaledObject ──────────────────────────────────
step "applying consumer Deployment (replicas: 0) + KEDA ScaledObject"
kubectl apply -n "${CONSUMER_NS}" -f "${MANIFESTS_DIR}/consumer-deployment.yaml"
kubectl apply -n "${CONSUMER_NS}" -f "${MANIFESTS_DIR}/scaled-object.yaml"
# Brief sleep so KEDA notices the ScaledObject
sleep 3
pass "consumer + ScaledObject applied"

# ── Phase 5: Assert initial replicas = 0 ────────────────────────────────────
step "asserting consumer is at 0 replicas (no traffic yet)"
INITIAL_REPLICAS=$(kubectl get deployment order-processor -n "${CONSUMER_NS}" \
    -o jsonpath='{.spec.replicas}')
info "current replicas: ${INITIAL_REPLICAS}"
if [[ "${INITIAL_REPLICAS}" != "0" ]]; then
    fail "expected 0 replicas before producing messages, got ${INITIAL_REPLICAS}"
fi
pass "consumer at 0 replicas (KEDA is in scale-to-zero state)"

# ── Phase 6: Produce messages ───────────────────────────────────────────────
step "producing ${MSG_COUNT} messages to topic '${TOPIC}'"
KAFKA_POD=$(kubectl get pod -n "${KAFKA_NS}" \
    -l strimzi.io/cluster=${KAFKA_CLUSTER},strimzi.io/broker-role=true \
    -o jsonpath='{.items[0].metadata.name}')
info "producing via kubectl exec into ${KAFKA_POD}"
# Build a here-doc of messages and pipe through kafka-console-producer
{
    for i in $(seq 1 "${MSG_COUNT}"); do
        echo "order-${i} {\"id\": ${i}, \"sku\": \"item-$((RANDOM % 100))\"}"
    done
} | kubectl exec -i -n "${KAFKA_NS}" "${KAFKA_POD}" -- \
    bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 \
        --topic "${TOPIC}" >/dev/null 2>&1
pass "${MSG_COUNT} messages produced"

# ── Phase 7: Watch consumer scale up ────────────────────────────────────────
step "waiting for KEDA to scale consumer up (up to ${SCALEUP_TIMEOUT}s)"
PEAK_REPLICAS=0
SCALED_UP=""
for i in $(seq 1 "${SCALEUP_TIMEOUT}"); do
    R=$(kubectl get deployment order-processor -n "${CONSUMER_NS}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [[ "${R}" -gt "${PEAK_REPLICAS}" ]]; then
        PEAK_REPLICAS="${R}"
        info "[${i}s] replicas climbed to ${R}"
    fi
    if [[ "${R}" -ge 1 && -z "${SCALED_UP}" ]]; then
        SCALED_UP="yes"
        info "[${i}s] scale-up confirmed (replicas ≥ 1)"
    fi
    sleep 1
    # Check every 3s to reduce kubectl chatter
    if [[ $((i % 3)) -ne 0 && -z "${SCALED_UP}" ]]; then
        continue
    fi
    if [[ -n "${SCALED_UP}" && "${i}" -gt 30 ]]; then
        # We've seen the scale-up; can leave the loop early
        break
    fi
done
if [[ -z "${SCALED_UP}" ]]; then
    info "consumer did not scale up. ScaledObject status:"
    kubectl describe scaledobject order-processor-scaler -n "${CONSUMER_NS}" \
        2>/dev/null | sed 's/^/    /' || true
    info "KEDA operator logs (last 30 lines):"
    kubectl logs -n keda deployment/keda-operator --tail=30 \
        2>/dev/null | sed 's/^/    /' || true
    fail "KEDA did not scale order-processor up within ${SCALEUP_TIMEOUT}s"
fi
pass "consumer scaled up — peak replicas: ${PEAK_REPLICAS}"

# ── Phase 8: Let the consumer drain the topic ───────────────────────────────
step "waiting for consumer to drain the topic (~${MSG_COUNT} × 0.5s / replicas)"
EST_DRAIN_S=$(( MSG_COUNT / 2 / PEAK_REPLICAS + 10 ))
info "estimated drain time: ${EST_DRAIN_S}s"
sleep "${EST_DRAIN_S}"
pass "drain wait complete"

# ── Phase 9: Wait for scale-down to 0 ───────────────────────────────────────
step "waiting for KEDA to scale down to 0 (cooldownPeriod=30s, allow up to ${SCALEDOWN_TIMEOUT}s)"
FINAL_REPLICAS=""
for i in $(seq 1 "${SCALEDOWN_TIMEOUT}"); do
    R=$(kubectl get deployment order-processor -n "${CONSUMER_NS}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
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
    R=$(kubectl get deployment order-processor -n "${CONSUMER_NS}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
    info "ScaledObject status:"
    kubectl describe scaledobject order-processor-scaler -n "${CONSUMER_NS}" \
        2>/dev/null | sed 's/^/    /' || true
    fail "consumer did not scale back to 0 within ${SCALEDOWN_TIMEOUT}s (last seen: ${R})"
fi
pass "consumer back at 0 replicas"

# ── Done ────────────────────────────────────────────────────────────────────
step "SUCCESS — KEDA scale-from-zero on Kafka consumer lag verified"
echo
echo "  Workload:    order-processor (Python Kafka consumer)"
echo "  Trigger:     Kafka topic '${TOPIC}' consumer lag"
echo "  Lifecycle:   0 → ${PEAK_REPLICAS} → 0 replicas"
echo "  Messages:    ${MSG_COUNT} produced and drained"
echo
echo "  Cleanup on exit removes the consumer Deployment + ScaledObject."
echo "  The Kafka cluster + topic stay running for re-runs. To fully"
echo "  clean up:"
echo "    kubectl delete kafka my-kafka -n kafka"
echo "    kubectl delete kafkatopic --all -n kafka"
echo
exit 0
