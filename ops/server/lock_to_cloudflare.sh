#!/usr/bin/env bash
# Only let Cloudflare reach the origin's 80/443, so nobody can bypass the proxy
# by hitting the IP directly. Re-runnable; run it again whenever Cloudflare
# publishes new ranges.
#
# Two things here are easy to get wrong and both fail quietly:
#
# 1. Docker-published ports NEVER traverse iptables INPUT. They are DNAT'd in
#    nat/PREROUTING and then forwarded, so INPUT rules for 80/443 look correct
#    and filter nothing. DOCKER-USER is the chain Docker guarantees is consulted
#    first in FORWARD, so that is where this has to live.
#
# 2. FORWARD carries BOTH directions. A rule matching only "--dports 80,443"
#    also matches containers dialling OUT to any https host, which silently
#    breaks image builds (pip/npm get "Network is unreachable"). Pinning -i to
#    the external interface limits this to packets arriving from outside;
#    egress leaves via -o and no longer matches.
set -euo pipefail

EXT="${EXT:-$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)}"
[ -n "$EXT" ] || { echo "could not determine the external interface; set EXT=..." >&2; exit 1; }
echo "external interface: $EXT"

CF4="$(curl -fsS --max-time 20 https://www.cloudflare.com/ips-v4 | tr '\n' ' ')"
[ -n "${CF4// /}" ] || { echo "could not fetch Cloudflare ranges" >&2; exit 1; }
echo "cloudflare ranges: $(echo "$CF4" | wc -w)"

# drop our previous rules first so re-running doesn't stack duplicates
while sudo iptables -L DOCKER-USER --line-numbers -n 2>/dev/null | grep -q clipcart-cf; do
  n="$(sudo iptables -L DOCKER-USER --line-numbers -n | grep -m1 clipcart-cf | awk '{print $1}')"
  sudo iptables -D DOCKER-USER "$n"
done

# insert the DROP first, then the allows above it, so the final order is:
#   [cloudflare ranges -> RETURN] ... [everything else inbound to 80/443 -> DROP]
sudo iptables -I DOCKER-USER 1 -i "$EXT" -p tcp -m multiport --dports 80,443 \
  -m conntrack --ctstate NEW -m comment --comment clipcart-cf -j DROP
for r in $CF4; do
  sudo iptables -I DOCKER-USER 1 -i "$EXT" -s "$r" -p tcp -m multiport --dports 80,443 \
    -m comment --comment clipcart-cf -j RETURN
done

sudo netfilter-persistent save >/dev/null 2>&1 || true
echo "rules installed: $(sudo iptables -S DOCKER-USER | grep -c clipcart-cf)"

echo "--- verifying egress still works (this is the one that breaks builds) ---"
sudo docker run --rm alpine:latest sh -c \
  'wget -q -T 12 -O /dev/null https://pypi.org/simple/ && echo "  egress OK" || { echo "  EGRESS BLOCKED"; exit 1; }'
echo "LOCK OK - now check from off-box that the raw IP refuses 80/443"
