#!/usr/bin/env bash
# Health check for the SOE. Run inside the container: soe-doctor
set -uo pipefail

ok()   { printf '  \e[32m✔\e[0m %s\n' "$*"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*"; }
bad()  { printf '  \e[31m✘\e[0m %s\n' "$*"; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

echo "Corporate SOE doctor"
echo "--------------------"
ok "SOE version: $(cat /opt/corporate-soe/VERSION)"
ok "OS: $(. /etc/os-release && echo "${PRETTY_NAME}") ($(uname -m))"
ok "User: $(id -un) (uid $(id -u))"

if command -v claude >/dev/null; then ok "Claude Code: $(claude --version 2>/dev/null)"; else bad "Claude Code not on PATH"; fi
ok "AWS CLI: $(aws --version 2>&1 | cut -d' ' -f1)"
ok "git: $(git --version | cut -d' ' -f3)   python: $(python3 --version | cut -d' ' -f2)"

[[ -f /etc/claude-code/managed-settings.json ]] && ok "Managed policy present" || bad "Managed policy missing"
[[ -w "${CFG}" ]] && ok "Claude config dir writable: ${CFG}" || bad "Claude config dir NOT writable: ${CFG}"
ok "Corporate skills: $(tr '\n' ' ' < "${CFG}/.soe-managed-skills" 2>/dev/null)"
ok "Corporate agents: $(tr '\n' ' ' < "${CFG}/.soe-managed-agents" 2>/dev/null)"

if [[ -w /workspace ]]; then ok "/workspace writable"; else bad "/workspace not writable"; fi

echo
echo "Model provider"
if [[ "${CLAUDE_CODE_USE_BEDROCK:-}" == "1" ]]; then
  ok "Amazon Bedrock (region ${AWS_REGION:-<unset>}, profile ${AWS_PROFILE:-<default>})"
  if aws sts get-caller-identity --query Arn --output text >/tmp/.soe-id 2>/dev/null; then
    ok "AWS identity: $(cat /tmp/.soe-id)"
  else
    bad "No valid AWS credentials. On your Mac run: aws sso login --profile ${AWS_PROFILE:-<profile>}"
  fi
elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ok "Anthropic API key provided via environment"
else
  warn "No provider env set - run 'claude' and use /login (login is kept in the config volume)"
fi

echo
echo "Network"
if [[ "${SOE_FIREWALL:-0}" == "1" ]]; then ok "Egress firewall: ON"; else warn "Egress firewall: OFF"; fi
