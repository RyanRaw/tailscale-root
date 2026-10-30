#!/system/bin/sh
# Android 没有 /etc/resolv.conf，而 tailscaled 是静态 Go 二进制：它无法走 netd
# （bionic getaddrinfo），只会读 /etc/resolv.conf。缺这个文件时解析控制服务器会
# 直接失败："failed to resolve ...; no DNS fallback candidates remain"。
# 模块通过 system/etc/resolv.conf 叠加到 /system（即 /etc）提供该文件，这里负责
# 用设备当前的 DNS 服务器刷新它。
#
#   sh update_resolv.sh           完整探测（getprop + dumpsys）
#   sh update_resolv.sh --quick   看门狗周期调用：能确定没换网就原地不动
#
# --quick 的坑：新版 Android 不再写 net.dns*，真实 DNS 只能从 dumpsys
# connectivity 的 LinkProperties 里拿。所以 "拿不到就写公共 DNS 兜底" 会把上次
# 全量探测到的局域网 DNS（如 192.168.4.21）在 5 分钟后覆盖掉。现在只有网络
# 指纹变了（或文件缺失）才会去 dumpsys，其余情况保留现状。
TS_DIR=/data/adb/tailscale
MODDIR=/data/adb/modules/tailscale_root
TARGET="$MODDIR/system/etc/resolv.conf"
OWN_CONF="$TS_DIR/resolv.conf"
LOG="$TS_DIR/log/resolv.log"
FP_FILE="$TS_DIR/.resolv_net"
QUICK="$1"

# 用户自定义优先（env 里的 TS_DNS，空格分隔）
TS_DNS=""
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"

servers=""

# 本机地址不能当上游（dumpsys 里会带上 wlan0/rmnet 的自身 IP，写进去等于死循环）
LOCAL_IPS=$(
  ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1
  ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1
)

is_local() {
  for l in $LOCAL_IPS; do
    [ "$l" = "$1" ] && return 0
  done
  return 1
}

add_server() {
  s="$1"
  [ -z "$s" ] && return 0
  case "$s" in *[!0-9a-fA-F:.]*) return 0 ;; esac
  case "$s" in *.*|*:*) ;; *) return 0 ;; esac
  case " $servers " in *" $s "*) return 0 ;; esac
  is_local "$s" && return 0
  servers="$servers $s"
}

# 网络指纹：每条 default 路由的 "table/dev/gateway"。
# 不能整行比较 —— IPv6 路由带 `expires 57473sec`、`hoplimit` 这类每秒/每网络
# 都会变的字段，整行做指纹等于每轮都"换了网"。只取结构性三要素，换 Wi-Fi
# （网关变）、切蜂窝（main 表的 dev 变）都能识别，同一网络下保持稳定。
net_fp() {
  for fam in -4 -6; do
    ip "$fam" route show table all 2>/dev/null | grep '^default' \
      | awk '{
          d = ""; g = ""; t = "main"
          for (i = 1; i <= NF; i++) {
            if ($i == "via")   g = $(i + 1)
            if ($i == "dev")   d = $(i + 1)
            if ($i == "table") t = $(i + 1)
          }
          print t "/" d "/" g
        }'
  done | sort -u
}
cur_fp=$(net_fp)
old_fp=$(cat "$FP_FILE" 2>/dev/null)

[ -n "$TS_DNS" ] && for s in $TS_DNS; do add_server "$s"; done

if [ -z "$servers" ]; then
  for p in net.dns1 net.dns2 net.dns3 net.dns4; do
    add_server "$(getprop "$p" 2>/dev/null)"
  done
fi

# 只有走到 dumpsys 才能拿到真实 DNS。--quick 模式下限定条件：网络变了、
# 或者文件还没写过，才值得探测一次；否则原样保留上次的结果。
if [ -z "$servers" ]; then
  if [ "$QUICK" = "--quick" ]; then
    # 连默认路由都没有（飞行模式 / 断网）：什么都别动
    [ -z "$cur_fp" ] && exit 0
    if [ "$cur_fp" = "$old_fp" ] && [ -s "$TARGET" ]; then
      exit 0
    fi
  fi
  for ip in $(dumpsys connectivity 2>/dev/null | grep 'DnsAddresses' | head -3 \
      | tr ',' '\n' | sed -n 's|.*/\([0-9a-fA-F:.]*\).*|\1|p'); do
    add_server "$ip"
  done
fi

fallback=0
if [ -z "$servers" ]; then
  # 兜底：AliDNS / DNSPod（国内可用，境外亦可解析）
  servers=" 223.5.5.5 119.29.29.29"
  fallback=1
fi

write_conf() {
  {
    echo "# tailscale_root $(date '+%F %T')"
    for s in $servers; do echo "nameserver $s"; done
    echo "options timeout:2 attempts:2"
  } > "$1" 2>/dev/null
}

mkdir -p "${TARGET%/*}" 2>/dev/null
write_conf "$TARGET"

# 模块自查/调试用的一份（system/etc 叠加在部分 ROM 上不生效）
write_conf "$OWN_CONF"

# 只有真拿到本网络的 DNS 才记指纹。写了兜底值就清掉指纹，让下一次 --quick
# 继续尝试探测 —— 兜底值不代表这个网络的上游。
if [ "$fallback" = "0" ]; then
  printf '%s\n' "$cur_fp" > "$FP_FILE" 2>/dev/null
else
  rm -f "$FP_FILE" 2>/dev/null
fi

[ -s "$OWN_CONF" ] && echo "$(date '+%F %T') [$QUICK] -> $servers" >> "$LOG" 2>/dev/null
exit 0
