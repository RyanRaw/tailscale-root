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

# 后台守护只在首次启动挂一次。换控制面后本脚本会以 TS_RESTART_ONLY=1 再跑一次
# 用来重启 daemon（见下面的控制面分支），那时这些循环已经在跑，重复挂只会多出
# 几份 update_desc / net_probe 循环。
if [ -z "$TS_RESTART_ONLY" ]; then
  # Update module description in background (every 30s).
  # /data/host is refreshed by ts_netwatch.sh on netlink route/address events;
  # this loop only keeps a slow safety net (every 60 rounds ≈ 30 min) in case the
  # watcher dies and the file would otherwise keep a stale address forever.
  (
    sleep 8
    n=0
    while true; do
      sh "$MODDIR/update_desc.sh"
      ensure_svm_guard
      n=$((n + 1))
      [ $((n % 60)) -eq 0 ] && sh "$MODDIR/ts_hosts.sh" --hosts >/dev/null 2>&1
      sleep 30
    done
  ) </dev/null >/dev/null 2>&1 &

  # Event driven re-resolve: netlink tells us the moment the uplink changes.
  if ! pgrep -f "$MODDIR/ts_netwatch.sh" >/dev/null 2>&1; then
    nohup sh "$MODDIR/ts_netwatch.sh" </dev/null >/dev/null 2>&1 &
  fi
fi

# ---- user config (/data/adb/tailscale/env) ----
TS_PROXY=""; TS_PORT="41641"; TS_HOSTNAME=""; TS_TUN="tailscale0"; TS_EXTRA_ARGS=""
TS_AUTHKEY=""; TS_LOGLEVEL="normal"
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
# old builds rolled to .bak; nothing reads or removes those any more
rm -f "$LOG.bak"

rm -f "$TS_DIR/sock"
ip link show tailscale0 >/dev/null 2>&1 && ip link del tailscale0 2>/dev/null

[ -z "$TS_SKIP_WAIT" ] && sleep 8

# Static Go binaries ignore Android's netd resolver and read only /etc/hosts and
# /etc/resolv.conf. Neither is usable here: /system is read-only, so the module's
# system/etc/resolv.conf never gets mounted (KernelSU bind-mounts single files and
# the target must already exist), and /etc/hosts only contains localhost.
# ts_hosts.sh points the binary's hosts path at /data/host and fills that file with
# the control server address resolved through bionic (netd / dnsproxyd).
sh "$MODDIR/update_resolv.sh" >/dev/null 2>&1
sh "$MODDIR/ts_hosts.sh" >/dev/null 2>&1

# Root traffic has no fwmark, so it only sees the (usually empty) main routing
# table -> "connect: network is unreachable". Mirror the default route.
sh "$MODDIR/root_net.sh" >/dev/null 2>&1

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

# TS_LOGLEVEL=debug turns on tailscaled verbose logging + periodic net snapshots
VERBOSE_ARG=""
[ "$TS_LOGLEVEL" = "debug" ] && VERBOSE_ARG="--verbose=2"

# tailscaled has no quiet flag — it always writes to stderr. Silent means routing
# it to /dev/null, otherwise "quiet" still grows tailscaled.log.
DAEMON_LOG="$LOG"
[ "$TS_LOGLEVEL" = "quiet" ] && DAEMON_LOG="/dev/null"

# one network snapshot per daemon start (skipped when logging is silenced)
[ "$TS_LOGLEVEL" != "quiet" ] && sh "$MODDIR/net_probe.sh" now >/dev/null 2>&1

# 1.104+ 的二进制自带 androiddns（走 dnsproxyd），正常无需任何 DNS 辅助。
# 这里只在 androiddns 不可用、且用户显式开启兜底时，才拉起回环转发器。
sh "$MODDIR/tsdns_start.sh" >/dev/null 2>&1

HTTPS_PROXY="$TS_PROXY" \
HTTP_PROXY="$TS_PROXY" \
nohup "$TS_DAEMON" \
  --tun="$TS_TUN" \
  --state="$TS_DIR/state/tailscaled.state" \
  --statedir="$TS_DIR/state" \
  --socket="$TS_DIR/sock" \
  --port="$TS_PORT" \
  $VERBOSE_ARG \
  $TS_EXTRA_ARGS \
  < /dev/null >> "$DAEMON_LOG" 2>&1 &
echo $! > "$PIDFILE"

# Control plane + auto login, in one place so the two cases can't race:
#   1. env 期望的控制面和 prefs 里存的不一致（典型：清空自建地址想切回官方）→
#      必须走 ts_up.sh（它会带 --reset --force-reauth）。只重启 daemon 是不够的：
#      `tailscale up` 不带 --login-server 会继续沿用 prefs 里的旧 ControlURL。
#   2. 一致且配了预授权 key、节点还没登录 → 自动注册。
[ -n "$TS_RESTART_ONLY" ] || (
  i=0
  while [ $i -lt 15 ] && [ ! -S "$TS_DIR/sock" ]; do sleep 1; i=$((i+1)); done
  [ -S "$TS_DIR/sock" ] || exit 0
  desired="${TS_LOGIN_SERVER:-https://controlplane.tailscale.com}"
  # daemon 刚起来时 localapi 可能还没就绪，读不到当前控制面就重试几次：
  # 一次读不到就放弃的话，env 里清掉的自建地址会一直生效到下次重启。
  cur=""
  r=0
  while [ $r -lt 4 ] && [ -z "$cur" ]; do
    cur=$(timeout 10 sh "$MODDIR/ts_up.sh" --current 2>/dev/null)
    [ -n "$cur" ] && break
    sleep 2
    r=$((r + 1))
  done
  if [ -n "$cur" ] && [ "$cur" != "$desired" ]; then
    echo "[control] $cur -> $desired" >>"$TS_DIR/log/up.log"
    # 换控制面后 up 会一直等交互登录，不能让它常驻：实测它会把 daemon 的状态接口
    # 卡死（status / route_guard / WebUI 全部阻塞）。25 秒拿到 AuthURL 就杀掉。
    timeout 25 sh "$MODDIR/ts_up.sh" >>"$TS_DIR/log/up.log" 2>&1
    # prefs 此时已落盘为新控制面，重启 daemon 既是解卡，也让它在 NeedsLogin 状态
    # 下重新生成 AuthURL —— WebUI 才有登录链接可显示。
    op=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$op" ] && kill "$op" 2>/dev/null
    i=0
    while [ $i -lt 10 ] && [ -n "$op" ] && kill -0 "$op" 2>/dev/null; do sleep 1; i=$((i+1)); done
    [ -n "$op" ] && kill -9 "$op" 2>/dev/null
    rm -f "$TS_DIR/sock" "$PIDFILE"
    TS_SKIP_WAIT=1 TS_RESTART_ONLY=1 \
      nohup sh "$MODDIR/service.sh" </dev/null >/dev/null 2>&1 &
    exit 0
  fi
  [ -n "$TS_AUTHKEY" ] || exit 0
  bs=$(timeout 10 "$TS_DIR/bin/tailscale" --socket="$TS_DIR/sock" status --json 2>/dev/null \
       | grep -o '"BackendState": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"//')
  case "$bs" in
    NeedsLogin|NoState|"") timeout 25 sh "$MODDIR/ts_up.sh" >>"$TS_DIR/log/up.log" 2>&1 ;;
  esac
) </dev/null >/dev/null 2>&1 &

# Post-start burst: squash src_valid_mark=1 within 1s for the first minute
( i=0; while [ $i -lt 60 ]; do
    [ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark 2>/dev/null)" = "1" ] && \
      echo 0 > /proc/sys/net/ipv4/conf/all/src_valid_mark
    sleep 1; i=$((i+1))
  done ) </dev/null >/dev/null 2>&1 &
