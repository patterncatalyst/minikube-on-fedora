#!/usr/bin/env bash
#
# smoke-om-lineage.sh — verify the OpenMetadata catalog was populated and the
# cross-product lineage declared (r27b).
#
# Does NOT run ingestion — that's scripts/ingest-openmetadata.sh. This proves
# the result, over the server API on the published NodePort 127.0.0.1:8585 (the
# smoke-openmetadata.sh pattern):
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
#   - mof-capstone profile running (kubectl/helm are pinned to it by scripts/lib/env.sh)
#   - scripts/setup-openmetadata.sh AND scripts/ingest-openmetadata.sh have run
#
# VERIFY-POINTS (OpenMetadata 1.12.8 API; confirm at build time):
#   - basic-auth login (see get_token.py), service/entity by-name endpoints,
#     and the lineage-by-name response shape (nodes + upstreamEdges +
#     downstreamEdges). These are the things most likely to need a tweak.

set -uo pipefail   # NOT -e: failures are handled so we can diagnose
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/env.sh"   # PROFILE, NS, ports; pins kubectl/helm to the profile

LOCAL_PORT="$HOST_PORT_OPENMETADATA"   # published NodePort on 127.0.0.1
OM="http://127.0.0.1:${LOCAL_PORT}"
GET_TOKEN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/openmetadata/ingestion/get_token.py"   # login lives there; credentials: see openmetadata/om-app-values.yaml

ORDERS_FQN="capstone-postgres.capstone.orders.orders"
TOPIC_FQN="capstone-kafka.order-placed"
NOTIFS_FQN="capstone-postgres.capstone.notifications.notifications"

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
    dump_diagnostics
    exit 1
}

# om_get PATH → echoes response body, returns curl's exit code
om_get() {
    curl -fsS -H "Authorization: Bearer ${TOKEN}" "${OM}$1" 2>/dev/null
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────

step "Pre-flight checks"
minikube status -p "$PROFILE" >/dev/null 2>&1 || fail "profile '$PROFILE' not running — ./scripts/setup-capstone-profile.sh"
command -v kubectl >/dev/null || fail "kubectl not in PATH"
command -v curl >/dev/null || fail "curl not in PATH"
command -v python3 >/dev/null || fail "python3 not in PATH"
kubectl get deployment openmetadata -n "$NS" >/dev/null 2>&1 \
    || fail "openmetadata not deployed — run scripts/setup-openmetadata.sh first"

# ─── Published NodePort + admin token ────────────────────────────────────────

step "Reaching the server on 127.0.0.1:${LOCAL_PORT} (published NodePort) and obtaining an admin token"
require_published_port "$PROFILE" "$NODE_PORT_OPENMETADATA" "$HOST_PORT_OPENMETADATA"
wait_for_http "${OM}/api/v1/system/version" 120 || fail "no response from ${OM} — is the server serving?"
TOKEN="$(OM_HOST="$OM" python3 "$GET_TOKEN" 2>/dev/null || echo '')"
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
printf '  http://127.0.0.1:%s   (credentials: see openmetadata/om-app-values.yaml)\n' "$LOCAL_PORT"
