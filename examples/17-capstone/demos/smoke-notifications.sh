#!/usr/bin/env bash
#
# smoke-notifications.sh — verify notification-service's real `notifications`
# table: the Alembic migration runs (init container), consumed events are
# persisted, and they SURVIVE A RESTART (the durability the in-memory list
# never had).
#
# Proves:
#   (1) migration ran — notification rollout only succeeds if the `migrate`
#       init container (`alembic upgrade head`) exited 0
#   (2) persistence  — place an order, see it in /received (DB-backed)
#   (3) durability   — restart notification, the event is STILL in /received
#       (it's in Postgres, not memory)
#
# Flow: ensure Strimzi+Kafka+Apicurio+Postgres → build+load inventory/order/
#       notification → deploy → place order → assert persisted → restart
#       notification → assert still present → cleanup on success.
#
# Usage:  ./demos/smoke-notifications.sh [--purge-db]

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"   # PROFILE, NS, host/node ports; pins kubectl/helm/istioctl to the profile
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"; KAFKA_CR="capstone-kafka"
APICURIO_RELEASE="apicurio"; APICURIO_CHART="charts/capstone/charts/apicurio"
LOCAL_ORDER="$HOST_PORT_ORDER"; LOCAL_NOTIF="$HOST_PORT_NOTIFICATION"   # published NodePorts on 127.0.0.1
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

DEPLOY=(inventory-service order-service notification-service)

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    printf '\n--- notification-service pods (incl. init container) ---\n' >&2
    kubectl get pods -n "$NS" -l "app.kubernetes.io/name=notification-service" -o wide 2>&1 || true
    kubectl logs -n "$NS" -l "app.kubernetes.io/name=notification-service" -c migrate --tail=40 2>&1 || true
    kubectl logs -n "$NS" -l "app.kubernetes.io/name=notification-service" --tail=30 2>&1 || true
    printf '\nResources left in place. Clean up with:\n  helm uninstall %s %s %s -n %s\n' \
        "${DEPLOY[*]}" "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$NS" >&2
    exit 1
}

check_received() {
    # $1 = order_id to look for in /received
    local recv
    recv="$(curl -fsS "http://127.0.0.1:${LOCAL_NOTIF}/received" 2>/dev/null || echo '[]')"
    printf '%s' "$recv" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(e.get('order_id')=='$1' for e in d) else 1)" 2>/dev/null
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
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running"

# ── platform ──────────────────────────────────────────────────────────────────
step "Ensuring Strimzi + Kafka + Apicurio are up"
kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1 || ./scripts/setup-kafka-operator.sh || fail "Strimzi install failed"
helm upgrade --install "$KAFKA_RELEASE" "$KAFKA_CHART" -n "$NS" >/dev/null || fail "kafka chart install failed"
kubectl wait "kafka/${KAFKA_CR}" -n "$NS" --for=condition=Ready --timeout=360s || fail "Kafka not Ready"
helm upgrade --install "$APICURIO_RELEASE" "$APICURIO_CHART" -n "$NS" >/dev/null || fail "apicurio install failed"
kubectl rollout status deployment/apicurio -n "$NS" --timeout=180s || fail "apicurio rollout failed"
printf '    ✓ Kafka + Apicurio ready\n'

# ── build + load + Postgres ───────────────────────────────────────────────────
for svc in "${DEPLOY[@]}"; do
    step "Building + loading ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/load failed"
done
step "Ensuring Postgres is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace >/dev/null || fail "postgres install failed"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        printf '    primary Ready after ~%ds\n' "$((i*5))"; pg_ready=1; break
    fi
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready"

# ── deploy (notification rollout success == migration init container ran) ─────
for svc in "${DEPLOY[@]}"; do
    step "Deploying ${svc}"
    helm upgrade --install "$svc" "charts/capstone/charts/${svc}" -n "$NS" >/dev/null || fail "${svc} install failed"
    kubectl rollout status "deployment/${svc}" -n "$NS" --timeout=150s || fail "${svc} rollout failed"
    assert_local_image "$svc"
done
printf '    ✓ notification-service rolled out — its `migrate` init container (alembic upgrade head) succeeded\n'

# ── confirm the table exists (migration really created it) ────────────────────
step "Verifying the notifications table exists in Postgres"
PG_PRIMARY="$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},role=primary" -o jsonpath='{.items[0].metadata.name}')"
TBL="$(kubectl exec -n "$NS" "$PG_PRIMARY" -c postgres -- psql -d capstone -tAqc \
    "select to_regclass('notifications.notifications')" 2>/dev/null || echo '')"
[[ "$TBL" == "notifications.notifications" ]] || fail "notifications.notifications table not found (got: '${TBL}')"
printf '    ✓ table notifications.notifications present\n'

# ── place an order ────────────────────────────────────────────────────────────
step "Waiting for order(${LOCAL_ORDER}) and notification(${LOCAL_NOTIF}) on their published NodePorts"
require_published_port "$PROFILE" "$NODE_PORT_ORDER" "$HOST_PORT_ORDER"
require_published_port "$PROFILE" "$NODE_PORT_NOTIFICATION" "$HOST_PORT_NOTIFICATION"
wait_for_http "http://127.0.0.1:${LOCAL_ORDER}/health" 60 || fail "order-service not answering on 127.0.0.1:${LOCAL_ORDER}"
wait_for_http "http://127.0.0.1:${LOCAL_NOTIF}/health" 60 || fail "notification-service not answering on 127.0.0.1:${LOCAL_NOTIF}"

step "Placing an in-stock order (WIDGET-001 x2)"
ORDER_ID="$(curl -fsS -X POST "http://127.0.0.1:${LOCAL_ORDER}/orders" -H 'Content-Type: application/json' \
    -d '{"customer_id":"cust-r25c","item_sku":"WIDGET-001","quantity":2,"amount":"19.98"}' \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"
[[ -n "$ORDER_ID" ]] || fail "no order id returned"
printf '    order id=%s\n' "$ORDER_ID"

step "Waiting for the notification to be persisted (/received, DB-backed)"
seen=0
for i in $(seq 1 30); do
    if check_received "$ORDER_ID"; then printf '    ✓ persisted after ~%ds\n' "$((i*2))"; seen=1; break; fi
    sleep 2
done
(( seen )) || fail "notification was not persisted within ~60s"

# ── durability: restart notification, the row must still be there ─────────────
step "Restarting notification-service to prove durability (in-memory would lose it)"
kubectl rollout restart deployment/notification-service -n "$NS" >/dev/null
kubectl rollout status deployment/notification-service -n "$NS" --timeout=150s || fail "restart rollout failed"
wait_for_http "http://127.0.0.1:${LOCAL_NOTIF}/health" 90 || fail "notification-service not answering after restart"
survived=0
for i in $(seq 1 15); do
    if check_received "$ORDER_ID"; then printf '    ✓ event still present after restart (~%ds)\n' "$((i*2))"; survived=1; break; fi
    sleep 2
done
(( survived )) || fail "event missing after restart — persistence is not working"

printf '\n✓ SUCCESS — Alembic migration ran in an init container; notifications persist to Postgres and survive a restart (create_all retired for notification)\n'

# ── cleanup on success ────────────────────────────────────────────────────────
step "Cleanup (success)"
helm uninstall "${DEPLOY[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
if (( PURGE_DB )); then
    helm uninstall "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "apicurio + kafka + postgres uninstalled"
fi
printf '  (Apicurio + Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
