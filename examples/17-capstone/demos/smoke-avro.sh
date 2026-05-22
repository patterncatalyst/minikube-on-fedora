#!/usr/bin/env bash
#
# smoke-avro.sh — verify the runtime contract: order-service registers the
# order.placed Avro schema with Apicurio and publishes Avro-encoded events;
# notification-service fetches the schema by id and decodes them.
#
# Proves two things:
#   (1) the schema lands in Apicurio (GET ccompat subject versions)
#   (2) the event still flows end-to-end, now as Avro (notification /received
#       shows the decoded order — which is only possible if the consumer
#       fetched the writer schema from the registry by id)
#
# Flow: registry guard → Strimzi+Kafka ready → deploy Apicurio → build+push
#       inventory/order/notification → Postgres → deploy → place order →
#       assert schema registered + event consumed → cleanup on success.
#
# Usage:  ./demos/smoke-avro.sh [--purge-db]

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

PROFILE="capstone"; NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"; KAFKA_CR="capstone-kafka"
APICURIO_RELEASE="apicurio"; APICURIO_CHART="charts/capstone/charts/apicurio"
SUBJECT="order-placed-value"
LOCAL_ORDER=18080; LOCAL_NOTIF=18097; LOCAL_APIC=18085
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

APP_SERVICES=(inventory-service order-service notification-service)

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    for svc in "${APP_SERVICES[@]}" apicurio; do
        printf '\n--- %s ---\n' "$svc" >&2
        kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${svc}" -o wide 2>&1 || true
        kubectl logs -n "$NS" -l "app.kubernetes.io/name=${svc}" --tail=30 2>&1 || true
    done
    printf '\nResources left in place. Clean up with:\n  helm uninstall %s %s %s -n %s\n' \
        "${APP_SERVICES[*]}" "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$NS" >&2
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

minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running"
kubectl config use-context "$PROFILE" >/dev/null

# ── 2. Strimzi + Kafka ────────────────────────────────────────────────────────
step "Ensuring the Strimzi operator + Kafka cluster are up"
kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1 || ./scripts/setup-kafka-operator.sh || fail "Strimzi operator install failed"
helm upgrade --install "$KAFKA_RELEASE" "$KAFKA_CHART" -n "$NS" || fail "kafka chart install failed"
kubectl wait "kafka/${KAFKA_CR}" -n "$NS" --for=condition=Ready --timeout=360s || fail "Kafka not Ready"
printf '    ✓ Kafka Ready\n'

# ── 3. Apicurio ───────────────────────────────────────────────────────────────
step "Deploying Apicurio Registry (in-memory)"
helm upgrade --install "$APICURIO_RELEASE" "$APICURIO_CHART" -n "$NS" || fail "apicurio install failed"
kubectl rollout status deployment/apicurio -n "$NS" --timeout=180s || fail "apicurio rollout failed"
printf '    ✓ Apicurio ready\n'

# ── 4. build + push ───────────────────────────────────────────────────────────
for svc in "${APP_SERVICES[@]}"; do
    step "Building + pushing ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/push failed"
done

# ── 5. Postgres + deploy ──────────────────────────────────────────────────────
step "Ensuring the shared Postgres cluster is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing"
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

# ── 6. place an order (registers schema on producer startup, emits Avro) ──────
step "Port-forwards: order(${LOCAL_ORDER}) notification(${LOCAL_NOTIF}) apicurio(${LOCAL_APIC})"
kubectl port-forward -n "$NS" service/order-service "${LOCAL_ORDER}:80" >/dev/null 2>&1 & PF_O=$!
kubectl port-forward -n "$NS" service/notification-service "${LOCAL_NOTIF}:80" >/dev/null 2>&1 & PF_N=$!
kubectl port-forward -n "$NS" service/apicurio "${LOCAL_APIC}:8080" >/dev/null 2>&1 & PF_A=$!
trap '[[ -n "${PF_O:-}" ]]&&kill "$PF_O" 2>/dev/null;[[ -n "${PF_N:-}" ]]&&kill "$PF_N" 2>/dev/null;[[ -n "${PF_A:-}" ]]&&kill "$PF_A" 2>/dev/null' EXIT
sleep 3

step "Placing an in-stock order (WIDGET-001 x2) via order-service REST"
ORDER_JSON="$(curl -fsS -X POST "http://127.0.0.1:${LOCAL_ORDER}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customer_id":"cust-avro","item_sku":"WIDGET-001","quantity":2,"amount":"19.98"}')" \
    || fail "could not place order"
ORDER_ID="$(printf '%s' "$ORDER_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"
[[ -n "$ORDER_ID" ]] || fail "no order id returned"
printf '    order id=%s\n' "$ORDER_ID"

# ── 7a. assert the Avro schema was registered in Apicurio ─────────────────────
step "Checking the order.placed Avro schema is registered in Apicurio"
VERSIONS="$(curl -fsS "http://127.0.0.1:${LOCAL_APIC}/apis/ccompat/v7/subjects/${SUBJECT}/versions" 2>/dev/null || echo '')"
printf '    subject %s versions: %s\n' "$SUBJECT" "${VERSIONS:-<none>}"
printf '%s' "$VERSIONS" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,list) and len(d)>=1 else 1)' 2>/dev/null \
    || fail "schema subject ${SUBJECT} not registered in Apicurio"
printf '    ✓ schema registered\n'

# ── 7b. assert the event was consumed (proves Avro decode via registry) ───────
step "Polling notification-service /received for the decoded order.placed event"
seen=0
for i in $(seq 1 30); do
    RECV="$(curl -fsS "http://127.0.0.1:${LOCAL_NOTIF}/received" 2>/dev/null || echo '[]')"
    if printf '%s' "$RECV" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(e.get('order_id')=='$ORDER_ID' and e.get('event_type')=='order.placed' and e.get('item_sku')=='WIDGET-001' for e in d) else 1)" 2>/dev/null; then
        printf '    ✓ notification decoded order.placed for %s (after ~%ds)\n' "$ORDER_ID" "$((i*2))"
        seen=1; break
    fi
    sleep 2
done
(( seen )) || fail "notification did not consume/decode the Avro event within ~60s"

printf '\n✓ SUCCESS — order.placed flows as registered Avro: schema in Apicurio + event decoded by the consumer via the registry\n'

# ── 8. cleanup on success ─────────────────────────────────────────────────────
step "Cleanup (success)"
kill "$PF_O" "$PF_N" "$PF_A" 2>/dev/null; PF_O=""; PF_N=""; PF_A=""
helm uninstall "${APP_SERVICES[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
if (( PURGE_DB )); then
    helm uninstall "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "apicurio + kafka + postgres uninstalled"
fi
printf '  (Apicurio + Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
