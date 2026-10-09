#!/usr/bin/env bash
#
# smoke-openmetadata.sh — verify the OpenMetadata catalog is deployed and
# healthy (r27).
#
# Unlike the per-service smokes, this does NOT install OpenMetadata — that's a
# platform install done once by scripts/setup-openmetadata.sh (mirroring the
# operator setups). This smoke assumes that ran, and proves the result:
#   * the openmetadata Deployment is rolled out
#   * the server answers its version API (proves it booted AND reached its
#     Postgres backend — OpenMetadata won't serve without a working DB)
#   * the version it reports is the pinned 2.0.5
#   * the dedicated `openmetadata` database really exists in capstone-postgres
#     and was populated by the server's migrations (sanity that Postgres reuse,
#     not bundled MySQL, is what's backing it)
#
# On failure it leaves resources in place and dumps diagnostics (the §11/§12
# pattern). Idempotent. Run from examples/17-capstone/:
#   ./demos/smoke-openmetadata.sh
#
# Prerequisites:
#   - mof-capstone profile running (kubectl/helm are pinned to it by scripts/lib/env.sh)
#   - scripts/setup-openmetadata.sh has been run (OpenMetadata installed)

set -uo pipefail   # NOT -e: failures are handled explicitly so we can diagnose
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/env.sh"   # PROFILE, NS, ports; pins kubectl/helm to the profile

PG_CLUSTER="capstone-postgres"
OM_DB="openmetadata"
EXPECTED_VERSION="2.0.5"
LOCAL_PORT="$HOST_PORT_OPENMETADATA"   # published NodePort on 127.0.0.1
SUCCESS=0

step() { printf '\n==> %s\n' "$1"; }

dump_diagnostics() {
    step "DIAGNOSTIC DUMP (failure — resources left in place for inspection)"
    printf '\n--- pods (capstone) ---\n'
    kubectl get pods -n "$NS" -o wide 2>&1
    local pod
    pod=$(kubectl get pods -n "$NS" -l app.kubernetes.io/name=openmetadata \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$pod" ]]; then
        printf '\n--- describe %s (events) ---\n' "$pod"
        kubectl describe pod -n "$NS" "$pod" 2>&1 | tail -35
        printf '\n--- openmetadata server logs ---\n'
        kubectl logs -n "$NS" "$pod" --tail=80 2>&1
    fi
    printf '\n--- migrate / reindex jobs (if any) ---\n'
    kubectl get jobs -n "$NS" 2>&1 | grep -i 'openmetadata\|migrate\|reindex' || echo "(no jobs)"
    printf '\nResources left running. To inspect or clean up:\n'
    printf '  kubectl logs -n %s deploy/openmetadata\n' "$NS"
    printf '  helm uninstall openmetadata openmetadata-dependencies -n %s\n' "$NS"
}

fail() {
    printf '\n✗ FAILED: %s\n' "$1" >&2
    dump_diagnostics
    exit 1
}


# ─── Pre-flight ──────────────────────────────────────────────────────────────

step "Pre-flight checks"
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
command -v kubectl >/dev/null || fail "kubectl not in PATH"
kubectl get deployment openmetadata -n "$NS" >/dev/null 2>&1 \
    || fail "openmetadata Deployment not found — run scripts/setup-openmetadata.sh first"

# ─── Rollout ─────────────────────────────────────────────────────────────────

step "Waiting for the OpenMetadata server to be rolled out"
kubectl rollout status deployment/openmetadata -n "$NS" --timeout=5m \
    || fail "openmetadata Deployment did not become available"
printf '    ✓ deployment available\n'

# ─── Version API (proves booted + DB-backed) ─────────────────────────────────

step "Querying the server version API (proves it booted and reached Postgres)"
require_published_port "$PROFILE" "$NODE_PORT_OPENMETADATA" "$HOST_PORT_OPENMETADATA"
wait_for_http "http://127.0.0.1:${LOCAL_PORT}/api/v1/system/version" 120 \
    || fail "no response from 127.0.0.1:${LOCAL_PORT} (the openmetadata-host NodePort) — is the server serving?"

VERSION_JSON="$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/api/v1/system/version" 2>/dev/null || echo '')"
[[ -n "$VERSION_JSON" ]] \
    || fail "no response from /api/v1/system/version (server up but not serving — check DB connectivity in the server logs)"
printf '    server reported: %s\n' "$VERSION_JSON"

echo "$VERSION_JSON" | grep -q "$EXPECTED_VERSION" \
    || fail "version API did not report expected ${EXPECTED_VERSION} (got: ${VERSION_JSON})"
printf '    ✓ version %s serving over the API\n' "$EXPECTED_VERSION"

# ─── Confirm Postgres (not MySQL) is the backend ─────────────────────────────

step "Confirming the openmetadata database exists in ${PG_CLUSTER} and was populated"
PG_PRIMARY="$(kubectl get pods -n "$NS" \
    -l "cnpg.io/cluster=${PG_CLUSTER},cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
[[ -n "$PG_PRIMARY" ]] || fail "no capstone-postgres primary pod found"

# The server's migrations create many tables in the openmetadata database.
# A non-zero count proves Postgres reuse is the live backend.
TABLE_COUNT="$(kubectl exec -n "$NS" "$PG_PRIMARY" -c postgres -- \
    psql -U postgres -d "$OM_DB" -tAqc \
    "select count(*) from information_schema.tables where table_schema='public'" \
    2>/dev/null || echo "0")"
printf '    public tables in %s: %s\n' "$OM_DB" "$TABLE_COUNT"
[[ "${TABLE_COUNT:-0}" -gt 0 ]] \
    || fail "openmetadata database has no tables — migrations did not run against Postgres"
printf '    ✓ Postgres-backed (openmetadata db populated with %s tables)\n' "$TABLE_COUNT"

# ─── Done ────────────────────────────────────────────────────────────────────

SUCCESS=1
step "SUCCESS"
printf 'OpenMetadata %s is deployed, Postgres-backed, and serving its API.\n' "$EXPECTED_VERSION"
printf 'Open the UI with:\n'
printf '  http://127.0.0.1:%s   (credentials: see openmetadata/om-app-values.yaml)\n' "$LOCAL_PORT"
printf '\nNext (r27b): register Postgres + Kafka, ingest, and declare lineage.\n'
