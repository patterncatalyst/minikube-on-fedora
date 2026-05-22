#!/usr/bin/env bash
#
# setup-kafka-operator.sh — install the Strimzi Kafka operator into the
# capstone namespace via Helm (the operator pattern, same as CloudNativePG
# in CAP-002). Pinned to a specific Strimzi version for reproducibility.
#
# Strimzi runs Kafka in KRaft mode (no ZooKeeper) since 0.46; the cluster CR
# is deployed separately by the kafka subchart. Strimzi 0.51 requires
# Kubernetes 1.30+.
#
# Idempotent: re-running upgrades the operator in place.

set -euo pipefail
export MINIKUBE_ROOTLESS=true   # CAP-010

NS="capstone"
STRIMZI_VERSION="0.51.0"

step() { printf '\n==> %s\n' "$1"; }

step "Installing the Strimzi cluster operator ${STRIMZI_VERSION} into '${NS}' (Helm)"
helm upgrade --install strimzi-cluster-operator \
    oci://quay.io/strimzi-helm/strimzi-kafka-operator \
    --version "$STRIMZI_VERSION" \
    --namespace "$NS" --create-namespace

step "Waiting for the operator to be Available"
kubectl rollout status deployment/strimzi-cluster-operator -n "$NS" --timeout=180s \
    || kubectl wait --for=condition=Available deployment -n "$NS" \
         -l strimzi.io/kind=cluster-operator --timeout=180s

step "Strimzi operator ready"
kubectl get crd | grep -i kafka.strimzi.io | head
