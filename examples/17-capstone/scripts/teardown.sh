#!/usr/bin/env bash
#
# teardown.sh — stop the capstone minikube profile (and optionally delete it).
#
# Usage:
#   ./teardown.sh                     # stop only (preserves state)
#   ./teardown.sh --remove-profile    # delete the profile entirely

set -euo pipefail

PROFILE_NAME="capstone"

REMOVE=0
if [[ "${1:-}" == "--remove-profile" ]]; then
    REMOVE=1
fi

if ! minikube status -p "$PROFILE_NAME" >/dev/null 2>&1; then
    printf '==> Profile %s is not present. Nothing to do.\n' "$PROFILE_NAME"
    exit 0
fi

printf '==> Stopping %s profile\n' "$PROFILE_NAME"
minikube stop -p "$PROFILE_NAME"

if (( REMOVE )); then
    printf '==> Deleting %s profile (--remove-profile specified)\n' "$PROFILE_NAME"
    minikube delete -p "$PROFILE_NAME"
    printf '==> Profile deleted. To recreate: ./setup-capstone-profile.sh\n'
else
    printf '==> Profile stopped. To restart: minikube start -p %s\n' "$PROFILE_NAME"
    printf '==> To delete entirely: ./teardown.sh --remove-profile\n'
fi
