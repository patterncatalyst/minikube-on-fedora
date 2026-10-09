#!/usr/bin/env bash
#
# cluster-status.sh — one-shot health report for the capstone cluster.
#
# Answers, in a single command, the questions we kept running ten commands to
# answer during the r29c debugging marathon:
#   - Is the profile running and is the control plane actually healthy?
#     (etcd can crashloop in place after a long uptime — see §17 troubleshooting.)
#   - Which locally-built images are MISSING from the node?
#     (`minikube -p mof-capstone image ls`; a missing image surfaces as
#     ErrImageNeverPull because the Deployments use pullPolicy: Never.)
#   - Are the core services, KEDA, and the observability stack up?
#
# Read-only: it changes nothing. Use it any time something looks off, and as the
# closing summary of cluster-up.sh.
#
# Run from examples/17-capstone/:  ./scripts/cluster-status.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/env.sh"

TAG="v1"
# Services whose images are loaded into the node (one per services/ dir).
SERVICES=(graphql-gateway inventory-service notification-service order-service payment-service shipping-service)

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }   # ✓
warn() { printf '    \xe2\x9a\xa0 %s\n' "$1"; }   # ⚠
bad()  { printf '    \xe2\x9c\x97 %s\n' "$1"; }   # ✗

PROBLEMS=0
note_problem() { PROBLEMS=$((PROBLEMS + 1)); }

# ─── Profile / node ──────────────────────────────────────────────────────────
step "minikube profile"
if minikube status -p "$PROFILE" >/dev/null 2>&1; then
    ok "profile '$PROFILE' is running"
else
    bad "profile '$PROFILE' is not running — start it with: ./scripts/cluster-up.sh"
    note_problem
    printf '\n(Stopping here — nothing else can be checked while the node is down.)\n'
    exit 1
fi

# ─── Control plane (the etcd-wedge check) ────────────────────────────────────
step "Control plane"
if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    ok "API server is serving (/readyz)"
else
    bad "API server is NOT responding — control plane may be wedged"
    note_problem
fi
# etcd specifically: a long-lived node can wedge etcd on its peer port (:2380),
# crashlooping it (Exit 1, not OOM) and taking the rest of the control plane down.
cp_bad="$(kubectl get pods -n kube-system 2>/dev/null \
    | grep -iE 'etcd|scheduler|controller-manager|apiserver' \
    | grep -ivE 'Running|Completed' || true)"
if [[ -n "$cp_bad" ]]; then
    bad "control-plane pods not healthy:"
    printf '%s\n' "$cp_bad" | sed 's/^/        /'
    warn "if etcd shows 'address already in use', cycle the node: minikube stop -p $PROFILE && minikube start -p $PROFILE"
    note_problem
else
    ok "etcd / scheduler / controller-manager all Running"
fi

# ─── Node images: which are missing? ─────────────────────────────────────────
step "Node images (minikube -p $PROFILE image ls)"
node_images="$(minikube -p "$PROFILE" image ls 2>/dev/null || true)"
if [[ -z "$node_images" ]]; then
    warn "could not list images in profile $PROFILE"
    note_problem
else
    missing=()
    for svc in "${SERVICES[@]}"; do
        if grep -qE "(^|/)${svc}:${TAG}\$" <<<"$node_images"; then
            :
        else
            missing+=("$svc")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "all ${#SERVICES[@]} service images present (:${TAG}) in the node"
    else
        bad "missing from the node (will cause ErrImageNeverPull): ${missing[*]}"
        warn "rebuild them with: ./scripts/cluster-up.sh   (or per-image: ./scripts/build-image.sh services/<svc> <svc> ${TAG})"
        note_problem
    fi
fi

# ─── Workload health by namespace ────────────────────────────────────────────
report_ns() {
    local ns="$1" label="$2"
    local bad_pods
    # Completed Jobs and 0-replica (KEDA-scaled) workloads are not failures.
    bad_pods="$(kubectl get pods -n "$ns" 2>/dev/null \
        | tail -n +2 | grep -ivE 'Running|Completed' || true)"
    if [[ -z "$bad_pods" ]]; then
        ok "${label}: all pods Running/Completed"
    else
        bad "${label}: pods not healthy:"
        printf '%s\n' "$bad_pods" | sed 's/^/        /'
        note_problem
    fi
}
step "Workloads"
report_ns capstone      "capstone (services)"
report_ns observability "observability (Prometheus/Grafana/Tempo)"
report_ns keda          "keda (autoscaler + HTTP add-on)"

# KEDA HTTPScaledObject — the gateway is meant to scale to zero, so 0 pods is fine.
hso="$(kubectl get httpscaledobject -n capstone graphql-gateway-http \
    -o jsonpath='{.status.conditions[?(@.type=="HTTPScaledObjectIsReady")].status}' 2>/dev/null || true)"
if [[ "$hso" == "True" ]]; then
    ok "KEDA HTTPScaledObject for graphql-gateway is Ready (gateway may be scaled to zero — expected)"
else
    warn "KEDA HTTPScaledObject not reporting Ready (status: ${hso:-unknown})"
fi

# ─── Verdict ─────────────────────────────────────────────────────────────────
step "Verdict"
if [[ $PROBLEMS -eq 0 ]]; then
    ok "cluster looks healthy — ready to demo/smoke"
else
    bad "$PROBLEMS area(s) need attention (see above). ./scripts/cluster-up.sh heals images + a wedged control plane."
    exit 1
fi
