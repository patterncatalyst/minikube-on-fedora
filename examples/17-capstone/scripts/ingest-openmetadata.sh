#!/usr/bin/env bash
#
# ingest-openmetadata.sh — populate the OpenMetadata catalog from the capstone's
# data sources and declare the cross-product lineage (r27b, CAP-023).
#
# Runs three one-off Kubernetes Jobs, in order:
#   1. om-ingest-postgres — catalog the capstone Postgres schemas as Tables
#      (Database Service "capstone-postgres")
#   2. om-ingest-kafka    — catalog the Strimzi topics as Topics
#      (Messaging Service "capstone-kafka"); bare, no schema registry
#   3. om-declare-lineage — PUT the two edges that connect them:
#         orders -> order-placed -> notifications
#
# Like setup-openmetadata.sh, this is a run-on-demand operation, separate from
# the long-lived Helm releases. The Jobs are plain kubectl-applied manifests,
# not Helm-managed: a Job's pod template is immutable, and these are meant to be
# re-run (after new data, or to refresh the catalog), so we delete-then-apply
# each rather than fight `helm upgrade`. OpenMetadata upserts entities by FQN
# and the lineage PUT is idempotent, so re-running is safe.
#
# Prerequisites:
#   * capstone profile running, kubectl context = capstone
#   * scripts/setup-openmetadata.sh has been run (the server is up and serving)
#   * the data sources exist: the capstone-postgres Cluster with the service
#     schemas, and the capstone-kafka cluster with the order-placed topic
#     (i.e. the app has been deployed and at least one order placed). Ingestion
#     reflects whatever exists at run time.
#
# Usage (from examples/17-capstone/):
#   ./scripts/ingest-openmetadata.sh
#
# Then verify end-to-end:
#   ./demos/smoke-om-lineage.sh

set -euo pipefail

NS="capstone"
JOB_TIMEOUT="10m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ING_DIR="$SCRIPT_DIR/../openmetadata/ingestion"

# ─── Pre-flight ──────────────────────────────────────────────────────────────

for tool in kubectl; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'ERROR: %s not in PATH. See §2 for installation.\n' "$tool" >&2
        exit 1
    }
done

for f in postgres.yaml kafka.yaml get_token.py lineage.py \
         job-postgres.yaml job-kafka.yaml job-lineage.yaml; do
    [[ -f "$ING_DIR/$f" ]] || { printf 'ERROR: missing %s\n' "$ING_DIR/$f" >&2; exit 1; }
done

current_context="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$current_context" != "capstone" ]]; then
    printf 'WARNING: current kubectl context is "%s", not "capstone".\n' "$current_context" >&2
    printf 'Switch with: kubectl config use-context capstone\n' >&2
    printf 'Continue anyway? [y/N] ' >&2
    read -r answer
    [[ "$answer" =~ ^[Yy] ]] || exit 1
fi

kubectl get deployment openmetadata -n "$NS" >/dev/null 2>&1 || {
    printf 'ERROR: openmetadata Deployment not found in %s.\n' "$NS" >&2
    printf 'Run scripts/setup-openmetadata.sh first.\n' >&2
    exit 1
}
printf '==> Waiting for the OpenMetadata server to be ready\n'
kubectl rollout status deployment/openmetadata -n "$NS" --timeout=5m

# ─── ConfigMap holding the workflow configs + helper scripts ─────────────────
# One ConfigMap, mounted read-only at /opt/ingestion by all three Jobs.

printf '==> Creating ConfigMap om-ingestion-config from %s\n' "$ING_DIR"
kubectl create configmap om-ingestion-config \
    --namespace "$NS" \
    --from-file=postgres.yaml="$ING_DIR/postgres.yaml" \
    --from-file=kafka.yaml="$ING_DIR/kafka.yaml" \
    --from-file=get_token.py="$ING_DIR/get_token.py" \
    --from-file=lineage.py="$ING_DIR/lineage.py" \
    --dry-run=client -o yaml | kubectl apply -f -

# ─── Helper: run one Job to completion (delete-then-apply for re-runnability) ─

run_job() {
    local name="$1" manifest="$2"
    printf '\n==> Job %s\n' "$name"
    kubectl delete job "$name" -n "$NS" --ignore-not-found >/dev/null
    kubectl apply -f "$ING_DIR/$manifest"
    printf '    waiting for %s to complete (timeout %s)...\n' "$name" "$JOB_TIMEOUT"
    if ! kubectl wait --for=condition=complete "job/$name" -n "$NS" --timeout="$JOB_TIMEOUT"; then
        printf '\n✗ Job %s did not complete. Recent logs:\n' "$name" >&2
        kubectl logs -n "$NS" "job/$name" --tail=60 2>&1 | sed 's/^/    /' >&2 || true
        printf '\nInspect with: kubectl logs -n %s job/%s\n' "$NS" "$name" >&2
        exit 1
    fi
    printf '    ✓ %s complete\n' "$name"
}

# ─── 1 & 2: ingest sources, then 3: declare lineage (order matters) ──────────

run_job om-ingest-postgres job-postgres.yaml
run_job om-ingest-kafka    job-kafka.yaml
run_job om-declare-lineage job-lineage.yaml

# ─── Done ────────────────────────────────────────────────────────────────────

printf '\n==> Catalog populated and lineage declared.\n\n'
printf 'Browse it:\n'
printf '  kubectl port-forward -n %s svc/openmetadata 8585:8585\n' "$NS"
printf '  open http://127.0.0.1:8585  (admin@open-metadata.org / admin)\n'
printf '  → Services shows capstone-postgres (Database) and capstone-kafka (Messaging)\n'
printf '  → the order-placed topic'\''s Lineage tab shows orders upstream, notifications downstream\n\n'
printf 'Verify end-to-end:\n'
printf '  ./demos/smoke-om-lineage.sh\n'
