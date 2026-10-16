#!/usr/bin/env bash
# Two accounts with different jobs, so a leaked CI key can't administer the box:
#   ccadmin - human admin, sudo, the interactive key from the workstation
#   deploy  - owns /opt/clipcart and the docker socket, nothing else. GitHub
#             Actions logs in as this one, and it deliberately has no sudo.
# Root login and passwords are then switched off entirely.
set -euo pipefail

ADMIN_KEY="$(cat /tmp/admin_key.pub)"
CI_KEY="$(cat /tmp/ci_key.pub)"
GH_KEY=/tmp/github_deploy

addkey() {  # user, key
  install -d -m 700 -o "$1" -g "$1" "/home/$1/.ssh"
  touch "/home/$1/.ssh/authorized_keys"
  grep -qxF "$2" "/home/$1/.ssh/authorized_keys" || echo "$2" >> "/home/$1/.ssh/authorized_keys"
  chmod 600 "/home/$1/.ssh/authorized_keys"
  chown "$1:$1" "/home/$1/.ssh/authorized_keys"
}

echo "=== users ==="
for u in ccadmin deploy; do
  id -u "$u" >/dev/null 2>&1 || sudo useradd -m -s /bin/bash "$u"
done
sudo usermod -aG sudo ccadmin
sudo usermod -aG docker deploy
sudo usermod -aG docker ccadmin
echo 'ccadmin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-ccadmin >/dev/null
sudo chmod 440 /etc/sudoers.d/90-ccadmin
sudo visudo -cf /etc/sudoers.d/90-ccadmin

echo "=== keys ==="
sudo bash -c "$(declare -f addkey); addkey ccadmin '$ADMIN_KEY'"
sudo bash -c "$(declare -f addkey); addkey deploy  '$CI_KEY'"
# the admin key also opens `deploy`, so the stack can be driven from the workstation
sudo bash -c "$(declare -f addkey); addkey deploy  '$ADMIN_KEY'"

echo "=== github key for the deploy user ==="
sudo install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
sudo install -m 600 -o deploy -g deploy "$GH_KEY" /home/deploy/.ssh/github_deploy
sudo tee /home/deploy/.ssh/config >/dev/null <<'CFG'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_deploy
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
CFG
sudo chown deploy:deploy /home/deploy/.ssh/config
sudo chmod 600 /home/deploy/.ssh/config
shred -u "$GH_KEY" /tmp/admin_key.pub /tmp/ci_key.pub 2>/dev/null || rm -f "$GH_KEY" /tmp/admin_key.pub /tmp/ci_key.pub

echo "=== /opt/clipcart owned by deploy ==="
# deploy has no sudo on purpose - that's the whole point of splitting it from
# ccadmin - so the directory is handed over here, while we still have root.
sudo install -d -o deploy -g deploy -m 755 /opt/clipcart
ls -ld /opt/clipcart

echo "=== sshd: keys only, no root ==="
sudo tee /etc/ssh/sshd_config.d/99-clipcart.conf >/dev/null <<'CONF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 4
CONF
sudo sshd -t && sudo systemctl reload ssh
echo "sshd reloaded"

echo "=== fail2ban ==="
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'CONF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
CONF
sudo systemctl enable --now fail2ban >/dev/null 2>&1 || true
sudo systemctl restart fail2ban
sleep 2
sudo fail2ban-client status sshd | head -5 || true

echo "HARDEN OK"
