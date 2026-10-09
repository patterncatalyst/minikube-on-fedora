#!/usr/bin/env bash
#
# smoke-kafka.sh — verify the async spine: order-service publishes an
# order.placed event to Kafka, notification-service consumes it.
#
# Flow:
#   1. (images are loaded into the profile, no registry; deployed images are asserted bare + pullPolicy Never)
#   2. ensure the Strimzi operator is installed
#   3. deploy the Kafka cluster chart; wait for the Kafka CR to be Ready
#   4. build + load inventory (order needs CheckStock), order, notification
#   5. ensure Postgres Ready; deploy inventory, order, notification
#   6. place an in-stock order via order-service REST (emits order.placed)
#   7. poll notification-service GET /received until the order_id appears
#   8. clean up on success (CAP-008); on failure, leave running + dump logs
#
# Usage:  ./demos/smoke-kafka.sh [--purge-db]

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"   # PROFILE, NS, host/node ports; pins kubectl/helm/istioctl to the profile
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"
KAFKA_CR="capstone-kafka"
LOCAL_ORDER="$HOST_PORT_ORDER"; LOCAL_NOTIF="$HOST_PORT_NOTIFICATION"   # published NodePorts on 127.0.0.1
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

APP_SERVICES=(inventory-service order-service notification-service)

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    for svc in "${APP_SERVICES[@]}"; do
        printf '\n--- %s ---\n' "$svc" >&2
        kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${svc}" -o wide 2>&1 || true
        kubectl logs -n "$NS" -l "app.kubernetes.io/name=${svc}" --tail=30 2>&1 || true
    done
    printf '\n--- kafka ---\n' >&2
    kubectl get kafka,kafkanodepool,kafkatopic,pods -n "$NS" -l 'strimzi.io/cluster=capstone-kafka' 2>&1 || true
    printf '\nResources left in place. Clean up with:\n  helm uninstall %s %s -n %s\n' "${APP_SERVICES[*]}" "$KAFKA_RELEASE" "$NS" >&2
    exit 1
}

# Deployed image must be the bare <svc>:v1 with imagePullPolicy Never, and loaded in the node.
assert_local_image() {  # deployment-name
    local d="$1" img pol
    img="$(kubectl get deployment "$d" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
    pol="$(kubectl get deployment "$d" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' 2>/dev/null)"
    [[ "$img" == "${d}:v1" ]] || fail "${d} image is '${img}' — must be the bare '${d}:v1'"
    [[ "$pol" == "Never" ]] || fail "${d} imagePullPolicy is '${pol}' — must be Never"
    minikube -p "$PROFILE" image ls 2>/dev/null | grep -qE "(^|/)${d}:v1\$" \
        || fail "${d}:v1 not in 'minikube -p ${PROFILE} image ls' — ./scripts/build-image.sh services/${d} ${d} v1"
    printf '    ✓ %s → %s (pullPolicy Never, present in the node)\n' "$d" "$img"
}

minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"

# ── 2. Strimzi operator ───────────────────────────────────────────────────────
step "Ensuring the Strimzi operator is installed"
if ! kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1; then
    ./scripts/setup-kafka-operator.sh || fail "Strimzi operator install failed"
else
    printf '    ✓ Strimzi CRDs present\n'
fi

# ── 3. Kafka cluster ──────────────────────────────────────────────────────────
step "Deploying the Kafka cluster (single-node KRaft)"
helm upgrade --install "$KAFKA_RELEASE" "$KAFKA_CHART" -n "$NS" || fail "kafka chart install failed"
step "Waiting for the Kafka cluster to be Ready (first creation can take a few minutes)"
kubectl wait "kafka/${KAFKA_CR}" -n "$NS" --for=condition=Ready --timeout=360s \
    || fail "Kafka cluster did not become Ready"
printf '    ✓ Kafka Ready\n'

# ── 4. build + load ───────────────────────────────────────────────────────────
for svc in "${APP_SERVICES[@]}"; do
    step "Building + loading ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/load failed"
done

# ── 5. Postgres + deploy services ─────────────────────────────────────────────
step "Ensuring the shared Postgres cluster is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing — ./scripts/setup-postgres-operator.sh"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace || fail "postgres CR install failed"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        printf '    primary Ready after ~%ds\n' "$((i*5))"; pg_ready=1; break
    fi
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready"

for svc in "${APP_SERVICES[@]}"; do
    step "Deploying ${svc}"
    helm upgrade --install "$svc" "charts/capstone/charts/${svc}" -n "$NS" || fail "${svc} install failed"
    kubectl rollout status "deployment/${svc}" -n "$NS" --timeout=120s || fail "${svc} rollout failed"
    assert_local_image "$svc"
done

# ── 6. place an order (emits order.placed) ────────────────────────────────────
step "Waiting for order-service (${LOCAL_ORDER}) and notification-service (${LOCAL_NOTIF}) on their published NodePorts"
require_published_port "$PROFILE" "$NODE_PORT_ORDER" "$HOST_PORT_ORDER"
require_published_port "$PROFILE" "$NODE_PORT_NOTIFICATION" "$HOST_PORT_NOTIFICATION"
wait_for_http "http://127.0.0.1:${LOCAL_ORDER}/health" 60 || fail "order-service not answering on 127.0.0.1:${LOCAL_ORDER}"
wait_for_http "http://127.0.0.1:${LOCAL_NOTIF}/health" 60 || fail "notification-service not answering on 127.0.0.1:${LOCAL_NOTIF}"

step "Placing an in-stock order (WIDGET-001 x2) via order-service REST"
ORDER_JSON="$(curl -fsS -X POST "http://127.0.0.1:${LOCAL_ORDER}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customer_id":"cust-kafka","item_sku":"WIDGET-001","quantity":2,"amount":"19.98"}')" \
    || fail "could not place order (is inventory up?)"
ORDER_ID="$(printf '%s' "$ORDER_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"
[[ -n "$ORDER_ID" ]] || fail "no order id returned"
printf '    order id=%s\n' "$ORDER_ID"

# ── 7. poll notification /received for the event ──────────────────────────────
step "Polling notification-service /received for the order.placed event"
seen=0
for i in $(seq 1 30); do
    RECV="$(curl -fsS "http://127.0.0.1:${LOCAL_NOTIF}/received" 2>/dev/null || echo '[]')"
    if printf '%s' "$RECV" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(e.get('order_id')=='$ORDER_ID' and e.get('event_type')=='order.placed' for e in d) else 1)" 2>/dev/null; then
        printf '    ✓ notification consumed order.placed for %s (after ~%ds)\n' "$ORDER_ID" "$((i*2))"
        seen=1; break
    fi
    sleep 2
done
(( seen )) || fail "notification-service did not consume the order.placed event within ~60s"

printf '\n✓ SUCCESS — async spine verified (order.placed: order-service → Kafka → notification-service)\n'

# ── 8. cleanup on success ─────────────────────────────────────────────────────
step "Cleanup (success)"
helm uninstall "${APP_SERVICES[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
# Kafka cluster left running for fast re-runs (like Postgres). --purge-db tears down both.
if (( PURGE_DB )); then
    helm uninstall "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "kafka + postgres uninstalled"
fi
printf '  (Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
