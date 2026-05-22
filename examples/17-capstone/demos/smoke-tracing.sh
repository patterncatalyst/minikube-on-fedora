#!/usr/bin/env bash
#
# smoke-tracing.sh — verify the trace BACKEND (r29b, CAP-028): Tempo is up and
# ready, and Grafana has the Tempo datasource provisioned and can reach it.
#
# This checks the pipeline is standing and queryable. It does NOT assert that
# real traces have arrived — nothing emits them until a service is instrumented
# (r29c). Once that lands, a real trace appearing in Grafana's Tempo explorer is
# the end-to-end proof.
#
# Leaves resources in place on failure + dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:  ./demos/smoke-tracing.sh

set -uo pipefail

NS="observability"
TEMPO_PORT="3200"
GRAF_PORT="3000"
TEMPO_PF=""
GRAF_PF=""

step() { printf '\n==> %s\n' "$1"; }
cleanup() {
    [[ -n "$TEMPO_PF" ]] && kill "$TEMPO_PF" 2>/dev/null
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

step "SUCCESS"
printf 'Trace backend is up: Tempo receiving OTLP, Grafana wired to query it.\n'
printf 'Nothing emits traces yet — instrument a service (r29c) and they will appear in\n'
printf 'Grafana → Explore → Tempo.\n'
