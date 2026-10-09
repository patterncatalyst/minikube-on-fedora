#!/usr/bin/env bash
#
# smoke-graphql.sh — verify the federated read layer: a single GraphQL query
# to graphql-gateway that stitches an order (order-service, REST) with its
# live stock (inventory-service, gRPC) into one response.
#
# Flow:
#   1. confirm committed gRPC stubs exist for the gateway
#   2. assert the deployed images are bare <svc>:v1 with pullPolicy Never
#   3. build + load inventory-service, order-service, graphql-gateway
#   4. ensure Postgres Ready; deploy all three
#   5. place an in-stock order via order-service REST to get an order id
#   6. query the gateway:  { order(id) { id itemSku quantity stock { sku quantityOnHand available } } }
#      and assert the response carries BOTH the order fields and nested stock
#   7. clean up on success (CAP-008); on failure, leave running + dump logs
#
# Usage:  ./demos/smoke-graphql.sh [--purge-db]

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "$ROOT/scripts/lib/env.sh"   # PROFILE, NS, host/node ports; pins kubectl/helm/istioctl to the profile
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
LOCAL_ORDER="$HOST_PORT_ORDER"; LOCAL_GQL="$HOST_PORT_GATEWAY"   # published NodePorts on 127.0.0.1
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

SERVICES=(inventory-service order-service graphql-gateway)

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    for svc in "${SERVICES[@]}"; do
        printf '\n--- %s ---\n' "$svc" >&2
        kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${svc}" -o wide 2>&1 || true
        kubectl logs -n "$NS" -l "app.kubernetes.io/name=${svc}" --tail=30 2>&1 || true
    done
    printf '\nResources left in place. Clean up with:\n  helm uninstall %s -n %s\n' "${SERVICES[*]}" "$NS" >&2
    exit 1
}

# ── 1. stubs present (gateway needs the inventory client stubs) ───────────────
step "Checking for committed gRPC stubs"
for svc in inventory-service order-service graphql-gateway; do
    [[ -f "services/${svc}/gen/capstone/inventory/v1/inventory_pb2_grpc.py" ]] \
        || fail "missing stubs for ${svc} — run ./scripts/gen-protos.sh"
done
printf '    ✓ stubs present\n'

# ── 2. image assertions (bare <svc>:v1, pullPolicy Never) ──────────────────────
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

# ── 3. build + load all three ─────────────────────────────────────────────────
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
for svc in "${SERVICES[@]}"; do
    step "Building + loading ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/load failed"
done

# ── 4. Postgres + deploy ──────────────────────────────────────────────────────
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

for svc in inventory-service order-service graphql-gateway; do
    step "Deploying ${svc}"
    helm upgrade --install "$svc" "charts/capstone/charts/${svc}" -n "$NS" || fail "${svc} install failed"
    kubectl rollout status "deployment/${svc}" -n "$NS" --timeout=120s || fail "${svc} rollout failed"
    assert_local_image "$svc"
done

# ── 5. seed an order via order-service REST ───────────────────────────────────
step "Waiting for order-service (${LOCAL_ORDER}) and graphql-gateway (${LOCAL_GQL}) on their published NodePorts"
require_published_port "$PROFILE" "$NODE_PORT_ORDER" "$HOST_PORT_ORDER"
wait_for_http "http://127.0.0.1:${LOCAL_ORDER}/health" 60 || fail "order-service not answering on 127.0.0.1:${LOCAL_ORDER}"
ensure_gateway_up   # direct call on 18099: scale up + wait for endpoints (not via the KEDA interceptor)

step "Placing an in-stock order (WIDGET-001 x2) via order-service REST"
ORDER_JSON="$(curl -fsS -X POST "http://127.0.0.1:${LOCAL_ORDER}/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customer_id":"cust-gql","item_sku":"WIDGET-001","quantity":2,"amount":"19.98"}')" \
    || fail "could not place seed order"
ORDER_ID="$(printf '%s' "$ORDER_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')"
[[ -n "$ORDER_ID" ]] || fail "no order id returned"
printf '    order id=%s\n' "$ORDER_ID"

# ── 6. query the gateway and assert stitched response ─────────────────────────
step "Querying graphql-gateway for the order + nested stock (REST + gRPC stitched)"
GQL_QUERY="$(printf '{"query":"{ order(id: \\"%s\\") { id itemSku quantity stock { sku quantityOnHand available } } }"}' "$ORDER_ID")"
RESP="$(curl -fsS -X POST "http://127.0.0.1:${LOCAL_GQL}/graphql" \
    -H 'Content-Type: application/json' \
    -d "$GQL_QUERY")" || fail "GraphQL query failed"
printf '    %s\n' "$RESP"

python3 - "$RESP" "$ORDER_ID" <<'PY' || fail "GraphQL response missing stitched fields"
import sys, json
resp = json.loads(sys.argv[1]); oid = sys.argv[2]
assert "errors" not in resp, f"GraphQL errors: {resp.get('errors')}"
o = resp["data"]["order"]
assert o["id"] == oid, f"order id mismatch: {o['id']} != {oid}"
assert o["itemSku"] == "WIDGET-001", o["itemSku"]
st = o["stock"]
assert st is not None and st["sku"] == "WIDGET-001", st
assert isinstance(st["quantityOnHand"], int) and st["quantityOnHand"] >= 0, st
assert st["available"] is True, st
print("    ✓ stitched: order (REST) + stock (gRPC) in one response; on_hand=%d available=%s"
      % (st["quantityOnHand"], st["available"]))
PY

printf '\n✓ SUCCESS — federated GraphQL query verified (order via REST + stock via gRPC, stitched by the gateway)\n'

# ── 7. cleanup on success ─────────────────────────────────────────────────────
step "Cleanup (success)"
helm uninstall "${SERVICES[@]}" -n "$NS" >/dev/null 2>&1 && echo "releases uninstalled"
if (( PURGE_DB )); then helm uninstall "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "postgres uninstalled"; fi
