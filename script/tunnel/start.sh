#!/usr/bin/env bash
# Starts a Cloudflare quick tunnel (random https://*.trycloudflare.com URL, no account) and the app in
# production mode behind it. Ctrl+C stops both. The URL changes every time. Usually started by restart.sh.
# Settings: $TUNNEL_HOME/env.sh (from env.example.sh); the URL is written to $TUNNEL_HOME/url.
set -euo pipefail
TUNNEL_HOME=${TUNNEL_HOME:-$HOME/.local/share/vn_badminton/tunnel}
source "$TUNNEL_HOME/env.sh"
APP=${APP:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$APP"

LOG=$TUNNEL_HOME/cloudflared.log; : > "$LOG"
cloudflared tunnel --no-autoupdate --url "http://localhost:$PORT" > "$LOG" 2>&1 &
TUNNEL_PID=$!
trap 'kill $TUNNEL_PID 2>/dev/null' EXIT

for _ in $(seq 1 60); do
  url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -1 || true)
  [ -n "$url" ] && break; sleep 1
done
[ -n "${url:-}" ] || { echo "The tunnel did not start, see $LOG"; exit 1; }

export APP_HOST=${url#https://}
echo "$url" > "$TUNNEL_HOME/url"
echo
echo "  Public URL: $url"
echo
bin/rails server -p "$PORT" -b 127.0.0.1
