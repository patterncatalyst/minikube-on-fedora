#!/usr/bin/env bash
#
# smoke-canary.sh — demonstrate AND verify the order-service v1→v2 canary
# (r26, CAP-024).
#
# The data-mesh point: a data product evolves its contract (v2 adds a
# `currency` field) without a flag-day break. v2 deploys alongside v1, and
# Istio shifts a controllable fraction of live traffic to it — the canary of a
# contract, not just a binary. This script proves the mechanism end-to-end:
#   * v1 (Helm-managed) and v2 (the istio/ overlay) both run, both meshed
#     (an istio-proxy sidecar is injected into each)
#   * traffic through the istio-ingressgateway splits by the VirtualService
#     weight — measured by hitting GET /version and counting which subset answers
#   * SHIFTING the weight (re-applying the VirtualService) moves the split,
#     which is the progressive-canary operation
#
# On failure it leaves resources in place and dumps diagnostics. Idempotent.
# Run from examples/17-capstone/:
#   ./demos/smoke-canary.sh
#
# Prerequisites:
#   - capstone profile running, kubectl context = capstone
#   - scripts/setup-istio.sh has run (Istio installed, namespace injection on)
#   - order-service (v1) deployed via the umbrella chart WITH the r26 selector
#     (version=v1). If the live Deployment predates r26, this smoke detects the
#     stale selector and prints the one-time migration.
#
# VERIFY-POINTS (Istio API / install; confirm against the installed version):
#   the networking.istio.io/v1 kinds, the ingressgateway Service name, and
#   subset-by-label routing. Flagged in istio/routing.yaml.

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

NS="capstone"
PROFILE="capstone"
ISTIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../istio" && pwd)"
LOCAL_PORT="8080"
GW="http://127.0.0.1:${LOCAL_PORT}"
REQUESTS=100
PORT_FORWARD_PID=""

step() { printf '\n==> %s\n' "$1"; }

dump_diagnostics() {
    step "DIAGNOSTIC DUMP (failure — resources left in place)"
    printf '\n--- order-service pods (both subsets) ---\n'
    kubectl get pods -n "$NS" -l app.kubernetes.io/name=order-service -o wide 2>&1
    printf '\n--- VirtualService / DestinationRule / Gateway ---\n'
    kubectl get virtualservice,destinationrule,gateway -n "$NS" 2>&1
    printf '\n--- istio-ingressgateway ---\n'
    kubectl get svc -n istio-system istio-ingressgateway 2>&1
    printf '\nInspect a sidecar: kubectl logs -n %s <pod> -c istio-proxy\n' "$NS"
}

fail() {
    printf '\n✗ FAILED: %s\n' "$1" >&2
    [[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null
    dump_diagnostics
    exit 1
}
trap '[[ -n "$PORT_FORWARD_PID" ]] && kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT

# apply_weights V1 V2 — render the VirtualService at the given split and apply
apply_weights() {
    local w1="$1" w2="$2"
    sed "s/__W_V1__/${w1}/; s/__W_V2__/${w2}/" "$ISTIO_DIR/routing.yaml" \
        | kubectl apply -f - >/dev/null \
        || fail "failed to apply routing at ${w1}/${w2}"
    # Give the ingress gateway a moment to pick up the new VirtualService.
    sleep 3
}

# measure_split LABEL EXPECT_V2_LOW EXPECT_V2_HIGH — drive traffic, assert band
measure_split() {
    local label="$1" lo="$2" hi="$3"
    local resp v1 v2
    resp="$(mktemp)"
    local i
    for ((i = 0; i < REQUESTS; i++)); do
        curl -fsS "${GW}/version" 2>/dev/null >>"$resp"; echo >>"$resp"
    done
    v2="$(grep -c 'v2' "$resp" 2>/dev/null || echo 0)"
    v1="$(grep -c 'v1' "$resp" 2>/dev/null || echo 0)"
    rm -f "$resp"
    printf '    %s: v1=%s  v2=%s  (of %s)\n' "$label" "$v1" "$v2" "$REQUESTS"
    [[ $((v1 + v2)) -ge $((REQUESTS - 5)) ]] \
        || fail "$label: only $((v1 + v2))/$REQUESTS responses parsed as v1/v2 (routing broken?)"
    [[ "$v2" -ge "$lo" && "$v2" -le "$hi" ]] \
        || fail "$label: v2 count $v2 outside expected band [$lo,$hi] — split not honored"
    LAST_V1="$v1"; LAST_V2="$v2"
    printf '    ✓ %s split within expected band\n' "$label"
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────

step "Pre-flight checks"
[[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
    || fail "kubectl context is not '$PROFILE' — run: kubectl config use-context $PROFILE"
for t in kubectl curl; do command -v "$t" >/dev/null || fail "$t not in PATH"; done
kubectl get deployment istiod -n istio-system >/dev/null 2>&1 \
    || fail "Istio not installed — run scripts/setup-istio.sh first"
kubectl get deployment order-service -n "$NS" >/dev/null 2>&1 \
    || fail "order-service (v1) not deployed — install it first:
       helm upgrade --install order-service charts/capstone/charts/order-service -n $NS"

# Selector migration check (r26 immutability): v1 Deployment must select version=v1.
SEL_VERSION="$(kubectl get deployment order-service -n "$NS" \
    -o jsonpath='{.spec.selector.matchLabels.version}' 2>/dev/null || echo '')"
if [[ "$SEL_VERSION" != "v1" ]]; then
    fail "order-service Deployment predates r26 (selector lacks version=v1). One-time migration:
       kubectl delete deployment order-service -n $NS
       helm upgrade --install order-service charts/capstone/charts/order-service -n $NS
     then re-run this smoke. (Deployment selectors are immutable, so v1 must be recreated.)"
fi
printf '    ✓ v1 selector carries version=v1\n'

# ─── Deploy v2 alongside v1 ──────────────────────────────────────────────────

step "Deploying the v2 subset alongside v1"
kubectl apply -f "$ISTIO_DIR/order-service-v2.yaml" >/dev/null \
    || fail "failed to apply the v2 overlay"
kubectl rollout status deployment/order-service-v2 -n "$NS" --timeout=3m \
    || fail "order-service-v2 did not become available"
printf '    ✓ order-service-v2 rolled out\n'

# Confirm BOTH subsets are meshed (istio-proxy present). Istio may inject the
# proxy either as a regular container (classic) or as a native sidecar — an
# initContainer with restartPolicy:Always (default on k8s >=1.29) — so check
# BOTH lists. Either way a meshed pod reports 2/2 Ready.
for v in v1 v2; do
    names="$(kubectl get pod -n "$NS" -l "app.kubernetes.io/name=order-service,version=$v" \
        -o jsonpath='{.items[0].spec.containers[*].name} {.items[0].spec.initContainers[*].name}' 2>/dev/null || echo '')"
    printf '    %s containers: %s\n' "$v" "$names"
    [[ "$names" == *istio-proxy* ]] \
        || fail "$v pod has no istio-proxy sidecar — injection didn't happen (was the namespace labeled / pod created after setup-istio.sh?)"
done
printf '    ✓ both subsets are in the mesh\n'

# ─── Routing + the split ─────────────────────────────────────────────────────

step "Applying the DestinationRule, Gateway, and a 90/10 canary"
apply_weights 90 10

step "Port-forwarding the istio-ingressgateway"
kubectl port-forward -n istio-system svc/istio-ingressgateway "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 4
curl -fsS "${GW}/version" >/dev/null 2>&1 \
    || fail "ingress gateway not reachable on ${GW} (is the port-forward up?)"

step "Driving ${REQUESTS} requests at the 90/10 split"
measure_split "90/10" 1 30      # ~10 expected; generous band for 100 samples

step "Shifting the canary to 50/50 (the progressive-canary move)"
apply_weights 50 50
measure_split "50/50" 25 75     # ~50 expected

# ─── Optional visual ─────────────────────────────────────────────────────────

if command -v python3 >/dev/null 2>&1; then
    step "Rendering the observed 50/50 split to an SVG"
    python3 "$ISTIO_DIR/render-split.py" "$LAST_V1" "$LAST_V2" /tmp/canary-split.svg \
        && printf '    ✓ wrote /tmp/canary-split.svg (open to see the v1/v2 bars)\n' \
        || printf '    (skipped: render-split.py failed; non-fatal)\n'
fi

# ─── Done ────────────────────────────────────────────────────────────────────

step "SUCCESS"
printf 'The order-service canary works: v2 deploys alongside v1, both meshed,\n'
printf 'and Istio shifts live traffic between the two contract versions by weight.\n\n'
printf 'Shift further yourself (e.g. promote v2 fully):\n'
printf '  sed "s/__W_V1__/0/; s/__W_V2__/100/" istio/routing.yaml | kubectl apply -f -\n'
printf '  # then: curl through the gateway; every response now reports v2 + currency\n'
