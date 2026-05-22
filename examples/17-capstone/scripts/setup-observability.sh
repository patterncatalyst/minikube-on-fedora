#!/usr/bin/env bash
#
# setup-observability.sh — install the capstone observability stack into the
# cluster (CAP-027 metrics, CAP-028 traces): Prometheus (+ kube-state-metrics),
# Tempo (trace backend), and Grafana, all in the 'observability' namespace.
#
# It needs no application changes for METRICS: it scrapes the Istio sidecar on
# the meshed order-service (istio_requests_total) and reads workload replica
# counts from kube-state-metrics, which is what makes KEDA scaling visible.
#
# TRACES: Tempo is installed here as the backend (it receives OTLP directly — no
# separate OpenTelemetry Collector, since our metrics come from scraping, not
# OTLP). Nothing emits traces yet; instrumenting a service to send them is the
# next step (see §17 and the tracing demo).
#
# Like the other capstone platform installs, this is run-once-per-cluster,
# separate from the app releases, and idempotent.
#
# Usage (from examples/17-capstone/):
#   ./scripts/setup-observability.sh
#   kubectl port-forward -n observability svc/grafana 3000:80
#   ./demos/smoke-observability.sh   # metrics plumbing
#   ./demos/smoke-tracing.sh         # trace backend plumbing

set -euo pipefail

NAMESPACE="observability"
OBS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../observability" && pwd)"

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

# ─── 1. helm repos ───────────────────────────────────────────────────────────
printf '==> Ensuring the prometheus-community and grafana-community helm repos are registered\n'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community grafana-community >/dev/null

# ─── 2. Prometheus (+ kube-state-metrics) ────────────────────────────────────
# Chart versions intentionally unpinned (latest from the repo) so this keeps
# working as charts move; pin with --version for a reproducible build.
printf '==> Installing Prometheus into namespace %s\n' "$NAMESPACE"
helm upgrade --install prometheus prometheus-community/prometheus \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$OBS_DIR/prometheus-values.yaml" \
    --wait

# ─── 3. Tempo (trace backend) ────────────────────────────────────────────────
# Monolithic single-binary Tempo (r29b). In the grafana-community repo (the
# grafana/* charts moved there 2026-01-30), so no extra repo beyond Grafana.
printf '==> Installing Tempo (trace backend) into namespace %s\n' "$NAMESPACE"
helm upgrade --install tempo grafana-community/tempo \
    --namespace "$NAMESPACE" \
    -f "$OBS_DIR/tempo-values.yaml" \
    --wait

# ─── 4. Grafana ──────────────────────────────────────────────────────────────
printf '==> Installing Grafana into namespace %s\n' "$NAMESPACE"
helm upgrade --install grafana grafana-community/grafana \
    --namespace "$NAMESPACE" \
    -f "$OBS_DIR/grafana-values.yaml" \
    --wait

# ─── Done ────────────────────────────────────────────────────────────────────
printf '\n==> Prometheus + Grafana installed in the %s namespace.\n\n' "$NAMESPACE"
printf 'Open Grafana and find the "Capstone — Scaling & Traffic" dashboard:\n'
printf '  kubectl port-forward -n %s svc/grafana 3000:80    # http://localhost:3000\n\n' "$NAMESPACE"
# The grafana chart preserves an existing admin password on upgrade (it looks up
# the secret), so the password is NOT reliably "capstone" if a grafana secret
# already existed. Read the truth from the secret rather than assuming.
printf 'Login (read the real credentials from the secret — the chart keeps an existing\n'
printf 'password on upgrade, so do not assume it is the values default):\n'
printf '  user: $(kubectl get secret grafana -n %s -o jsonpath="{.data.admin-user}" | base64 -d)\n' "$NAMESPACE"
printf '  pass: $(kubectl get secret grafana -n %s -o jsonpath="{.data.admin-password}" | base64 -d)\n\n' "$NAMESPACE"
printf 'Then make the graphs move:\n'
printf '  ./demos/smoke-keda-http.sh    # watch graphql-gateway replicas go 0→1→0\n'
printf '  ./demos/smoke-canary.sh       # watch order-service request rate by code\n'
printf '  ./demos/smoke-observability.sh  # verify the stack is scraping\n'
