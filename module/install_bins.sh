#!/system/bin/sh
# 离线包部署器 —— 只负责"没有二进制时兜底装一个"。
#
# 单一版本原则：本模块只维护 $TS_DIR/bin 里的那一份 tailscaled / tailscale。
# 它从哪来（离线包 / 在线下载 / 本地文件）只作为信息记在 bin/.installed 里，不再
# 分"内置"和"外置"两套状态。因此这里的默认行为是**只补缺、绝不覆盖**：
# 只要已经有一份能跑的二进制，开机就不动它 —— 你在线装的、本地装的新版本不会在
# 重启后被离线包顶回去。
#
#   sh install_bins.sh           开机兜底：没有可用二进制时才部署离线包
#   sh install_bins.sh --force   显式用离线包覆盖当前版本（清锁定）
#   sh install_bins.sh --info    给 WebUI 的机器可读状态
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
BIN_DIR="$TS_DIR/bin"
BUNDLE_DIR="$MODDIR/bins"
STATE="$BIN_DIR/.installed"
MODE="$1"

# ---- 架构 ------------------------------------------------------------------
ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
case "$ABI" in
  arm64-v8a*)            ARCH=arm64 ;;
  armeabi-v7a*|armeabi*) ARCH=arm ;;
  x86_64*)               ARCH=x86_64 ;;
  x86*)                  ARCH=x86 ;;
  *)                     ARCH= ;;
esac
if [ -z "$ARCH" ]; then
  case "$(uname -m 2>/dev/null)" in
    aarch64|arm64) ARCH=arm64 ;;
    armv7*|armv8l) ARCH=arm ;;
    x86_64)        ARCH=x86_64 ;;
  esac
fi

SRC="$BUNDLE_DIR/$ARCH"
BVER=$(head -1 "$SRC/VERSION" 2>/dev/null | tr -d ' \r\n')
INST=""
[ -x "$BIN_DIR/tailscale" ] && INST=$(timeout 8 "$BIN_DIR/tailscale" --version 2>/dev/null | head -1 | awk '{print $1}')

AVAILABLE=0
[ -n "$ARCH" ] && [ -f "$SRC/tailscale" ] && [ -f "$SRC/tailscaled" ] && AVAILABLE=1

state_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -1; }

# ---- 一次性迁移：老的 .managed_version / .custom 折算成统一记录 -------------
if [ ! -s "$STATE" ] && [ -n "$INST" ]; then
  OLD_MVER=$(head -1 "$BIN_DIR/.managed_version" 2>/dev/null | tr -d ' \r\n')
  OLD_SRC=$(sed -n 's/^src=//p' "$BIN_DIR/.custom" 2>/dev/null | head -1)
  if [ -n "$OLD_MVER" ] && [ "$OLD_MVER" = "$INST" ]; then
    SRCKIND=bundle; ORIGIN="offline bundle $OLD_MVER"
  elif [ -f "$BIN_DIR/.custom" ]; then
    SRCKIND=local; ORIGIN="${OLD_SRC:-unknown}"
  else
    SRCKIND=unknown; ORIGIN=""
  fi
  {
    echo "version=$INST"
    echo "source=$SRCKIND"
    echo "origin=$ORIGIN"
    echo "pinned=0"
    echo "time=$(date '+%F %T')"
  } > "$STATE.tmp.$$" 2>/dev/null && mv -f "$STATE.tmp.$$" "$STATE"
  rm -f "$BIN_DIR/.managed_version" "$BIN_DIR/.custom"
fi

CUR_SOURCE=$(state_get source)
CUR_ORIGIN=$(state_get origin)
CUR_PINNED=$(state_get pinned)
[ -n "$CUR_PINNED" ] || CUR_PINNED=0

if [ "$MODE" = "--info" ]; then
  # 不可用时给原因，让 WebUI 能说清是"这个包没带二进制"还是"架构对不上"
  REASON=""
  if [ "$AVAILABLE" != "1" ]; then
    if [ -z "$ARCH" ]; then
      REASON=arch
    elif [ ! -d "$BUNDLE_DIR/$ARCH" ]; then
      REASON=missing
    else
      REASON=incomplete
    fi
  fi
  echo "ARCH=$ARCH"
  echo "BUNDLE=$BVER"
  echo "INSTALLED=$INST"
  echo "SOURCE=$CUR_SOURCE"
  echo "ORIGIN=$CUR_ORIGIN"
  echo "PINNED=$CUR_PINNED"
  echo "AVAILABLE=$AVAILABLE"
  echo "REASON=$REASON"
  exit 0
fi

# ---- 决定要不要部署 --------------------------------------------------------
# 默认只补缺：已经有一份能跑的二进制就一概不动，来源无关
NEED=0
if [ "$MODE" = "--force" ]; then
  NEED=1
  echo "用离线包覆盖当前版本…"
elif [ ! -x "$BIN_DIR/tailscaled" ] || [ ! -x "$BIN_DIR/tailscale" ]; then
  NEED=1
  echo "未检测到可用二进制，部署离线包…"
fi

if [ "$NEED" = "1" ]; then
  if [ "$AVAILABLE" != "1" ]; then
    echo "✗ 无离线包：bins/${ARCH:-unknown} 缺失，无法部署"
    exit 2
  fi
  if [ -z "$BVER" ]; then
    echo "✗ 离线包版本号缺失"
    exit 2
  fi

  if pgrep -x tailscaled >/dev/null 2>&1; then
    echo "停止 tailscaled…"
    pkill -x tailscaled 2>/dev/null
    i=0
    while pgrep -x tailscaled >/dev/null 2>&1 && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
  fi
  rm -f "$TS_DIR/sock" "$TS_DIR/tailscaled.pid"

  mkdir -p "$BIN_DIR"
  rm -f "$BIN_DIR/tailscale.new" "$BIN_DIR/tailscaled.new"
  echo "复制离线包二进制 ($ARCH $BVER)…"
  if ! cp -f "$SRC/tailscale" "$BIN_DIR/tailscale.new"; then
    rm -f "$BIN_DIR/tailscale.new"
    echo "✗ 复制 tailscale 失败"
    exit 3
  fi
  if ! cp -f "$SRC/tailscaled" "$BIN_DIR/tailscaled.new"; then
    rm -f "$BIN_DIR/tailscale.new" "$BIN_DIR/tailscaled.new"
    echo "✗ 复制 tailscaled 失败"
    exit 3
  fi
  chmod 755 "$BIN_DIR/tailscale.new" "$BIN_DIR/tailscaled.new"
  # 静态 Go 二进制只认 /etc/hosts，Android 上那份只有 localhost；先把 hosts 路径
  # 指到 /data/host 再上线
  sh "$MODDIR/ts_hosts.sh" --patch "$BIN_DIR/tailscale.new" >/dev/null 2>&1
  sh "$MODDIR/ts_hosts.sh" --patch "$BIN_DIR/tailscaled.new" >/dev/null 2>&1
  # rename 交换：避免运行中的 daemon 撞 "text file busy"
  mv -f "$BIN_DIR/tailscale.new" "$BIN_DIR/tailscale" || exit 3
  mv -f "$BIN_DIR/tailscaled.new" "$BIN_DIR/tailscaled" || exit 3

  {
    echo "version=$BVER"
    echo "source=bundle"
    echo "origin=offline bundle $BVER"
    echo "pinned=0"
    echo "time=$(date '+%F %T')"
  } > "$STATE.tmp.$$" 2>/dev/null && mv -f "$STATE.tmp.$$" "$STATE"
  rm -f "$BIN_DIR/.managed_version" "$BIN_DIR/.custom"
  echo "✓ 已部署离线包 $BVER"
fi

# tsdns：本地 DNS 转发器。静态 tailscaled 在 Android 上唯一的解析途径
# （/etc/resolv.conf 缺失时 Go 退回 127.0.0.1:53），独立于上面的版本逻辑。
if [ -f "$SRC/tsdns" ] && ! cmp -s "$SRC/tsdns" "$BIN_DIR/tsdns" 2>/dev/null; then
  mkdir -p "$BIN_DIR"
  if cp -f "$SRC/tsdns" "$BIN_DIR/tsdns.new"; then
    chmod 755 "$BIN_DIR/tsdns.new"
    mv -f "$BIN_DIR/tsdns.new" "$BIN_DIR/tsdns"
    echo "已部署 tsdns"
  else
    rm -f "$BIN_DIR/tsdns.new"
  fi
fi

VER=$("$BIN_DIR/tailscale" --version 2>/dev/null | head -1)
echo "✓ 当前二进制: ${VER:-未安装}"
