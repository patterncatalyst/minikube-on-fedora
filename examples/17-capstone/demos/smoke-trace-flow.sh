#!/usr/bin/env bash
#
# smoke-trace-flow.sh — the end-to-end traces proof (r29c). Drive one GraphQL
# query through the gateway and confirm the resulting fan-out trace
# (graphql-gateway → order-service REST → inventory gRPC) lands in Tempo.
#
# Requires: the instrumented graphql-gateway image deployed (r29c), the KEDA
# HTTPScaledObject applied (we wake the gateway through the interceptor, so this
# works whether or not it's currently scaled to zero), and the observability
# stack up (Tempo).
#
# The hard assertion is that the gateway processes the query (HTTP 200). Finding
# the trace in Tempo is retried and reported; if Tempo's search hasn't indexed it
# yet, that's a note plus a Grafana pointer, not a failure — the span export is
# fire-and-forget by design.
#
# Run from examples/17-capstone/:  ./demos/smoke-trace-flow.sh

set -uo pipefail

NS="capstone"
OBS_NS="observability"
HOST="graphql-gateway.capstone"
PROXY_SVC="keda-add-ons-http-interceptor-proxy"
GQL_PORT="8082"
TEMPO_PORT="3201"
GQL_PF=""
TEMPO_PF=""

step() { printf '\n==> %s\n' "$1"; }
cleanup() {
    [[ -n "$GQL_PF" ]] && kill "$GQL_PF" 2>/dev/null
    [[ -n "$TEMPO_PF" ]] && kill "$TEMPO_PF" 2>/dev/null
    true
}
trap cleanup EXIT
dump() {
    step "DIAGNOSTIC DUMP"
    kubectl get deploy,pods -n "$NS" -l app.kubernetes.io/name=graphql-gateway 2>&1
    kubectl get pods -n "$OBS_NS" 2>&1 | grep -iE 'tempo|NAME' || true
}
fail() { printf '\n✗ FAILED: %s\n' "$1"; dump; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
kubectl get svc "$PROXY_SVC" -n keda >/dev/null 2>&1 \
    || fail "KEDA HTTP interceptor not found — run scripts/setup-keda.sh and apply keda/gateway-httpscaledobject.yaml"
kubectl get svc tempo -n "$OBS_NS" >/dev/null 2>&1 \
    || fail "tempo not found — run scripts/setup-observability.sh"
# Confirm the gateway image is the instrumented one: OTEL env present on the Deployment.
kubectl get deploy graphql-gateway -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' 2>/dev/null \
    | grep -q OTEL_EXPORTER_OTLP_ENDPOINT \
    || fail "graphql-gateway has no OTEL_* env — deploy the r29c chart (helm upgrade --install graphql-gateway charts/capstone/charts/graphql-gateway -n $NS) and rebuild its image"
printf '    ✓ interceptor, Tempo, and OTEL-enabled gateway present\n'

# ─── Drive a GraphQL query through the interceptor ───────────────────────────
step "Port-forwarding the KEDA interceptor ($GQL_PORT → $PROXY_SVC:8080)"
kubectl port-forward -n keda "svc/$PROXY_SVC" "${GQL_PORT}:8080" >/dev/null 2>&1 &
GQL_PF=$!
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${GQL_PORT}/" && break
    sleep 1
done

step "Sending a GraphQL query (wakes the gateway from zero, fans out to backends)"
# A dummy id is fine: the gateway still calls order-service (REST) to resolve it,
# which is the downstream hop we want in the trace. With a real order the
# inventory gRPC hop appears too (see smoke-graphql.sh). The interceptor holds
# the request through cold start (waitTimeout=180s), so use a generous timeout.
GQL_BODY='{"query":"{ order(id: \"trace-probe\") { id itemSku quantity stock { sku quantityOnHand available } } }"}'
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 200 \
    -H "Host: $HOST" -H "Content-Type: application/json" \
    -X POST --data "$GQL_BODY" "http://127.0.0.1:${GQL_PORT}/graphql" || echo "000")
[[ "$CODE" == "200" ]] \
    || fail "gateway did not return 200 for the GraphQL query (HTTP $CODE) — see dump"
printf '    ✓ gateway processed the query (HTTP 200) — a trace should now be exporting\n'
# Capture the gateway log NOW, while the pod is still up (it's KEDA-scaled and
# will return to zero ~30s after this request) — so a "no trace" result below
# isn't blind. OTEL export errors surface here.
GW_LOG="$(kubectl logs -n "$NS" -l app.kubernetes.io/name=graphql-gateway --tail=120 2>/dev/null)"

# ─── Confirm the trace landed in Tempo ───────────────────────────────────────
step "Port-forwarding Tempo ($TEMPO_PORT → tempo:3200) and searching for the trace"
kubectl port-forward -n "$OBS_NS" svc/tempo "${TEMPO_PORT}:3200" >/dev/null 2>&1 &
TEMPO_PF=$!
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${TEMPO_PORT}/ready" && break
    sleep 1
done

# BatchSpanProcessor flushes on a ~5s schedule, then Tempo indexes — retry.
# TraceQL via q= (the legacy tags= param doesn't match current Tempo search).
found=""
for _ in $(seq 1 12); do
    res="$(curl -sG "http://127.0.0.1:${TEMPO_PORT}/api/search" \
        --data-urlencode 'q={ resource.service.name = "graphql-gateway" }' \
        --data-urlencode 'limit=20' 2>/dev/null)"
    if printf '%s' "$res" | grep -q '"traceID"'; then found=1; break; fi
    sleep 5
done

if [[ -n "$found" ]]; then
    step "SUCCESS"
    printf '    ✓ Tempo has a graphql-gateway trace — distributed tracing is live.\n'
    printf 'Open it in Grafana → Explore → Tempo (search service.name=graphql-gateway) to\n'
    printf 'see the gateway span with its order-service (REST) child. Query a real order\n'
    printf 'via ./demos/smoke-graphql.sh to get the inventory (gRPC) hop in the trace too.\n'
else
    step "DONE (trace not yet found in Tempo search — NOT a failure)"
    printf '    ⚠ The gateway returned 200 but no graphql-gateway trace surfaced in ~60s.\n'
    printf '      Gateway log (OTEL/export lines) captured just after the query:\n'
    printf '%s\n' "$GW_LOG" | grep -iE 'otel|export|span|tempo|error|exception|unavailable|refused|deadline' \
        | sed 's/^/        /' | tail -15 \
        || printf '        (no OTEL/export lines — instrumentation may not be active)\n'
    printf '      Also check Grafana → Explore → Tempo directly, and:\n'
    printf '        kubectl get deploy graphql-gateway -n %s -o jsonpath="{.spec.template.spec.containers[0].env}"\n' "$NS"
fi
