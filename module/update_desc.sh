#!/system/bin/sh
TS_DIR=/data/adb/tailscale
TS="$TS_DIR/bin/tailscale"
PROP=/data/adb/modules/tailscale_root/module.prop
DEFAULT="$TS_DIR/module.prop.default"

# module.prop 是管理器读取 id/name/version/author 的唯一来源，而本脚本每 30 秒
# 改写它一次。麻烦在于 /data 常见挂载是 f2fs + fsync_mode=nobarrier —— 异常重启
# （掉电、kernel panic）后，刚写进去的数据块可能没落盘：inode 大小还在，内容变成
# 一整片 \0，管理器里 id/版本/作者全部显示 unknown。而且原来的 sed 只会替换
# ^description= 行，在全 0 文件里永远匹配不到，于是每轮都原样写回一堆 0 —— 自己
# 永远好不了，只能手动救。
# 因此这里三件事：① 每轮先看文件还认不认得出来，坏了就整份重建；
# ② 内容没变就不写（空闲时完全不碰磁盘，把风险窗口从每天 2880 次降到 0）；
# ③ 写入改成 temp + rename，避免读到半截文件。

if [ ! -s "$PROP" ] || ! grep -q '^id=' "$PROP" 2>/dev/null; then
  if [ -s "$DEFAULT" ] && grep -q '^id=' "$DEFAULT" 2>/dev/null; then
    cat "$DEFAULT" > "$PROP"
  else
    # 兜底：默认副本也坏了/不存在时，至少把身份信息写回来
    printf 'id=tailscale_root\nname=Tailscale Root\nversion=v0.6.5\nversionCode=17\nauthor=Lxns\ndescription=\n' > "$PROP"
  fi
  sync
  [ -s "$PROP" ] || exit 0
fi

if [ ! -x "$TS" ]; then
  desc="❌ 未安装"
elif ! pidof tailscaled >/dev/null 2>&1; then
  desc="❌ 未运行"
else
  # localapi 卡住时 status 会一直不返回（控制面 long-poll 断开后实测会出现）：
  # 这里不设上限的话，整个 30s 刷新循环就被永久钉死，而且每轮还会再多留一个
  # 挂死的 CLI 进程，最后 WebUI / route_guard 全部转圈。所以一律过 timeout。
  ver=$(timeout 8 $TS --version 2>/dev/null | head -1)
  line=$(timeout 8 $TS --socket="$TS_DIR/sock" status 2>/dev/null | head -1)
  if echo "$line" | grep -q "^100\."; then
    ip=$(echo "$line" | awk '{print $1}')
    host=$(echo "$line" | awk '{print $2}')
    online=$(timeout 8 $TS --socket="$TS_DIR/sock" status --json 2>/dev/null | grep -c '"Online": true')
    desc="✅ 已连接 | $host | $ip | ${online} 个在线 | v$ver"
  elif echo "$line" | grep -qi "logged out\|NeedsLogin\|not logged"; then
    desc="⚠️ 需要登录 | v$ver"
  else
    desc="🔄 启动中 | v$ver"
  fi
fi

# 内容没变就一个字节都不写：空闲设备上这条 path 每 30 秒都会命中，
# 这正是那份 164 字节 \0 文件的成因。
tmp="$PROP.tmp.$$"
{ grep -v '^description=' "$PROP"; printf 'description=%s\n' "$desc"; } > "$tmp" 2>/dev/null
if [ -s "$tmp" ] && ! cmp -s "$tmp" "$PROP"; then
  mv -f "$tmp" "$PROP"
  sync
else
  rm -f "$tmp"
fi
