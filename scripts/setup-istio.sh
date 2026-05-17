#!/usr/bin/env bash
#
# scripts/setup-istio.sh
#
# One-time setup for §11. Idempotent — safe to re-run.
#
# What this does:
#   1. Downloads istio-1.29.2-linux-amd64.tar.gz from istio.io if
#      not already cached
#   2. Extracts to ~/.local/share/istio-1.29.2/
#   3. Installs istioctl to ~/.local/bin/istioctl (creates the
#      directory if needed)
#   4. Maintains a ~/.local/share/istio-current symlink to the
#      installed version so examples/11-istio/demo.sh can reference
#      a stable path
#   5. Warns if ~/.local/bin isn't in PATH
#
# What this does NOT do:
#   - Install Istio into a cluster (that's `istioctl install --set
#     profile=demo -y`, which the §11 demo does)
#   - Create the minikube istio profile (that's `minikube start -p
#     istio ...`, see §11 prose)
#
# To bump versions: change ISTIO_VERSION and re-run. The symlink
# moves; the older tarball stays unless you remove it.

set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.29.2}"
TARGET_ARCH="${TARGET_ARCH:-x86_64}"
INSTALL_PREFIX="${HOME}/.local"
ISTIO_BASE="${INSTALL_PREFIX}/share"
ISTIO_DIR="${ISTIO_BASE}/istio-${ISTIO_VERSION}"
ISTIO_CURRENT="${ISTIO_BASE}/istio-current"
BIN_DIR="${INSTALL_PREFIX}/bin"

# ── Color helpers ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; NC=''
fi

info()  { echo -e "  ${YELLOW}→${NC} $*"; }
pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*" >&2; exit 1; }
step()  { echo -e "${YELLOW}━━${NC} $*"; }

# ── Step 1: Working directories ─────────────────────────────────────────────
step "ensuring ~/.local/bin and ~/.local/share exist"
mkdir -p "${BIN_DIR}" "${ISTIO_BASE}"
pass "directories ready"

# ── Step 2: Download + extract Istio (skip if already done) ─────────────────
step "checking for istio-${ISTIO_VERSION} at ${ISTIO_DIR}"
if [[ -d "${ISTIO_DIR}" && -x "${ISTIO_DIR}/bin/istioctl" ]]; then
    pass "already present at ${ISTIO_DIR}"
else
    info "downloading via https://istio.io/downloadIstio (version ${ISTIO_VERSION})"
    cd "${ISTIO_BASE}"
    curl -fsSL https://istio.io/downloadIstio \
        | ISTIO_VERSION="${ISTIO_VERSION}" TARGET_ARCH="${TARGET_ARCH}" sh -
    if [[ ! -d "${ISTIO_DIR}" ]]; then
        fail "download did not produce ${ISTIO_DIR} — check stderr above"
    fi
    pass "extracted to ${ISTIO_DIR}"
fi

# ── Step 3: Install istioctl to ~/.local/bin ────────────────────────────────
step "installing istioctl to ${BIN_DIR}/istioctl"
install -m 0755 "${ISTIO_DIR}/bin/istioctl" "${BIN_DIR}/istioctl"
INSTALLED_VERSION=$("${BIN_DIR}/istioctl" version --remote=false 2>/dev/null | head -1 || echo "unknown")
pass "istioctl installed (${INSTALLED_VERSION})"

# ── Step 4: Maintain ~/.local/share/istio-current symlink ───────────────────
step "updating ${ISTIO_CURRENT} symlink"
ln -sfn "${ISTIO_DIR}" "${ISTIO_CURRENT}"
pass "${ISTIO_CURRENT} → istio-${ISTIO_VERSION}"

# ── Step 5: PATH sanity check ───────────────────────────────────────────────
step "checking that ${BIN_DIR} is in your PATH"
case ":${PATH}:" in
    *":${BIN_DIR}:"*)
        pass "${BIN_DIR} is on PATH"
        ;;
    *)
        info "${BIN_DIR} is NOT on your PATH"
        info "add this to ~/.zshrc (or ~/.bashrc):"
        echo
        echo "    export PATH=\"${BIN_DIR}:\$PATH\""
        echo
        info "then 'source ~/.zshrc' (or open a new terminal)"
        ;;
esac

# ── Done ────────────────────────────────────────────────────────────────────
echo
step "SUCCESS — Istio ${ISTIO_VERSION} ready"
echo
echo "  Binary:    ${BIN_DIR}/istioctl"
echo "  Samples:   ${ISTIO_CURRENT}/samples/"
echo
echo "  Next: start the istio minikube profile and install Istio into it:"
echo
echo "    minikube start -p istio --memory=6g --cpus=4 \\"
echo "        --container-runtime=containerd --rootless=true"
echo "    istioctl install --set profile=demo -y"
echo
echo "  Or run the full §11 demo end-to-end:"
echo
echo "    cd examples/11-istio && ./demo.sh"
echo
exit 0
