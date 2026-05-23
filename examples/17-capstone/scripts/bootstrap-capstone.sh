#!/usr/bin/env bash
#
# bootstrap-capstone.sh — stand up the ENTIRE §17 capstone from a fresh node, in
# the correct order, with a health gate between each tier. This is the one-command
# bring-up that did not exist before (the README froze at r20 and the real order
# was scattered across setup-* scripts, smokes, and helm installs) — which is why
# every recovery had been manual archaeology.
#
# Use it after `minikube delete -p capstone` (a clean rebuild), or any time you
# want the full stack from nothing. Idempotent: helm upgrade --install, kubectl
# apply, kubectl wait, and build-only-if-missing, so re-running resumes safely.
#
# Tiers (each gated on health before the next):
#   1. profile + registry        5. Kafka operator + cluster CR
#   2. Istio                      6. KEDA
#   3. CloudNativePG operator     7. OpenMetadata (needs Postgres) + observability
#   4. Postgres cluster CR        8. images → apicurio → services → scalers → seed
#
# Catalog population (discovery contracts + OpenMetadata ingestion) is printed as
# the final follow-on rather than run inline — those need warm-server port-forwards
# and are better as explicit steps (and the ingestion Jobs opt out of the mesh, r34).
#
# Run from examples/17-capstone/:  ./scripts/bootstrap-capstone.sh

set -uo pipefail
export MINIKUBE_ROOTLESS=true

NS="capstone"
PROFILE="capstone"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

PG_RELEASE="capstone-postgres";  PG_CHART="charts/capstone/charts/postgres"
KAFKA_RELEASE="capstone-kafka";  KAFKA_CHART="charts/capstone/charts/kafka"; KAFKA_CR="capstone-kafka"
APICURIO_RELEASE="apicurio";     APICURIO_CHART="charts/capstone/charts/apicurio"
SERVICES=(graphql-gateway inventory-service notification-service order-service payment-service shipping-service)

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
fail() { printf '\n\xe2\x9c\x97 %s\n' "$1" >&2; exit 1; }

wait_rollout() { kubectl rollout status "$1" -n "$NS" --timeout="${2:-300s}"; }

# ── Tier 1: profile + registry ───────────────────────────────────────────────
step "1/8 Profile + in-cluster registry"
./scripts/setup-capstone-profile.sh || fail "profile setup failed"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] || kubectl config use-context "$PROFILE"
ok "profile up, context set"

# ── Tier 2: Istio ────────────────────────────────────────────────────────────
step "2/8 Istio control plane"
kubectl get ns istio-system >/dev/null 2>&1 && kubectl get deploy istiod -n istio-system >/dev/null 2>&1 \
    && ok "istiod already present" \
    || { ./scripts/setup-istio.sh || fail "istio setup failed"; }
kubectl wait -n istio-system --for=condition=Available deploy/istiod --timeout=180s || fail "istiod not Available"
ok "istiod Available"

# ── Tier 3: CloudNativePG operator ───────────────────────────────────────────
step "3/8 CloudNativePG operator"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 \
    && ok "CNPG CRDs present" \
    || { ./scripts/setup-postgres-operator.sh || fail "postgres-operator setup failed"; }

# ── Tier 4: Postgres cluster CR (OpenMetadata depends on this) ───────────────
step "4/8 Postgres cluster"
helm upgrade --install "$PG_RELEASE" "$PG_CHART" -n "$NS" --create-namespace || fail "postgres CR install failed"
pg_ready=0
for i in $(seq 1 72); do
    kubectl get pods -n "$NS" -l "cnpg.io/cluster=$PG_RELEASE,role=primary" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
        | grep -q True && { pg_ready=1; break; }
    sleep 5
done
(( pg_ready )) || fail "Postgres primary did not become Ready"
ok "Postgres primary Ready"

# ── Tier 5: Kafka operator + cluster ─────────────────────────────────────────
step "5/8 Kafka (Strimzi operator + cluster)"
kubectl get crd kafkas.kafka.strimzi.io >/dev/null 2>&1 \
    && ok "Strimzi CRDs present" \
    || { ./scripts/setup-kafka-operator.sh || fail "kafka-operator setup failed"; }
helm upgrade --install "$KAFKA_RELEASE" "$KAFKA_CHART" -n "$NS" || fail "kafka CR install failed"
kubectl wait "kafka/${KAFKA_CR}" -n "$NS" --for=condition=Ready --timeout=360s || fail "Kafka not Ready"
ok "Kafka cluster Ready"

# ── Tier 6: KEDA ─────────────────────────────────────────────────────────────
step "6/8 KEDA (core + HTTP add-on)"
kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1 \
    && ok "KEDA CRDs present" \
    || { ./scripts/setup-keda.sh || fail "keda setup failed"; }

# ── Tier 7: OpenMetadata (needs Postgres) + observability ────────────────────
step "7/8 OpenMetadata + observability"
kubectl get deploy openmetadata -n "$NS" >/dev/null 2>&1 \
    && ok "OpenMetadata already deployed" \
    || { ./scripts/setup-openmetadata.sh || fail "openmetadata setup failed"; }
# Ensure it's scaled up and serving (a prior session may have scaled it to 0).
kubectl scale deploy openmetadata -n "$NS" --replicas=1 >/dev/null 2>&1 || true
wait_rollout deploy/openmetadata 420s || fail "openmetadata did not roll out"
ok "OpenMetadata rolled out"
./scripts/setup-observability.sh || fail "observability setup failed"
ok "observability (Prometheus/Grafana/Tempo) installed"

# ── Tier 8: images → apicurio → services → scalers → seed ────────────────────
step "8/8 Workloads: images, apicurio, services, scalers"
HOST_PORT="$(podman port "$PROFILE" 2>/dev/null | awk -F'[:]' '/5000\/tcp/ {print $NF; exit}')"
[[ -n "$HOST_PORT" ]] || fail "registry host port not found"
for svc in "${SERVICES[@]}"; do
    if curl -fsS --max-time 4 "http://127.0.0.1:${HOST_PORT}/v2/${svc}/tags/list" 2>/dev/null | grep -q '"v1"'; then
        ok "image ${svc}:v1 present"
    else
        printf '    building %s...\n' "$svc"
        ./scripts/build-image.sh "services/${svc}" "$svc" v1 >/dev/null || fail "build of $svc failed"
        ok "built ${svc}:v1"
    fi
done

helm upgrade --install "$APICURIO_RELEASE" "$APICURIO_CHART" -n "$NS" || fail "apicurio install failed"
for svc in "${SERVICES[@]}"; do
    helm upgrade --install "$svc" "charts/capstone/charts/$svc" -n "$NS" || fail "$svc install failed"
done
# Scalers (gateway scale-to-zero + notification consumer-lag).
kubectl apply -f keda/notification-scaledobject.yaml >/dev/null 2>&1 || true
kubectl apply -f keda/gateway-httpscaledobject.yaml >/dev/null 2>&1 || true
ok "apicurio + ${#SERVICES[@]} services + scalers applied"

step "Waiting for the core services to be Ready"
# Skip graphql-gateway (KEDA-scaled to zero by design).
for svc in inventory-service notification-service order-service payment-service shipping-service; do
    kubectl rollout status "deploy/$svc" -n "$NS" --timeout=240s || fail "$svc did not become Ready"
done
ok "core services Ready"

# Seed one order so the Kafka topic + Postgres have data for the catalog/ingestion.
step "Seeding one order (gives the catalog data to ingest)"
kubectl port-forward -n "$NS" svc/order-service 18080:80 >/dev/null 2>&1 &
SEED_PF=$!; sleep 3
curl -s -o /dev/null --max-time 8 -X POST "http://127.0.0.1:18080/orders" \
    -H 'Content-Type: application/json' \
    --data '{"customer_id":"cust-1001","item_sku":"SKU-ABC-42","quantity":1,"amount":19.99}' \
    && ok "seed order placed" || printf '    (seed skipped — place one later via smoke-order.sh)\n'
kill "$SEED_PF" 2>/dev/null || true

# ── Status + follow-ons ──────────────────────────────────────────────────────
step "Cluster status"
bash ./scripts/cluster-status.sh || true

step "Bring-up complete — to populate the catalog and finish:"
cat <<EOF
    # Discovery contracts (Apicurio) + OpenMetadata catalog + lineage:
    ./demos/smoke-discovery.sh        # publishes OpenAPI/proto/SDL to Apicurio
    ./scripts/ingest-openmetadata.sh  # catalogs schemas + declares lineage (Jobs opt out of mesh, r34)

    # The Istio v1->v2 canary (Phase B) is a separate add:
    kubectl apply -f istio/routing.yaml   # after order-service-v2 is deployed

    # Phase A demo (add/back-out the review-service data product):
    ./demos/demo-add-data-product.sh up
EOF
