#!/system/bin/sh
# 模块描述刷新。结构照搬 zygisk-module-xfingerprint-pay-all / tricky_store 的成熟
# 做法：一个 watch 循环 + "变了才写" + 整份重写到临时文件再 rename。
#
# 为什么不再用 sed -i 每 30 秒无条件重写：module.prop 是管理器读 id/name/version/
# author 的唯一来源，而 /data 常见挂载是 f2fs + fsync_mode=nobarrier —— 异常重启
# （掉电 / kernel panic）后，刚写进去的数据块可能没落盘：inode 大小还在、内容变成
# 一整片 \0，管理器里 id/版本/作者全部 unknown。sed -i 每次都会新建 inode + 新数据
# 块（实测 inode 会变），等于每 30 秒把文件重新推进一次危险窗口，一天 2880 次。
#
# 三条防线：
#   1) 内容没变就一个字节都不写 —— 空闲设备从每天 2880 次写盘降到 0；
#   2) 写入走 temp + rename + sync，不会留下半截文件；
#   3) 每轮先自检文件还认不认得出来，坏了从 $TS_DIR/module.prop.default 整份重建。
#
# 调用方式：
#   sh update_desc.sh          # 刷一次就退出
#   sh update_desc.sh watch    # 常驻循环（service.sh 用这个）
TS_DIR=/data/adb/tailscale
TS="$TS_DIR/bin/tailscale"
PROP=/data/adb/modules/tailscale_root/module.prop
DEFAULT="$TS_DIR/module.prop.default"
# 探测一次要跑 3 次 tailscale CLI（实测约 370ms），比那些只需读文件的模块贵得多，
# 所以间隔取 60 秒（它们用 15~120 秒，且探针几乎零成本）。
INTERVAL=60

# 自检 + 自愈：文件不存在、或已经不是一份能解析的 module.prop（被写成一整片 \0）
# 时，用开机时留下的干净副本整份重建。
ensure_prop() {
  [ -s "$PROP" ] && grep -q '^id=' "$PROP" 2>/dev/null && return 0
  if [ -s "$DEFAULT" ] && grep -q '^id=' "$DEFAULT" 2>/dev/null; then
    cat "$DEFAULT" > "$PROP"
  else
    # 兜底：默认副本也坏了/不存在时，至少把身份信息写回来
    printf 'id=tailscale_root\nname=Tailscale Root\nversion=v0.6.5\nversionCode=17\nauthor=Lxns\ndescription=\n' > "$PROP"
  fi
  sync
  [ -s "$PROP" ]
}

# 算出当前应该显示的描述，打到 stdout
current_desc() {
  if [ ! -x "$TS" ]; then
    echo "❌ 未安装"
    return
  fi
  if ! pidof tailscaled >/dev/null 2>&1; then
    echo "❌ 未运行"
    return
  fi
  # localapi 卡住时 status 会一直不返回（控制面 long-poll 断开后实测会出现）：
  # 这里不设上限的话，整个刷新循环就被永久钉死，而且每轮还会再多留一个挂死的
  # CLI 进程，最后 WebUI / route_guard 全部转圈。所以一律过 timeout。
  ver=$(timeout 8 $TS --version 2>/dev/null | head -1)
  line=$(timeout 8 $TS --socket="$TS_DIR/sock" status 2>/dev/null | head -1)
  if echo "$line" | grep -q "^100\."; then
    ip=$(echo "$line" | awk '{print $1}')
    host=$(echo "$line" | awk '{print $2}')
    online=$(timeout 8 $TS --socket="$TS_DIR/sock" status --json 2>/dev/null | grep -c '"Online": true')
    echo "✅ 已连接 | $host | $ip | ${online} 个在线 | v$ver"
  elif echo "$line" | grep -qi "logged out\|NeedsLogin\|not logged"; then
    echo "⚠️ 需要登录 | v$ver"
  else
    echo "🔄 启动中 | v$ver"
  fi
}

update_card() {
  ensure_prop || return 1
  desired="description=$(current_desc)"
  # 目标行已经一模一样就什么都不做 —— 空闲时不碰磁盘，这是防写坏的核心
  grep -qxF "$desired" "$PROP" && return 0
  tmp="$PROP.tmp.$$"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      description=*) printf '%s\n' "$desired" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$PROP" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 0644 "$tmp"
  mv -f "$tmp" "$PROP"
  sync
}

if [ "$1" = watch ]; then
  while [ -f "$PROP" ]; do
    update_card
    sleep $INTERVAL
  done
else
  update_card
fi
