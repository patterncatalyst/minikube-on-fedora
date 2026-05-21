#!/usr/bin/env bash
#
# gen-protos.sh — generate Python gRPC stubs from proto/ and copy them into
# each service that needs them (option b: per-service committed copies).
#
# Run this ONCE whenever the protos change, then commit the regenerated
# stubs alongside the proto change. The stubs are committed so the service
# images build without buf/protoc inside them (CAP-013) and builds stay
# reproducible (CAP-001).
#
# Generator: prefers `buf` (CAP-R19-4). Falls back to `python -m
# grpc_tools.protoc` if buf isn't installed. buf's remote plugins need
# network at generation time; the grpc_tools path works fully offline.
#
# Usage:  ./scripts/gen-protos.sh
#
# Which services get the stubs: inventory-service (implements the server),
# order-service (calls it as a client). Both get identical generated files;
# the _pb2_grpc.py contains both the Servicer and the Stub.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STAGING=".gen-staging"
SERVICES=(inventory-service order-service)

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

[[ -d proto ]] || fail "proto/ not found (run from examples/17-capstone via scripts/)"

rm -rf "$STAGING"
mkdir -p "$STAGING"

step "Generating Python stubs"
PROTO_FILE="$ROOT/proto/capstone/inventory/v1/inventory.proto"
OUT="$ROOT/$STAGING"
if command -v buf >/dev/null 2>&1; then
    printf '    using buf\n'
    buf generate || fail "buf generate failed"
elif python3 -c "import grpc_tools" >/dev/null 2>&1; then
    printf '    buf not found — using python -m grpc_tools.protoc (system/active venv)\n'
    python3 -m grpc_tools.protoc \
        -I"$ROOT/proto" --python_out="$OUT" --grpc_python_out="$OUT" "$PROTO_FILE" \
        || fail "grpc_tools.protoc failed"
elif command -v poetry >/dev/null 2>&1 \
        && ( cd services/inventory-service && poetry run python -c "import grpc_tools" ) >/dev/null 2>&1; then
    printf '    using grpc_tools from inventory-service'\''s Poetry venv (dev dependency)\n'
    ( cd services/inventory-service && poetry run python -m grpc_tools.protoc \
        -I"$ROOT/proto" --python_out="$OUT" --grpc_python_out="$OUT" "$PROTO_FILE" ) \
        || fail "poetry-run grpc_tools.protoc failed"
else
    fail "no protobuf generator found. Any one of these works:
      - buf:           https://buf.build/docs/installation
      - Poetry venv:   run 'poetry install' in services/inventory-service first
                       (grpcio-tools is already a dev dependency), then re-run this
      - throwaway venv: python3 -m venv /tmp/protogen && /tmp/protogen/bin/pip install grpcio-tools
                        && source /tmp/protogen/bin/activate && ./scripts/gen-protos.sh
      - dnf:           sudo dnf install pipx && pipx install grpcio-tools"
fi

[[ -d "$STAGING/capstone" ]] || fail "generation produced no capstone/ package in $STAGING"

step "Distributing stubs to services: ${SERVICES[*]}"
for svc in "${SERVICES[@]}"; do
    dest="services/${svc}/gen"
    [[ -d "services/${svc}" ]] || fail "service dir services/${svc} not found"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -r "$STAGING/capstone" "$dest/capstone"
    # Add __init__.py at each package level so the tree is importable even
    # without relying on implicit namespace packages.
    find "$dest" -type d -exec sh -c 'touch "$1/__init__.py"' _ {} \;
    printf '    ✓ %s\n' "$dest/capstone/inventory/v1/"
done

rm -rf "$STAGING"

step "Done"
cat <<EOF

Stubs written to:
  services/inventory-service/gen/capstone/inventory/v1/
  services/order-service/gen/capstone/inventory/v1/

Each contains inventory_pb2.py (messages) and inventory_pb2_grpc.py
(InventoryServiceServicer for the server, InventoryServiceStub for the client).

Commit these alongside the proto. Next:
  - regenerate lockfiles (grpc deps were added):
      (cd services/inventory-service && poetry lock)
      (cd services/order-service && poetry lock)
  - run the demo:
      ./demos/smoke-grpc.sh
EOF
