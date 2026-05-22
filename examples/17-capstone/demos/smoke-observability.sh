#!/usr/bin/env bash
#
# smoke-observability.sh — verify the metrics stack (r29, CAP-027) is actually
# working: Prometheus is up and scraping (kube-state-metrics gives us capstone
# workload metrics; the Istio series exists), and Grafana is up with the
# capstone dashboard provisioned.
#
# This checks the PLUMBING, not pretty graphs — it confirms the data is flowing
# so the dashboard has something to draw. Run the scaling/canary demos to make
# the graphs actually move.
#
# Leaves resources in place on failure + dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:  ./demos/smoke-observability.sh

set -uo pipefail

NS="observability"
PROM_PORT="9090"
GRAF_PORT="3000"
PROM_PF=""
GRAF_PF=""

step() { printf '\n==> %s\n' "$1"; }
cleanup() {
    [[ -n "$PROM_PF" ]] && kill "$PROM_PF" 2>/dev/null
    [[ -n "$GRAF_PF" ]] && kill "$GRAF_PF" 2>/dev/null
    true
}
trap cleanup EXIT
dump() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    kubectl get deployment,pods -n "$NS" 2>&1
}
fail() { printf '\n✗ FAILED: %s\n' "$1"; dump; exit 1; }

ready() { # ready <deployment>
    local r
    r="$(kubectl get deploy "$1" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
    [[ "$r" =~ ^[0-9]+$ ]] && [[ "$r" -ge 1 ]]
}
wait_ready() { # wait_ready <deployment> <seconds>
    local d="$1" budget="$2" start; start=$(date +%s)
    while (( $(date +%s) - start < budget )); do ready "$d" && return 0; sleep 3; done
    return 1
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
kubectl get ns "$NS" >/dev/null 2>&1 \
    || fail "namespace $NS not found — run scripts/setup-observability.sh first"
kubectl get deploy prometheus-server -n "$NS" >/dev/null 2>&1 \
    || fail "prometheus-server not found — run scripts/setup-observability.sh"
kubectl get deploy grafana -n "$NS" >/dev/null 2>&1 \
    || fail "grafana not found — run scripts/setup-observability.sh"

step "Waiting for Prometheus and Grafana to be Ready"
wait_ready prometheus-server 180 || fail "prometheus-server did not become Ready"
wait_ready grafana 180          || fail "grafana did not become Ready"
printf '    ✓ prometheus-server and grafana are Ready\n'

# ─── Prometheus is scraping ──────────────────────────────────────────────────
step "Port-forwarding Prometheus ($PROM_PORT → prometheus-server:80)"
kubectl port-forward -n "$NS" svc/prometheus-server "${PROM_PORT}:80" >/dev/null 2>&1 &
PROM_PF=$!
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PROM_PORT}/-/ready" && break
    sleep 1
done

step "Confirming kube-state-metrics gives us capstone workload replicas"
# kube_deployment_spec_replicas for capstone deployments proves both that
# kube-state-metrics is up AND that Prometheus is scraping it. This is the series
# the dashboard's scaling panel draws.
PROM_Q="http://127.0.0.1:${PROM_PORT}/api/v1/query"
result="$(curl -sG "$PROM_Q" --data-urlencode 'query=kube_deployment_spec_replicas{namespace="capstone"}' 2>/dev/null)"
printf '%s' "$result" | grep -q '"result":\[{' \
    || fail "Prometheus returned no kube_deployment_spec_replicas for namespace=capstone (is kube-state-metrics scraping? are the services deployed?)"
printf '    ✓ Prometheus has capstone replica metrics (kube-state-metrics scraping)\n'

step "Confirming the Istio request series is present (order-service is meshed)"
# The series should EXIST even at 0 req/s once the sidecar has reported once.
# If empty, it usually just means no traffic has flowed yet — a soft note, not a
# hard failure, since metrics plumbing is already proven above.
istio="$(curl -sG "$PROM_Q" --data-urlencode 'query=istio_requests_total{destination_workload="order-service"}' 2>/dev/null)"
if printf '%s' "$istio" | grep -q '"result":\[{'; then
    printf '    ✓ istio_requests_total present for order-service\n'
else
    printf '    ⚠ no istio_requests_total yet — drive traffic (./demos/smoke-canary.sh)\n'
    printf '      then re-check. (Metrics plumbing is already proven above.)\n'
fi

# ─── Grafana is up with the dashboard provisioned ────────────────────────────
step "Port-forwarding Grafana ($GRAF_PORT → grafana:80)"
kubectl port-forward -n "$NS" svc/grafana "${GRAF_PORT}:80" >/dev/null 2>&1 &
GRAF_PF=$!
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${GRAF_PORT}/api/health" && break
    sleep 1
done

step "Checking Grafana health and the provisioned dashboard"
health="$(curl -s --max-time 5 "http://127.0.0.1:${GRAF_PORT}/api/health" 2>/dev/null)"
printf '%s' "$health" | grep -q '"database": *"ok"' \
    || fail "Grafana /api/health did not report database ok (got: $health)"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -u admin:capstone "http://127.0.0.1:${GRAF_PORT}/api/dashboards/uid/capstone-scaling" 2>/dev/null)"
[[ "$code" == "200" ]] \
    || fail "Grafana dashboard 'capstone-scaling' not provisioned (HTTP $code from the dashboards API)"
printf '    ✓ Grafana healthy and the "Capstone — Scaling & Traffic" dashboard is provisioned\n'

step "SUCCESS"
printf 'Metrics stack verified. Open the dashboard and drive a demo to watch it move:\n'
printf '  kubectl port-forward -n %s svc/grafana 3000:80\n' "$NS"
printf '  ./demos/smoke-keda-http.sh   # graphql-gateway replicas 0→1→0\n'
