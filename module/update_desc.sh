#!/system/bin/sh
TS_DIR=/data/adb/tailscale
TS="$TS_DIR/bin/tailscale"
PROP=/data/adb/modules/tailscale_root/module.prop

if [ ! -x "$TS" ]; then
  desc="❌ 未安装"
elif ! pidof tailscaled >/dev/null 2>&1; then
  desc="❌ 未运行"
else
  ver=$($TS --version 2>/dev/null | head -1)
  line=$($TS --socket="$TS_DIR/sock" status 2>/dev/null | head -1)
  if echo "$line" | grep -q "^100\."; then
    ip=$(echo "$line" | awk '{print $1}')
    host=$(echo "$line" | awk '{print $2}')
    online=$($TS --socket="$TS_DIR/sock" status --json 2>/dev/null | grep -c '"Online": true')
    desc="✅ 已连接 | $host | $ip | ${online} 个在线 | v$ver"
  elif echo "$line" | grep -qi "logged out\|NeedsLogin\|not logged"; then
    desc="⚠️ 需要登录 | v$ver"
  else
    desc="🔄 启动中 | v$ver"
  fi
fi
sed -i "s#^description=.*#description=$desc#" "$PROP"
