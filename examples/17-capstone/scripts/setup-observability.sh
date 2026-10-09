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
#   kubectl apply -f host-access/{prometheus,grafana,tempo}-host.yaml   # bootstrap-capstone.sh does this
#   ./demos/smoke-observability.sh   # metrics plumbing
#   ./demos/smoke-tracing.sh         # trace backend plumbing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

NAMESPACE="observability"

# Pinned chart versions (current stable, verified against the repo index 2026-10-09).
PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-29.36.1}"   # prometheus-community/prometheus
TEMPO_CHART_VERSION="${TEMPO_CHART_VERSION:-3.1.0}"               # grafana-community/tempo
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-13.4.0}"          # grafana-community/grafana
OBS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../observability" && pwd)"

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }
command -v helm    >/dev/null 2>&1 || { printf 'ERROR: helm not in PATH — see §2.\n' >&2; exit 1; }

# ─── 1. helm repos ───────────────────────────────────────────────────────────
printf '==> Ensuring the prometheus-community and grafana-community helm repos are registered\n'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community grafana-community >/dev/null

# ─── 2. Prometheus (+ kube-state-metrics) ────────────────────────────────────
# Chart versions are pinned above for a reproducible build; override with
# PROMETHEUS_CHART_VERSION / TEMPO_CHART_VERSION / GRAFANA_CHART_VERSION.
printf '==> Installing Prometheus into namespace %s\n' "$NAMESPACE"
helm upgrade --install prometheus prometheus-community/prometheus \
    --version "$PROMETHEUS_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$OBS_DIR/prometheus-values.yaml" \
    --wait

# ─── 3. Tempo (trace backend) ────────────────────────────────────────────────
# Monolithic single-binary Tempo (r29b). In the grafana-community repo (the
# grafana/* charts moved there 2026-01-30), so no extra repo beyond Grafana.
printf '==> Installing Tempo (trace backend) into namespace %s\n' "$NAMESPACE"
helm upgrade --install tempo grafana-community/tempo \
    --version "$TEMPO_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    -f "$OBS_DIR/tempo-values.yaml" \
    --wait

# ─── 4. Grafana ──────────────────────────────────────────────────────────────
printf '==> Installing Grafana into namespace %s\n' "$NAMESPACE"
helm upgrade --install grafana grafana-community/grafana \
    --version "$GRAFANA_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    -f "$OBS_DIR/grafana-values.yaml" \
    --wait

# ─── Done ────────────────────────────────────────────────────────────────────
printf '\n==> Prometheus + Grafana installed in the %s namespace.\n\n' "$NAMESPACE"
printf 'Open Grafana and find the "Capstone — Scaling & Traffic" dashboard (after the\n'
printf 'host-access companions are applied; bootstrap-capstone.sh does this):\n'
printf '  http://127.0.0.1:%s     (credentials: see observability/grafana-values.yaml)\n' "$HOST_PORT_GRAFANA"
printf '  Prometheus: http://127.0.0.1:%s    Tempo: http://127.0.0.1:%s\n\n' "$HOST_PORT_PROMETHEUS" "$HOST_PORT_TEMPO"
printf 'Then make the graphs move:\n'
printf '  ./demos/smoke-keda-http.sh    # watch graphql-gateway replicas go 0→1→0\n'
printf '  ./demos/smoke-canary.sh       # watch order-service request rate by code\n'
printf '  ./demos/smoke-observability.sh  # verify the stack is scraping\n'
