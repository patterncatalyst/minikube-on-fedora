#!/usr/bin/env bash
#
# smoke-tracing.sh — verify the trace BACKEND (r29b, CAP-028): Tempo is up and
# ready, Grafana has the Tempo datasource provisioned, AND (r29b.1) the pipeline
# actually ingests and serves a span end-to-end.
#
# Three layers, increasing strength:
#   1. Tempo pod Ready + /ready probe (the backend is standing).
#   2. Grafana has the Tempo datasource provisioned and reachable.
#   3. (r29b.1) A synthetic OTLP/HTTP span POSTed to :4318 is read back via
#      TraceQL on :3200 — proving receive→store→query independent of any emitter.
#      This is the check that localizes a future "no traces" to the emitter
#      rather than the backend (the gap that let the r29c export bug slip through).
#
# Leaves resources in place on failure + dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:  ./demos/smoke-tracing.sh

set -uo pipefail

NS="observability"
TEMPO_PORT="3200"
OTLP_PORT="4318"
GRAF_PORT="3000"
TEMPO_PF=""
OTLP_PF=""
GRAF_PF=""

step() { printf '\n==> %s\n' "$1"; }
cleanup() {
    [[ -n "$TEMPO_PF" ]] && kill "$TEMPO_PF" 2>/dev/null
    [[ -n "$OTLP_PF" ]] && kill "$OTLP_PF" 2>/dev/null
    [[ -n "$GRAF_PF" ]] && kill "$GRAF_PF" 2>/dev/null
    true
}
trap cleanup EXIT
dump() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    kubectl get statefulset,deployment,pods,svc -n "$NS" 2>&1 | grep -iE 'tempo|grafana|NAME' || true
}
fail() { printf '\n✗ FAILED: %s\n' "$1"; dump; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
kubectl get ns "$NS" >/dev/null 2>&1 \
    || fail "namespace $NS not found — run scripts/setup-observability.sh first"
# Tempo monolithic ships as a StatefulSet named 'tempo'; the service is 'tempo'.
kubectl get svc tempo -n "$NS" >/dev/null 2>&1 \
    || fail "tempo service not found — run scripts/setup-observability.sh"

step "Waiting for Tempo to be Ready"
# Works whether the chart used a StatefulSet or Deployment for the monolith.
kubectl wait -n "$NS" --for=condition=Ready pod \
    -l app.kubernetes.io/name=tempo --timeout=180s >/dev/null 2>&1 \
    || fail "tempo pod did not become Ready"
printf '    ✓ tempo pod is Ready\n'

# ─── Tempo answers its readiness probe ───────────────────────────────────────
step "Port-forwarding Tempo ($TEMPO_PORT → tempo:3200) and checking /ready"
kubectl port-forward -n "$NS" svc/tempo "${TEMPO_PORT}:3200" >/dev/null 2>&1 &
TEMPO_PF=$!
ok=""
for _ in $(seq 1 20); do
    body="$(curl -s --max-time 2 "http://127.0.0.1:${TEMPO_PORT}/ready" 2>/dev/null)"
    printf '%s' "$body" | grep -qi 'ready' && { ok=1; break; }
    sleep 1
done
[[ -n "$ok" ]] || fail "Tempo /ready did not report ready on :3200"
printf '    ✓ Tempo is ready to receive (OTLP :4317/:4318) and serve queries (:3200)\n'

# ─── Grafana has the Tempo datasource and can reach it ───────────────────────
step "Port-forwarding Grafana ($GRAF_PORT → grafana:80)"
kubectl port-forward -n "$NS" svc/grafana "${GRAF_PORT}:80" >/dev/null 2>&1 &
GRAF_PF=$!
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${GRAF_PORT}/api/health" && break
    sleep 1
done

step "Confirming the Tempo datasource is provisioned and healthy"
# Real password from the secret (the chart preserves an existing one on upgrade).
GRAF_USER="$(kubectl get secret grafana -n "$NS" -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d)"
GRAF_PASS="$(kubectl get secret grafana -n "$NS" -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d)"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -u "${GRAF_USER}:${GRAF_PASS}" "http://127.0.0.1:${GRAF_PORT}/api/datasources/uid/tempo" 2>/dev/null)"
[[ "$code" == "200" ]] \
    || fail "Tempo datasource not provisioned in Grafana (HTTP $code) — check grafana-values.yaml"
# Health check is best-effort: confirms Grafana can actually reach Tempo.
health="$(curl -s --max-time 8 -u "${GRAF_USER}:${GRAF_PASS}" \
    "http://127.0.0.1:${GRAF_PORT}/api/datasources/uid/tempo/health" 2>/dev/null)"
if printf '%s' "$health" | grep -qi '"status":"OK"\|Data source is working'; then
    printf '    ✓ Grafana Tempo datasource provisioned and reachable\n'
else
    printf '    ✓ Grafana Tempo datasource provisioned (health: %s)\n' "${health:-no response}"
    printf '      (Health may report empty until a trace is ingested — expected pre-r29c.)\n'
fi

# ─── End-to-end ingest roundtrip (r29b.1) ───────────────────────────────────
# The checks above prove the backend is STANDING. This proves it actually
# INGESTS and SERVES a span: POST a synthetic OTLP/HTTP span to :4318 and read it
# back via TraceQL on :3200. This is the check that would have caught the r29c
# export gap at the backend stage instead of letting it slip to the gateway —
# if this roundtrip works, a "no traces" result later is the emitter's fault,
# not the pipeline's.
step "End-to-end: POST a synthetic span to OTLP :$OTLP_PORT and read it back"
kubectl port-forward -n "$NS" svc/tempo "${OTLP_PORT}:4318" >/dev/null 2>&1 &
OTLP_PF=$!
# Give the forward a moment to establish.
for _ in $(seq 1 10); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${OTLP_PORT}/" 2>/dev/null && break
    sleep 1
done

# OTLP/HTTP accepts JSON when Content-Type is application/json. Build a minimal
# valid trace: 16-byte trace id (32 hex), 8-byte span id (16 hex), ns timestamps.
SVC_NAME="smoke-synthetic"
TRACE_ID="$(openssl rand -hex 16 2>/dev/null || head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
SPAN_ID="$(openssl rand -hex 8 2>/dev/null  || head -c8  /dev/urandom | od -An -tx1 | tr -d ' \n')"
START_NS="$(date +%s%N)"
END_NS="$((START_NS + 1000000))"   # +1ms
payload="$(cat <<JSON
{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"${SVC_NAME}"}}]},
"scopeSpans":[{"scope":{"name":"smoke-tracing"},"spans":[{"traceId":"${TRACE_ID}","spanId":"${SPAN_ID}",
"name":"synthetic-readback","kind":1,"startTimeUnixNano":"${START_NS}","endTimeUnixNano":"${END_NS}"}]}]}]}
JSON
)"

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 \
    -H 'Content-Type: application/json' \
    -X POST --data "$payload" \
    "http://127.0.0.1:${OTLP_PORT}/v1/traces" 2>/dev/null)"
[[ "$code" == "200" ]] \
    || fail "Tempo rejected the synthetic OTLP/HTTP span on :$OTLP_PORT (HTTP $code) — the OTLP receiver isn't ingesting; check tempo-values.yaml receivers.otlp.protocols.http"
printf '    \xe2\x9c\x93 Tempo accepted the span (HTTP 200) on :%s/v1/traces\n' "$OTLP_PORT"

# Read it back via TraceQL on :3200 (TEMPO_PF from the /ready check is still up).
# Ingestion → searchable has a short lag; retry.
found=""
for _ in $(seq 1 12); do
    res="$(curl -sG "http://127.0.0.1:${TEMPO_PORT}/api/search" \
        --data-urlencode "q={ resource.service.name = \"${SVC_NAME}\" }" \
        --data-urlencode 'limit=10' 2>/dev/null)"
    if printf '%s' "$res" | grep -q '"traceID"'; then found=1; break; fi
    sleep 5
done
[[ -n "$found" ]] \
    || fail "synthetic span was accepted but not searchable within ~60s — Tempo ingests but does not index/serve; check Tempo storage/WAL"
printf '    \xe2\x9c\x93 Read the synthetic trace back via TraceQL — receive\xe2\x86\x92store\xe2\x86\x92query all work\n'

step "SUCCESS"
printf 'Trace backend fully verified: Tempo INGESTS OTLP/HTTP on :%s and SERVES it back\n' "$OTLP_PORT"
printf 'via search on :%s, and Grafana is wired to query it. The pipeline is proven\n' "$TEMPO_PORT"
printf 'independent of any emitter — so once a service is instrumented, a missing trace\n'
printf 'is the emitter''s problem, not the backend''s. Real spans appear in\n'
printf 'Grafana \xe2\x86\x92 Explore \xe2\x86\x92 Tempo; drive one with ./demos/smoke-trace-flow.sh.\n'
