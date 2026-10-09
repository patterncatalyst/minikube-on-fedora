#!/usr/bin/env bash
# Shared environment for the §17 capstone scripts and demos. Source it; do not
# execute it. Sets the profile, namespace, the published-NodePort map and the
# host/node port variables, and pins kubectl/helm/istioctl to the profile's
# context so a changed current-context can never redirect a script.
#
# The profile is "mof-capstone", NOT "capstone": the name "capstone" belongs to
# another repository's cluster on the same host. The namespace stays "capstone".
#
# scripts/check-port-map.sh cross-checks CAPSTONE_PORTS against the YAML and docs.

_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../scripts/lib/_helpers.sh
source "$_ENV_DIR/../../../../scripts/lib/_helpers.sh"

PROFILE="mof-capstone"
NS="capstone"

# Published at profile creation: 127.0.0.1:<host>:<nodePort>[,...]
CAPSTONE_PORTS="127.0.0.1:18080:30180,127.0.0.1:18082:30182,127.0.0.1:18083:30183,127.0.0.1:18084:30184,127.0.0.1:18085:30185,127.0.0.1:18086:30186,127.0.0.1:18097:30197,127.0.0.1:18099:30199,127.0.0.1:8585:30585,127.0.0.1:5432:30432,127.0.0.1:8080:30880,127.0.0.1:8081:30881,127.0.0.1:20001:30201,127.0.0.1:9090:30090,127.0.0.1:3000:30300,127.0.0.1:3200:30320,127.0.0.1:4318:30418"

# Host port (127.0.0.1) and node port for each published Service.
HOST_PORT_ORDER=18080
HOST_PORT_INVENTORY=18082
HOST_PORT_PAYMENT=18083
HOST_PORT_SHIPPING=18084
HOST_PORT_APICURIO=18085
HOST_PORT_REVIEW=18086
HOST_PORT_NOTIFICATION=18097
HOST_PORT_GATEWAY=18099
HOST_PORT_OPENMETADATA=8585
HOST_PORT_POSTGRES=5432
HOST_PORT_INGRESS=8080
HOST_PORT_INTERCEPTOR=8081
HOST_PORT_KIALI=20001
HOST_PORT_PROMETHEUS=9090
HOST_PORT_GRAFANA=3000
HOST_PORT_TEMPO=3200
HOST_PORT_TEMPO_OTLP=4318

NODE_PORT_ORDER=30180
NODE_PORT_INVENTORY=30182
NODE_PORT_PAYMENT=30183
NODE_PORT_SHIPPING=30184
NODE_PORT_APICURIO=30185
NODE_PORT_REVIEW=30186
NODE_PORT_NOTIFICATION=30197
NODE_PORT_GATEWAY=30199
NODE_PORT_OPENMETADATA=30585
NODE_PORT_POSTGRES=30432
NODE_PORT_INGRESS=30880
NODE_PORT_INTERCEPTOR=30881
NODE_PORT_KIALI=30201
NODE_PORT_PROMETHEUS=30090
NODE_PORT_GRAFANA=30300
NODE_PORT_TEMPO=30320
NODE_PORT_TEMPO_OTLP=30418

pin_context "$PROFILE"
