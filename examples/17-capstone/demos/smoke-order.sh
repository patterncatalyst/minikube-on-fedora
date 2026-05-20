#!/usr/bin/env bash
#
# smoke-order.sh — the r21 walking-skeleton verification.
#
# Proves the entire spine end-to-end:
#   image build → minikube image cache → helm deploy →
#   operator-managed Postgres → service connects → REST works →
#   data round-trips through Postgres → assertions pass
#
# Idempotent. Cleans up on exit (trap). Run from examples/17-capstone/:
#   ./demos/smoke-order.sh
#
# Prerequisites:
#   - capstone minikube profile running (scripts/setup-capstone-profile.sh)
#   - CloudNativePG operator installed (scripts/setup-postgres-operator.sh)
#   - kubectl context = capstone

set -euo pipefail

NS="capstone"
PROFILE="capstone"
RELEASE_PG="capstone-postgres"
RELEASE_ORDER="order-service"
PG_CHART="charts/capstone/charts/postgres"
ORDER_CHART="charts/capstone/charts/order-service"
SERVICE_DIR="services/order-service"
PORT_FORWARD_PID=""

# ─── Helpers ─────────────────────────────────────────────────────────────────

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\n✗ FAILED: %s\n' "$1" >&2; exit 1; }

cleanup() {
    step "Cleanup"
    [[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null || true
    helm uninstall "$RELEASE_ORDER" -n "$NS" 2>/dev/null || true
    # Leave Postgres up by default (re-runs are faster). Pass --purge-db to
    # also tear down the Postgres cluster.
    if [[ "${1:-}" == "--purge-db" ]]; then
        helm uninstall "$RELEASE_PG" -n "$NS" 2>/dev/null || true
    fi
}
trap 'cleanup' EXIT

PURGE_DB=0
[[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

# ─── Pre-flight ──────────────────────────────────────────────────────────────

step "Pre-flight checks"

[[ "$(kubectl config current-context)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE' — run: kubectl config use-context $PROFILE"

kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 \
    || fail "CloudNativePG CRDs not found — run scripts/setup-postgres-operator.sh first"

command -v helm >/dev/null || fail "helm not in PATH"

# ─── Build the image into the capstone profile ───────────────────────────────

step "Building order-service:v1 image inside the $PROFILE profile"
# minikube image build builds directly into the profile's image cache, so no
# registry push is needed (same pattern as §6).
minikube image build -p "$PROFILE" -t order-service:v1 "$SERVICE_DIR" \
    || fail "image build failed"

# ─── Deploy Postgres (Cluster CR; operator provisions it) ────────────────────

step "Deploying Postgres Cluster CR"
helm upgrade --install "$RELEASE_PG" "$PG_CHART" -n "$NS" --create-namespace

step "Waiting for the Postgres cluster to be ready (operator-provisioned)"
# CNPG marks the Cluster ready via a condition; the primary pod gets a label.
# Wait for the primary pod to be Ready.
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=$RELEASE_PG,role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
        | grep -q "True"; then
        printf '    primary pod Ready after ~%ds\n' "$((i*5))"
        break
    fi
    [[ $i -eq 60 ]] && fail "Postgres primary did not become Ready within 300s"
    sleep 5
done

# ─── Deploy order-service ────────────────────────────────────────────────────

step "Deploying order-service"
helm upgrade --install "$RELEASE_ORDER" "$ORDER_CHART" -n "$NS"

step "Waiting for order-service to be Available"
kubectl wait --for=condition=Available --timeout=180s \
    deployment/order-service -n "$NS" \
    || fail "order-service deployment did not become Available"

# ─── Exercise the REST surface ───────────────────────────────────────────────

step "Port-forwarding order-service to 127.0.0.1:18080"
kubectl port-forward -n "$NS" service/order-service 18080:80 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 3

BASE="http://127.0.0.1:18080"

step "Assert /health returns ok"
health=$(curl -fsS "$BASE/health") || fail "/health unreachable"
echo "$health" | grep -q '"status":"ok"' || fail "/health did not return ok: $health"

step "Assert /healthz reports readiness (Postgres reachable)"
healthz=$(curl -fsS "$BASE/healthz") || fail "/healthz returned non-2xx (DB unreachable?)"
echo "$healthz" | grep -q '"status":"ready"' || fail "/healthz not ready: $healthz"

step "POST a new order"
created=$(curl -fsS -X POST "$BASE/orders" \
    -H 'Content-Type: application/json' \
    -d '{"customer_id":"cust-1001","item_sku":"SKU-ABC-42","quantity":3,"amount":"59.97"}') \
    || fail "POST /orders failed"
order_id=$(echo "$created" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])') \
    || fail "could not parse order id from: $created"
printf '    created order id=%s\n' "$order_id"

step "GET the order back by id (round-trips through Postgres)"
fetched=$(curl -fsS "$BASE/orders/$order_id") || fail "GET /orders/$order_id failed"
echo "$fetched" | grep -q "\"id\":\"$order_id\"" || fail "fetched order id mismatch: $fetched"
echo "$fetched" | grep -q '"customer_id":"cust-1001"' || fail "fetched order data mismatch"

step "GET /orders list contains the new order"
listing=$(curl -fsS "$BASE/orders") || fail "GET /orders failed"
echo "$listing" | grep -q "$order_id" || fail "list does not contain new order"

step "Verify the row actually persisted in Postgres (direct query)"
pg_pod=$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=$RELEASE_PG,role=primary" \
    -o jsonpath='{.items[0].metadata.name}')
row_count=$(kubectl exec -n "$NS" "$pg_pod" -- \
    psql -U postgres -d capstone -tAc \
    "SELECT count(*) FROM orders.orders WHERE id = '$order_id';" 2>/dev/null || echo "0")
[[ "$row_count" == "1" ]] || fail "expected 1 row in orders.orders, found '$row_count'"
printf '    confirmed: 1 row in orders.orders for id=%s\n' "$order_id"

# ─── Done ────────────────────────────────────────────────────────────────────

if (( PURGE_DB )); then
    printf '\n✓ SUCCESS — order-service walking skeleton verified (DB will be purged on exit)\n'
else
    printf '\n✓ SUCCESS — order-service walking skeleton verified\n'
    printf '  (Postgres left running for fast re-runs; pass --purge-db to tear it down)\n'
fi
