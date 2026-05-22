#!/usr/bin/env bash
#
# debug-ephemeral.sh — demonstrate the Ephemeral Container counterpart to the
# migration init container (see §17, "Schema migrations, and two kinds of
# temporary container").
#
# The init container runs ONCE, BEFORE the app (alembic upgrade head). An
# ephemeral container is attached on demand to a pod that is ALREADY RUNNING,
# via `kubectl debug`. Our runtime images are minimal (the venv and nothing
# else — no curl, no psql), so to inspect a live pod we attach a throwaway
# container that carries the tools, rather than baking them into the image.
#
# This runs two non-interactive probes against a running notification-service
# pod and prints what each ephemeral container saw:
#   1. network-shared: curl the app's own /received from inside the pod
#   2. process-shared (--target): list the running processes in the app container
#
# Ephemeral containers cannot be removed (they live with the pod), so each run
# uses a unique container name. Re-running is safe; it just adds another.
#
# Prereqs: a running capstone cluster with notification-service deployed
# (e.g. after ./demos/smoke-notifications.sh, or deploy it first).
#
# Usage:  ./demos/debug-ephemeral.sh

set -uo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

NS="capstone"
APP="notification-service"
DEBUG_IMAGE="registry.access.redhat.com/ubi9/ubi"   # has curl + ps; any tool image works
STAMP="$(date +%s)"

step() { printf '\n==> %s\n' "$1"; }
die()  { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

command -v kubectl >/dev/null || die "kubectl not found"

POD="$(kubectl get pods -n "$NS" -l "app.kubernetes.io/name=${APP}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
[[ -n "$POD" ]] || die "no running ${APP} pod in namespace ${NS} — deploy it first (e.g. ./demos/smoke-notifications.sh)"
printf 'Target pod: %s\n' "$POD"

# Run an ephemeral container non-interactively and print its logs once it ends.
# $1 = container name, $2.. = extra kubectl debug flags + command (terminated by --)
run_probe() {
    local cname="$1"; shift
    # kubectl debug (without -it) adds the ephemeral container and returns; the
    # container runs the command and terminates. We then poll for termination
    # and print its logs.
    kubectl debug -n "$NS" "$POD" -c "$cname" --image="$DEBUG_IMAGE" "$@" >/dev/null 2>&1 \
        || die "kubectl debug failed to add ephemeral container ${cname} (is the EphemeralContainers feature enabled? it is by default on k8s >=1.25)"
    local reason="" code=""
    for _ in $(seq 1 30); do
        reason="$(kubectl get pod -n "$NS" "$POD" \
            -o jsonpath="{.status.ephemeralContainerStatuses[?(@.name=='${cname}')].state.terminated.reason}" 2>/dev/null)"
        [[ -n "$reason" ]] && break
        sleep 2
    done
    # Surface logs (do NOT suppress stderr — a missing tool must be visible).
    local out
    out="$(kubectl logs -n "$NS" "$POD" -c "$cname" 2>&1)"
    if [[ -z "$out" ]]; then
        code="$(kubectl get pod -n "$NS" "$POD" \
            -o jsonpath="{.status.ephemeralContainerStatuses[?(@.name=='${cname}')].state.terminated.exitCode}" 2>/dev/null)"
        out="<no output — container terminated reason=${reason:-?} exitCode=${code:-?}>"
    fi
    printf '%s' "$out"
}

step "Probe 1 — network namespace shared: curl the app's /received from inside the pod"
echo "    (the app container has no curl; the ephemeral container provides it)"
echo "    \$ kubectl debug $POD -c probe-net-$STAMP --image=$DEBUG_IMAGE -- curl -s http://localhost:8080/received"
OUT1="$(run_probe "probe-net-${STAMP}" -- curl -s http://localhost:8080/received)"
printf '    --- app /received (seen from the ephemeral container) ---\n'
printf '%s\n' "${OUT1:-<no output>}" | sed 's/^/    /'

step "Probe 2 — process namespace shared (--target): the app's processes via /proc"
echo "    (reads /proc directly — no 'ps' needed, and proves --target shares the app's PIDs)"
echo "    \$ kubectl debug $POD -c probe-proc-$STAMP --target=$APP --image=$DEBUG_IMAGE -- sh -c 'for p in /proc/[0-9]*; do printf \"%s %s\\n\" \"\${p#/proc/}\" \"\$(cat \$p/comm 2>/dev/null)\"; done'"
OUT2="$(run_probe "probe-proc-${STAMP}" --target="$APP" -- sh -c 'for p in /proc/[0-9]*; do printf "%s %s\n" "${p#/proc/}" "$(cat $p/comm 2>/dev/null)"; done')"
printf '    --- PID COMM in the shared process namespace (uvicorn/python should appear) ---\n'
printf '%s\n' "${OUT2:-<no output>}" | sed 's/^/    /'

step "Done"
cat <<EOF
Two ephemeral containers were attached to the running pod and have now
terminated. They remain listed in the pod's ephemeralContainerStatuses (they
can't be removed) but consume nothing. Inspect them with:

  kubectl get pod -n $NS $POD -o jsonpath='{range .status.ephemeralContainerStatuses[*]}{.name}{"\n"}{end}'

Init container (before start, one-shot setup) vs ephemeral container (mid-flight,
on-demand debugging): the two temporary-container bookends of a pod's life.
EOF
