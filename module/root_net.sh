#!/system/bin/sh
# Android 把默认路由放在「按网络」的路由表里，靠 socket 的 fwmark 选中；
# 普通 App 由 netd 打标记，root（uid 0）的流量不带标记，只能查 main 表。
# main 表通常是空的，于是 root 直连就是：
#   dial tcp 1.2.3.4:443: connect: network is unreachable
# 连 DNS 兜底（bootstrap-dns）也跟着全灭。
# 这里把当前默认网络（含纯 IPv6 + CLAT 场景）的默认路由镜像进 main 表，
# 只影响未打标记的 root 流量，不影响 App（App 走各自 fwmark 表，优先级更高）。
TS_DIR=/data/adb/tailscale
LOG="$TS_DIR/log/net.log"

# dummy/tun 之类的 default 是代理/VPN 留下的黑洞，不能当上行镜像进 main
IFACE_RE='^(wlan|eth|rmnet|ccmni|pdp|radio|swlan|ap|clat|v4-)[0-9a-z_]*$'

have_route() {
  ip -4 route get 1.1.1.1 >/dev/null 2>&1 || ip -6 route get 2001:4860:4860::8888 >/dev/null 2>&1
}
# main 里已经留下指向 dummy0 的默认路由时 ip route get 仍会"成功"，但包全进黑洞
main_is_blackhole() {
  ip -4 route show table main 2>/dev/null | grep -Eq '^default dev (dummy|tun|tap|utun)'
}

have_route && ! main_is_blackhole && exit 0

# $1 = -4 / -6 ; prints "dev gw"
pick() {
  ip "$1" route show table all 2>/dev/null | awk -v re="$IFACE_RE" -v fam="$1" '
    /^default/ {
      dev=""; gw="";
      for (i=1;i<=NF;i++) {
        if ($i=="via") gw=$(i+1);
        if ($i=="dev") dev=$(i+1);
      }
      if (dev == "" || dev !~ re) next
      # IPv4 没有网关的 default 只可能是虚拟接口，不是真上行
      if (fam == "-4" && gw == "") next
      print dev, gw; exit
    }'
}

apply() {
  fam="$1"; line="$2"
  [ -n "$line" ] || return 0
  set -- $line
  dev="$1"; gw="$2"
  [ -n "$dev" ] || return 0
  # 该接口必须真的承载地址，否则写进 main 只会把 root 流量打进黑洞
  ip "$fam" addr show dev "$dev" 2>/dev/null | grep -q 'inet' || return 0
  if [ -n "$gw" ]; then
    ip "$fam" route replace default via "$gw" dev "$dev" table main 2>/dev/null && return 0
    ip "$fam" route del default table main 2>/dev/null
    ip "$fam" route add default via "$gw" dev "$dev" table main 2>&1
  else
    ip "$fam" route replace default dev "$dev" table main 2>/dev/null && return 0
    ip "$fam" route del default table main 2>/dev/null
    ip "$fam" route add default dev "$dev" table main 2>&1
  fi
}

v4line=$(pick -4)
v6line=$(pick -6)
[ -z "$v4line" ] && [ -z "$v6line" ] && exit 0

err4=$(apply -4 "$v4line")
err6=$(apply -6 "$v6line")

if have_route; then
  echo "$(date '+%F %T') root route v4=[$v4line] v6=[$v6line] -> main" >> "$LOG"
else
  echo "$(date '+%F %T') root route failed v4=[$v4line]($err4) v6=[$v6line]($err6)" >> "$LOG"
fi
exit 0
