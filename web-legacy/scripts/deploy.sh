#!/usr/bin/env bash
set -euo pipefail

HOST="dh_rieips@vps61393.dreamhostps.com"
SSH="ssh -p 22 -o StrictHostKeyChecking=no"
SCP="scp -P 22 -o StrictHostKeyChecking=no"
REMOTE_DIR="~/stark-web"
SERVICE_DIR="~/.config/systemd/user"

DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Deploying stark-web to DreamHost..."

$SSH "$HOST" "mkdir -p $REMOTE_DIR/src $REMOTE_DIR/public $SERVICE_DIR"

$SCP "$DIR/package.json" "$DIR/bun.lock" "$DIR/tsconfig.json" "$HOST:$REMOTE_DIR/"
$SCP "$DIR/src/index.ts" "$HOST:$REMOTE_DIR/src/"
$SCP -r "$DIR/public/." "$HOST:$REMOTE_DIR/public/"
$SCP "$DIR/scripts/stark-web.service" "$HOST:$SERVICE_DIR/"

$SSH "$HOST" bash <<'REMOTE'
  set -euo pipefail
  cd ~/stark-web
  ~/.bun/bin/bun install --frozen-lockfile 2>/dev/null || ~/.bun/bin/bun install
  loginctl enable-linger 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable stark-web
  systemctl --user restart stark-web
  sleep 2
  systemctl --user status stark-web --no-pager -l | head -10
REMOTE

echo "Done. https://stark.caritos.com"
