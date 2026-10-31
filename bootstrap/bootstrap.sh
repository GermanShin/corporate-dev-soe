#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Per-developer provisioning. Runs as the developer user on EVERY container
# start, but is idempotent: real work only happens on first run, after a new
# SOE version is pulled, or when SOE_FORCE_BOOTSTRAP=1.
#
# Never installs packages - those are baked into the image at build time.
# -----------------------------------------------------------------------------
set -euo pipefail

SOE_HOME=/opt/corporate-soe
SOE_VERSION="$(cat "${SOE_HOME}/VERSION")"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="${CFG}/.soe-provisioned-version"

if [[ ! -w "${CFG}" ]]; then
  mkdir -p "${CFG}" 2>/dev/null || {
    echo "ERROR: ${CFG} is not writable by $(id -un). Check the volume mount." >&2
    exit 1
  }
fi

current="$(cat "${STAMP}" 2>/dev/null || true)"

if [[ "${current}" == "${SOE_VERSION}" && "${SOE_FORCE_BOOTSTRAP:-0}" != "1" ]]; then
  echo "Corporate SOE ${SOE_VERSION} ready."
  exit 0
fi

if [[ -z "${current}" ]]; then
  echo "Initialising Corporate Development SOE ${SOE_VERSION} (first run)..."
else
  echo "Updating Corporate Development SOE ${current} -> ${SOE_VERSION}..."
fi

"${SOE_HOME}/bootstrap/configure-claude.sh"

echo "${SOE_VERSION}" > "${STAMP}"
echo "Corporate SOE ${SOE_VERSION} ready. Run 'soe-doctor' to check the environment."
