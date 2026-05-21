#!/usr/bin/env bash
#
# smoke-graphql.sh — verify the federated read layer: a single GraphQL query
# to graphql-gateway that stitches an order (order-service, REST) with its
# live stock (inventory-service, gRPC) into one response.
#
# Flow:
#   1. confirm committed gRPC stubs exist for the gateway
#   2. sanity: charts point at the in-cluster registry
#   3. build + push inventory-service, order-service, graphql-gateway
#   4. ensure Postgres Ready; deploy all three
#   5. place an in-stock order via order-service REST to get an order id
#   6. query the gateway:  { order(id) { id itemSku quantity stock { sku quantityOnHand available } } }
#      and assert the response carries BOTH the order fields and nested stock
#   7. clean up on success (CAP-008); on failure, leave running + dump logs
#
# Usage:  ./demos/smoke-graphql.sh [--purge-db]

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

PROFILE="capstone"; NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
LOCAL_ORDER=18080; LOCAL_GQL=18099
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

# ── 2. registry-prefix guard ──────────────────────────────────────────────────
step "Sanity: chart image.repository points at the registry"
for svc in "${SERVICES[@]}"; do
    repo="$(awk '/^  repository:/{print $2; exit}' "charts/capstone/charts/${svc}/values.yaml")"
    case "$repo" in
        localhost:5000/*) printf '    ✓ %s → %s\n' "$svc" "$repo" ;;
        *) fail "${svc} image.repository is '${repo}' — must start with localhost:5000/" ;;
    esac
done

# ── 3. build + push all three ─────────────────────────────────────────────────
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
kubectl config use-context "$PROFILE" >/dev/null
for svc in "${SERVICES[@]}"; do
    step "Building + pushing ${svc}"
    ./scripts/build-image.sh "services/${svc}" "${svc}" v1 || fail "${svc} build/push failed"
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
done

# ── 5. seed an order via order-service REST ───────────────────────────────────
step "Port-forwarding order-service (${LOCAL_ORDER}) and graphql-gateway (${LOCAL_GQL})"
kubectl port-forward -n "$NS" service/order-service "${LOCAL_ORDER}:80" >/dev/null 2>&1 &
PF_O=$!
kubectl port-forward -n "$NS" service/graphql-gateway "${LOCAL_GQL}:80" >/dev/null 2>&1 &
PF_G=$!
trap '[[ -n "${PF_O:-}" ]] && kill "$PF_O" 2>/dev/null; [[ -n "${PF_G:-}" ]] && kill "$PF_G" 2>/dev/null' EXIT
sleep 3

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
kill "$PF_O" "$PF_G" 2>/dev/null; PF_O=""; PF_G=""
helm uninstall "${SERVICES[@]}" -n "$NS" >/dev/null 2>&1 && echo "releases uninstalled"
if (( PURGE_DB )); then helm uninstall "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "postgres uninstalled"; fi
