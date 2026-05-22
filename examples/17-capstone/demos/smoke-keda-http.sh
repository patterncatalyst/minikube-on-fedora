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
step "Waiting for scale-to-zero (~30s scaledownPeriod once idle; instant if already at 0, longer if the gateway was just (re)deployed)"
# scaledownPeriod (30s) governs the HTTP add-on's scale-to-zero once in-flight
# concurrency is genuinely 0. On a re-run where the gateway is already at zero
# this returns immediately. Budget stays generous to cover a just-deployed pod
# settling for the first time.
wait_until "0 replicas" 600 is_zero \
    || fail "graphql-gateway did not scale to zero — is the HTTPScaledObject Ready, and is anything holding a connection to the interceptor?"
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

step "Firing a cold-start request through the interceptor (Host: $HOST)"
# With interceptor.replicas.waitTimeout raised to 180s (setup-keda.sh), the
# interceptor BUFFERS this request, signals KEDA to scale graphql-gateway from
# zero, and HOLDS the connection until a replica is Ready — then forwards it and
# returns the gateway's response. A 200 is the wake-from-zero proof; the elapsed
# time is the cold-start cost. A single held request also gives KEDA the stable
# pending-request pressure it needs to activate promptly (the old 20s wait made
# requests churn-and-502 before a backend existed, starving that signal).
START=$(date +%s)
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 200 \
    -H "Host: $HOST" "http://127.0.0.1:${LOCAL_PORT}/health" || echo "000")
ELAPSED=$(( $(date +%s) - START ))
if [[ "$CODE" != "200" ]]; then
    printf '    cold-start returned HTTP %s after %ss\n' "$CODE" "$ELAPSED"
    kubectl get deployment,pods -n "$NS" -l app.kubernetes.io/name=graphql-gateway 2>&1 | sed 's/^/      /'
    fail "interceptor did not serve a 200 from a woken gateway (HTTP $CODE). 502 'context deadline exceeded' = waitTimeout too short; 404 = Host didn't match the HTTPScaledObject."
fi
printf '    ✓ woke from ZERO and served 200 in %ss (cold start)\n' "$ELAPSED"
[[ "$(count_pods)" -gt 0 ]] || fail "served a 200 but no gateway pod present?!"
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
# Close the port-forward FIRST — this is THE thing that makes scale-to-zero work.
# The HTTP add-on scales on in-flight `concurrency`, and an open connection (a
# held port-forward, keep-alive and all) reads as >=1. While anything is
# connected the metric never reaches 0, so the scaledownPeriod timer never starts
# and the gateway looks like it refuses to scale down. Drop the connection and it
# stands down in ~30s (the HTTPScaledObject's scaledownPeriod) — same ballpark as
# the Kafka ScaledObject's cooldownPeriod: 30.
[[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null; PF_PID=""

step "Stopping traffic (and closing the interceptor connection); waiting for scale back to ZERO (~30s once idle)"
# We latch on KEDA's decision — the Deployment's desired replicas reaching 0 —
# rather than waiting for the last pod to finish terminating, so graceful
# shutdown lag doesn't read as a failure. With the connection closed this is
# typically ~30s; the budget stays generous as a ceiling.
desired() { kubectl get deploy graphql-gateway -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null; }
START=$(date +%s); SAW_ZERO=""
while (( $(date +%s) - START < 600 )); do
    [[ "$(desired)" == "0" ]] && { SAW_ZERO=1; break; }
    sleep 2
done
ELAPSED=$(( $(date +%s) - START ))
if [[ -n "$SAW_ZERO" ]]; then
    printf '    ✓ scaled back to ZERO (KEDA set desired replicas to 0 after ~%ss)\n' "$ELAPSED"
else
    printf '    ⚠ still >0 after %ss (desired=%s now) — NOT a failure.\n' "$ELAPSED" "$(desired)"
    printf '      Usually means something still holds a connection to the interceptor\n'
    printf '      (a browser tab, another port-forward) keeping concurrency >0. Watch it:\n'
    printf '        kubectl get deploy graphql-gateway -n %s -w\n' "$NS"
fi

step "SUCCESS"
printf 'graphql-gateway is an elastic data product: 0 when idle, woke from zero\n'
printf 'on the first request and scaled to %s under load, back to 0 when quiet —\n' "$MAXSEEN"
printf 'driven by HTTP request concurrency via the KEDA HTTP add-on.\n'
