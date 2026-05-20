#!/usr/bin/env bash
# test-r21.sh — cluster verification for r21 (no git, no merges).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/examples/17-capstone"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Ensure capstone profile is running"
minikube status -p capstone >/dev/null 2>&1 || ./scripts/setup-capstone-profile.sh

step "Ensure kubectl context is capstone"
kubectl config use-context capstone

step "Ensure CloudNativePG operator is installed"
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || ./scripts/setup-postgres-operator.sh

step "Run the order-service walking-skeleton smoke test"
./demos/smoke-order.sh

printf '\n\033[1m==> test-r21 complete\033[0m\n'
