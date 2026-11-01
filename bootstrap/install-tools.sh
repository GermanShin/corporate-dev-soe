#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# BUILD-TIME ONLY. Installs OS packages, AWS CLI v2 and the developer user.
# Called from the Dockerfile; never runs when a developer starts a container.
# -----------------------------------------------------------------------------
set -euo pipefail

USERNAME="${USERNAME:-dev}"
USER_UID="${USER_UID:-1000}"
USER_GID="${USER_GID:-1000}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing OS packages"
packages=$(grep -vE '^\s*(#|$)' "${HERE}/apt-packages.txt" | tr '\n' ' ')
apt-get update
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends ${packages}
rm -rf /var/lib/apt/lists/*

echo "==> Installing AWS CLI v2"
case "$(uname -m)" in
  x86_64)  aws_arch="x86_64" ;;
  aarch64) aws_arch="aarch64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
tmp="$(mktemp -d)"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "${tmp}/awscliv2.zip"
unzip -q "${tmp}/awscliv2.zip" -d "${tmp}"
"${tmp}/aws/install"
rm -rf "${tmp}"

echo "==> Creating developer user '${USERNAME}' (${USER_UID}:${USER_GID})"
# Ubuntu 24.04 ships a default 'ubuntu' user on UID 1000 - remove it.
if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || userdel ubuntu; fi
getent group "${USER_GID}" >/dev/null || groupadd --gid "${USER_GID}" "${USERNAME}"
useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}"

# Directories that become volumes must exist (and be owned by the user) in the
# image, so Docker initialises new named volumes with the right ownership.
install -d -o "${USER_UID}" -g "${USER_GID}" \
  "/home/${USERNAME}/.claude" "/home/${USERNAME}/.aws" "/home/${USERNAME}/.local/bin" /workspace
# install -d only sets ownership on the leaf, so parents it created (.local) are root-owned.
chown "${USER_UID}:${USER_GID}" "/home/${USERNAME}/.local"

echo "==> System git defaults"
git config --system --add safe.directory /workspace
git config --system init.defaultBranch main
git config --system pull.rebase false

echo "==> Shell prompt"
cat >> "/home/${USERNAME}/.bashrc" <<'EOF'

# --- Corporate SOE ---
export PS1='\[\e[1;36m\][soe $(cat /opt/corporate-soe/VERSION)]\[\e[0m\] \w \$ '
alias ll='ls -alF'
EOF
chown "${USER_UID}:${USER_GID}" "/home/${USERNAME}/.bashrc"

echo "==> install-tools.sh complete"
