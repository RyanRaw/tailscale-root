#!/system/bin/sh
TS_DIR=/data/adb/tailscale
LOG="$TS_DIR/log/tailscaled.log"
PIDFILE="$TS_DIR/tailscaled.pid"
MODDIR=/data/adb/modules/tailscale_root

mkdir -p "$TS_DIR/state" "$TS_DIR/log"

# Update module description in background (every 30s)
(
  sleep 8
  while true; do
    sh "$MODDIR/update_desc.sh"
    sleep 30
  done
) </dev/null >/dev/null 2>&1 &

# ---- user config (/data/adb/tailscale/env) ----
TS_PROXY=""; TS_PORT="41641"; TS_HOSTNAME=""
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"
[ -z "$TS_PROXY" ] && [ -d /data/adb/box ] && TS_PROXY="http://127.0.0.1:7890"

[ -x "$TS_DIR/bin/tailscaled" ] || exit 0

if [ -f "$PIDFILE" ]; then
  op=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$op" ] && [ "$(cat /proc/$op/comm 2>/dev/null)" = "tailscaled" ]; then
    exit 0
  fi
fi

i=0
while pgrep -x tailscaled >/dev/null && [ $i -lt 8 ]; do sleep 1; i=$((i+1)); done
p=$(pgrep -x tailscaled | head -1)
if [ -n "$p" ]; then
  echo "$p" > "$PIDFILE"
  exit 0
fi

if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 2097152 ]; then
  mv "$LOG" "$LOG.old"
fi

rm -f "$TS_DIR/sock"
ip link show tailscale0 >/dev/null 2>&1 && ip link del tailscale0 2>/dev/null

[ -z "$TS_SKIP_WAIT" ] && sleep 8

H="$TS_HOSTNAME"
if [ -z "$H" ]; then
  DEVNAME=$(settings get global device_name 2>/dev/null)
  case "$DEVNAME" in ""|null) DEVNAME=$(getprop ro.product.marketname) ;; esac
  [ -z "$DEVNAME" ] && DEVNAME=$(getprop ro.product.model)
  H=$(printf %s "$DEVNAME" | tr '[:upper:]' '[:lower:]' \
      | sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-*//' -e 's/-*$//' \
      | cut -c1-63)
fi
[ -n "$H" ] && echo "$H" > /proc/sys/kernel/hostname

HTTPS_PROXY="$TS_PROXY" \
HTTP_PROXY="$TS_PROXY" \
nohup "$TS_DIR/bin/tailscaled" \
  --tun=tailscale0 \
  --state="$TS_DIR/state/tailscaled.state" \
  --statedir="$TS_DIR/state" \
  --socket="$TS_DIR/sock" \
  --port="$TS_PORT" \
  < /dev/null >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"

# src_valid_mark guard
nohup setsid sh "$MODDIR/svm_guard.sh" </dev/null >/dev/null 2>&1 &

# Post-start burst: squash src_valid_mark=1 within 1s for the first minute
( i=0; while [ $i -lt 60 ]; do
    [ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark 2>/dev/null)" = "1" ] && \
      echo 0 > /proc/sys/net/ipv4/conf/all/src_valid_mark
    sleep 1; i=$((i+1))
  done ) </dev/null >/dev/null 2>&1 &
