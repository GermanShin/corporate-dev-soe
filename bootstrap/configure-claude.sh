#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Seeds corporate Claude Code skills and agents into the developer's persistent
# config volume WITHOUT touching anything the developer created themselves.
#
#   - Corporate items shipped in this image are (re)installed / updated.
#   - Corporate items removed from a newer image are removed from the volume.
#   - Developer-owned skills/agents are never modified.
#
# Corporate policy (managed-settings.json and CLAUDE.md) is NOT copied - it is
# read directly from /etc/claude-code and cannot be overridden.
# -----------------------------------------------------------------------------
set -euo pipefail

SRC=/opt/corporate-soe/claude
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

sync_dir() {
  local kind="$1"                       # skills | agents
  local src="${SRC}/${kind}" dst="${CFG}/${kind}"
  local manifest="${CFG}/.soe-managed-${kind}"
  mkdir -p "${dst}"
  touch "${manifest}"

  # Remove corporate items that are no longer shipped.
  while IFS= read -r old; do
    [[ -z "${old}" ]] && continue
    if [[ ! -e "${src}/${old}" ]]; then
      rm -rf -- "${dst:?}/${old}"
      echo "  - removed retired ${kind%s}: ${old}"
    fi
  done < "${manifest}"

  # Install / update shipped items.
  : > "${manifest}.new"
  if [[ -d "${src}" ]]; then
    for item in "${src}"/*; do
      [[ -e "${item}" ]] || continue
      name="$(basename "${item}")"
      rm -rf -- "${dst:?}/${name}"
      cp -R "${item}" "${dst}/${name}"
      echo "${name}" >> "${manifest}.new"
      echo "  + ${kind%s}: ${name}"
    done
  fi
  mv "${manifest}.new" "${manifest}"
}

echo "Configuring Claude Code..."
sync_dir skills
sync_dir agents

# Developer-level settings file is created once and then belongs to the developer.
if [[ ! -f "${CFG}/settings.json" ]]; then
  cat > "${CFG}/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json"
}
EOF
fi
