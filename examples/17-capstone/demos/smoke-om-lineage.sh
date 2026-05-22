#!/usr/bin/env bash
#
# smoke-om-lineage.sh — verify the OpenMetadata catalog was populated and the
# cross-product lineage declared (r27b).
#
# Does NOT run ingestion — that's scripts/ingest-openmetadata.sh. This proves
# the result, over the server API (via a port-forward, the smoke-openmetadata.sh
# pattern):
#   * the Database Service  capstone-postgres  exists
#   * the Messaging Service capstone-kafka      exists
#   * the three spine entities exist:
#       - table  capstone-postgres.capstone.orders.orders
#       - topic  capstone-kafka.order-placed
#       - table  capstone-postgres.capstone.notifications.notifications
#   * lineage on the topic has an upstream (orders) AND a downstream
#     (notifications) edge — i.e. orders -> order-placed -> notifications
#
# On failure it leaves resources in place and dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:
#   ./demos/smoke-om-lineage.sh
#
# Prerequisites:
#   - capstone profile running, kubectl context = capstone
#   - scripts/setup-openmetadata.sh AND scripts/ingest-openmetadata.sh have run
#
# VERIFY-POINTS (OpenMetadata 1.12.8 API; confirm at build time):
#   - basic-auth login (see get_token.py), service/entity by-name endpoints,
#     and the lineage-by-name response shape (nodes + upstreamEdges +
#     downstreamEdges). These are the things most likely to need a tweak.

set -uo pipefail   # NOT -e: failures are handled so we can diagnose
export MINIKUBE_ROOTLESS=true   # CAP-010

NS="capstone"
PROFILE="capstone"
LOCAL_PORT="8585"
OM="http://127.0.0.1:${LOCAL_PORT}"
ADMIN_EMAIL="admin@open-metadata.org"
ADMIN_PASSWORD="admin"   # demo default (r27)

ORDERS_FQN="capstone-postgres.capstone.orders.orders"
TOPIC_FQN="capstone-kafka.order-placed"
NOTIFS_FQN="capstone-postgres.capstone.notifications.notifications"

PORT_FORWARD_PID=""
TOKEN=""

step() { printf '\n==> %s\n' "$1"; }

dump_diagnostics() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    printf '\n--- ingestion jobs ---\n'
    kubectl get jobs -n "$NS" -l app.kubernetes.io/component=openmetadata-ingestion 2>&1
    printf '\n--- recent logs per ingestion job ---\n'
    for j in om-ingest-postgres om-ingest-kafka om-declare-lineage; do
        printf '  [%s]\n' "$j"
        kubectl logs -n "$NS" "job/$j" --tail=25 2>&1 | sed 's/^/    /' || true
    done
    printf '\nRe-run ingestion with: ./scripts/ingest-openmetadata.sh\n'
}

fail() {
    printf '\n✗ FAILED: %s\n' "$1" >&2
    [[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null
    dump_diagnostics
    exit 1
}

trap '[[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT

# om_get PATH → echoes response body, returns curl's exit code
om_get() {
    curl -fsS -H "Authorization: Bearer ${TOKEN}" "${OM}$1" 2>/dev/null
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────

step "Pre-flight checks"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE' — run: kubectl config use-context $PROFILE"
command -v kubectl >/dev/null || fail "kubectl not in PATH"
command -v curl >/dev/null || fail "curl not in PATH"
command -v python3 >/dev/null || fail "python3 not in PATH"
kubectl get deployment openmetadata -n "$NS" >/dev/null 2>&1 \
    || fail "openmetadata not deployed — run scripts/setup-openmetadata.sh first"

# ─── Port-forward + admin token ──────────────────────────────────────────────

step "Port-forwarding the server and obtaining an admin token"
kubectl port-forward -n "$NS" svc/openmetadata "${LOCAL_PORT}:8585" >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 4

PW_B64="$(printf '%s' "$ADMIN_PASSWORD" | base64)"
LOGIN_JSON="$(curl -fsS -X POST "${OM}/api/v1/users/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${PW_B64}\"}" 2>/dev/null || echo '')"
TOKEN="$(printf '%s' "$LOGIN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("accessToken",""))' 2>/dev/null || echo '')"
[[ -n "$TOKEN" ]] || fail "could not obtain an admin token (is the server serving? check auth provider)"
printf '    ✓ authenticated\n'

# ─── Services ────────────────────────────────────────────────────────────────

step "Confirming the ingested services exist"
om_get "/api/v1/services/databaseServices/name/capstone-postgres" >/dev/null \
    || fail "Database Service 'capstone-postgres' not found — did om-ingest-postgres run?"
printf '    ✓ database service capstone-postgres\n'
om_get "/api/v1/services/messagingServices/name/capstone-kafka" >/dev/null \
    || fail "Messaging Service 'capstone-kafka' not found — did om-ingest-kafka run?"
printf '    ✓ messaging service capstone-kafka\n'

# ─── Spine entities ──────────────────────────────────────────────────────────

step "Confirming the three spine entities were cataloged"
om_get "/api/v1/tables/name/$(python3 -c "import urllib.parse;print(urllib.parse.quote('${ORDERS_FQN}',safe=''))")" >/dev/null \
    || fail "table ${ORDERS_FQN} not found"
printf '    ✓ table orders\n'
om_get "/api/v1/topics/name/$(python3 -c "import urllib.parse;print(urllib.parse.quote('${TOPIC_FQN}',safe=''))")" >/dev/null \
    || fail "topic ${TOPIC_FQN} not found"
printf '    ✓ topic order-placed\n'
om_get "/api/v1/tables/name/$(python3 -c "import urllib.parse;print(urllib.parse.quote('${NOTIFS_FQN}',safe=''))")" >/dev/null \
    || fail "table ${NOTIFS_FQN} not found"
printf '    ✓ table notifications\n'

# ─── Lineage edges ───────────────────────────────────────────────────────────

step "Confirming lineage: orders -> order-placed -> notifications"
TOPIC_ENC="$(python3 -c "import urllib.parse;print(urllib.parse.quote('${TOPIC_FQN}',safe=''))")"
LINEAGE_JSON="$(om_get "/api/v1/lineage/topic/name/${TOPIC_ENC}?upstreamDepth=1&downstreamDepth=1")" \
    || fail "could not fetch lineage for the order-placed topic"

# Assert at least one upstream edge (orders -> topic) and one downstream edge
# (topic -> notifications). The response carries upstreamEdges/downstreamEdges
# arrays; we only need each to be non-empty.
read -r UP DOWN < <(printf '%s' "$LINEAGE_JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(len(d.get("upstreamEdges", []) or []), len(d.get("downstreamEdges", []) or []))
' 2>/dev/null || echo "0 0")
printf '    upstream edges: %s   downstream edges: %s\n' "${UP:-0}" "${DOWN:-0}"
[[ "${UP:-0}" -ge 1 ]] || fail "no upstream edge into order-placed (orders -> order-placed missing)"
[[ "${DOWN:-0}" -ge 1 ]] || fail "no downstream edge from order-placed (order-placed -> notifications missing)"
printf '    ✓ both edges present — the cross-product spine is wired\n'

# ─── Done ────────────────────────────────────────────────────────────────────

step "SUCCESS"
printf 'The catalog is populated and the lineage is declared:\n'
printf '  orders (Postgres) -> order-placed (Kafka) -> notifications (Postgres)\n\n'
printf 'Browse it:\n'
printf '  kubectl port-forward -n %s svc/openmetadata 8585:8585\n' "$NS"
printf '  http://127.0.0.1:8585  (admin@open-metadata.org / admin)\n'
