# Settings of the tunnel test site (production mode on this computer, behind a Cloudflare quick tunnel).
# Copy to ~/.local/share/vn_badminton/tunnel/env.sh (outside the repository) and adjust. No secret is written here:
# they are read from files in ~/.config/vn_badminton/ (chmod 600), see docs/dev-setup.md.
export RAILS_ENV=production
export PORT=3100
export SOLID_QUEUE_IN_PUMA=1
export RAILS_LOG_LEVEL=info
# Local Postgres over the Unix socket as the current user, with its own databases (separate from development).
u=$(whoami)
export DATABASE_URL="postgres:///vn_badminton_tunnel?username=$u"
export CACHE_DATABASE_URL="postgres:///vn_badminton_tunnel_cache?username=$u"
export QUEUE_DATABASE_URL="postgres:///vn_badminton_tunnel_queue?username=$u"
export CABLE_DATABASE_URL="postgres:///vn_badminton_tunnel_cable?username=$u"
# Assets under their own prefix, so precompiling for the tunnel never touches development's.
export ASSETS_PREFIX=/tunnel-assets
# The repository (default: the one holding these scripts) and the app's checkout, whose config/dev.json gets the URL.
# APP=$HOME/projects/vn_badminton
# MOBILE=/mnt/d/dev/vn_badminton_mobile

# Optional services: leave a line out and that feature is simply off.
# Bank transfers confirmed by SePay's webhook (TT-04).
[ -f ~/.config/vn_badminton/sepay_webhook_api_key ] && export SEPAY_WEBHOOK_API_KEY=$(cat ~/.config/vn_badminton/sepay_webhook_api_key)
# Push notifications to the app (TB-04).
[ -f ~/.config/vn_badminton/firebase-service-account.json ] && export FIREBASE_SERVICE_ACCOUNT_PATH=$HOME/.config/vn_badminton/firebase-service-account.json
# Google sign-in (AP-05): the Web client ID of the Google Cloud project (public, not a secret).
# export GOOGLE_WEB_CLIENT_ID=1234567890-xxxxxxxx.apps.googleusercontent.com
# Android App Links (AP-04): SHA-256 fingerprint of the key signing the APK (debug key of the computer that builds it).
# export ANDROID_CERT_SHA256=AA:BB:...
