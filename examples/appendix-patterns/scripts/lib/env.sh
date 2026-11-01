#!/usr/bin/env bash
# Shared environment for the Kubernetes-patterns appendix examples. Source it; do
# not execute it. Sets the profile and namespace and pins kubectl/helm to the
# profile's context so a changed current-context can never redirect a script.
#
# The profile is "mof-patterns", deliberately separate from §3's `minikube`
# profile and §17's `mof-capstone`: the appendix examples are applied and torn
# down independently of the capstone, and must never share a cluster with it.
#
# Each pattern chapter's example lives in examples/appendix-patterns/<pattern>/
# and reuses this profile. Most examples reach a service with `kubectl
# port-forward` rather than a published NodePort, so no fixed port map lives here.

_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../scripts/lib/_helpers.sh
source "$_ENV_DIR/../../../../scripts/lib/_helpers.sh"

PROFILE="mof-patterns"
NS="patterns"

pin_context "$PROFILE"
