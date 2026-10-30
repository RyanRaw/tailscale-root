#!/system/bin/sh
# Android 把默认路由放在「按网络」的路由表里，靠 socket 的 fwmark 选中；
# 普通 App 由 netd 打标记，而 root（uid 0）的流量不带标记，只能查 main 表。
# main 表通常是空的，于是 tailscaled 的每一次外连都是：
#   dial tcp 1.2.3.4:443: connect: network is unreachable
# 连 DNS 兜底（bootstrap-dns）也跟着全灭。
# 这里把当前默认网络的默认路由镜像一份到 main 表，只影响未打标记的 root 流量，
# 不影响 App（App 走各自的 fwmark 表，优先级更高）。
TS_DIR=/data/adb/tailscale
LOG="$TS_DIR/log/net.log"

# 已经能路由就不用动
ip route get 1.1.1.1 >/dev/null 2>&1 && exit 0

line=$(ip route show table all 2>/dev/null | awk '
  /^default/ {
    dev=""; gw="";
    for (i=1;i<=NF;i++) {
      if ($i=="via") gw=$(i+1);
      if ($i=="dev") dev=$(i+1);
    }
    if (dev ~ /^(wlan|eth|rmnet|ccmni|pdp|radio|swlan|ap|wlan[0-9])/) { print dev, gw; exit }
  }')

[ -z "$line" ] && exit 0
set -- $line
DEV="$1"
GW="$2"
[ -n "$DEV" ] || exit 0

if [ -n "$GW" ]; then
  ip route replace default via "$GW" dev "$DEV" table main 2>/dev/null
else
  ip route replace default dev "$DEV" table main 2>/dev/null
fi

if ip route get 1.1.1.1 >/dev/null 2>&1; then
  echo "$(date '+%F %T') root route -> $DEV ${GW:+via $GW} (table main)" >> "$LOG"
else
  echo "$(date '+%F %T') root route failed for $DEV ${GW:+via $GW}" >> "$LOG"
fi
exit 0
