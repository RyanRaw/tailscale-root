#!/system/bin/sh
# guard v6 — persistent watchdog. Duties:
# 1) src_valid_mark guard: tailscaled/WireGuard sets it to 1 (kills tproxy
#    modules like Box for Root); force it back to 0.
# 2) restore a missing Wi-Fi IPv4 default route only when Android's current
#    LinkProperties still advertises that exact route.
# 3) keep the ColorOS reject-rule guard alive and run its idempotent cleanup.
# 4) health watchdog: deep sleep (doze) can deadlock the daemon after wake
#    (log frozen, LocalAPI dead, data plane stalled). Restart it — but only
#    with a startup grace period, 3 consecutive failures, and a 10-minute
#    rate limit: v4 misjudged slow proxy-chain startups and flap-restarted
#    perfectly healthy daemons.
TS_DIR=/data/adb/tailscale
MODDIR=/data/adb/modules/tailscale_root
GUARD_PIDFILE=$TS_DIR/svm_guard.pid
SVM=/proc/sys/net/ipv4/conf/all/src_valid_mark
COLOROS_GUARD=/data/adb/box/scripts/coloros_guard.sh

guard_pid=$(cat "$GUARD_PIDFILE" 2>/dev/null)
if [ -n "$guard_pid" ] && kill -0 "$guard_pid" 2>/dev/null; then
  guard_cmdline=$(tr '\0' ' ' <"/proc/$guard_pid/cmdline" 2>/dev/null)
  case "$guard_cmdline" in
    *"$MODDIR/svm_guard.sh"*) exit 0 ;;
  esac
fi
echo $$ > "$GUARD_PIDFILE"

# 5) wakelock: deep sleep freezes the daemon's data plane on EVERY screen-off
#    cycle (30-60s dead on each wake, occasional hard deadlock). While the
#    daemon runs, hold a kernel wakelock so the CPU never fully suspends.
#    Opt out with TS_WAKELOCK=0 in /data/adb/tailscale/env (saves battery,
#    accepts stalls while the screen is off).
WL=tailscale_root

repair_wifi_default_route() {
  ip -4 addr show dev wlan0 2>/dev/null | grep -q 'inet ' || return 0
  ip -4 route show table wlan0 2>/dev/null | grep -q '^default ' && return 0

  gateway=$(dumpsys connectivity 2>/dev/null \
    | grep -o '0\.0\.0\.0/0 -> [0-9.]* wlan0' \
    | head -1 \
    | awk '{print $3}')
  [ -n "$gateway" ] || return 0

  if ip -4 route add default via "$gateway" dev wlan0 table wlan0 proto static 2>/dev/null; then
    echo "$(date '+%F %T') guard: restored wlan0 default via $gateway" \
      >>"$TS_DIR/log/watchdog.log"
  fi
}

ensure_coloros_guard() {
  [ -x "$COLOROS_GUARD" ] || return 0
  "$COLOROS_GUARD"

  for watcher_pid in $(pidof inotifyd 2>/dev/null); do
    if grep -q coloros_guard "/proc/$watcher_pid/cmdline" 2>/dev/null; then
      return 0
    fi
  done

  setsid inotifyd "$COLOROS_GUARD" /data/misc/net >/dev/null 2>&1 &
}

fails=0; lastpid=""; grace=0; lastrestart=0
while :; do
  [ "$(cat $SVM 2>/dev/null)" = "1" ] && echo 0 > $SVM
  repair_wifi_default_route
  ensure_coloros_guard

  TS_WAKELOCK=1; [ -f "$TS_DIR/env" ] && . "$TS_DIR/env"

  pid=$(pgrep -x tailscaled | head -1)
  if [ -n "$pid" ]; then
    if [ "$TS_WAKELOCK" != "0" ]; then
      echo $WL > /sys/power/wake_lock 2>/dev/null
    else
      echo $WL > /sys/power/wake_unlock 2>/dev/null
    fi
  else
    echo $WL > /sys/power/wake_unlock 2>/dev/null
  fi

  if [ -n "$pid" ] && [ -S "$TS_DIR/sock" ]; then
    if [ "$pid" != "$lastpid" ]; then
      lastpid="$pid"; grace=6; fails=0      # new daemon: ~90s grace
    fi
    if [ "$grace" -gt 0 ]; then
      grace=$((grace-1))
    elif timeout 10 "$TS_DIR/bin/tailscale" --socket="$TS_DIR/sock" status --json >/dev/null 2>&1; then
      fails=0
    else
      fails=$((fails+1))
      now=$(date +%s)
      if [ "$fails" -ge 3 ] && [ $((now - lastrestart)) -gt 600 ]; then
        echo "$(date '+%F %T') watchdog: LocalAPI dead x$fails, restarting tailscaled" >> "$TS_DIR/log/watchdog.log"
        pkill -x tailscaled; sleep 2
        pkill -9 -x tailscaled 2>/dev/null
        rm -f "$TS_DIR/sock" "$TS_DIR/tailscaled.pid"
        TS_SKIP_WAIT=1 sh "$MODDIR/service.sh"
        lastrestart=$now; fails=0; lastpid=""
      fi
    fi
  else
    fails=0; lastpid=""
  fi
  sleep 15
done
