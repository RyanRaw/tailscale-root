#!/system/bin/sh
# 把网络诊断快照写进 /data/adb/tailscale/log/net_probe.log
#   sh net_probe.sh        按 TS_LOGLEVEL 节流（debug 60s / normal 300s / quiet 不写）
#   sh net_probe.sh now    立即写一条
TS_DIR=/data/adb/tailscale
LOG="$TS_DIR/log/net_probe.log"
ENV_FILE="$TS_DIR/env"
SOCK="$TS_DIR/sock"
MODE="$1"

TS_LOGLEVEL="normal"
TS_LOGIN_SERVER=""
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
[ -z "$TS_LOGLEVEL" ] && TS_LOGLEVEL="normal"

interval=300
case "$TS_LOGLEVEL" in
  debug) interval=60 ;;
  quiet) interval=86400 ;;
esac

# 静默级别下彻底不写定时快照；状态页「抓取」传 now，仍然能手动采一份
[ "$TS_LOGLEVEL" = "quiet" ] && [ "$MODE" != "now" ] && exit 0

stamp_file="$TS_DIR/.probe_stamp"
now=$(date +%s)
if [ "$MODE" != "now" ]; then
  last=$(cat "$stamp_file" 2>/dev/null)
  [ -n "$last" ] && [ $((now - last)) -lt "$interval" ] && exit 0
fi
echo "$now" > "$stamp_file" 2>/dev/null

ts_state() {
  printf '%s' "$("$TS_DIR/bin/tailscale" --socket="$SOCK" status --json --peers=false 2>/dev/null \
    | grep -o '"BackendState": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"//')"
}

{
  echo "===== $(date '+%F %T') lvl=$TS_LOGLEVEL ====="
  echo "-- route v4 --"
  ip -4 route get 1.1.1.1 2>&1 | head -2
  echo "-- route v6 --"
  ip -6 route get 2001:4860:4860::8888 2>&1 | head -2
  echo "-- defaults --"
  ip -4 route show table all 2>/dev/null | grep '^default' | head -4
  ip -6 route show table all 2>/dev/null | grep '^default' | head -4
  echo "-- main --"
  ip -4 route show table main 2>&1 | head -4
  echo "-- ifaces v4 --"
  ip -o -4 addr show 2>/dev/null | awk '{print $2, $4}' | head -8
  echo "-- resolv.conf --"
  cat /etc/resolv.conf 2>&1 | head -5
  echo "-- tsdns --"
  tsdns_pid=$(pgrep -f "$TS_DIR/bin/tsdns" | head -1)
  echo "pid=${tsdns_pid:-none} upstream=$(tail -n 1 "$TS_DIR/log/tsdns.log" 2>/dev/null | grep -o 'upstream=.*' )"
  echo "-- dns prop --"
  echo "net.dns1=$(getprop net.dns1) net.dns2=$(getprop net.dns2)"
  echo "-- daemon --"
  echo "pid=$(pidof tailscaled | head -1) state=$(ts_state)"
  echo "-- curl github --"
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' --max-time 6 https://api.github.com 2>&1
  if [ -n "$TS_LOGIN_SERVER" ]; then
    echo "-- curl login server ($TS_LOGIN_SERVER) --"
    curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' --max-time 6 "$TS_LOGIN_SERVER" 2>&1
  fi
  echo "-- last errors --"
  grep -E 'Received error|dns: |network is unreachable' "$TS_DIR/log/tailscaled.log" 2>/dev/null | tail -5 | sed 's/^/   /'
  echo ""
} >> "$LOG" 2>&1

sz=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
[ "$sz" -gt 524288 ] && mv -f "$LOG" "$LOG.old"
exit 0
