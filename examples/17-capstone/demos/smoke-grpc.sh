#!/usr/bin/env bash
#
# smoke-grpc.sh — verify the first cross-service call in the mesh:
# order-service → inventory-service (InventoryService.CheckStock over gRPC).
#
# Flow:
#   1. confirm the committed gRPC stubs exist (run scripts/gen-protos.sh if not)
#   2. build + push both images to the in-cluster registry (CAP-007/009)
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
export MINIKUBE_ROOTLESS=true   # CAP-010

PROFILE="capstone"; NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
PG_RELEASE="capstone-postgres"; PG_CHART="charts/capstone/charts/postgres"
INV_CHART="charts/capstone/charts/inventory-service"
ORD_CHART="charts/capstone/charts/order-service"
LOCAL_PORT=18080
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

# ── 1b. charts point at the in-cluster registry? ──────────────────────────────
step "Sanity: chart image.repository points at the registry"
for svc in inventory-service order-service; do
    repo="$(awk '/^  repository:/{print $2; exit}' "charts/capstone/charts/${svc}/values.yaml")"
    case "$repo" in
        localhost:5000/*) printf '    ✓ %s → %s\n' "$svc" "$repo" ;;
        *) fail "${svc} image.repository is '${repo}' — must start with localhost:5000/ (a bare name pulls from Docker Hub and ErrImagePulls)" ;;
    esac
done

# ── 2. build + push both images ───────────────────────────────────────────────
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
kubectl config use-context "$PROFILE" >/dev/null
step "Building + pushing inventory-service"
./scripts/build-image.sh services/inventory-service inventory-service v1 || fail "inventory build/push failed"
step "Building + pushing order-service"
./scripts/build-image.sh services/order-service order-service v1 || fail "order build/push failed"

# ── 3. Postgres ───────────────────────────────────────────────────────────────
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

# ── 4. deploy both services ───────────────────────────────────────────────────
step "Deploying inventory-service (seeds demo stock)"
helm upgrade --install inventory-service "$INV_CHART" -n "$NS" || fail "inventory install failed"
kubectl rollout status deployment/inventory-service -n "$NS" --timeout=120s || fail "inventory rollout failed"

step "Deploying order-service"
helm upgrade --install order-service "$ORD_CHART" -n "$NS" || fail "order install failed"
kubectl rollout status deployment/order-service -n "$NS" --timeout=120s || fail "order rollout failed"

# ── 5. exercise the cross-service call via order-service REST ─────────────────
step "Port-forwarding order-service to 127.0.0.1:${LOCAL_PORT}"
kubectl port-forward -n "$NS" service/order-service "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF=$!; trap '[[ -n "${PF:-}" ]] && kill "$PF" 2>/dev/null' EXIT
sleep 3

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
kill "$PF" 2>/dev/null; PF=""
helm uninstall order-service inventory-service -n "$NS" >/dev/null 2>&1 && echo "releases uninstalled"
if (( PURGE_DB )); then helm uninstall "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "postgres uninstalled"; fi
