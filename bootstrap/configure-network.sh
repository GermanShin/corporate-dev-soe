#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# OPTIONAL egress allowlist. Runs as root at container start when SOE_FIREWALL=1
# (requires: docker run --cap-add=NET_ADMIN --cap-add=NET_RAW).
#
# Default-deny outbound traffic, then allow DNS, the Docker host, and the
# domains in /opt/corporate-soe/config/allowed-domains.txt (+ SOE_EXTRA_DOMAINS).
#
# Note: domains are resolved to IPs once at start-up. CDN-backed services can
# change IPs, so this is a guard rail for the sandbox, not a replacement for
# the corporate egress proxy.
# -----------------------------------------------------------------------------
set -euo pipefail

DOMAINS_FILE=/opt/corporate-soe/config/allowed-domains.txt
REGION="${AWS_REGION:-ap-southeast-2}"
SET=soe-allowed

echo "Applying SOE egress firewall..."

domains=$(grep -vE '^\s*(#|$)' "${DOMAINS_FILE}" | sed "s/{{AWS_REGION}}/${REGION}/g")
if [[ -n "${SOE_EXTRA_DOMAINS:-}" ]]; then
  domains="${domains}"$'\n'"$(echo "${SOE_EXTRA_DOMAINS}" | tr ',' '\n')"
fi

# Resolve BEFORE locking down (DNS must still work).
ipset destroy "${SET}" 2>/dev/null || true
ipset create "${SET}" hash:net
count=0
while IFS= read -r domain; do
  domain="$(echo "${domain}" | xargs)"
  [[ -z "${domain}" ]] && continue
  ips=$(dig +short +time=3 +tries=2 A "${domain}" | grep -E '^[0-9]+(\.[0-9]+){3}$' || true)
  if [[ -z "${ips}" ]]; then
    echo "  ! could not resolve ${domain} (skipped)"
    continue
  fi
  for ip in ${ips}; do ipset add -exist "${SET}" "${ip}"; count=$((count+1)); done
done <<< "${domains}"

host_net=$(ip route | awk '/default/ {print $3; exit}')

iptables -F OUTPUT
iptables -P OUTPUT DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
[[ -n "${host_net}" ]] && iptables -A OUTPUT -d "${host_net}" -j ACCEPT
iptables -A OUTPUT -m set --match-set "${SET}" dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# Block IPv6 egress entirely so it can't be used to bypass the allowlist.
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -F OUTPUT 2>/dev/null || true
  ip6tables -P OUTPUT DROP 2>/dev/null || true
  ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
fi

echo "  allowed ${count} addresses; everything else is blocked."

# Self-test
if curl -s --max-time 4 https://example.com >/dev/null 2>&1; then
  echo "  ! WARNING: example.com is reachable - firewall is NOT effective." >&2
else
  echo "  verified: non-allowlisted sites are blocked."
fi
