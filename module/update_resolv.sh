#!/system/bin/sh
# Android 没有 /etc/resolv.conf，而 tailscaled 是静态 Go 二进制：它无法走 netd
# （bionic getaddrinfo），只会读 /etc/resolv.conf。缺这个文件时解析控制服务器会
# 直接失败："failed to resolve ...; no DNS fallback candidates remain"。
# 模块通过 system/etc/resolv.conf 叠加到 /system（即 /etc）提供该文件，这里负责
# 用设备当前的 DNS 服务器刷新它。
#
#   sh update_resolv.sh           完整探测（getprop + dumpsys）
#   sh update_resolv.sh --quick   只用 getprop，供看门狗周期调用
TS_DIR=/data/adb/tailscale
MODDIR=/data/adb/modules/tailscale_root
TARGET="$MODDIR/system/etc/resolv.conf"
LOG="$TS_DIR/log/resolv.log"
QUICK="$1"

# 用户自定义优先（env 里的 TS_DNS，空格分隔）
TS_DNS=""
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"

servers=""

add_server() {
  s="$1"
  [ -z "$s" ] && return 0
  case "$s" in *[!0-9a-fA-F:.]*) return 0 ;; esac
  case "$s" in *.*|*:*) ;; *) return 0 ;; esac
  case " $servers " in *" $s "*) return 0 ;; esac
  servers="$servers $s"
}

[ -n "$TS_DNS" ] && for s in $TS_DNS; do add_server "$s"; done

if [ -z "$servers" ]; then
  for p in net.dns1 net.dns2 net.dns3 net.dns4; do
    add_server "$(getprop "$p" 2>/dev/null)"
  done
fi

# 新版 Android 不再写 net.dns*，退回 LinkProperties
if [ -z "$servers" ] && [ "$QUICK" != "--quick" ]; then
  for ip in $(dumpsys connectivity 2>/dev/null | grep 'DnsAddresses' | head -3 \
      | tr ',' '\n' | sed -n 's|.*/\([0-9a-fA-F:.]*\).*|\1|p'); do
    add_server "$ip"
  done
fi

# 兜底：AliDNS / DNSPod（国内可用，境外亦可解析）
[ -z "$servers" ] && servers=" 223.5.5.5 119.29.29.29"

write_conf() {
  {
    echo "# tailscale_root $(date '+%F %T')"
    for s in $servers; do echo "nameserver $s"; done
    echo "options timeout:2 attempts:2"
  } > "$1" 2>/dev/null
}

mkdir -p "${TARGET%/*}" 2>/dev/null
write_conf "$TARGET"

# 叠加没生效 / 模块目录不可写时，直接尝试合并后的路径
if [ ! -s "$TARGET" ]; then
  TARGET=/system/etc/resolv.conf
  write_conf "$TARGET"
fi

[ -s "$TARGET" ] && echo "$(date '+%F %T') [$QUICK] -> $servers" >> "$LOG" 2>/dev/null
exit 0
