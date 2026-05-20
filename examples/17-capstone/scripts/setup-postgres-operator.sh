#!/usr/bin/env bash
#
# setup-postgres-operator.sh — install the CloudNativePG operator into the
# capstone cluster.
#
# IMPORTANT: installing an operator is a CLUSTER-WIDE action. It:
#   - registers Custom Resource Definitions (CRDs are always cluster-scoped:
#     once installed, `Cluster`, `Pooler`, `Backup`, etc. exist in EVERY
#     namespace)
#   - runs a controller (in the cnpg-system namespace) that watches for
#     those CRs across ALL namespaces and reconciles them
#
# This is fundamentally different from deploying an application into a
# namespace. You are modifying the cluster's type system and adding a
# control loop that spans the whole cluster. Treat operator installs with
# the same care you'd treat any cluster-scoped change.
#
# Consistent with how §11 (Istio) and §12 (Strimzi, KEDA) install their
# operators: separate from the application helm release, run once per
# cluster.
#
# Idempotent — re-running upgrades the operator in place.
#
# Usage:
#   ./setup-postgres-operator.sh

set -euo pipefail

OPERATOR_NS="cnpg-system"
CHART_VERSION="0.23.0"   # CloudNativePG helm chart version; pin for reproducibility
RELEASE_NAME="cnpg"

# ─── Pre-flight ──────────────────────────────────────────────────────────────

if ! command -v helm >/dev/null 2>&1; then
    printf 'ERROR: helm not in PATH. See §2 for installation.\n' >&2
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    printf 'ERROR: kubectl not in PATH. See §2 for installation.\n' >&2
    exit 1
fi

current_context=$(kubectl config current-context 2>/dev/null || echo "")
if [[ "$current_context" != "capstone" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "capstone".\n' "$current_context" >&2
    printf 'The operator will be installed cluster-wide on THAT cluster.\n' >&2
    printf 'Switch with: kubectl config use-context capstone\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

# ─── Install ─────────────────────────────────────────────────────────────────

printf '==> Adding the CloudNativePG helm repository\n'
helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
helm repo update cnpg >/dev/null

printf '==> Installing CloudNativePG operator (cluster-wide) into %s\n' "$OPERATOR_NS"
printf '    This registers CRDs (Cluster, Pooler, Backup, ...) cluster-wide\n'
printf '    and runs a controller that watches all namespaces.\n'

helm upgrade --install "$RELEASE_NAME" cnpg/cloudnative-pg \
    --namespace "$OPERATOR_NS" \
    --create-namespace \
    --version "$CHART_VERSION" \
    --wait \
    --timeout 5m

printf '==> Waiting for the operator deployment to be Available\n'
kubectl wait --for=condition=Available --timeout=180s \
    deployment/cnpg-cloudnative-pg \
    -n "$OPERATOR_NS"

printf '==> Verifying CRDs are registered (cluster-scoped)\n'
kubectl get crd | grep -E 'cnpg\.io' || {
    printf 'ERROR: CloudNativePG CRDs not found after install.\n' >&2
    exit 1
}

printf '\n'
printf '==> CloudNativePG operator is installed and watching cluster-wide.\n'
printf '\n'
printf 'What just happened (cluster-wide effects):\n'
printf '  - CRDs registered: clusters.postgresql.cnpg.io, poolers..., backups...\n'
printf '    (these now exist in every namespace on this cluster)\n'
printf '  - Controller running in namespace %s, reconciling Cluster CRs\n' "$OPERATOR_NS"
printf '    in any namespace\n'
printf '\n'
printf 'Next: the capstone umbrella chart ships a Cluster CR in the\n'
printf 'capstone namespace (charts/capstone/charts/postgres/). The operator\n'
printf 'will see it and provision the actual Postgres pods + services.\n'
