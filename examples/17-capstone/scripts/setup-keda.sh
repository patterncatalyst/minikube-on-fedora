#!/usr/bin/env bash
#
# setup-keda.sh — install KEDA (core + HTTP add-on) into the capstone cluster,
# in preparation for the dual autoscalers (r26b, CAP-025):
#   * Kafka consumer-lag scaling for notification-service (core KEDA)
#   * HTTP request scaling for graphql-gateway (the HTTP add-on)
#
# Like the other capstone platform installs, this is run-once-per-cluster,
# separate from the app releases. Idempotent. Versions match §12.
#
# Usage (from examples/17-capstone/):
#   ./scripts/setup-keda.sh
#
# Then apply the scalers:
#   kubectl apply -f keda/notification-scaledobject.yaml
#   kubectl apply -f keda/gateway-httpscaledobject.yaml
#   ./demos/smoke-keda-kafka.sh
#   ./demos/smoke-keda-http.sh

set -euo pipefail

NAMESPACE="keda"
KEDA_VERSION="${KEDA_VERSION:-2.19.0}"
KEDA_HTTP_VERSION="${KEDA_HTTP_VERSION:-0.12.2}"

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH — see §2.\n' >&2; exit 1; }

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "capstone" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "capstone".\n' "$current_context" >&2
    printf 'Switch with: kubectl config use-context capstone\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── 1. kedacore helm repo ───────────────────────────────────────────────────
printf '==> Ensuring the kedacore helm repo is registered\n'
if helm repo list 2>/dev/null | grep -q '^kedacore'; then
    helm repo update kedacore >/dev/null
else
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update kedacore >/dev/null
fi

# ─── 2. KEDA core ────────────────────────────────────────────────────────────
printf '==> Installing KEDA core %s into namespace %s\n' "$KEDA_VERSION" "$NAMESPACE"
helm upgrade --install keda kedacore/keda \
    --version "$KEDA_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait

# ─── 3. KEDA HTTP add-on ─────────────────────────────────────────────────────
printf '==> Installing the KEDA HTTP add-on %s into namespace %s\n' "$KEDA_HTTP_VERSION" "$NAMESPACE"
# interceptor.replicas.waitTimeout (default 20s) is how long the interceptor
# holds a request waiting for the scaled-from-zero workload to have a Ready
# replica. 20s is too short here: a cold start (KEDA activation + image pull +
# Python boot + startupProbe) routinely exceeds it, so requests 502 with
# "context deadline exceeded" BEFORE a backend exists — which also starves KEDA
# of the stable pending-request pressure it needs to activate promptly, making
# scale-up slow and erratic. 180s holds the request through the whole cold start.
helm upgrade --install keda-add-ons-http kedacore/keda-add-ons-http \
    --version "$KEDA_HTTP_VERSION" \
    --namespace "$NAMESPACE" \
    --set interceptor.replicas.waitTimeout=180s \
    --wait

# ─── Done ────────────────────────────────────────────────────────────────────
printf '\n==> KEDA core + HTTP add-on installed in the %s namespace.\n\n' "$NAMESPACE"
printf 'Apply the two scalers, then run the demos:\n'
printf '  kubectl apply -f keda/notification-scaledobject.yaml\n'
printf '  kubectl apply -f keda/gateway-httpscaledobject.yaml\n'
printf '  ./demos/smoke-keda-kafka.sh    # consumer-lag scaling, notification-service\n'
printf '  ./demos/smoke-keda-http.sh     # HTTP request scaling, graphql-gateway\n'
