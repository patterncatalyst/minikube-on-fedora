#!/usr/bin/env bash
#
# walkthrough.sh — the capstone's replayable presenter walkthrough (Phase E).
#
# Five acts, each shelling out to an existing demo/smoke script with narration
# between them. Presenter-driven: Enter to advance between acts so you control
# the tempo and can answer questions in the gaps. Maps one-for-one to the deck's
# "What you can see it do" slide:
#
#   1. trace      — one GraphQL query → trace spans across three products in Tempo
#   2. scale      — KEDA scales notification-service on Kafka lag (zero → up → zero)
#   3. canary     — order-service v1→v2 contract evolution, weight-shifted by Istio
#   4. lineage    — OpenMetadata shows the cross-product lineage of the spine
#   5. topology   — Kiali shows the live mesh graph with the canary split
#
# Run from examples/17-capstone/. Each act exits non-zero on failure with the
# act's own diagnostics — the walkthrough stops there so you can investigate
# (resources left in place; the underlying demos are designed for that).
#
# Usage:
#   ./demos/walkthrough.sh                     # run all five acts
#   ./demos/walkthrough.sh --only canary       # rehearse one act
#   ./demos/walkthrough.sh --skip lineage      # skip an act (repeatable)
#   ./demos/walkthrough.sh --no-preflight      # skip the readiness checks (faster)
#   ./demos/walkthrough.sh --help

set -uo pipefail

# ─── Setup ───────────────────────────────────────────────────────────────────

# resolve repo paths regardless of where this is invoked from, then cd to the
# capstone root so the demo scripts see the relative paths they expect.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPSTONE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$CAPSTONE_ROOT"

NS="capstone"
OBS_NS="observability"
ISTIO_SYSTEM="istio-system"

# colors only when stdout is a TTY (no escape junk in logs/pipes)
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YEL=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; RST=""
fi

# ─── Args ────────────────────────────────────────────────────────────────────

ALL_ACTS=(trace scale canary lineage topology)
SKIP=()
ONLY=""
PREFLIGHT=1

usage() {
    cat <<'USAGE'
walkthrough.sh — the capstone's five-act presenter walkthrough

  ./demos/walkthrough.sh                     # all five acts, Enter to advance
  ./demos/walkthrough.sh --only ACT          # run one act in isolation
  ./demos/walkthrough.sh --skip ACT          # skip an act (repeatable)
  ./demos/walkthrough.sh --no-preflight      # skip readiness checks
  ./demos/walkthrough.sh --help              # this message

Acts (in order):  trace  scale  canary  lineage  topology
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --only)    ONLY="$2"; shift 2 ;;
        --skip)    SKIP+=("$2"); shift 2 ;;
        --no-preflight) PREFLIGHT=0; shift ;;
        *) printf '%sunknown flag:%s %s\n\n' "$RED" "$RST" "$1"; usage; exit 2 ;;
    esac
done

want_act() {
    local act="$1"
    [[ -n "$ONLY" && "$ONLY" != "$act" ]] && return 1
    for s in ${SKIP[@]+"${SKIP[@]}"}; do [[ "$s" == "$act" ]] && return 1; done
    return 0
}

# validate --only / --skip values up front so a typo doesn't silently no-op
validate_act() {
    local a="$1"
    for x in "${ALL_ACTS[@]}"; do [[ "$x" == "$a" ]] && return 0; done
    printf '%sunknown act:%s %s  (valid: %s)\n' "$RED" "$RST" "$a" "${ALL_ACTS[*]}"
    exit 2
}
[[ -n "$ONLY" ]] && validate_act "$ONLY"
for s in ${SKIP[@]+"${SKIP[@]}"}; do validate_act "$s"; done

# ─── Presentation helpers ────────────────────────────────────────────────────

ACT_NUM=0
ACT_TOTAL=0
for a in "${ALL_ACTS[@]}"; do want_act "$a" && ACT_TOTAL=$((ACT_TOTAL + 1)); done

act_header() {
    local short="$1" title="$2" lede="$3"
    ACT_NUM=$((ACT_NUM + 1))
    printf '\n%s%s═══════════════════════════════════════════════════════════════════════%s\n' "$BOLD" "$BLU" "$RST"
    printf '%s%s  ACT %d / %d  ·  %s%s\n' "$BOLD" "$BLU" "$ACT_NUM" "$ACT_TOTAL" "$title" "$RST"
    printf '%s%s═══════════════════════════════════════════════════════════════════════%s\n' "$BOLD" "$BLU" "$RST"
    printf '%s%s%s\n\n' "$DIM" "$lede" "$RST"
}

narrate() { printf '%s  ▸ %s%s\n' "$YEL" "$1" "$RST"; }
info()    { printf '%s    %s%s\n' "$DIM" "$1" "$RST"; }
prompt_enter() {
    local label="${1:-press Enter to begin this act}"
    printf '\n%s[%s]%s ' "$BOLD" "$label" "$RST"
    read -r _ </dev/tty || true
}

# act runner: announces the underlying script, runs it, surfaces success/failure
run_act() {
    local title="$1"; shift
    local cmd=("$@")
    printf '%s  ↻ running: %s%s\n\n' "$DIM" "${cmd[*]}" "$RST"
    if "${cmd[@]}"; then
        printf '\n%s  ✓ act passed: %s%s\n' "$GRN" "$title" "$RST"
        return 0
    else
        printf '\n%s  ✗ act FAILED: %s%s\n' "$RED" "$title" "$RST"
        printf '%s    (resources left in place — investigate, then resume with --only or --skip)%s\n' "$DIM" "$RST"
        return 1
    fi
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
# Kiali act starts a port-forward the presenter keeps open in the browser
# through the rest of the discussion. Tear it down on exit no matter how we got
# there (Ctrl-C, normal exit, failure).
KIALI_PF=""
cleanup() {
    if [[ -n "$KIALI_PF" ]] && kill -0 "$KIALI_PF" 2>/dev/null; then
        printf '\n%s  cleaning up Kiali port-forward (pid %s)%s\n' "$DIM" "$KIALI_PF" "$RST"
        kill "$KIALI_PF" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'printf "\n%sinterrupted%s\n" "$RED" "$RST"; exit 130' INT

# ─── Preflight ───────────────────────────────────────────────────────────────
# Cheap "is the stack actually here?" checks. Each failure includes the fix.

preflight() {
    printf '%s%spreflight%s\n' "$BOLD" "$BLU" "$RST"
    local fail=0

    # check: at least one Ready pod matching a label selector in a namespace.
    # Resilient to chart name changes (Deployment vs StatefulSet, release-name
    # prefixes, etc.) — we don't care WHAT kind of object owns the pod, only
    # that it's Ready.
    ready_by_label() { # ready_by_label <namespace> <label-selector>
        local ns="$1" sel="$2" line
        # jsonpath emits one "True/False" per pod's Ready condition; we need at least one True
        line="$(kubectl get pods -n "$ns" -l "$sel" \
                -o 'jsonpath={range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
                2>/dev/null || true)"
        [[ -n "$line" ]] && printf '%s\n' "$line" | grep -qx True
    }
    # check: namespace exists
    ns_exists() { kubectl get ns "$1" >/dev/null 2>&1; }

    check() { # check <label> <test-expression> <fix-message>
        local label="$1" cmd="$2" fix="$3"
        if eval "$cmd"; then
            printf '  %s✓%s %s\n' "$GRN" "$RST" "$label"
        else
            printf '  %s✗%s %s\n      %sfix:%s %s\n' "$RED" "$RST" "$label" "$DIM" "$RST" "$fix"
            fail=$((fail + 1))
        fi
    }

    check "kubectl reachable" \
          "kubectl version --request-timeout=5s >/dev/null 2>&1" \
          "is the cluster up? try: ./scripts/cluster-up.sh"
    check "capstone namespace exists" \
          "ns_exists $NS" \
          "run the full bring-up: ./scripts/bootstrap-capstone.sh"

    if want_act trace || want_act lineage || want_act topology; then
        check "Tempo Ready" \
              "ready_by_label $OBS_NS 'app.kubernetes.io/name=tempo'" \
              "./scripts/setup-observability.sh   (or: kubectl get pods -n $OBS_NS -l app.kubernetes.io/name=tempo)"
    fi
    if want_act trace || want_act canary || want_act topology; then
        check "Prometheus Ready" \
              "ready_by_label $OBS_NS 'app.kubernetes.io/name=prometheus'" \
              "./scripts/setup-observability.sh"
    fi
    if want_act canary || want_act topology; then
        check "Istio control plane Ready" \
              "ready_by_label $ISTIO_SYSTEM 'app=istiod'" \
              "./scripts/setup-istio.sh"
    fi
    if want_act scale; then
        check "KEDA Ready" \
              "ready_by_label keda 'app=keda-operator'" \
              "./scripts/setup-keda.sh"
    fi
    if want_act lineage; then
        check "OpenMetadata server Ready" \
              "ready_by_label openmetadata 'app.kubernetes.io/name=openmetadata'" \
              "./scripts/setup-openmetadata.sh"
        check "OpenMetadata ingestion has run (catalog populated)" \
              "kubectl get job -n $NS om-ingest-postgres om-ingest-kafka om-declare-lineage --no-headers 2>/dev/null | wc -l | grep -q '^3$'" \
              "./scripts/ingest-openmetadata.sh   (or re-run bootstrap-capstone.sh, which now does this)"
    fi
    if want_act topology; then
        check "Kiali Ready (CAP-042)" \
              "ready_by_label $ISTIO_SYSTEM 'app.kubernetes.io/name=kiali'" \
              "./scripts/setup-kiali.sh   (or re-run bootstrap-capstone.sh, which now does this)"
    fi

    if (( fail > 0 )); then
        printf '\n%s  preflight found %d problem(s) — fix the items above, or pass --no-preflight to bypass.%s\n' "$RED" "$fail" "$RST"
        exit 1
    fi
    printf '  %sall preflight checks passed%s\n' "$GRN" "$RST"
}

# ─── Opening ─────────────────────────────────────────────────────────────────

clear 2>/dev/null || true
cat <<INTRO
${BOLD}${BLU}╔═══════════════════════════════════════════════════════════════════════╗
║              ${RST}${BOLD}Data Mesh on OpenShift — live walkthrough${RST}${BOLD}${BLU}                ║
╚═══════════════════════════════════════════════════════════════════════╝${RST}

  ${DIM}Five acts, one for each piece of the deck's "What you can see it do"
  slide. Each act is the corresponding demo script, with narration around it.
  Press Enter between acts to control the tempo.${RST}

  ${BOLD}1. trace${RST}      one GraphQL query, a trace fanning out across three products
  ${BOLD}2. scale${RST}      KEDA scales notification-service on Kafka lag (down to zero)
  ${BOLD}3. canary${RST}     order-service v1→v2 contract evolution, weight-shifted live
  ${BOLD}4. lineage${RST}    OpenMetadata shows the cross-product lineage of the spine
  ${BOLD}5. topology${RST}   Kiali shows the live mesh graph with the canary split

INTRO

(( PREFLIGHT == 1 )) && preflight
prompt_enter "press Enter to start"

# ─── ACT 1 · TRACE ───────────────────────────────────────────────────────────

if want_act trace; then
    act_header "trace" "Trace across products" \
      "One GraphQL query at the gateway becomes a trace with spans in three products. The mesh's interesting behavior lives BETWEEN products — this is what makes it legible."
    narrate "we drive a single query through graphql-gateway"
    narrate "the resolver makes a REST call to order-service and a gRPC call to inventory-service"
    narrate "all three spans land in Tempo, stitched by a shared trace id"
    info "underlying script: demos/smoke-trace-flow.sh"
    prompt_enter "press Enter to run"
    run_act "trace" ./demos/smoke-trace-flow.sh || exit 1
    narrate "what to point at next: open Grafana → Explore → Tempo, paste the trace id"
    narrate "you'll see the span tree — HTTP server → REST client → gRPC client — across products"
fi

# ─── ACT 2 · SCALE ───────────────────────────────────────────────────────────

if want_act scale; then
    act_header "scale" "Elastic data product — KEDA on Kafka lag" \
      "An event consumer's real demand is the backlog waiting for it. KEDA scales notification-service on lag, including all the way down to zero when idle."
    narrate "at rest, notification-service is at zero replicas — it costs nothing"
    narrate "we publish a burst on order-placed; lag rises; KEDA wakes replicas"
    narrate "as the backlog drains, KEDA scales it back down to zero"
    info "underlying script: demos/smoke-keda-kafka.sh"
    prompt_enter "press Enter to run"
    run_act "scale" ./demos/smoke-keda-kafka.sh || exit 1
    narrate "the lesson: scale on the work WAITING, not the work being done"
    narrate "a consumer pegged at 0% CPU with a 10k backlog needs to scale UP — lag sees that, CPU can't"
fi

# ─── ACT 3 · CANARY ──────────────────────────────────────────────────────────

if want_act canary; then
    act_header "canary" "Canary a contract — v1 → v2, by weight" \
      "The interesting thing to canary in a mesh isn't a new binary, it's a new version of the CONTRACT. v2 adds the additive currency field; Istio shifts live traffic by weight; rollback is the same operation in reverse."
    narrate "step 1 — bring up the canary at 90/10 (v2 gets 10% of traffic)"
    info "underlying script: demos/demo-canary.sh up 90 10"
    prompt_enter "press Enter to bring up 90/10"
    run_act "canary up 90/10" ./demos/demo-canary.sh up 90 10 || exit 1

    narrate "step 2 — shift to 50/50 (no flag-day; the same VirtualService, two numbers changed)"
    info "underlying script: demos/demo-canary.sh shift 50 50"
    prompt_enter "press Enter to shift to 50/50"
    run_act "canary shift 50/50" ./demos/demo-canary.sh shift 50 50 || exit 1

    narrate "step 3 — clean rollback to v1-only (the same mechanism in reverse)"
    info "underlying script: demos/demo-canary.sh down"
    prompt_enter "press Enter to roll back to v1-only"
    run_act "canary down" ./demos/demo-canary.sh down || exit 1

    narrate "the mesh did the traffic-splitting; the application did not change"
    narrate "this is progressive delivery as a platform property, not application code"
fi

# ─── ACT 4 · LINEAGE ─────────────────────────────────────────────────────────

if want_act lineage; then
    act_header "lineage" "Cross-product lineage in OpenMetadata" \
      "A mesh's whole premise is consumers finding products without a broker. The catalog answers which products exist, who owns them, who consumes whom, and where data came from."
    narrate "we don't run ingestion here — we verify the lineage that was declared"
    narrate "the spine: orders (Postgres) → order-placed topic (Kafka) → notification consumer"
    info "underlying script: demos/smoke-om-lineage.sh"
    prompt_enter "press Enter to verify the lineage"
    run_act "lineage" ./demos/smoke-om-lineage.sh || exit 1
    narrate "what to show in the UI: OpenMetadata → orders table → Lineage tab"
    narrate "the graph runs operational → event → consumer — across three products"
fi

# ─── ACT 5 · TOPOLOGY ────────────────────────────────────────────────────────

if want_act topology; then
    act_header "topology" "Live mesh topology in Kiali" \
      "Kiali's traffic graph is the live view of the mesh: products, the edges between them, and — if the canary is up — the split rendered as parallel paths."
    narrate "first, confirm Kiali itself is healthy and sees the capstone namespace"
    info "underlying script: demos/smoke-kiali.sh"
    prompt_enter "press Enter to verify Kiali"
    run_act "topology (smoke)" ./demos/smoke-kiali.sh || exit 1

    narrate "now opening a port-forward to Kiali for you to show in the browser"
    info "  http://localhost:20001/kiali   (Graph → namespace: capstone)"
    info "  the port-forward stays open until this script exits (Ctrl-C or end of walkthrough)"
    # background port-forward; cleanup trap kills it on any exit
    kubectl port-forward -n "$ISTIO_SYSTEM" svc/kiali 20001:20001 >/dev/null 2>&1 &
    KIALI_PF=$!
    # give it a couple seconds to bind, then probe
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if curl -fsS http://127.0.0.1:20001/kiali/healthz >/dev/null 2>&1; then
            printf '%s    ✓ Kiali port-forward live at http://localhost:20001/kiali%s\n' "$GRN" "$RST"
            break
        fi
        sleep 1
    done

    narrate "to make EDGES appear in the graph, generate some traffic:"
    info "  in another shell:  for i in {1..40}; do ./demos/smoke-trace-flow.sh >/dev/null; done"
    info "  or re-run a canary act (./demos/demo-canary.sh up 90 10) and watch the split appear"
    narrate "Kiali draws the picture; the mesh and Prometheus did the measuring"
fi

# ─── Close ───────────────────────────────────────────────────────────────────

printf '\n%s%s═══════════════════════════════════════════════════════════════════════%s\n' "$BOLD" "$GRN" "$RST"
printf '%s%s  walkthrough complete  ·  %d / %d acts run%s\n' "$BOLD" "$GRN" "$ACT_NUM" "$ACT_TOTAL" "$RST"
printf '%s%s═══════════════════════════════════════════════════════════════════════%s\n\n' "$BOLD" "$GRN" "$RST"

if want_act topology && [[ -n "$KIALI_PF" ]] && kill -0 "$KIALI_PF" 2>/dev/null; then
    printf '%s  Kiali port-forward is still up (pid %s) — http://localhost:20001/kiali%s\n' "$DIM" "$KIALI_PF" "$RST"
    printf '%s  press Enter to tear it down and exit, or Ctrl-C to keep the script alive until you do%s\n\n' "$DIM" "$RST"
    prompt_enter "press Enter to exit"
fi
