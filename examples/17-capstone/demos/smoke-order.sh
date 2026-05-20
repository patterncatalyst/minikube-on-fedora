#!/usr/bin/env bash
#
# smoke-order.sh — the r21 walking-skeleton verification (r21a-corrected).
#
# Proves the entire spine end-to-end:
#   image build (host podman) → load into profile → helm deploy →
#   operator-managed Postgres → service connects → REST works →
#   data round-trips through Postgres → assertions pass
#
# r21a changes:
#   - builds via scripts/build-image.sh (host podman + minikube image load),
#     fixing the ErrImagePull seen with `minikube image build` under the
#     rootless-podman + containerd combo
#   - on failure, LEAVES the failed resources in place and dumps a
#     diagnostic bundle inline (pod status, describe events, logs) instead
#     of tearing everything down — so a failed run hands you the evidence
#     directly (the §11/§12 demo pattern). Successful runs still clean up.
#
# Idempotent. Run from examples/17-capstone/:
#   ./demos/smoke-order.sh
#
# Prerequisites:
#   - capstone minikube profile running (scripts/setup-capstone-profile.sh)
#   - CloudNativePG operator installed (scripts/setup-postgres-operator.sh)
#   - kubectl context = capstone

set -uo pipefail   # NOT -e: we manage failures explicitly so we can diagnose

NS="capstone"
PROFILE="capstone"
RELEASE_PG="capstone-postgres"
RELEASE_ORDER="order-service"
PG_CHART="charts/capstone/charts/postgres"
ORDER_CHART="charts/capstone/charts/order-service"
SERVICE_DIR="services/order-service"
IMAGE="order-service:v1"
PORT_FORWARD_PID=""
SUCCESS=0

step() { printf '\n==> %s\n' "$1"; }

dump_diagnostics() {
    step "DIAGNOSTIC DUMP (failure — resources left in place for inspection)"
    printf '\n--- pods ---\n'
    kubectl get pods -n "$NS" -o wide 2>&1
    local pod
    pod=$(kubectl get pods -n "$NS" -l app.kubernetes.io/name=order-service \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$pod" ]]; then
        printf '\n--- describe %s (events) ---\n' "$pod"
        kubectl describe pod -n "$NS" "$pod" 2>&1 | tail -35
        printf '\n--- logs (current) ---\n'
        kubectl logs -n "$NS" "$pod" --tail=60 2>&1
        printf '\n--- logs (previous, if crash-looped) ---\n'
        kubectl logs -n "$NS" "$pod" --previous --tail=60 2>&1 || true
    fi
    printf '\n--- images in profile ---\n'
    minikube image ls -p "$PROFILE" 2>&1 | grep -i order-service || echo "(order-service image NOT in profile)"
    printf '\nResources left running. To clean up manually:\n'
    printf '  helm uninstall %s -n %s\n' "$RELEASE_ORDER" "$NS"
    printf '  helm uninstall %s -n %s   # also removes Postgres\n' "$RELEASE_PG" "$NS"
}

fail() {
    printf '\n✗ FAILED: %s\n' "$1" >&2
    [[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null
    dump_diagnostics
    exit 1
}

cleanup_on_success() {
    [[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null || true
    helm uninstall "$RELEASE_ORDER" -n "$NS" 2>/dev/null || true
    if (( PURGE_DB )); then
        helm uninstall "$RELEASE_PG" -n "$NS" 2>/dev/null || true
    fi
}

# Only clean up if we got all the way to SUCCESS. On failure the trap leaves
# everything in place (dump_diagnostics already ran via fail()).
on_exit() {
    if (( SUCCESS )); then
        step "Cleanup (success)"
        cleanup_on_success
    fi
}
trap on_exit EXIT

PURGE_DB=0
[[ "${1:-}" == "--purge-db" ]] && PURGE_DB=1

# ─── Pre-flight ──────────────────────────────────────────────────────────────

step "Pre-flight checks"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE' — run: kubectl config use-context $PROFILE"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 \
    || fail "CloudNativePG CRDs not found — run scripts/setup-postgres-operator.sh first"
command -v helm >/dev/null || fail "helm not in PATH"

# ─── Build + load the image (r21a: host podman + minikube image load) ────────

step "Building and loading $IMAGE into the $PROFILE profile"
./scripts/build-image.sh "$SERVICE_DIR" "$IMAGE" || fail "image build/load failed"

# ─── Deploy Postgres (Cluster CR; operator provisions it) ────────────────────

step "Deploying Postgres Cluster CR"
helm upgrade --install "$RELEASE_PG" "$PG_CHART" -n "$NS" --create-namespace \
    || fail "helm install of Postgres chart failed"

step "Waiting for the Postgres cluster primary to be Ready"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=$RELEASE_PG,role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
        | grep -q "True"; then
        printf '    primary pod Ready after ~%ds\n' "$((i*5))"
        pg_ready=1
        break
    fi
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready within 300s"

# ─── Deploy order-service ────────────────────────────────────────────────────

step "Deploying order-service"
helm upgrade --install "$RELEASE_ORDER" "$ORDER_CHART" -n "$NS" \
    || fail "helm install of order-service chart failed"

step "Waiting for order-service to roll out"
kubectl rollout status deployment/order-service -n "$NS" --timeout=180s \
    || fail "order-service did not roll out (see diagnostics below)"

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
    "SELECT count(*) FROM orders.orders WHERE id = '$order_id';" 2>/dev/null | tr -d '[:space:]')
[[ "$row_count" == "1" ]] || fail "expected 1 row in orders.orders, found '$row_count'"
printf '    confirmed: 1 row in orders.orders for id=%s\n' "$order_id"

# ─── Done ────────────────────────────────────────────────────────────────────

SUCCESS=1
if (( PURGE_DB )); then
    printf '\n✓ SUCCESS — order-service walking skeleton verified (DB purged on exit)\n'
else
    printf '\n✓ SUCCESS — order-service walking skeleton verified\n'
    printf '  (Postgres left running for fast re-runs; pass --purge-db to tear it down)\n'
fi
