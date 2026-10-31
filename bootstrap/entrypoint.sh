#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Container entrypoint.
#   Phase 1 (root):  optional egress firewall, fix volume ownership, drop privileges.
#   Phase 2 (dev):   run the idempotent bootstrap, then exec the requested command.
# -----------------------------------------------------------------------------
set -euo pipefail

SOE_HOME=/opt/corporate-soe
SOE_USER="${SOE_USER:-dev}"

if [[ "$(id -u)" -eq 0 ]]; then
  if [[ "${SOE_FIREWALL:-0}" == "1" ]]; then
    "${SOE_HOME}/bootstrap/configure-network.sh"
  fi

  # A volume created by an older Docker or a bind mount may arrive root-owned.
  user_home="/home/${SOE_USER}"
  for d in "${user_home}/.claude" "${user_home}/.aws"; do
    if [[ -d "$d" && "$(stat -c %u "$d")" == "0" ]]; then
      chown "${SOE_USER}:${SOE_USER}" "$d" 2>/dev/null || true
    fi
  done

  # Forwarded SSH agent socket (Docker Desktop) must be usable by the dev user.
  if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    chmod a+rw "${SSH_AUTH_SOCK}" 2>/dev/null || true
  fi

  export HOME="${user_home}" USER="${SOE_USER}" LOGNAME="${SOE_USER}"
  exec setpriv --reuid="${SOE_USER}" --regid="${SOE_USER}" --init-groups \
       --no-new-privs "$0" "$@"
fi

# ---- running as the developer user from here on ----
"${SOE_HOME}/bootstrap/bootstrap.sh"

exec "$@"
