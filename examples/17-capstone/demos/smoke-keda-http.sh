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
    kubectl get pods -n "$NS" -l "$SEL" --no-headers 2>/dev/null | grep -vc 'Terminating'
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
step "Waiting for scale-to-zero (KEDA HTTP cooldown ~300s + HPA settle; up to ~6 min if the gateway was just (re)deployed — instant if already at 0)"
# See the note below on the HTTP add-on's ~300s default cooldown. On a re-run
# where the gateway is already at zero this returns immediately.
wait_until "0 replicas" 600 is_zero \
    || fail "graphql-gateway did not scale to zero — is the HTTPScaledObject Ready?"
printf '    ✓ scaled to ZERO (no traffic, costing nothing)\n'

# ─── 2. Wake from zero through the interceptor ───────────────────────────────
step "Port-forwarding the KEDA HTTP interceptor (proxy :8080)"
# The proxy listens on 8080 on keda-add-ons-http-interceptor-proxy (matches the
# proven §12 pattern). Hardcoded — discovering ports[0] risks hitting a non-proxy
# port, which silently drops the routing and the pending-request metric.
kubectl port-forward -n keda "svc/$PROXY_SVC" "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
PF_PID=$!
# Wait for the port-forward TCP socket to accept connections (not a routing check).
for _ in $(seq 1 15); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/" && break
    sleep 1
done

step "Waking the gateway from zero through the interceptor (Host: $HOST)"
# A single request can 502 if the cold start outruns the interceptor's ~20s
# WorkloadReplicas wait — and with imagePullPolicy: Always (CAP-015) a cold pull
# can push the gateway past that. So we drive SUSTAINED trigger requests (each
# keeps a pending request, so KEDA keeps the gateway scaled up) while we wait for
# the Deployment to report a Ready replica. The 0→Ready transition IS the
# wake-from-zero proof; we then assert the gateway serves a 200.
ready_replicas() { kubectl get deployment graphql-gateway -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null; }
is_ready() { [[ "$(ready_replicas)" =~ ^[0-9]+$ ]] && [[ "$(ready_replicas)" -ge 1 ]]; }

( while true; do
    curl -s -o /dev/null --max-time 25 -H "Host: $HOST" "http://127.0.0.1:${LOCAL_PORT}/health" || true
    sleep 1
  done ) &
LOAD_PIDS+=($!)

START=$(date +%s)
wait_until "gateway Ready (woke from zero)" 420 is_ready || {
    printf '    deployment/pods at timeout:\n'
    kubectl get deployment,pods -n "$NS" -l app.kubernetes.io/name=graphql-gateway 2>&1 | sed 's/^/      /'
    fail "graphql-gateway did not reach a Ready replica under traffic within 420s — KEDA scale-up or pod start (see above)."
}
ELAPSED=$(( $(date +%s) - START ))
printf '    ✓ woke from ZERO to a Ready replica in %ss\n' "$ELAPSED"

# Now that a replica is Ready, the interceptor forwards: assert a real 200.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
    -H "Host: $HOST" "http://127.0.0.1:${LOCAL_PORT}/health" || echo "000")
[[ "$CODE" == "200" ]] || fail "gateway is Ready but the interceptor returned HTTP $CODE (routing?)"
printf '    ✓ interceptor served HTTP 200 from the woken gateway\n'
MAXSEEN="$(count_pods)"

step "Driving brief sustained load (it stays warm under traffic)"
for _ in $(seq 1 8); do
    ( for _ in $(seq 1 40); do
        curl -s -o /dev/null --max-time 10 -H "Host: $HOST" "http://127.0.0.1:${LOCAL_PORT}/health" || true
      done ) &
    LOAD_PIDS+=($!)
done
for _ in 1 2 3 4 5; do sleep 3; [[ "$(count_pods)" -gt "$MAXSEEN" ]] && MAXSEEN="$(count_pods)"; done
for p in "${LOAD_PIDS[@]}"; do kill "$p" 2>/dev/null; done
LOAD_PIDS=()
printf '    ✓ stayed up under load (peak %s replica(s))\n' "$MAXSEEN"

# ─── 3. Traffic stops → scale back to zero ───────────────────────────────────
step "Stopping traffic; waiting for scale back to ZERO (~5 min — the HTTP add-on uses KEDA's default 300s cooldownPeriod for 1→0, unlike the Kafka scaler's fast 30s)"
# The KEDA HTTP add-on's generated ScaledObject uses KEDA's DEFAULT
# cooldownPeriod (~300s) for the final 1→0 — the HTTPScaledObject's 30s
# scaledownPeriod governs metric idle, not the cooldown. So scale-to-zero
# lands at ~5 min. Wait past it. (Unlike the Kafka ScaledObject, whose own
# cooldownPeriod: 30 is honored directly and scales down in well under a minute.)
wait_until "0 replicas" 600 is_zero \
    || fail "graphql-gateway did not return to zero after traffic stopped (waited 420s)"
printf '    ✓ scaled back to ZERO\n'

step "SUCCESS"
printf 'graphql-gateway is an elastic data product: 0 when idle, woke from zero\n'
printf 'on the first request and scaled to %s under load, back to 0 when quiet —\n' "$MAXSEEN"
printf 'driven by HTTP request concurrency via the KEDA HTTP add-on.\n'
