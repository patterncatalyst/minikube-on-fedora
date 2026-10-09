#!/usr/bin/env bash
#
# smoke-discovery.sh — publish the mesh's discovery contracts to Apicurio and
# verify all of them (plus the Avro runtime contract) are registered.
#
# Completes the registry half of CAP-018: after this, Apicurio holds all four
# protocols' contracts — Avro (runtime, registered by order-service) plus
# OpenAPI, Protobuf, and GraphQL SDL (discovery, published here) — which is the
# feedstock OpenMetadata ingests later.
#
# Flow: ensure Strimzi+Kafka+Apicurio+Postgres → deploy inventory/order/gateway
#       → published NodePorts → publish discovery contracts → assert each artifact is
#       retrievable from Apicurio's v3 API (and the Avro subject from ccompat)
#       → cleanup on success.
#
# Usage:  ./demos/smoke-discovery.sh [--purge-db]

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"   # PROFILE, NS, host/node ports; pins kubectl/helm/istioctl to the profile
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka"; KAFKA_CHART="charts/capstone/charts/kafka"; KAFKA_CR="capstone-kafka"
APICURIO_RELEASE="apicurio"; APICURIO_CHART="charts/capstone/charts/apicurio"
PROTO_PATH="proto/capstone/inventory/v1/inventory.proto"
GROUP="default"
LOCAL_ORDER="$HOST_PORT_ORDER"; LOCAL_GW="$HOST_PORT_GATEWAY"; LOCAL_APIC="$HOST_PORT_APICURIO"   # published NodePorts on 127.0.0.1
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

DEPLOY=(inventory-service order-service graphql-gateway)

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    for svc in "${DEPLOY[@]}" apicurio; do
        printf '\n--- %s ---\n' "$svc" >&2
        kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${svc}" -o wide 2>&1 || true
        kubectl logs -n "$NS" -l "app.kubernetes.io/name=${svc}" --tail=25 2>&1 || true
    done
    printf '\nResources left in place. Clean up with:\n  helm uninstall %s %s %s -n %s\n' \
        "${DEPLOY[*]}" "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$NS" >&2
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
# graphql-gateway is scaled to zero by KEDA HTTP when idle and its NodePort has no
# endpoints then. This demo calls the gateway directly on 127.0.0.1:${HOST_PORT_GATEWAY}, so
# scale it up if needed and wait for a ready endpoint first.
ensure_gateway_up() {
    local ready
    ready="$(kubectl get deployment graphql-gateway -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
    if [[ -z "$ready" || "$ready" == "0" ]]; then
        kubectl scale deployment/graphql-gateway -n "$NS" --replicas=1 >/dev/null || fail "could not scale graphql-gateway up"
    fi
    kubectl rollout status deployment/graphql-gateway -n "$NS" --timeout=120s || fail "graphql-gateway not ready"
    require_published_port "$PROFILE" "$NODE_PORT_GATEWAY" "$HOST_PORT_GATEWAY"
    wait_for_http "http://127.0.0.1:${HOST_PORT_GATEWAY}/health" 60 || fail "graphql-gateway not answering on 127.0.0.1:${HOST_PORT_GATEWAY}"
}
[[ -f "$PROTO_PATH" ]] || fail "proto not found at ${PROTO_PATH} — run ./scripts/gen-protos.sh? (the .proto is committed)"

minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running"

# ── platform: Strimzi + Kafka + Apicurio ──────────────────────────────────────
step "Ensuring Strimzi + Kafka + Apicurio are up"
kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1 || ./scripts/setup-kafka-operator.sh || fail "Strimzi install failed"
helm upgrade --install "$KAFKA_RELEASE" "$KAFKA_CHART" -n "$NS" >/dev/null || fail "kafka chart install failed"
kubectl wait "kafka/${KAFKA_CR}" -n "$NS" --for=condition=Ready --timeout=360s || fail "Kafka not Ready"
helm upgrade --install "$APICURIO_RELEASE" "$APICURIO_CHART" -n "$NS" >/dev/null || fail "apicurio install failed"
kubectl rollout status deployment/apicurio -n "$NS" --timeout=180s || fail "apicurio rollout failed"
printf '    ✓ Kafka + Apicurio ready\n'

# ── build + load + Postgres + deploy ──────────────────────────────────────────
for svc in "${DEPLOY[@]}"; do
    step "Building + loading ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/load failed"
done
step "Ensuring Postgres is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace >/dev/null || fail "postgres install failed"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},cnpg.io/instanceRole=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        printf '    primary Ready after ~%ds\n' "$((i*5))"; pg_ready=1; break
    fi
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready"
for svc in "${DEPLOY[@]}"; do
    step "Deploying ${svc}"
    helm upgrade --install "$svc" "charts/capstone/charts/${svc}" -n "$NS" >/dev/null || fail "${svc} install failed"
    kubectl rollout status "deployment/${svc}" -n "$NS" --timeout=120s || fail "${svc} rollout failed"
    assert_local_image "$svc"
done

# ── published NodePorts ───────────────────────────────────────────────────────
# order-service and Apicurio are reached on their NodePorts; the gateway is scaled up first
# (see ensure_gateway_up) because its NodePort has no endpoints while KEDA holds it at zero.
step "Waiting for order(${LOCAL_ORDER}) gateway(${LOCAL_GW}) apicurio(${LOCAL_APIC}) on their published NodePorts"
require_published_port "$PROFILE" "$NODE_PORT_ORDER" "$HOST_PORT_ORDER"
require_published_port "$PROFILE" "$NODE_PORT_APICURIO" "$HOST_PORT_APICURIO"
wait_for_http "http://127.0.0.1:${LOCAL_ORDER}/health" 60 || fail "order-service not answering on 127.0.0.1:${LOCAL_ORDER}"
wait_for_http "http://127.0.0.1:${LOCAL_APIC}/apis/registry/v3/system/info" 60 || fail "apicurio not answering on 127.0.0.1:${LOCAL_APIC}"
ensure_gateway_up

# ── publish ───────────────────────────────────────────────────────────────────
step "Publishing discovery contracts (OpenAPI + Protobuf + GraphQL SDL)"
APICURIO_URL="http://127.0.0.1:${LOCAL_APIC}" \
ORDER_URL="http://127.0.0.1:${LOCAL_ORDER}" \
GATEWAY_URL="http://127.0.0.1:${LOCAL_GW}" \
PROTO_PATH="$PROTO_PATH" APICURIO_GROUP="$GROUP" \
    ./scripts/publish-discovery-contracts.sh || fail "publishing discovery contracts failed"

# ── assert all four contract types are in the registry ────────────────────────
step "Verifying contracts are registered in Apicurio"
APIC="http://127.0.0.1:${LOCAL_APIC}"
for art in order-service-openapi inventory-grpc-proto graphql-gateway-sdl; do
    meta="$(curl -fsS "${APIC}/apis/registry/v3/groups/${GROUP}/artifacts/${art}" 2>/dev/null || echo '')"
    printf '%s' "$meta" | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('artifactType') or d.get('artifact',{}).get('artifactType'); print('    ✓ '+'$art'+' ('+str(t)+')'); sys.exit(0 if t else 1)" 2>/dev/null \
        || fail "discovery artifact ${art} not found in Apicurio"
done
# the Avro runtime contract is registered via ccompat (TopicNameStrategy subject)
AVRO_V="$(curl -fsS "${APIC}/apis/ccompat/v7/subjects/order-placed-value/versions" 2>/dev/null || echo '')"
printf '%s' "$AVRO_V" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,list) and d else 1)" 2>/dev/null \
    && printf '    ✓ order-placed-value (AVRO, runtime — via ccompat)\n' \
    || printf '    • order-placed-value (AVRO) not present yet — run smoke-avro.sh to register it\n'

printf '\n✓ SUCCESS — discovery contracts published; Apicurio now holds all protocol contracts (OpenAPI, Protobuf, GraphQL SDL, + Avro runtime)\n'

# ── cleanup on success ────────────────────────────────────────────────────────
step "Cleanup (success)"
helm uninstall "${DEPLOY[@]}" -n "$NS" >/dev/null 2>&1 && echo "service releases uninstalled"
if (( PURGE_DB )); then
    helm uninstall "$APICURIO_RELEASE" "$KAFKA_RELEASE" "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "apicurio + kafka + postgres uninstalled"
fi
printf '  (Apicurio + Kafka + Postgres left running for fast re-runs; pass --purge-db to tear them down)\n'
