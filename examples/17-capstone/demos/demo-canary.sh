#!/usr/bin/env bash
#
# demo-canary.sh — the order-service v1→v2 canary as a REPEATABLE, BACKABLE-OUT
# demo (Phase B). The verification-facing counterpart is smoke-canary.sh (which
# asserts the split lands in expected bands); this script is the presenter-facing
# one: bring the canary up at a chosen weight, shift it, and tear it cleanly back
# to a v1-only baseline so it can be replayed.
#
# The data-mesh point: a data product (order-service) evolves its contract — v2
# adds an additive `currency` field — and Istio shifts a controllable fraction of
# live traffic to the new contract version, with no flag-day break and a clean
# rollback. v2 is the same image with API_VERSION=v2 (so GET /version reports v2
# and advertises currency); the VirtualService weights decide the split.
#
# Usage (run from examples/17-capstone/):
#   ./demos/demo-canary.sh up [W_V1 W_V2]   # default 90 10
#   ./demos/demo-canary.sh shift W_V1 W_V2  # move the split (e.g. 50 50, 0 100)
#   ./demos/demo-canary.sh down             # back to v1-only; removes v2 + routing
#
# Idempotent. up re-applies; down ignores-not-found.

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

NS="capstone"
PROFILE="capstone"
ISTIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../istio" && pwd)"
V2_MANIFEST="$ISTIO_DIR/order-service-v2.yaml"
ROUTING="$ISTIO_DIR/routing.yaml"

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
fail() { printf '\n\xe2\x9c\x97 %s\n' "$1" >&2; exit 1; }

apply_weights() {
    local w1="$1" w2="$2"
    sed "s/__W_V1__/${w1}/; s/__W_V2__/${w2}/" "$ROUTING" | kubectl apply -f - >/dev/null \
        || fail "failed to apply routing at ${w1}/${w2}"
    ok "routing applied: v1=${w1}% v2=${w2}%"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  up)
    w1="${1:-90}"; w2="${2:-10}"
    [[ "$(kubectl config current-context 2>/dev/null)" == "$PROFILE" ]] \
        || fail "kubectl context is not '$PROFILE'"
    kubectl get deployment order-service -n "$NS" >/dev/null 2>&1 \
        || fail "order-service (v1) not deployed — install it first via its chart"

    step "Deploying the v2 subset alongside v1"
    kubectl apply -f "$V2_MANIFEST" >/dev/null || fail "failed to apply v2 manifest"
    kubectl rollout status deployment/order-service-v2 -n "$NS" --timeout=3m \
        || fail "order-service-v2 did not become Ready"
    ok "order-service-v2 Ready (meshed; same image, API_VERSION=v2)"

    step "Opening the canary at ${w1}/${w2}"
    apply_weights "$w1" "$w2"

    step "Canary is live. Observe the split:"
    cat <<EOF
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &
    for i in \$(seq 20); do curl -s localhost:8080/version; echo; done
    # ~${w2}% of responses report api_version=v2 and include "currency":"USD"

    Shift the canary forward:   ./demos/demo-canary.sh shift 50 50
    Promote v2 fully:           ./demos/demo-canary.sh shift 0 100
    Back out to v1-only:        ./demos/demo-canary.sh down
EOF
    ;;

  shift)
    [[ $# -eq 2 ]] || fail "usage: demo-canary.sh shift W_V1 W_V2  (e.g. 50 50)"
    step "Shifting the canary to $1/$2"
    apply_weights "$1" "$2"
    ok "split shifted — re-run your observe loop to see the new ratio"
    ;;

  down)
    step "Backing the canary out — returning to a v1-only baseline"
    # 1. Send all traffic to v1 first (so in-flight requests drain to a live subset),
    #    then remove the routing objects entirely (back to plain ClusterIP routing).
    sed "s/__W_V1__/100/; s/__W_V2__/0/" "$ROUTING" | kubectl apply -f - >/dev/null 2>&1 || true
    sleep 2
    kubectl delete virtualservice order-service -n "$NS" --ignore-not-found >/dev/null
    kubectl delete gateway order-service-gateway -n "$NS" --ignore-not-found >/dev/null
    kubectl delete destinationrule order-service -n "$NS" --ignore-not-found >/dev/null
    ok "removed Gateway / VirtualService / DestinationRule"
    # 2. Remove the v2 subset.
    kubectl delete -f "$V2_MANIFEST" --ignore-not-found >/dev/null
    ok "removed order-service-v2"
    step "Baseline restored: only v1 remains, reachable via its ClusterIP Service."
    ;;

  *)
    fail "usage: demo-canary.sh up [W_V1 W_V2] | shift W_V1 W_V2 | down"
    ;;
esac
