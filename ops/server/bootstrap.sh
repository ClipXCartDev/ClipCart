#!/usr/bin/env bash
# ClipCart on Oracle Cloud (Ubuntu 24.04, aarch64) - system prep.
#
# Oracle's Ubuntu images ship an iptables INPUT chain that REJECTs everything
# except 22, independently of the cloud-side Security List. Opening the Security
# List alone leaves the box looking dead on 80/443, so both have to be opened -
# that is the single most common "my Oracle server is broken" cause.
set -euo pipefail

echo "=== host ==="
uname -m; lsb_release -ds 2>/dev/null || true
nproc; free -g | head -2; df -h / | tail -1

echo "=== iptables: allow 80/443 ahead of the REJECT ==="
sudo iptables -S INPUT | head -20
for port in 80 443; do
  if ! sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    pos=$(sudo iptables -S INPUT | grep -n -m1 -E '^-A INPUT -j (REJECT|DROP)' | cut -d: -f1 || true)
    if [ -n "${pos:-}" ]; then
      sudo iptables -I INPUT "$((pos - 1))" -p tcp --dport "$port" -j ACCEPT
    else
      sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    fi
    echo "opened $port"
  else
    echo "$port already open"
  fi
done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q iptables-persistent >/dev/null 2>&1 || true
sudo netfilter-persistent save >/dev/null 2>&1 || sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
echo "--- INPUT now ---"; sudo iptables -S INPUT | head -20

echo "=== packages ==="
sudo DEBIAN_FRONTEND=noninteractive apt-get update -q >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  ca-certificates curl git ffmpeg fail2ban python3-venv python3-pip >/dev/null
echo "base packages installed"

echo "=== docker ==="
if ! command -v docker >/dev/null; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -q >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
fi
sudo docker --version; sudo docker compose version

echo "=== swap (24 GB RAM is plenty, but builds like a little headroom) ==="
if ! sudo swapon --show | grep -q swapfile; then
  sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi
free -h | head -3

echo "BOOTSTRAP OK"
