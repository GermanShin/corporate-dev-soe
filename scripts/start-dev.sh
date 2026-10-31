#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Corporate SOE launcher for macOS (works on Linux too).
# Compatible with the macOS system bash 3.2.
#
# Install once:   sudo install -m 0755 scripts/start-dev.sh /usr/local/bin/soe
# Use:            cd ~/code/my-project && soe
#
#   soe                 open a shell in the SOE for the current folder
#   soe claude          start Claude Code directly
#   soe --doctor        run the health check
#   soe --firewall      start with the egress allowlist enabled
#   soe --local         use a locally built image (corporate-dev-soe:local)
#   soe --no-pull       don't check ECR for a newer image
#   soe --reset         delete your persistent Claude config volume
#   soe -- <cmd...>     run any command inside the SOE
# -----------------------------------------------------------------------------
set -euo pipefail

CONFIG_FILE="${SOE_CONFIG_FILE:-$HOME/.config/corporate-soe/soe.env}"
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SOE_REGISTRY="${SOE_REGISTRY:-}"
SOE_REPOSITORY="${SOE_REPOSITORY:-corporate-dev-soe}"
SOE_TAG="${SOE_TAG:-stable}"
SOE_AWS_PROFILE="${SOE_AWS_PROFILE:-${AWS_PROFILE:-}}"
SOE_AWS_REGION="${SOE_AWS_REGION:-${AWS_REGION:-ap-southeast-2}}"
SOE_MODEL_PROVIDER="${SOE_MODEL_PROVIDER:-bedrock}"
SOE_FIREWALL="${SOE_FIREWALL:-0}"
SOE_FORWARD_SSH="${SOE_FORWARD_SSH:-1}"
SOE_EXTRA_DOMAINS="${SOE_EXTRA_DOMAINS:-}"
CONFIG_VOLUME="soe-claude-config"

use_local=0; do_pull=1; cmd=()

die()  { echo "soe: $*" >&2; exit 1; }
info() { echo "soe: $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --local)    use_local=1; do_pull=0 ;;
    --no-pull)  do_pull=0 ;;
    --firewall) SOE_FIREWALL=1 ;;
    --doctor)   cmd=(soe-doctor) ;;
    --reset)
      printf 'Delete your Claude login, settings and personal skills (volume %s)? [y/N] ' "$CONFIG_VOLUME"
      read -r ans
      [ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 0
      docker volume rm "$CONFIG_VOLUME" && info "volume removed"
      exit 0 ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    --)         shift; cmd=("$@"); break ;;
    *)          cmd=("$@"); break ;;
  esac
  shift
done
[ ${#cmd[@]} -eq 0 ] && cmd=(bash -l)

# --- Pre-flight -------------------------------------------------------------
command -v docker >/dev/null || die "Docker is not installed. Install Docker Desktop first."
docker info >/dev/null 2>&1    || die "Docker is not running. Start Docker Desktop and try again."

if [ "$use_local" -eq 1 ]; then
  IMAGE="corporate-dev-soe:local"
else
  [ -n "$SOE_REGISTRY" ] || die "SOE_REGISTRY is not set. Copy config/soe.env.example to $CONFIG_FILE"
  IMAGE="${SOE_REGISTRY}/${SOE_REPOSITORY}:${SOE_TAG}"
fi

aws_args=()
[ -n "$SOE_AWS_PROFILE" ] && aws_args=(--profile "$SOE_AWS_PROFILE")

# --- Pull the approved image from ECR ---------------------------------------
if [ "$do_pull" -eq 1 ]; then
  command -v aws >/dev/null || die "AWS CLI not found. Install it with: brew install awscli"
  if ! aws sts get-caller-identity ${aws_args[@]+"${aws_args[@]}"} >/dev/null 2>&1; then
    info "AWS session expired - signing in..."
    aws sso login ${aws_args[@]+"${aws_args[@]}"} || die "AWS sign-in failed."
  fi
  info "checking ECR for ${IMAGE}"
  aws ecr get-login-password --region "$SOE_AWS_REGION" ${aws_args[@]+"${aws_args[@]}"} \
    | docker login --username AWS --password-stdin "$SOE_REGISTRY" >/dev/null \
    || die "ECR login failed. Check SOE_REGISTRY and your AWS permissions."
  if ! docker pull --quiet "$IMAGE" >/dev/null; then
    docker image inspect "$IMAGE" >/dev/null 2>&1 \
      && info "pull failed - using the copy already on this Mac" \
      || die "could not pull ${IMAGE}"
  fi
fi
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image ${IMAGE} not found locally."

# --- One container per project folder ---------------------------------------
project="$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_.-]/-/g')"
name="soe-${project}"

if [ -n "$(docker ps -q --filter "name=^/${name}$")" ]; then
  info "attaching to running SOE for '${project}'"
  exec docker exec -it -u dev "$name" /opt/corporate-soe/bootstrap/entrypoint.sh "${cmd[@]}"
fi

run_args=(
  run -it --rm --init
  --name "$name"
  --hostname soe
  -v "$PWD:/workspace"
  -v "${CONFIG_VOLUME}:/home/dev/.claude"
  -w /workspace
  -e TERM -e COLORTERM
  -e "AWS_REGION=${SOE_AWS_REGION}"
)

# AWS credentials: mount ~/.aws so SSO tokens refresh in one place.
if [ -d "$HOME/.aws" ]; then
  run_args+=(-v "$HOME/.aws:/home/dev/.aws")
  [ -n "$SOE_AWS_PROFILE" ] && run_args+=(-e "AWS_PROFILE=${SOE_AWS_PROFILE}")
fi

# Model provider
case "$SOE_MODEL_PROVIDER" in
  bedrock)
    run_args+=(-e CLAUDE_CODE_USE_BEDROCK=1)
    [ -n "${SOE_ANTHROPIC_MODEL:-}" ] && run_args+=(-e "ANTHROPIC_MODEL=${SOE_ANTHROPIC_MODEL}")
    ;;
  anthropic)
    [ -n "${ANTHROPIC_API_KEY:-}" ] && run_args+=(-e ANTHROPIC_API_KEY)
    ;;
  *) die "SOE_MODEL_PROVIDER must be 'bedrock' or 'anthropic'" ;;
esac

# Git identity from the Mac
gname="$(git config --global user.name 2>/dev/null || true)"
gmail="$(git config --global user.email 2>/dev/null || true)"
[ -n "$gname" ] && run_args+=(-e "GIT_AUTHOR_NAME=$gname" -e "GIT_COMMITTER_NAME=$gname")
[ -n "$gmail" ] && run_args+=(-e "GIT_AUTHOR_EMAIL=$gmail" -e "GIT_COMMITTER_EMAIL=$gmail")

# SSH agent forwarding (Docker Desktop for Mac magic socket)
if [ "$SOE_FORWARD_SSH" = "1" ] && [ -n "${SSH_AUTH_SOCK:-}" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    run_args+=(-v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock
               -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock)
  else
    run_args+=(-v "$SSH_AUTH_SOCK:/run/ssh-agent.sock" -e SSH_AUTH_SOCK=/run/ssh-agent.sock)
  fi
fi

# Egress firewall
if [ "$SOE_FIREWALL" = "1" ]; then
  run_args+=(--cap-add=NET_ADMIN --cap-add=NET_RAW -e SOE_FIREWALL=1)
  [ -n "$SOE_EXTRA_DOMAINS" ] && run_args+=(-e "SOE_EXTRA_DOMAINS=${SOE_EXTRA_DOMAINS}")
fi

info "starting ${IMAGE} for '${project}'"
exec docker "${run_args[@]}" "$IMAGE" "${cmd[@]}"
