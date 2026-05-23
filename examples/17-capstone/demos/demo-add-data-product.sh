#!/usr/bin/env bash
#
# demo-add-data-product.sh up|down — the Phase A demonstration, replayable.
#
# Walks the full add-a-data-product-to-the-mesh workflow for review-service, then
# backs it out so it can be replayed:
#
#   up    deploy the product → publish its OpenAPI contract to Apicurio →
#         ingest it into OpenMetadata (catalog + reviews->products lineage) →
#         print the ways to retrieve the data and discover its metadata.
#   down  remove the lineage edge → delete the catalog entry → delete the
#         Apicurio artifact → uninstall the service → drop its Postgres schema.
#         Returns the mesh to baseline.
#
# This is a TEMPORARY demo product; `down` leaves no trace. Reuses the proven
# discovery machinery (publish pattern, ingest-openmetadata.sh, get_token.py).
#
# Assumes the capstone is up (Apicurio, OpenMetadata, Postgres, inventory-service
# all running — the products lineage target is inventory.stock). Run from
# examples/17-capstone/:  ./demos/demo-add-data-product.sh up   (then ... down)

set -uo pipefail
export MINIKUBE_ROOTLESS=true

NS="capstone"
RELEASE="review-service"
CHART="charts/capstone/charts/review-service"
SERVICE_DIR="services/review-service"
IMAGE="review-service"; TAG="v1"

GROUP="default"
ARTIFACT_ID="review-service-openapi"
REVIEWS_SCHEMA_FQN="capstone-postgres.capstone.reviews"
REVIEWS_TABLE_FQN="capstone-postgres.capstone.reviews.reviews"

L_REVIEW="18086"; L_APIC="18085"; L_OM="18585"
PIDS=()

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
warn() { printf '    \xe2\x9a\xa0 %s\n' "$1"; }
fail() { printf '\n\xe2\x9c\x97 FAILED: %s\n' "$1" >&2; cleanup; exit 1; }
cleanup() { for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

pf() {  # pf <local> <svc> <remote> ; records pid, waits for the tunnel
    kubectl port-forward -n "$NS" "svc/$2" "$1:$3" >/dev/null 2>&1 &
    PIDS+=("$!")
    sleep 2
}

om_token() {  # echoes an admin bearer token from the port-forwarded server
    OM_HOST="http://127.0.0.1:${L_OM}" python3 openmetadata/ingestion/get_token.py
}

MODE="${1:-}"
[[ "$MODE" == "up" || "$MODE" == "down" ]] || { echo "usage: $0 up|down" >&2; exit 2; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight"
[[ "$(kubectl config current-context 2>/dev/null)" == "capstone" ]] \
    || fail "kubectl context is not 'capstone'"
for svc in apicurio openmetadata; do
    kubectl get svc "$svc" -n "$NS" >/dev/null 2>&1 \
        || fail "$svc not found — bring the capstone up (./scripts/cluster-up.sh)"
done

if [[ "$MODE" == "up" ]]; then
    # ── 1. Deploy the product ────────────────────────────────────────────────
    step "Deploying the review-service data product"
    ./scripts/build-image.sh "$SERVICE_DIR" "$IMAGE" "$TAG" || fail "image build failed"
    helm upgrade --install "$RELEASE" "$CHART" -n "$NS" || fail "helm install failed"
    kubectl wait -n "$NS" --for=condition=Ready pod \
        -l app.kubernetes.io/name=review-service --timeout=180s >/dev/null 2>&1 \
        || fail "review-service did not become Ready"
    ok "review-service deployed and Ready (its reviews schema is created + seeded)"

    # ── 2. Publish the OpenAPI contract to Apicurio ──────────────────────────
    step "Publishing the OpenAPI contract to Apicurio"
    pf "$L_REVIEW" review-service 80
    pf "$L_APIC" apicurio 8080
    python3 - "$ARTIFACT_ID" "$GROUP" "http://127.0.0.1:${L_REVIEW}" "http://127.0.0.1:${L_APIC}" <<'PY' || fail "publish to Apicurio failed"
import json, sys, urllib.request, urllib.error
artifact_id, group, review_url, apicurio = sys.argv[1:5]
openapi = urllib.request.urlopen(f"{review_url}/openapi.json", timeout=10).read().decode()
body = json.dumps({"artifactId": artifact_id, "artifactType": "OPENAPI",
    "firstVersion": {"content": {"content": openapi, "contentType": "application/json"}}}).encode()
url = f"{apicurio}/apis/registry/v3/groups/{group}/artifacts"
req = urllib.request.Request(url, data=body, method="POST", headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req, timeout=10).read(); print("    published", artifact_id)
except urllib.error.HTTPError as e:
    print(f"    {artifact_id} already registered" if e.code == 409 else f"    HTTP {e.code}", file=sys.stderr)
    if e.code != 409: raise
PY
    ok "OpenAPI contract registered as '$ARTIFACT_ID'"

    # ── 3. Ingest into OpenMetadata (re-catalogs all schemas incl. reviews) ──
    step "Cataloging in OpenMetadata (re-running ingestion)"
    ./scripts/ingest-openmetadata.sh || fail "OpenMetadata ingestion failed"
    ok "reviews schema cataloged"

    # ── 4. Declare reviews -> products lineage ───────────────────────────────
    step "Declaring lineage (inventory.stock -> reviews.reviews)"
    pf "$L_OM" openmetadata 8585
    TOKEN="$(om_token)"; [[ -n "$TOKEN" ]] || fail "could not get an OpenMetadata token"
    OM_HOST="http://127.0.0.1:${L_OM}" OM_JWT="$TOKEN" \
        python3 openmetadata/ingestion/reviews_lineage.py up || fail "lineage declaration failed"
    ok "lineage edge declared"

    # ── 5. Verify the catalog entry exists ───────────────────────────────────
    step "Verifying the reviews table is in the catalog"
    code="$(curl -s -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer $TOKEN" \
        "http://127.0.0.1:${L_OM}/api/v1/tables/name/$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$REVIEWS_TABLE_FQN")")"
    [[ "$code" == "200" ]] || warn "reviews table not found in catalog yet (HTTP $code) — ingestion may lag; check Explore"
    [[ "$code" == "200" ]] && ok "reviews table present in OpenMetadata"

    # ── Ways in ──────────────────────────────────────────────────────────────
    step "The data product is live. Ways to retrieve it and discover its metadata:"
    cat <<EOF
    Retrieve the data (REST):
      kubectl port-forward -n $NS svc/review-service 8086:80
      curl -s localhost:8086/reviews?sku=SKU-ABC-42 | jq

    Discover the contract (Apicurio):
      kubectl port-forward -n $NS svc/apicurio 8085:8080
      open http://localhost:8085  → artifact '$ARTIFACT_ID' (OpenAPI)

    Discover the data + lineage (OpenMetadata):
      kubectl port-forward -n $NS svc/openmetadata 8585:8585
      open http://localhost:8585  → search 'reviews' → Lineage tab
        (reviews.reviews linked to inventory.stock)

    Replay/clean up:  ./demos/demo-add-data-product.sh down
EOF

else
    # ═══ down: remove every trace, return to baseline ════════════════════════
    step "Backing out the review-service data product"

    # 1. lineage edge + 2. catalog entry (best-effort; OM API verify-points)
    pf "$L_OM" openmetadata 8585
    TOKEN="$(om_token || true)"
    if [[ -n "$TOKEN" ]]; then
        OM_HOST="http://127.0.0.1:${L_OM}" OM_JWT="$TOKEN" \
            python3 openmetadata/ingestion/reviews_lineage.py down || warn "lineage removal reported an issue"
        # Delete the reviews schema entity (removes its tables from the catalog).
        sch="$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$REVIEWS_SCHEMA_FQN")"
        c="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H "Authorization: Bearer $TOKEN" \
            "http://127.0.0.1:${L_OM}/api/v1/databaseSchemas/name/${sch}?hardDelete=true&recursive=true")"
        [[ "$c" =~ ^20 ]] && ok "removed reviews schema from the catalog" || warn "catalog schema delete returned HTTP $c (verify-point)"
    else
        warn "no OpenMetadata token — skipping catalog cleanup; remove 'reviews' in Explore manually"
    fi

    # 3. Apicurio artifact
    step "Deleting the Apicurio artifact"
    pf "$L_APIC" apicurio 8080
    c="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
        "http://127.0.0.1:${L_APIC}/apis/registry/v3/groups/${GROUP}/artifacts/${ARTIFACT_ID}")"
    [[ "$c" =~ ^20 || "$c" == "404" ]] && ok "Apicurio artifact removed" || warn "artifact delete returned HTTP $c"

    # 4. Uninstall the service
    step "Uninstalling review-service"
    helm uninstall "$RELEASE" -n "$NS" 2>/dev/null && ok "helm release removed" || warn "release was not installed"

    # 5. Drop the Postgres schema (so a future re-ingest won't re-add it)
    step "Dropping the reviews Postgres schema"
    primary="$(kubectl get pods -n "$NS" -l cnpg.io/cluster=capstone-postgres,role=primary -o name 2>/dev/null | head -1)"
    if [[ -n "$primary" ]]; then
        kubectl exec -n "$NS" "$primary" -c postgres -- \
            psql -U postgres -d capstone -c 'DROP SCHEMA IF EXISTS reviews CASCADE' >/dev/null 2>&1 \
            && ok "reviews schema dropped" || warn "could not drop reviews schema (verify-point: pod/user)"
    else
        warn "could not find the Postgres primary to drop the schema"
    fi

    step "Baseline restored"
    printf 'review-service removed from the mesh: service, contract, catalog entry, lineage,\n'
    printf 'and schema. Run `%s up` to replay the demonstration.\n' "$0"
fi
