#!/usr/bin/env bash
# Full restart of the tunnel test site behind a new Cloudflare quick tunnel (the URL changes): stops the old
# tunnel and server, prepares the databases and assets of the current branch, starts start.sh detached from this
# terminal, writes the URL into the app's config/dev.json and prints it.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
TUNNEL_HOME=${TUNNEL_HOME:-$HOME/.local/share/vn_badminton/tunnel}
export TUNNEL_HOME

# Bracketed patterns so pkill does not match its own command line.
pkill -9 -f "[t]unnel/start.sh" || true
pkill -f "[c]loudflared tunnel" || true
pkill -f "[p]uma.*3100" || true
sleep 2

(
  source "$TUNNEL_HOME/env.sh"
  cd "${APP:-$D/../..}"
  echo "Branch: $(git branch --show-current)"
  bin/rails db:prepare
  bin/rails assets:clobber
  bin/rails assets:precompile > /dev/null
)

rm -f "$TUNNEL_HOME/url"
setsid nohup "$D/start.sh" > "$TUNNEL_HOME/server.log" 2>&1 < /dev/null &

for _ in $(seq 1 60); do [ -s "$TUNNEL_HOME/url" ] && break; sleep 1; done
[ -s "$TUNNEL_HOME/url" ] || { echo "The tunnel did not start, see $TUNNEL_HOME/cloudflared.log"; exit 1; }
url=$(cat "$TUNNEL_HOME/url")

# The mobile app reads the server address from this file (flutter run --dart-define-from-file).
MOBILE=$(source "$TUNNEL_HOME/env.sh"; echo "${MOBILE:-/mnt/d/dev/vn_badminton_mobile}")
[ -d "$MOBILE/config" ] && printf '{\n  "API_URL": "%s"\n}\n' "$url" > "$MOBILE/config/dev.json"

for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$url/up" || true)" = 200 ] && break
  sleep 2
done

echo
echo "  Public URL: $url  (/up: $(curl -s -o /dev/null -w '%{http_code}' -m 10 "$url/up" || true))"
echo "  Log: $TUNNEL_HOME/server.log"
