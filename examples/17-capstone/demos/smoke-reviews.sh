#!/usr/bin/env bash
#
# smoke-reviews.sh — verify the review-service data product (Phase A).
#
# Builds + deploys review-service against the capstone Postgres and asserts its
# REST surface end-to-end: probes, the seeded rows, create, fetch-by-id, and the
# ?sku= filter. This proves the new data product stands and serves before we
# layer discovery (Apicurio contract + OpenMetadata catalog/lineage) on top.
#
# Assumes the capstone cluster is up with Postgres (cluster-up.sh / the capstone
# deploy). Leaves resources in place + dumps diagnostics on failure; cleans up
# review-service on success (Postgres is shared and left alone).
#
# Run from examples/17-capstone/:  ./demos/smoke-reviews.sh

set -uo pipefail
export MINIKUBE_ROOTLESS=true

NS="capstone"
PROFILE="capstone"
RELEASE="review-service"
CHART="charts/capstone/charts/review-service"
SERVICE_DIR="services/review-service"
IMAGE_NAME="review-service"
IMAGE_TAG="v1"
PORT="18086"
PF=""
SUCCESS=0

step() { printf '\n==> %s\n' "$1"; }
dump() {
    step "DIAGNOSTIC DUMP (failure — review-service left in place)"
    kubectl get pods -n "$NS" -l app.kubernetes.io/name=review-service -o wide 2>&1
    local pod
    pod=$(kubectl get pods -n "$NS" -l app.kubernetes.io/name=review-service \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$pod" ]]; then
        kubectl describe pod -n "$NS" "$pod" 2>&1 | tail -30
        kubectl logs -n "$NS" "$pod" --tail=50 2>&1
        kubectl logs -n "$NS" "$pod" --previous --tail=40 2>&1 || true
    fi
    printf '\nClean up manually: helm uninstall %s -n %s\n' "$RELEASE" "$NS"
}
fail() { printf '\n✗ FAILED: %s\n' "$1" >&2; [[ -n "$PF" ]] && kill "$PF" 2>/dev/null; dump; exit 1; }
on_exit() {
    [[ -n "$PF" ]] && kill "$PF" 2>/dev/null || true
    if (( SUCCESS )); then
        step "Cleanup (success)"
        helm uninstall "$RELEASE" -n "$NS" 2>/dev/null || true
    fi
}
trap on_exit EXIT

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE' — run: kubectl config use-context $PROFILE"
kubectl get cluster.postgresql.cnpg.io capstone-postgres -n "$NS" >/dev/null 2>&1 \
    || fail "capstone-postgres not found — bring the capstone up first (./scripts/cluster-up.sh)"
command -v helm >/dev/null || fail "helm not in PATH"

# ─── Build + deploy ──────────────────────────────────────────────────────────
step "Building and pushing ${IMAGE_NAME}:${IMAGE_TAG}"
./scripts/build-image.sh "$SERVICE_DIR" "$IMAGE_NAME" "$IMAGE_TAG" || fail "image build/push failed"

step "Deploying review-service"
helm upgrade --install "$RELEASE" "$CHART" -n "$NS" || fail "helm install failed"

step "Waiting for review-service to be Ready"
kubectl wait -n "$NS" --for=condition=Ready pod \
    -l app.kubernetes.io/name=review-service --timeout=180s >/dev/null 2>&1 \
    || fail "review-service pod did not become Ready"
printf '    ✓ review-service Ready\n'

# ─── Port-forward + assert the REST surface ──────────────────────────────────
step "Port-forwarding review-service ($PORT → svc:80)"
kubectl port-forward -n "$NS" "svc/${RELEASE}" "${PORT}:80" >/dev/null 2>&1 &
PF=$!
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/health" && break
    sleep 1
done

base="http://127.0.0.1:${PORT}"

step "GET /health + /healthz + /version"
curl -fsS --max-time 5 "${base}/health"  | grep -q '"status":"ok"'    || fail "/health not ok"
curl -fsS --max-time 5 "${base}/healthz" | grep -q '"status":"ready"' || fail "/healthz not ready (Postgres?)"
curl -fsS --max-time 5 "${base}/version" | grep -q '"version"'        || fail "/version missing"
printf '    ✓ probes + version OK\n'

step "GET /reviews — seeded rows present"
seeded="$(curl -fsS --max-time 5 "${base}/reviews")"
printf '%s' "$seeded" | grep -q 'SKU-ABC-42' || fail "seeded reviews not found (expected SKU-ABC-42)"
printf '    ✓ seeded reviews returned\n'

step "POST /reviews — create"
created="$(curl -fsS --max-time 5 -X POST "${base}/reviews" \
    -H 'Content-Type: application/json' \
    --data '{"sku":"SKU-NEW-1","rating":5,"reviewer":"smoke","comment":"created by smoke"}')"
rid="$(printf '%s' "$created" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
[[ -n "$rid" ]] || fail "POST /reviews did not return an id"
printf '    ✓ created review %s\n' "$rid"

step "GET /reviews/{id} — fetch back"
curl -fsS --max-time 5 "${base}/reviews/${rid}" | grep -q '"sku":"SKU-NEW-1"' \
    || fail "could not fetch the created review by id"
printf '    ✓ fetched the created review\n'

step "GET /reviews?sku=SKU-ABC-42 — filter"
filtered="$(curl -fsS --max-time 5 "${base}/reviews?sku=SKU-ABC-42")"
printf '%s' "$filtered" | grep -q 'SKU-ABC-42'  || fail "sku filter returned no SKU-ABC-42 rows"
printf '%s' "$filtered" | grep -q 'SKU-NEW-1'    && fail "sku filter leaked non-matching rows"
printf '    ✓ sku filter works\n'

SUCCESS=1
step "SUCCESS"
printf 'review-service is a working data product: REST surface + seeded data over its\n'
printf 'own reviews schema. Next (Phase A, r33): publish its OpenAPI to Apicurio and\n'
printf 'ingest it into OpenMetadata with lineage, then wrap it in a replayable up/down\n'
printf 'demo. (Postgres is shared and left running; review-service was uninstalled.)\n'
