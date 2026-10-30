#!/system/bin/sh
TS_DIR=/data/adb/tailscale
LOG="$TS_DIR/log/tailscaled.log"
PIDFILE="$TS_DIR/tailscaled.pid"
MODDIR=/data/adb/modules/tailscale_root

mkdir -p "$TS_DIR/state" "$TS_DIR/log"

ensure_svm_guard() {
  guard_pid=$(cat "$TS_DIR/svm_guard.pid" 2>/dev/null)
  if [ -n "$guard_pid" ] && kill -0 "$guard_pid" 2>/dev/null; then
    guard_cmdline=$(tr '\0' ' ' <"/proc/$guard_pid/cmdline" 2>/dev/null)
    case "$guard_cmdline" in
      *"$MODDIR/svm_guard.sh"*) return 0 ;;
    esac
  fi

  rm -f "$TS_DIR/svm_guard.pid"
  nohup setsid sh "$MODDIR/svm_guard.sh" \
    </dev/null >"$TS_DIR/log/svm_guard.out" 2>&1 &
}

# Update module description in background (every 30s)
(
  sleep 8
  while true; do
    sh "$MODDIR/update_desc.sh"
    ensure_svm_guard
    sleep 30
  done
) </dev/null >/dev/null 2>&1 &

# ---- user config (/data/adb/tailscale/env) ----
TS_PROXY=""; TS_PORT="41641"; TS_HOSTNAME=""; TS_TUN="tailscale0"; TS_EXTRA_ARGS=""
TS_AUTHKEY=""
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"
# disabled: eBPF handles proxying transparently
# [ -z "$TS_PROXY" ] && [ -d /data/adb/box ] && TS_PROXY="http://127.0.0.1:7890"

# Self-built / third-party daemon support: point TS_DAEMON at any executable.
TS_DAEMON="${TS_DAEMON:-$TS_DIR/bin/tailscaled}"
[ -x "$TS_DAEMON" ] || exit 0

# This must run before either existing-daemon early return below. Otherwise a
# dead guard leaves src_valid_mark=1 until the next reboot or manual repair.
ensure_svm_guard

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

# tailscaled is a static Go binary: it cannot use Android's netd resolver and
# only reads /etc/resolv.conf (absent on Android). Refresh the overlay copy so
# the control server / DERP host names actually resolve.
sh "$MODDIR/update_resolv.sh" >/dev/null 2>&1

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
nohup "$TS_DAEMON" \
  --tun="$TS_TUN" \
  --state="$TS_DIR/state/tailscaled.state" \
  --statedir="$TS_DIR/state" \
  --socket="$TS_DIR/sock" \
  --port="$TS_PORT" \
  $TS_EXTRA_ARGS \
  < /dev/null >> "$LOG" 2>&1 &
echo $! > "$PIDFILE"

# Pre-auth key configured: register automatically when the node still needs a login.
if [ -n "$TS_AUTHKEY" ]; then
  (
    i=0
    while [ $i -lt 15 ] && [ ! -S "$TS_DIR/sock" ]; do sleep 1; i=$((i+1)); done
    [ -S "$TS_DIR/sock" ] || exit 0
    bs=$("$TS_DIR/bin/tailscale" --socket="$TS_DIR/sock" status --json 2>/dev/null \
         | grep -o '"BackendState": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"//')
    case "$bs" in
      NeedsLogin|NoState|"") sh "$MODDIR/ts_up.sh" >>"$TS_DIR/log/up.log" 2>&1 ;;
    esac
  ) </dev/null >/dev/null 2>&1 &
fi

# Post-start burst: squash src_valid_mark=1 within 1s for the first minute
( i=0; while [ $i -lt 60 ]; do
    [ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark 2>/dev/null)" = "1" ] && \
      echo 0 > /proc/sys/net/ipv4/conf/all/src_valid_mark
    sleep 1; i=$((i+1))
  done ) </dev/null >/dev/null 2>&1 &
