#!/system/bin/sh
# 给静态 Go 二进制喂一份自己的 hosts。
#
# 背景：tailscaled / tailscale 是 CGO_ENABLED=0 的静态 Go 二进制，解析域名只认
# /etc/hosts 与 /etc/resolv.conf，两者在 Android 上都不可用：
#   - /system 分区只读，且 resolv.conf 根本不存在。KernelSU 用的是单文件
#     bind mount（magic mount），目标文件必须已存在才能挂载，所以模块里的
#     system/etc/resolv.conf 永远挂不上（hosts 反而能挂，因为它存在）。
#   - /etc/hosts 存在，但内容只有 localhost。
# 结果是 Go 手里一个 nameserver 都没有，解析只会落到 tailscale 的 DoH 兜底
# （derp*.tailscale.com，国内 4G 基本全超时）。
#
# 这里的做法（全程不碰系统分区）：
#   1. 把二进制里的 "/etc/hosts" 等长替换成 "/data/host" —— 10 字节对 10 字节，
#      文件大小不变，也不改变任何逻辑。
#   2. 用 bionic（ping → netd → dnsproxyd）解析控制服务器域名，写进 /data/host。
# Go 的解析顺序是 hosts 优先，命中就不查 DNS，于是自建控制服务器/官方控制面
# 都能连上，且换域名时下次启动会自动重新解析。
#
#   sh ts_hosts.sh                 补丁已部署的二进制 + 重新生成 hosts
#   sh ts_hosts.sh --hosts         只重新生成 hosts
#   sh ts_hosts.sh --patch <file>  只给指定文件打补丁（部署 .new 时用）
TS_DIR=/data/adb/tailscale
BIN_DIR="$TS_DIR/bin"
HOSTS=/data/host
OLD_PATH='/etc/hosts'
NEW_PATH='/data/host'

# 把文件里的 "/etc/hosts" 就地换成 "/data/host"。
# 幂等：已经换过、或者这个版本根本没有该字符串，都直接返回成功。
# 用 -F 固定字符串匹配：路径里的点不要当正则通配，否则可能误判成"已补丁"。
patch_file() {
  pf="$1"
  [ -f "$pf" ] || return 0
  if grep -qaF -- "$NEW_PATH" "$pf" 2>/dev/null; then
    return 0
  fi
  # 注意：toybox grep 不支持 -aboF 组合（会静默失败），这里只用 -abo
  off=$(grep -abo -e "$OLD_PATH" "$pf" 2>/dev/null | head -1 | cut -d: -f1)
  [ -z "$off" ] && return 0
  printf '%s' "$NEW_PATH" | dd of="$pf" bs=1 seek="$off" conv=notrunc 2>/dev/null || return 1
  return 0
}

# 对运行中的可执行文件直接写会 ETXTBSY，所以补到副本再原子替换。
# 正在跑的进程用的是旧 inode，不受影响；下次启动即生效。
# 变量名不要用 f：patch_file 内部也会用到，ash 没有函数作用域。
patch_deployed() {
  for name in tailscaled tailscale; do
    df="$BIN_DIR/$name"
    [ -f "$df" ] || continue
    if grep -qaF -- "$NEW_PATH" "$df" 2>/dev/null; then
      continue
    fi
    tmp="$df.patchnew"
    cp -f "$df" "$tmp" 2>/dev/null || continue
    if patch_file "$tmp"; then
      chmod 755 "$tmp" 2>/dev/null
      mv -f "$tmp" "$df" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$tmp"
    fi
  done
}

# https://host:port/path -> host
domain_of() {
  printf '%s' "$1" | sed -e 's|^[A-Za-z][A-Za-z0-9+.-]*://||' -e 's|/.*$||' -e 's|:.*$||'
}

# 从 ping 首行取地址。只认第一个括号：输出形如 "PING host (1.2.3.4) 56(84) bytes"，
# 贪婪匹配会捞到 (84)。地址形态不确定：AAAA 优先时括号里是 "2606:4700::1"，
# 只匹配点分四段的正则会取到空值，所以统一按"到右括号为止"取。
addr_from_ping() {
  sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' | head -1
}

# 借 bionic 的解析结果：ping 会先 getaddrinfo，即使 ICMP 不通也会打印 IP。
# 先试 -4：hosts 是"命中即终止"的，写进去一条 v6 而链路只有 v4 时，Go 会连
# v6 失败且不再回退查 DNS，比不写还糟。老版本 toybox ping 不认 -4，会直接
# 报用法错误，此时退回不带参数（getaddrinfo 首选族）再按通用形态取一次。
resolve_bionic() {
  a=$(ping -4 -c 1 -W 2 "$1" 2>/dev/null | addr_from_ping)
  [ -n "$a" ] && { printf '%s\n' "$a"; return 0; }
  ping -c 1 -W 2 "$1" 2>/dev/null | addr_from_ping
}

gen_hosts() {
  TS_LOGIN_SERVER=""
  [ -f "$TS_DIR/env" ] && . "$TS_DIR/env"
  mine=$(domain_of "$TS_LOGIN_SERVER")

  # 即使切回官方（没有自建域名）也要重写一份，避免上上次的 IP 留在文件里
  {
    echo "127.0.0.1 localhost"
    echo "::1 ip6-localhost"
    if [ -n "$mine" ]; then
      ip=$(resolve_bionic "$mine")
      if [ -z "$ip" ]; then
        # 解析失败（移动网络抖动很常见）不能把上次可用的 IP 抹掉，
        # 否则下次重连会拿着空 hosts 落回那个必败的 DoH 兜底
        # 老条目可能是 v6（点分四段的正则匹配不到），按"第一个字段"取即可
        ip=$(sed -n "s|^\([^ ][^ ]*\) $mine\$|\1|p" "$HOSTS" 2>/dev/null | head -1)
      fi
      if [ -n "$ip" ]; then
        echo "$ip $mine"
      else
        echo "# $mine unresolved at $(date '+%F %T')"
      fi
    fi
  } > "$HOSTS.new" 2>/dev/null && mv -f "$HOSTS.new" "$HOSTS"
  chmod 644 "$HOSTS" 2>/dev/null
}

case "$1" in
  --patch)
    patch_file "$2"
    ;;
  --hosts)
    gen_hosts
    ;;
  *)
    patch_deployed
    gen_hosts
    ;;
esac
exit 0
