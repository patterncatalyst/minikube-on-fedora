#!/usr/bin/env bash
#
# smoke-kafka.sh — verify the async spine: order-service publishes an
# order.placed event to Kafka, notification-service consumes it.
#
# Flow:
#   1. registry-prefix guard on the charts we deploy
#   2. ensure the Strimzi operator is installed
#   3. deploy the Kafka cluster chart; wait for the Kafka CR to be Ready
#   4. build + push inventory (order needs CheckStock), order, notification
#   5. ensure Postgres Ready; deploy inventory, order, notification
#   6. place an in-stock order via order-service REST (emits order.placed)
#   7. poll notification-service GET /received until the order_id appears
#   8. clean up on success (CAP-008); on failure, leave running + dump logs
#
# Usage:  ./demos/smoke-kafka.sh [--purge-db]

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

PROFILE="capstone"; NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"
KAFKA_CR="capstone-kafka"
LOCAL_ORDER=18080; LOCAL_NOTIF=18097
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

# ── 1. registry guard ─────────────────────────────────────────────────────────
step "Sanity: chart image.repository points at the registry"
for svc in "${APP_SERVICES[@]}"; do
    repo="$(awk '/^  repository:/{print $2; exit}' "charts/capstone/charts/${svc}/values.yaml")"
    case "$repo" in
        localhost:5000/*) printf '    ✓ %s → %s\n' "$svc" "$repo" ;;
        *) fail "${svc} image.repository is '${repo}' — must start with localhost:5000/" ;;
    esac
done

minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
kubectl config use-context "$PROFILE" >/dev/null

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

# ── 4. build + push ───────────────────────────────────────────────────────────
for svc in "${APP_SERVICES[@]}"; do
    step "Building + pushing ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/push failed"
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
done

# ── 6. place an order (emits order.placed) ────────────────────────────────────
step "Port-forwarding order-service (${LOCAL_ORDER}) and notification-service (${LOCAL_NOTIF})"
kubectl port-forward -n "$NS" service/order-service "${LOCAL_ORDER}:80" >/dev/null 2>&1 &
PF_O=$!
kubectl port-forward -n "$NS" service/notification-service "${LOCAL_NOTIF}:80" >/dev/null 2>&1 &
PF_N=$!
trap '[[ -n "${PF_O:-}" ]] && kill "$PF_O" 2>/dev/null; [[ -n "${PF_N:-}" ]] && kill "$PF_N" 2>/dev/null' EXIT
sleep 3

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
kill "$PF_O" "$PF_N" 2>/dev/null; PF_O=""; PF_N=""
helm uninstall "${APP_SERVICES[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
# Kafka cluster left running for fast re-runs (like Postgres). --purge-db tears down both.
if (( PURGE_DB )); then
    helm uninstall "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "kafka + postgres uninstalled"
fi
printf '  (Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
