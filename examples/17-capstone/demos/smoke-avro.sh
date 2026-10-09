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
# Flow: Strimzi+Kafka ready → deploy Apicurio → build+load
#       inventory/order/notification → Postgres → deploy → place order →
#       assert schema registered + event consumed → cleanup on success.
#
# Usage:  ./demos/smoke-avro.sh [--purge-db]

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"   # PROFILE, NS, host/node ports; pins kubectl/helm/istioctl to the profile
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"; KAFKA_CR="capstone-kafka"
APICURIO_RELEASE="apicurio"; APICURIO_CHART="charts/capstone/charts/apicurio"
SUBJECT="order-placed-value"
LOCAL_ORDER="$HOST_PORT_ORDER"; LOCAL_NOTIF="$HOST_PORT_NOTIFICATION"; LOCAL_APIC="$HOST_PORT_APICURIO"   # published NodePorts on 127.0.0.1
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

# ── 4. build + load ───────────────────────────────────────────────────────────
for svc in "${APP_SERVICES[@]}"; do
    step "Building + loading ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/load failed"
done

# ── 5. Postgres + deploy ──────────────────────────────────────────────────────
step "Ensuring the shared Postgres cluster is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace || fail "postgres CR install failed"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},cnpg.io/instanceRole=primary" \
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

# ── 6. place an order (registers schema on producer startup, emits Avro) ──────
step "Waiting for order(${LOCAL_ORDER}) notification(${LOCAL_NOTIF}) apicurio(${LOCAL_APIC}) on their published NodePorts"
require_published_port "$PROFILE" "$NODE_PORT_ORDER" "$HOST_PORT_ORDER"
keda_hold_replicas notification-service-scaler 1 notification-service \
    || fail "notification-service did not come up under the KEDA hold"
require_published_port "$PROFILE" "$NODE_PORT_NOTIFICATION" "$HOST_PORT_NOTIFICATION"
require_published_port "$PROFILE" "$NODE_PORT_APICURIO" "$HOST_PORT_APICURIO"
wait_for_http "http://127.0.0.1:${LOCAL_ORDER}/health" 60 || fail "order-service not answering on 127.0.0.1:${LOCAL_ORDER}"
wait_for_http "http://127.0.0.1:${LOCAL_NOTIF}/health" 60 || fail "notification-service not answering on 127.0.0.1:${LOCAL_NOTIF}"
wait_for_http "http://127.0.0.1:${LOCAL_APIC}/apis/registry/v3/system/info" 60 || fail "apicurio not answering on 127.0.0.1:${LOCAL_APIC}"

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
helm uninstall "${APP_SERVICES[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
if (( PURGE_DB )); then
    helm uninstall "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "apicurio + kafka + postgres uninstalled"
fi
printf '  (Apicurio + Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
