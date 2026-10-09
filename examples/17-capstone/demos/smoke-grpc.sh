#!/usr/bin/env bash
#
# smoke-grpc.sh — verify the first cross-service call in the mesh:
# order-service → inventory-service (InventoryService.CheckStock over gRPC).
#
# Flow:
#   1. confirm the committed gRPC stubs exist (run scripts/gen-protos.sh if not)
#   2. build both images and load them into the profile (no registry)
#   3. ensure the shared Postgres cluster is Ready
#   4. deploy inventory-service (seeds demo stock: WIDGET-001=50, WIDGET-OOS=0)
#      and order-service
#   5. assert, via order-service's REST surface:
#        - POST /orders for an in-stock SKU            → 201 (gRPC said available)
#        - POST /orders for an out-of-stock SKU        → 409 (gRPC said no)
#        - POST /orders for more than on-hand quantity → 409 (quantity check)
#   6. clean up on success (CAP-008); on failure, leave running + dump diagnostics
#
# Usage:  ./demos/smoke-grpc.sh [--purge-db]

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/env.sh"   # PROFILE, NS, ports; pins kubectl/helm to the profile
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
INV_CHART="charts/capstone/charts/inventory-service"
ORD_CHART="charts/capstone/charts/order-service"
LOCAL_PORT="$HOST_PORT_ORDER"   # published NodePort on 127.0.0.1
PURGE_DB=0; [[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    for svc in inventory-service order-service; do
        printf '\n--- %s pods ---\n' "$svc" >&2
        kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${svc}" -o wide 2>&1 || true
        kubectl logs -n "$NS" -l "app.kubernetes.io/name=${svc}" --tail=40 2>&1 || true
    done
    printf '\nResources left in place. Clean up with:\n  helm uninstall order-service inventory-service -n %s\n' "$NS" >&2
    exit 1
}

# ── 1. stubs present? ─────────────────────────────────────────────────────────
step "Checking for committed gRPC stubs"
for svc in inventory-service order-service; do
    if [[ ! -f "services/${svc}/gen/capstone/inventory/v1/inventory_pb2_grpc.py" ]]; then
        fail "missing stubs for ${svc} — generate them first: ./scripts/gen-protos.sh"
    fi
done
printf '    ✓ stubs present in both services\n'

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

# ── 2. build + push both images ───────────────────────────────────────────────
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
step "Building + loading inventory-service"
./scripts/build-image.sh services/inventory-service inventory-service v1 || fail "inventory build/load failed"
step "Building + loading order-service"
./scripts/build-image.sh services/order-service order-service v1 || fail "order build/load failed"

# ── 3. Postgres ───────────────────────────────────────────────────────────────
step "Ensuring the shared Postgres cluster is Ready"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || fail "CloudNativePG operator missing — ./scripts/setup-postgres-operator.sh"
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

# ── 4. deploy both services ───────────────────────────────────────────────────
step "Deploying inventory-service (seeds demo stock)"
helm upgrade --install inventory-service "$INV_CHART" -n "$NS" || fail "inventory install failed"
kubectl rollout status deployment/inventory-service -n "$NS" --timeout=120s || fail "inventory rollout failed"
assert_local_image inventory-service

step "Deploying order-service"
helm upgrade --install order-service "$ORD_CHART" -n "$NS" || fail "order install failed"
kubectl rollout status deployment/order-service -n "$NS" --timeout=120s || fail "order rollout failed"
assert_local_image order-service

# ── 5. exercise the cross-service call via order-service REST ─────────────────
step "Waiting for order-service on the published NodePort 127.0.0.1:${LOCAL_PORT}"
require_published_port "$PROFILE" "$NODE_PORT_ORDER" "$HOST_PORT_ORDER"
wait_for_http "http://127.0.0.1:${LOCAL_PORT}/health" 60 || fail "order-service not answering on 127.0.0.1:${LOCAL_PORT}"

post_order() {  # sku quantity → prints HTTP status code
    curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${LOCAL_PORT}/orders" \
        -H 'Content-Type: application/json' \
        -d "{\"customer_id\":\"cust-1\",\"item_sku\":\"$1\",\"quantity\":$2,\"amount\":\"9.99\"}"
}

step "In-stock SKU (WIDGET-001 x2) → expect 201"
code="$(post_order WIDGET-001 2)"; echo "    HTTP $code"
[[ "$code" == "201" ]] || fail "expected 201 for in-stock order, got $code"

step "Out-of-stock SKU (WIDGET-OOS x1) → expect 409"
code="$(post_order WIDGET-OOS 1)"; echo "    HTTP $code"
[[ "$code" == "409" ]] || fail "expected 409 for out-of-stock order, got $code"

step "Excess quantity (WIDGET-001 x9999) → expect 409"
code="$(post_order WIDGET-001 9999)"; echo "    HTTP $code"
[[ "$code" == "409" ]] || fail "expected 409 for excess-quantity order, got $code"

printf '\n✓ SUCCESS — order→inventory gRPC CheckStock verified end to end\n'
printf '  (in-stock placed; out-of-stock and excess-quantity both rejected via the gRPC round-trip)\n'

# ── 6. cleanup on success ─────────────────────────────────────────────────────
step "Cleanup (success)"
helm uninstall order-service inventory-service -n "$NS" >/dev/null 2>&1 && echo "releases uninstalled"
if (( PURGE_DB )); then helm uninstall "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "postgres uninstalled"; fi
