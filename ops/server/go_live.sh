#!/usr/bin/env bash
# One-shot bring-up of a fresh Oracle box.  usage: go_live.sh <public-ip>
# Idempotent: every stage re-runs safely, so a failed stage can just be retried.
set -euo pipefail
IP="${1:?usage: go_live.sh <public-ip>}"
K=D:/keys/oracle-clipcart
HERE="$(cd "$(dirname "$0")" && pwd)"
SSHO="-i $K/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$HERE/known_hosts"

say() { printf '\n== %s ==\n' "$1"; }

say "waiting for ssh on $IP"
for i in $(seq 1 60); do
  if ssh $SSHO -o ConnectTimeout=8 -o BatchMode=yes "ubuntu@$IP" true 2>/dev/null; then
    echo "ssh up after $i tries"; break
  fi
  [ "$i" = 60 ] && { echo "ssh never came up"; exit 1; }
  sleep 10
done

say "uploading scripts + keys"
scp $SSHO -q "$HERE/bootstrap.sh" "$HERE/harden.sh" "$HERE/stack.sh" "ubuntu@$IP:/tmp/"
scp $SSHO -q "$K/id_ed25519.pub" "ubuntu@$IP:/tmp/admin_key.pub"
scp $SSHO -q "$K/ci_deploy.pub"  "ubuntu@$IP:/tmp/ci_key.pub"
scp $SSHO -q "$HOME/.ssh/clipcart_deploy" "ubuntu@$IP:/tmp/github_deploy"

say "stage 1/3 - bootstrap (iptables, docker, swap)"
ssh $SSHO "ubuntu@$IP" 'bash /tmp/bootstrap.sh'

say "stage 2/3 - harden (users, /opt/clipcart, sshd, fail2ban)"
ssh $SSHO "ubuntu@$IP" 'bash /tmp/harden.sh'

say "stage 3/3 - stack (clone, .env, docker compose up)"
ssh $SSHO "deploy@$IP" 'bash /tmp/stack.sh'

say "done - next: fill .env secrets, then the catalog restore"
echo "  ssh -i $K/id_ed25519 deploy@$IP"
