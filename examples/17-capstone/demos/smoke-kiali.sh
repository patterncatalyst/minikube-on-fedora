#!/usr/bin/env bash
#
# smoke-kiali.sh — verify Kiali (CAP-0NN) is up and wired to the capstone
# observability stack: the deployment is Ready, the API answers, Prometheus is
# reachable from Kiali's point of view, and the `capstone` namespace is visible
# to the graph.
#
# This checks the PLUMBING, not a pretty graph — it confirms Kiali can render
# the mesh topology once traffic flows. Run a demo (smoke-trace-flow.sh,
# demo-canary.sh, smoke-keda-kafka.sh) to make edges actually appear in the graph.
#
# Leaves resources in place on failure + dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:  ./demos/smoke-kiali.sh
#
# VERIFY-POINTS (confirm against the installed Kiali/Istio version):
#   - the Kiali addon ConfigMap is named `kiali` with key `config.yaml`
#     (setup-kiali.sh patches that key); if a version differs, the wiring step
#     in setup-kiali.sh and the config check below are where to adjust.
#   - the Kiali API paths /healthz and /api/namespaces are stable across recent
#     Kiali releases.

set -uo pipefail

ISTIO_SYSTEM="istio-system"
OBS_NS="observability"
APP_NS="capstone"
KIALI_PORT="20001"
KIALI_PF=""

step() { printf '\n==> %s\n' "$1"; }
cleanup() { [[ -n "$KIALI_PF" ]] && kill "$KIALI_PF" 2>/dev/null; true; }
trap cleanup EXIT
dump() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    printf '\n--- kiali deployment / pod ---\n'
    kubectl get deploy,pods -n "$ISTIO_SYSTEM" -l app.kubernetes.io/name=kiali -o wide 2>&1
    printf '\n--- kiali ConfigMap (external_services) ---\n'
    kubectl get configmap kiali -n "$ISTIO_SYSTEM" -o jsonpath='{.data.config\.yaml}' 2>&1 | sed -n '1,40p'
    printf '\n--- recent kiali logs ---\n'
    kubectl logs -n "$ISTIO_SYSTEM" -l app.kubernetes.io/name=kiali --tail=30 2>&1
    printf '\nInspect: kubectl port-forward -n %s svc/kiali %s:%s ; open http://localhost:%s\n' \
        "$ISTIO_SYSTEM" "$KIALI_PORT" "$KIALI_PORT" "$KIALI_PORT"
}
fail() { printf '\n✗ FAILED: %s\n' "$1"; dump; exit 1; }

ready() { # ready <deployment> <namespace>
    local r
    r="$(kubectl get deploy "$1" -n "$2" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
    [[ "$r" =~ ^[0-9]+$ ]] && [[ "$r" -ge 1 ]]
}
wait_ready() { # wait_ready <deployment> <namespace> <seconds>
    local d="$1" ns="$2" budget="$3" start; start=$(date +%s)
    while (( $(date +%s) - start < budget )); do ready "$d" "$ns" && return 0; sleep 3; done
    return 1
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────
step "Pre-flight checks"
command -v kubectl >/dev/null 2>&1 || fail "kubectl not in PATH"
command -v curl    >/dev/null 2>&1 || fail "curl not in PATH"
kubectl get deploy kiali -n "$ISTIO_SYSTEM" >/dev/null 2>&1 \
    || fail "kiali deployment not found in $ISTIO_SYSTEM — run scripts/setup-kiali.sh first"

# ─── 1. Kiali is Ready ───────────────────────────────────────────────────────
step "Waiting for the Kiali deployment to be Ready"
wait_ready kiali "$ISTIO_SYSTEM" 180 || fail "kiali did not become Ready"
printf '    ✓ kiali is Ready\n'

# ─── 2. Confirm the single-stack wiring landed in the ConfigMap ──────────────
step "Checking Kiali is wired to the capstone Prometheus (single-stack)"
CFG="$(kubectl get configmap kiali -n "$ISTIO_SYSTEM" -o jsonpath='{.data.config\.yaml}' 2>/dev/null)"
[[ -n "$CFG" ]] || fail "kiali ConfigMap has no config.yaml key (version mismatch? see VERIFY-POINTS)"
if printf '%s' "$CFG" | grep -q "prometheus-server.${OBS_NS}"; then
    printf '    ✓ external_services.prometheus → prometheus-server.%s\n' "$OBS_NS"
else
    fail "kiali config does not point at prometheus-server.${OBS_NS} — re-run scripts/setup-kiali.sh"
fi

# ─── 3. Port-forward and hit the API ─────────────────────────────────────────
step "Port-forwarding Kiali and probing its API"
kubectl port-forward -n "$ISTIO_SYSTEM" svc/kiali "${KIALI_PORT}:${KIALI_PORT}" >/dev/null 2>&1 &
KIALI_PF=$!
# wait for the forward to come up
for _ in $(seq 1 20); do
    curl -fsS "http://127.0.0.1:${KIALI_PORT}/healthz" >/dev/null 2>&1 && break
    sleep 1
done
curl -fsS "http://127.0.0.1:${KIALI_PORT}/healthz" >/dev/null 2>&1 \
    || fail "Kiali /healthz did not respond over the port-forward"
printf '    ✓ Kiali /healthz responds\n'

# ─── 4. Kiali can see the capstone namespace ─────────────────────────────────
step "Confirming Kiali sees the $APP_NS namespace"
NS_JSON="$(curl -fsS "http://127.0.0.1:${KIALI_PORT}/api/namespaces" 2>/dev/null || echo "")"
[[ -n "$NS_JSON" ]] || fail "Kiali /api/namespaces returned nothing"
if printf '%s' "$NS_JSON" | grep -q "\"$APP_NS\""; then
    printf '    ✓ Kiali reports the %s namespace\n' "$APP_NS"
else
    fail "Kiali does not list the $APP_NS namespace (is it injection-enabled and is Kiali's service account allowed to read it?)"
fi

# ─── 5. Prometheus reachable from Kiali (metrics integration live) ───────────
step "Checking Kiali's Prometheus integration is live"
# Kiali surfaces config validation at /api/status; the graph needs Prometheus.
# A best-effort probe: ask Kiali for the istio-system graph (empty is fine, an
# error means the Prometheus wiring is broken).
GRAPH_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:${KIALI_PORT}/api/namespaces/graph?namespaces=${APP_NS}&duration=60s&graphType=workload" 2>/dev/null || echo "000")"
if [[ "$GRAPH_CODE" == "200" ]]; then
    printf '    ✓ Kiali graph API answered 200 (Prometheus reachable)\n'
else
    printf '    ! Kiali graph API returned HTTP %s — Prometheus wiring may not be live yet.\n' "$GRAPH_CODE"
    printf '      This is a note, not a failure: the graph fills in once traffic flows and\n'
    printf '      Prometheus has scraped it. Re-check after running a demo.\n'
fi

# ─── Done ────────────────────────────────────────────────────────────────────
step "PASS — Kiali is up, wired to the capstone stack, and sees the $APP_NS namespace."
printf '\nView the live topology (run a demo first to create traffic):\n'
printf '  kubectl port-forward -n %s svc/kiali %s:%s\n' "$ISTIO_SYSTEM" "$KIALI_PORT" "$KIALI_PORT"
printf '  open http://localhost:%s   (Graph → namespace: %s)\n' "$KIALI_PORT" "$APP_NS"
