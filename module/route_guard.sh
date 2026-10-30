#!/system/bin/sh
# 自动处理「对端 advertise 的子网与本机所在局域网重叠」。
#
# 症状：本机在 192.168.4.0/24，对端也 advertise 192.168.4.0/24，tailscaled 把
# 这条路由装进了自己的 table 52，而 `ip rule 5270: from all lookup 52` 优先级高于
# netd 的打标表 —— 于是**所有 App** 访问本地路由器/NAS 都被塞进隧道绕一圈
# （实测 34ms + 33% 丢包，直连是 9ms + 0% 丢包）。
#
# 处理：本机地址只要落在对端某个子网内，就说明"已经在同一个局域网"，此时不需要
# 也经不起这条隧道路由，运行时关掉 accept-routes；换到外网（不再重叠）再恢复，
# 否则访问不了对端子网。判断用真正的 CIDR 位比较，不是前三段字符串近似。
#
# 用标记文件记住"是我们改的"，避免覆盖用户手动设置。
TS_DIR=/data/adb/tailscale
SOCK=$TS_DIR/sock
TS=$TS_DIR/bin/tailscale
LOG=$TS_DIR/log/route_guard.log
MARK=$TS_DIR/.accept_routes_auto

[ -S "$SOCK" ] || exit 0

status=$("$TS" --socket="$SOCK" status --json 2>/dev/null) || exit 0
[ -n "$status" ] || exit 0

# 对端 advertise 的子网：PrimaryRoutes 是字符串数组，按块提取，
# 不用 AllowedIPs（那里可能含 0.0.0.0/0 的 exit node 候选）
nets=$(printf '%s' "$status" | awk '
  /"PrimaryRoutes": \[/ { blk = 1; next }
  blk && /\]/          { blk = 0; next }
  blk {
    gsub(/[\t ",]/, "")
    if ($0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/) print
  }' | sort -u)
[ -z "$nets" ] && exit 0

# 本机全局 IPv4 地址（带前缀长度）
addrs=$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}')
[ -z "$addrs" ] && exit 0

overlap=$(printf '%s\n' "$addrs" | awk -v nets="$nets" '
  function ip2i(s, a) {
    split(s, a, ".")
    return a[1]*16777216 + a[2]*65536 + a[3]*256 + a[4]
  }
  BEGIN { n = split(nets, list, "\n") }
  {
    split($0, x, "/")
    ip = x[1]
    for (i = 1; i <= n; i++) {
      split(list[i], p, "/")
      mask = p[2] + 0
      if (mask == 0) { print 1; exit }
      step = 2 ^ (32 - mask)
      if (int(ip2i(ip) / step) == int(ip2i(p[1]) / step)) { print 1; exit }
    }
  }')

cur=$("$TS" --socket="$SOCK" debug prefs 2>/dev/null \
  | grep -o '"RouteAll": *[a-z]*' | awk '{print $2}')

if [ "$overlap" = "1" ]; then
  if [ "$cur" = "true" ]; then
    if "$TS" --socket="$SOCK" set --accept-routes=false >/dev/null 2>&1; then
      echo "$(date '+%F %T') local net overlaps advertised route -> accept-routes=false" >>"$LOG"
      echo 1 >"$MARK"
    fi
  fi
elif [ "$cur" = "false" ] && [ -f "$MARK" ]; then
  if "$TS" --socket="$SOCK" set --accept-routes=true >/dev/null 2>&1; then
    echo "$(date '+%F %T') no overlap -> accept-routes=true" >>"$LOG"
    rm -f "$MARK"
  fi
fi

exit 0
