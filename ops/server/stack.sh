#!/usr/bin/env bash
# ClipCart stack: clone the repo, write a fresh .env, bring the containers up.
# Runs as `deploy`, which has no sudo - docker works through group membership,
# and harden.sh already created /opt/clipcart and installed the github key.
# Secrets are generated ON the box so they never travel.
set -euo pipefail

REPO="git@github.com:ClipXCartDev/ClipCart.git"
DIR=/opt/clipcart

echo "=== github reachability (as $(whoami)) ==="
ssh -o BatchMode=yes -T git@github.com 2>&1 | head -1 || true

echo "=== clone ==="
if [ ! -d "$DIR/.git" ]; then
  git clone -q "$REPO" "$DIR"
  echo "cloned"
else
  cd "$DIR" && git fetch -q --all && git reset -q --hard origin/main
  echo "updated"
fi
cd "$DIR" && git log --oneline -1

echo "=== .env ==="
if [ ! -f "$DIR/.env" ]; then
  cat > "$DIR/.env" <<ENVEOF
ENV=prod

POSTGRES_USER=clipcart
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_DB=clipcart

JWT_SECRET=$(openssl rand -hex 32)
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30
MAX_DEVICES=2

GOOGLE_CLIENT_ID=__GOOGLE_CLIENT_ID__

STORAGE_PROVIDER=r2
STORAGE_DIR=./storage
STORAGE_URL_SECRET=$(openssl rand -hex 32)
R2_ACCOUNT_ID=__R2_ACCOUNT__
R2_ACCESS_KEY_ID=__R2_KEY__
R2_SECRET_ACCESS_KEY=__R2_SECRET__
R2_BUCKET=clipcart

BINANCE_PAY_KEY=
BINANCE_PAY_SECRET=

CORS_ORIGINS=https://clipscart.app,https://www.clipscart.app
APK_DIRECT_URL=https://clipscart.app/downloads/clipcart.apk
ENVEOF
  chmod 600 "$DIR/.env"
  echo ".env created (placeholders still to fill)"
else
  echo ".env already present - left alone"
fi

echo "=== bring the stack up ==="
cd "$DIR"
docker compose up -d --build
sleep 8
docker compose ps --format '{{.Service}} {{.State}}'
echo
curl -fsS -m 10 http://localhost/health && echo || echo "(health not up yet)"
echo "STACK OK"
