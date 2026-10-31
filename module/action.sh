#!/system/bin/sh
# KSU manager "Action" button — toggle Tailscale on/off
TS_DIR=/data/adb/tailscale
SOCK=$TS_DIR/sock
PIDFILE=$TS_DIR/tailscaled.pid
MODDIR=/data/adb/modules/tailscale_root
TS="$TS_DIR/bin/tailscale --socket=$SOCK"

pid=$(pgrep -f "tailscaled.*--socket=$SOCK" | head -1)

if [ -n "$pid" ]; then
  echo "● Tailscale is RUNNING (pid $pid)"
  echo "→ stopping tailscaled ..."
  pkill -f "tailscaled.*--socket=$SOCK"
  rm -f "$PIDFILE"
  sleep 1
  if pgrep -f "tailscaled.*--socket=$SOCK" >/dev/null; then
    sleep 2
    pkill -9 -f "tailscaled.*--socket=$SOCK" 2>/dev/null
  fi
  # wait for socket release so an immediate re-start cannot race it
  i=0
  while [ $i -lt 6 ] && pgrep -x tailscaled >/dev/null; do sleep 1; i=$((i+1)); done
  pgrep -x tailscaled >/dev/null || rm -f "$SOCK"
  echo ""
  echo "○ Tailscale STOPPED."
  echo "  (svm_guard exits by itself within 10s)"
  sh "$MODDIR/update_desc.sh"
else
  echo "○ Tailscale is STOPPED"
  echo "→ starting tailscaled ..."
  TS_SKIP_WAIT=1 sh "$MODDIR/service.sh"
  i=0
  while [ $i -lt 15 ]; do
    [ -S "$SOCK" ] && break
    sleep 1; i=$((i+1))
  done
  if [ ! -S "$SOCK" ]; then
    echo "✗ daemon did not come up — check WebUI logs"
    exit 1
  fi
  # backend auto-reconnects (WantRunning persisted); give it a moment
  i=0
  while [ $i -lt 12 ]; do
    bs=$(timeout 4 $TS status --json 2>/dev/null | grep -o '"BackendState": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"//')
    [ "$bs" = "Running" ] && break
    sleep 1; i=$((i+1))
  done
  ip4=$(timeout 4 $TS ip -4 2>/dev/null | head -1)
  echo ""
  if [ "$bs" = "Running" ]; then
    echo "● Tailscale ONLINE"
    [ -n "$ip4" ] && echo "  ip: $ip4"
  else
    echo "◐ daemon up, backend: ${bs:-unknown}"
    echo "  (open WebUI if login is required)"
  fi
  sh "$MODDIR/update_desc.sh"
fi

if [ -d /data/adb/box ]; then
  echo ""
  echo "── box guard ──"
  svm=$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark 2>/dev/null)
  if [ "$svm" = "1" ]; then
    echo 0 > /proc/sys/net/ipv4/conf/all/src_valid_mark
    echo "src_valid_mark was 1 → reset to 0 (box tproxy protected)"
  else
    echo "src_valid_mark=$svm — safe"
  fi
  gp=$(cat $TS_DIR/svm_guard.pid 2>/dev/null)
  if [ -n "$gp" ] && kill -0 "$gp" 2>/dev/null; then
    echo "svm_guard active (pid $gp)"
  fi
fi
exit 0
