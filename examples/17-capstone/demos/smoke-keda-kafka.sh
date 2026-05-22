#!/usr/bin/env bash
#
# smoke-keda-kafka.sh — demonstrate AND verify Kafka consumer-lag autoscaling of
# notification-service (r26b, CAP-025).
#
# The elastic-data-product point: an event consumer should run only as much as
# its backlog warrants — and nothing at all when the topic is quiet. This proves
# the full lifecycle:
#   * with no lag, KEDA scales notification-service to ZERO
#   * a burst of messages on `order-placed` creates lag → KEDA scales it UP
#   * once the backlog is drained, KEDA scales it back to ZERO
#
# The burst is raw bytes, not Avro: the consumer auto-commits and skips
# undecodable messages (logs "skipping undecodable message"), so offsets advance
# and lag clears — which is all the lag-based scaler needs. No order-service /
# inventory / valid-Avro path required, keeping the demo dependency-light.
#
# Leaves resources in place on failure + dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:  ./demos/smoke-keda-kafka.sh

set -uo pipefail
export MINIKUBE_ROOTLESS=true

NS="capstone"
PROFILE="capstone"
KEDA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../keda" && pwd)"
DEP="notification-service"
SEL="app.kubernetes.io/name=notification-service"
TOPIC="order-placed"
BURST=500

step() { printf '\n==> %s\n' "$1"; }

# count_pods — non-terminating pods for the consumer (KEDA's replica count, live)
count_pods() {
    kubectl get pods -n "$NS" -l "$SEL" --no-headers 2>/dev/null \
        | grep -v 'Terminating' | grep -c . || echo 0
}

dump() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    kubectl get scaledobject,deployment,pods -n "$NS" -l "$SEL" 2>&1
    printf '\nKEDA HPA + scaler events:\n'
    kubectl get hpa -n "$NS" 2>&1
    kubectl describe scaledobject notification-service-scaler -n "$NS" 2>&1 | tail -25
}
fail() { printf '\n✗ FAILED: %s\n' "$1" >&2; dump; exit 1; }

# wait_until "desc" <timeout_s> <predicate-cmd...> — poll every 3s
wait_until() {
    local desc="$1" timeout="$2"; shift 2
    local waited=0
    while ! "$@"; do
        sleep 3; waited=$((waited + 3))
        if [[ $waited -ge $timeout ]]; then
            printf '    (timed out after %ss waiting for: %s; pods now=%s)\n' "$timeout" "$desc" "$(count_pods)"
            return 1
        fi
    done
    return 0
}
is_zero()    { [[ "$(count_pods)" -eq 0 ]]; }
is_scaledup(){ [[ "$(count_pods)" -gt 0 ]]; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE'"
kubectl get deployment keda-operator -n keda >/dev/null 2>&1 \
    || fail "KEDA not installed — run scripts/setup-keda.sh first"
kubectl get deployment "$DEP" -n "$NS" >/dev/null 2>&1 \
    || fail "$DEP not deployed — helm upgrade --install notification-service charts/capstone/charts/notification-service -n $NS"

step "Applying the Kafka consumer-lag ScaledObject"
kubectl apply -f "$KEDA_DIR/notification-scaledobject.yaml" >/dev/null \
    || fail "failed to apply the ScaledObject"
printf '    ✓ scaledobject applied — KEDA now owns %s replicas\n' "$DEP"

# ─── 1. Scale to zero (quiet topic) ──────────────────────────────────────────
step "Waiting for scale-to-zero (no lag → 0 replicas, ~cooldown 30s)"
wait_until "0 replicas" 150 is_zero \
    || fail "$DEP did not scale to zero — is there residual lag, or is minReplicaCount honored?"
printf '    ✓ scaled to ZERO (consumer idle, costing nothing)\n'

# ─── 2. Create lag → scale up ────────────────────────────────────────────────
step "Producing a ${BURST}-message burst to '${TOPIC}' to create lag"
BROKER="$(kubectl get pods -n "$NS" -l strimzi.io/cluster=capstone-kafka -o name 2>/dev/null \
    | grep -E 'kafka-.*-[0-9]+$' | head -1 | cut -d/ -f2)"
[[ -n "$BROKER" ]] || fail "could not find a capstone-kafka broker pod"
printf '    using broker pod: %s\n' "$BROKER"
seq 1 "$BURST" | kubectl exec -i -n "$NS" "$BROKER" -- \
    /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$TOPIC" >/dev/null 2>&1 \
    || fail "failed to produce to $TOPIC"
printf '    ✓ produced %s messages (lag now ≈ %s)\n' "$BURST" "$BURST"

step "Waiting for KEDA to scale UP on lag"
wait_until ">0 replicas" 90 is_scaledup \
    || fail "$DEP did not scale up despite lag — check the kafka trigger (bootstrap/consumerGroup/topic)"
MAXSEEN="$(count_pods)"
sleep 6; [[ "$(count_pods)" -gt "$MAXSEEN" ]] && MAXSEEN="$(count_pods)"
printf '    ✓ scaled UP to %s replica(s) on lag\n' "$MAXSEEN"

# ─── 3. Backlog drains → scale back to zero ──────────────────────────────────
step "Waiting for the backlog to drain and KEDA to scale back to ZERO"
wait_until "0 replicas" 180 is_zero \
    || fail "$DEP did not return to zero after draining — consumer stuck (not auto-committing)?"
printf '    ✓ drained and scaled back to ZERO\n'

step "SUCCESS"
printf 'notification-service is an elastic data product: 0 when idle, up to %s\n' "$MAXSEEN"
printf 'under backlog, back to 0 when drained — driven by Kafka consumer lag.\n'
