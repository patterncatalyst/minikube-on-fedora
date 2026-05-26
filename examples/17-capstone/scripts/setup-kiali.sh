#!/usr/bin/env bash
#
# setup-kiali.sh — add Kiali (the mesh-visualization console) to the capstone
# cluster, wired to the EXISTING capstone observability stack rather than
# standing up its own (CAP-0NN). Run-once-per-cluster, idempotent.
#
# Why this exists: the capstone observability stack (setup-observability.sh) is
# Prometheus + Tempo + Grafana in the `observability` namespace. Kiali gives the
# one thing that stack doesn't: a live mesh-topology graph — the products and the
# traffic between them, the canary split included. The demo walkthrough's final
# act drives it.
#
# SINGLE-STACK WIRING (the whole point of this script): the upstream Istio
# `samples/addons/kiali.yaml` ships a Kiali that expects its OWN Prometheus at
# http://prometheus.istio-system:9090. We do NOT want a second Prometheus. So
# this script applies ONLY the Kiali addon (not the full samples/addons/ bundle,
# which would also install Prometheus, Grafana, Jaeger, and Loki), then patches
# Kiali's ConfigMap so external_services points at the capstone's existing
# Prometheus, Grafana, and Tempo in the `observability` namespace.
#
# What it does:
#   1. Verifies the Istio dir (samples/addons/kiali.yaml) and the capstone
#      observability stack are present.
#   2. Applies ONLY samples/addons/kiali.yaml into istio-system.
#   3. Patches the kiali ConfigMap external_services → capstone Prometheus /
#      Grafana / Tempo, and restarts Kiali to pick it up.
#   4. Waits for the Kiali deployment to be Ready.
#
# Prerequisites (run these first):
#   - scripts/setup-istio.sh        (istiod + ingress gateway + injection)
#   - scripts/setup-observability.sh (Prometheus + Tempo + Grafana)
#
# Usage (from examples/17-capstone/):
#   ./scripts/setup-kiali.sh
#
# Then verify + view:
#   ./demos/smoke-kiali.sh
#   kubectl port-forward -n istio-system svc/kiali 20001:20001
#   open http://localhost:20001   (Graph → namespace: capstone)

set -euo pipefail

ISTIO_SYSTEM="istio-system"
OBS_NS="observability"
ISTIO_DIR="${ISTIO_DIR:-${HOME}/.local/share/istio-current}"

# capstone observability service endpoints (single-stack wiring targets)
PROM_URL="http://prometheus-server.${OBS_NS}:80"
GRAFANA_IN_URL="http://grafana.${OBS_NS}:80"
GRAFANA_EXT_URL="http://localhost:3000"          # what a browser uses (port-forward)
TEMPO_URL="http://tempo.${OBS_NS}:3100"

step() { printf '\n==> %s\n' "$1"; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────

command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl not in PATH.\n' >&2; exit 1; }

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "capstone" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "capstone".\n' "$current_context" >&2
    printf 'Switch with: kubectl config use-context capstone\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

KIALI_MANIFEST="${ISTIO_DIR}/samples/addons/kiali.yaml"
if [[ ! -f "$KIALI_MANIFEST" ]]; then
    printf 'ERROR: Kiali addon manifest not found at:\n  %s\n' "$KIALI_MANIFEST" >&2
    printf 'The §11 base setup downloads the Istio release (with samples/addons) to\n' >&2
    printf '~/.local/share/istio-current. Run the repo-root scripts/setup-istio.sh first,\n' >&2
    printf 'or set ISTIO_DIR to your Istio distribution directory.\n' >&2
    exit 1
fi

kubectl get ns "$ISTIO_SYSTEM" >/dev/null 2>&1 \
    || { printf 'ERROR: namespace %s not found — run scripts/setup-istio.sh first.\n' "$ISTIO_SYSTEM" >&2; exit 1; }

# the single-stack wiring targets must exist; warn (not fail) so Kiali can still
# come up for topology even if a metrics piece is mid-install.
if ! kubectl get svc prometheus-server -n "$OBS_NS" >/dev/null 2>&1; then
    printf 'WARNING: %s/prometheus-server not found. Kiali will install but its\n' "$OBS_NS" >&2
    printf 'metrics integration will be dark until scripts/setup-observability.sh has run.\n' >&2
fi

# ─── 1. Apply ONLY the Kiali addon ───────────────────────────────────────────

step "Applying ONLY the Kiali addon (not the full samples/addons bundle)"
printf '    source: %s\n' "$KIALI_MANIFEST"
kubectl apply -f "$KIALI_MANIFEST"

# ─── 2. Wire Kiali to the existing capstone observability stack ──────────────
# The addon ships a ConfigMap `kiali` whose key config.yaml contains the
# external_services block. We overwrite that block to point at the capstone
# Prometheus / Grafana / Tempo instead of Kiali's bundled defaults.

step "Wiring Kiali external_services → the capstone observability stack"
printf '    prometheus: %s\n' "$PROM_URL"
printf '    grafana:    %s (in-cluster) / %s (browser)\n' "$GRAFANA_IN_URL" "$GRAFANA_EXT_URL"
printf '    tracing:    %s (Tempo)\n' "$TEMPO_URL"

# Build the desired config.yaml for the kiali ConfigMap. Kiali reads this on
# startup; we patch ONLY the config.yaml key so the addon's own labels and
# metadata are preserved (idempotent — re-running produces the same value).
read -r -d '' KIALI_CONFIG <<EOF || true
istio_namespace: ${ISTIO_SYSTEM}
auth:
  strategy: anonymous
deployment:
  view_only_mode: false
external_services:
  istio:
    root_namespace: ${ISTIO_SYSTEM}
  prometheus:
    url: ${PROM_URL}
  grafana:
    enabled: true
    internal_url: ${GRAFANA_IN_URL}
    external_url: ${GRAFANA_EXT_URL}
  tracing:
    enabled: true
    provider: tempo
    use_grpc: false
    internal_url: ${TEMPO_URL}
    external_url: ${GRAFANA_EXT_URL}/explore
server:
  web_root: /
EOF

# Patch only the data."config.yaml" key. A JSON merge patch with the value
# passed via --patch-file avoids quoting hell with the multi-line YAML string.
PATCH_FILE="$(mktemp)"
trap 'rm -f "$PATCH_FILE"' EXIT
python3 - "$KIALI_CONFIG" >"$PATCH_FILE" <<'PY'
import json, sys
cfg = sys.argv[1]
print(json.dumps({"data": {"config.yaml": cfg}}))
PY
kubectl patch configmap kiali -n "$ISTIO_SYSTEM" --type merge --patch-file "$PATCH_FILE"

step "Restarting Kiali to pick up the rewired config"
kubectl rollout restart deployment/kiali -n "$ISTIO_SYSTEM"

# ─── 3. Wait for Kiali to be Ready ───────────────────────────────────────────

step "Waiting for the Kiali deployment to be Ready"
kubectl rollout status deployment/kiali -n "$ISTIO_SYSTEM" --timeout=5m

# ─── Done ────────────────────────────────────────────────────────────────────

step "Kiali is installed and wired to the capstone observability stack."
printf '\nView the mesh topology:\n'
printf '  kubectl port-forward -n %s svc/kiali 20001:20001\n' "$ISTIO_SYSTEM"
printf '  open http://localhost:20001   (Graph → namespace: capstone)\n'
printf '\nVerify:\n'
printf '  ./demos/smoke-kiali.sh\n'
printf '\nNote: the live traffic graph only shows edges while traffic is flowing —\n'
printf 'run a demo (e.g. ./demos/smoke-trace-flow.sh or ./demos/demo-canary.sh)\n'
printf 'to make the products and their calls appear.\n'
