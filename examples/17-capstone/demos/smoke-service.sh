#!/usr/bin/env bash
#
# smoke-service.sh — build, deploy, and verify the health surface of a
# scaffolded capstone service (r22). Generic counterpart to smoke-order.sh
# (which also asserts order-service's domain endpoints).
#
# What it does:
#   1. build + push the service image to the in-cluster registry (CAP-007/009)
#   2. ensure the shared Postgres cluster is up (deploys the CR if absent)
#   3. helm upgrade --install the service subchart
#   4. wait for rollout, then assert GET /health and GET /healthz
#   5. clean up the service release ON SUCCESS only (CAP-008); on failure,
#      leave it running and dump diagnostics
#
# Usage:
#   ./demos/smoke-service.sh <name>            e.g. ./demos/smoke-service.sh inventory
#   ./demos/smoke-service.sh <name> --purge-db   also tears down Postgres at the end

set -uo pipefail   # NOT -e: we manage failures explicitly so we can diagnose
export MINIKUBE_ROOTLESS=true   # CAP-010: mandatory for rootless-podman host ops

BASE="${1:?usage: smoke-service.sh <name> [--purge-db]}"
SERVICE="${BASE}-service"
PURGE_DB=0
[[ "${2:-}" == "--purge-db" ]] && PURGE_DB=1

PROFILE="capstone"
NS="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SVC_DIR="services/${SERVICE}"
CHART="charts/capstone/charts/${SERVICE}"
PG_RELEASE="capstone-postgres"
PG_CHART="charts/capstone/charts/postgres"   # the Cluster CR chart (r21)
LOCAL_PORT=18080

step() { printf '\n==> %s\n' "$1"; }
fail() {
    printf '\nFAILED: %s\n' "$1" >&2
    diagnostics
    printf '\nResources left in place for inspection. Clean up with:\n' >&2
    printf '  helm uninstall %s -n %s\n' "$SERVICE" "$NS" >&2
    exit 1
}

diagnostics() {
    printf '\n--- diagnostics: %s ---\n' "$SERVICE" >&2
    kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${SERVICE}" -o wide 2>&1 || true
    printf '\n--- describe ---\n' >&2
    kubectl describe pod -n "$NS" -l "app.kubernetes.io/name=${SERVICE}" 2>&1 | tail -40 || true
    printf '\n--- current logs ---\n' >&2
    kubectl logs -n "$NS" -l "app.kubernetes.io/name=${SERVICE}" --tail=50 2>&1 || true
    printf '\n--- previous logs (if crashed) ---\n' >&2
    kubectl logs -n "$NS" -l "app.kubernetes.io/name=${SERVICE}" --previous --tail=50 2>&1 || true
    printf '\n--- registry catalog ---\n' >&2
    local hp; hp="$(podman port "$PROFILE" 2>/dev/null | awk -F: '/5000\/tcp/{print $NF; exit}')"
    [[ -n "$hp" ]] && curl -fsS "http://127.0.0.1:${hp}/v2/_catalog" 2>&1 || echo "(could not query registry)" >&2
}

[[ -d "$SVC_DIR" ]] || fail "service dir $SVC_DIR not found — scaffold it first: ./scripts/scaffold-service.sh $BASE <schema>"
[[ -d "$CHART"   ]] || fail "chart dir $CHART not found"

step "Sanity: chart image.repository points at the registry"
repo="$(awk '/^  repository:/{print $2; exit}' "$CHART/values.yaml")"
case "$repo" in
    localhost:5000/*) printf '    \xe2\x9c\x93 %s -> %s\n' "$SERVICE" "$repo" ;;
    *) fail "$SERVICE image.repository is '$repo' - must start with localhost:5000/ (a bare name pulls from Docker Hub and ErrImagePulls)" ;;
esac

step "Pre-flight: profile + context"
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
kubectl config use-context "$PROFILE" >/dev/null

step "Build + push ${SERVICE}:v1 to the in-cluster registry"
./scripts/build-image.sh "$SVC_DIR" "$SERVICE" v1 || fail "image build/push failed"

step "Ensure the shared Postgres cluster is up"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 \
    || fail "CloudNativePG operator not installed — ./scripts/setup-postgres-operator.sh"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace \
    || fail "postgres CR install failed"

step "Waiting for the Postgres cluster primary to be Ready"
pg_ready=0
for i in $(seq 1 60); do
    if kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
        | grep -q "True"; then
        printf '    primary pod Ready after ~%ds\n' "$((i*5))"
        pg_ready=1
        break
    fi
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready within 300s"

step "Deploying ${SERVICE}"
helm upgrade --install "$SERVICE" "$CHART" -n "$NS" || fail "helm install failed"
kubectl rollout status "deployment/${SERVICE}" -n "$NS" --timeout=120s || fail "rollout did not complete"

step "Port-forwarding ${SERVICE} to 127.0.0.1:${LOCAL_PORT}"
kubectl port-forward -n "$NS" "service/${SERVICE}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF=$!
trap '[[ -n "${PF:-}" ]] && kill "$PF" 2>/dev/null' EXIT
sleep 3

step "Assert GET /health returns ok"
H="$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health")" || fail "/health did not return 200"
echo "    $H"
echo "$H" | grep -q '"status":"ok"' || fail "/health body unexpected: $H"
echo "$H" | grep -q "\"service\":\"${SERVICE}\"" || fail "/health service name mismatch: $H"

step "Assert GET /healthz reports readiness (Postgres reachable)"
Z="$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/healthz")" || fail "/healthz did not return 200 (Postgres unreachable?)"
echo "    $Z"
echo "$Z" | grep -q '"status":"ready"' || fail "/healthz not ready: $Z"

step "Verify the schema exists in Postgres (direct query)"
SCHEMA="$(helm get values "$SERVICE" -n "$NS" -a 2>/dev/null | awk '/schema:/{print $2; exit}')"
SCHEMA="${SCHEMA:-$BASE}"
PRIMARY="$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=${PG_RELEASE},role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [[ -n "$PRIMARY" ]]; then
    if kubectl exec -n "$NS" "$PRIMARY" -- psql -U postgres -d capstone -tAc \
        "SELECT 1 FROM information_schema.schemata WHERE schema_name='${SCHEMA}'" 2>/dev/null | grep -q 1; then
        printf '    confirmed: schema "%s" exists\n' "$SCHEMA"
    else
        printf '    note: schema "%s" not found via direct query (probe-level readiness still passed)\n' "$SCHEMA"
    fi
fi

printf '\n✓ SUCCESS — %s health skeleton verified\n' "$SERVICE"
printf '  (Postgres left running for fast re-runs; pass --purge-db to tear it down)\n'

step "Cleanup (success)"
kill "$PF" 2>/dev/null; PF=""
helm uninstall "$SERVICE" -n "$NS" >/dev/null 2>&1 && echo "release \"${SERVICE}\" uninstalled"
if (( PURGE_DB )); then
    helm uninstall "$PG_RELEASE" -n "$NS" >/dev/null 2>&1 && echo "release \"${PG_RELEASE}\" uninstalled"
fi
