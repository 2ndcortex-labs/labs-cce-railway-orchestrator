#!/usr/bin/env bash
set -euo pipefail

export PATH="/workspace/.onboarding/bin:${HOME}/.local/bin:${PATH}"
RAILWAY_VERSION="${RAILWAY_VERSION:-4.3.0}"

if command -v railway >/dev/null 2>&1; then
  echo "railway CLI already installed: $(railway --version)"
  exit 0
fi

if [ -n "${RAILWAY_INSTALL_DIR:-}" ]; then
  INSTALL_DIR="${RAILWAY_INSTALL_DIR}"
elif [ -w "/usr/local/bin" ]; then
  INSTALL_DIR="/usr/local/bin"
elif [ -d "/workspace" ] && [ -w "/workspace" ]; then
  INSTALL_DIR="/workspace/.onboarding/bin"
else
  INSTALL_DIR="${HOME}/.local/bin"
fi
mkdir -p "${INSTALL_DIR}"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64)
    TARGET="x86_64-unknown-linux-musl"
    ;;
  aarch64|arm64)
    TARGET="aarch64-unknown-linux-musl"
    ;;
  *)
    echo "ERROR: Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

TARBALL="railway-v${RAILWAY_VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/railwayapp/cli/releases/download/v${RAILWAY_VERSION}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading Railway CLI v${RAILWAY_VERSION} (${TARGET})..."
curl -fsSL "${BASE_URL}/${TARBALL}" -o "${TMP_DIR}/${TARBALL}"

if [ -n "${RAILWAY_CLI_SHA256:-}" ]; then
  echo "${RAILWAY_CLI_SHA256}  ${TMP_DIR}/${TARBALL}" | sha256sum -c -
fi

tar -xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"
install -m 0755 "${TMP_DIR}/railway" "${INSTALL_DIR}/railway"
echo "Installed: $("${INSTALL_DIR}/railway" --version) to ${INSTALL_DIR}/railway"
