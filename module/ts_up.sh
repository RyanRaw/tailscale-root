#!/system/bin/sh
# Bring the backend up / start login, honouring the self-hosted control server
# settings from /data/adb/tailscale/env:
#   TS_LOGIN_SERVER  e.g. https://headscale.example.com   (empty = Tailscale SaaS)
#   TS_AUTHKEY       pre-auth key, skips the interactive login
#   TS_UP_ARGS       extra `tailscale up` flags, e.g. --reset (needed when the
#                    control server changed) or --advertise-routes=...
TS_DIR=/data/adb/tailscale
SOCK="$TS_DIR/sock"

TS_LOGIN_SERVER=""; TS_AUTHKEY=""; TS_UP_ARGS=""
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"

LOGIN_ARG=""
[ -n "$TS_LOGIN_SERVER" ] && LOGIN_ARG="--login-server=$TS_LOGIN_SERVER"
AUTH_ARG=""
[ -n "$TS_AUTHKEY" ] && AUTH_ARG="--authkey=$TS_AUTHKEY"

# word splitting of LOGIN_ARG / AUTH_ARG / TS_UP_ARGS is intentional
exec "$TS_DIR/bin/tailscale" --socket="$SOCK" up \
  --accept-routes --accept-dns=false \
  $LOGIN_ARG $AUTH_ARG $TS_UP_ARGS
