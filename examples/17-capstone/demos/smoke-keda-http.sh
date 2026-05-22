#!/usr/bin/env bash
#
# smoke-keda-http.sh — demonstrate AND verify HTTP request autoscaling of the
# graphql-gateway via the KEDA HTTP add-on (r26b, CAP-025).
#
# The other half of "elastic data products": a synchronous service should run
# only when there's demand. This proves the lifecycle:
#   * with no traffic, KEDA scales graphql-gateway to ZERO
#   * a request through the add-on's interceptor wakes it from zero (the
#     interceptor holds the request until a replica is Ready) → scales UP
#   * when traffic stops, KEDA scales it back to ZERO
#
# Load is driven at /health (liveness, no datastore) so the demo doesn't depend
# on the gateway's downstreams. Traffic enters via the interceptor with a Host
# header matching the HTTPScaledObject.
#
# Leaves resources in place on failure + dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:  ./demos/smoke-keda-http.sh

set -uo pipefail
export MINIKUBE_ROOTLESS=true

NS="capstone"
PROFILE="capstone"
KEDA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../keda" && pwd)"
SEL="app.kubernetes.io/name=graphql-gateway"
HOST="graphql-gateway.capstone"
LOCAL_PORT="8081"
PROXY_SVC="keda-add-ons-http-interceptor-proxy"
PF_PID=""
declare -a LOAD_PIDS=()

step() { printf '\n==> %s\n' "$1"; }
count_pods() {
    kubectl get pods -n "$NS" -l "$SEL" --no-headers 2>/dev/null \
        | grep -v 'Terminating' | grep -c . || echo 0
}
cleanup() {
    for p in "${LOAD_PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
    [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null
    true
}
trap cleanup EXIT
dump() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    kubectl get httpscaledobject,deployment,pods -n "$NS" -l "$SEL" 2>&1
    kubectl get pods -n keda 2>&1 | grep -i interceptor
    kubectl describe httpscaledobject graphql-gateway-http -n "$NS" 2>&1 | tail -20
}
fail() { printf '\n✗ FAILED: %s\n' "$1" >&2; cleanup; dump; exit 1; }

wait_until() {
    local desc="$1" timeout="$2"; shift 2
    local waited=0
    while ! "$@"; do
        sleep 3; waited=$((waited + 3))
        [[ $waited -ge $timeout ]] && { printf '    (timed out after %ss: %s; pods now=%s)\n' "$timeout" "$desc" "$(count_pods)"; return 1; }
    done
}
is_zero()     { [[ "$(count_pods)" -eq 0 ]]; }
is_scaledup() { [[ "$(count_pods)" -gt 0 ]]; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE'"
for t in kubectl curl; do command -v "$t" >/dev/null || fail "$t not in PATH"; done
kubectl get svc "$PROXY_SVC" -n keda >/dev/null 2>&1 \
    || fail "KEDA HTTP add-on not installed (no $PROXY_SVC in keda ns) — run scripts/setup-keda.sh"
kubectl get deployment graphql-gateway -n "$NS" >/dev/null 2>&1 \
    || fail "graphql-gateway not deployed — helm upgrade --install graphql-gateway charts/capstone/charts/graphql-gateway -n $NS"

step "Applying the HTTPScaledObject"
kubectl apply -f "$KEDA_DIR/gateway-httpscaledobject.yaml" >/dev/null \
    || fail "failed to apply the HTTPScaledObject"
printf '    ✓ applied — KEDA HTTP add-on now fronts graphql-gateway\n'

# ─── 1. Scale to zero (no traffic) ───────────────────────────────────────────
step "Waiting for scale-to-zero (no traffic → 0 replicas, ~scaledownPeriod 30s)"
wait_until "0 replicas" 150 is_zero \
    || fail "graphql-gateway did not scale to zero — is the HTTPScaledObject Ready?"
printf '    ✓ scaled to ZERO (no traffic, costing nothing)\n'

# ─── 2. Drive traffic through the interceptor → wake from zero ───────────────
step "Port-forwarding the KEDA HTTP interceptor"
PROXY_PORT="$(kubectl get svc "$PROXY_SVC" -n keda -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
[[ -n "$PROXY_PORT" ]] || PROXY_PORT=8080
kubectl port-forward -n keda "svc/$PROXY_SVC" "${LOCAL_PORT}:${PROXY_PORT}" >/dev/null 2>&1 &
PF_PID=$!
sleep 4

step "Driving HTTP load at /health through the interceptor (wakes it from zero)"
# A handful of concurrent loops keeps in-flight concurrency above the target so
# the gateway both activates and stays up while we observe it.
for _ in $(seq 1 12); do
    ( while true; do
        curl -m 90 -s -o /dev/null -H "Host: $HOST" "http://127.0.0.1:${LOCAL_PORT}/health" || true
      done ) &
    LOAD_PIDS+=($!)
done

wait_until ">0 replicas" 120 is_scaledup \
    || fail "graphql-gateway did not wake from zero under traffic — interceptor routing / Host header?"
MAXSEEN="$(count_pods)"
for _ in 1 2 3 4; do sleep 4; [[ "$(count_pods)" -gt "$MAXSEEN" ]] && MAXSEEN="$(count_pods)"; done
printf '    ✓ woke from ZERO and scaled to %s replica(s) under load\n' "$MAXSEEN"

# stop the load
for p in "${LOAD_PIDS[@]}"; do kill "$p" 2>/dev/null; done
LOAD_PIDS=()

# ─── 3. Traffic stops → scale back to zero ───────────────────────────────────
step "Stopping traffic; waiting for scale back to ZERO"
wait_until "0 replicas" 150 is_zero \
    || fail "graphql-gateway did not return to zero after traffic stopped"
printf '    ✓ scaled back to ZERO\n'

step "SUCCESS"
printf 'graphql-gateway is an elastic data product: 0 when idle, woke from zero\n'
printf 'on the first request and scaled to %s under load, back to 0 when quiet —\n' "$MAXSEEN"
printf 'driven by HTTP request concurrency via the KEDA HTTP add-on.\n'
