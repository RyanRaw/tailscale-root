#!/system/bin/sh
# Offline installer for the bundled (prebuilt) Tailscale binaries.
#   sh install_bins.sh           auto-sync: only when missing or when the module shipped a new bundle
#   sh install_bins.sh --force   always reinstall from the bundled copy
#   sh install_bins.sh --info    machine-readable status for the WebUI
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
BIN_DIR="$TS_DIR/bin"
BUNDLE_DIR="$MODDIR/bins"
MODE="$1"

# ---- architecture ----------------------------------------------------------
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
# version that the module itself last deployed; empty = bins are user-managed
MVER=$(head -1 "$BIN_DIR/.managed_version" 2>/dev/null | tr -d ' \r\n')
INST=""
[ -x "$BIN_DIR/tailscale" ] && INST=$("$BIN_DIR/tailscale" --version 2>/dev/null | head -1 | awk '{print $1}')

AVAILABLE=0
[ -n "$ARCH" ] && [ -f "$SRC/tailscale" ] && [ -f "$SRC/tailscaled" ] && AVAILABLE=1

# bins that were not deployed by the module (self-built / manually installed)
CUSTOM=0
CUSTOM_SRC=""
if [ -n "$INST" ] && [ -z "$MVER" ]; then
  CUSTOM=1
  CUSTOM_SRC=$(sed -n 's/^src=//p' "$BIN_DIR/.custom" 2>/dev/null | head -1)
fi

if [ "$MODE" = "--info" ]; then
  # 不可用时给出原因，让 WebUI 能说清是"这个包没带二进制"还是"架构对不上"
  REASON=""
  if [ "$AVAILABLE" != "1" ]; then
    if [ -z "$ARCH" ]; then
      REASON="arch"
    elif [ ! -d "$BUNDLE_DIR/$ARCH" ]; then
      REASON="missing"
    else
      REASON="incomplete"
    fi
  fi
  echo "ARCH=$ARCH"
  echo "BUNDLED=$BVER"
  echo "MANAGED=$MVER"
  echo "INSTALLED=$INST"
  echo "AVAILABLE=$AVAILABLE"
  echo "REASON=$REASON"
  echo "CUSTOM=$CUSTOM"
  echo "CUSTOM_SRC=$CUSTOM_SRC"
  exit 0
fi

if [ "$AVAILABLE" != "1" ]; then
  echo "✗ 无内置二进制：bins/${ARCH:-unknown} 缺失"
  exit 2
fi
if [ -z "$BVER" ]; then
  echo "✗ 内置版本号缺失"
  exit 2
fi

# ---- decide ----------------------------------------------------------------
NEED=0
if [ "$MODE" = "--force" ]; then
  NEED=1
elif [ ! -x "$BIN_DIR/tailscale" ] || [ ! -x "$BIN_DIR/tailscaled" ]; then
  NEED=1
  [ -f "$BIN_DIR/.custom" ] && echo "⚠ 之前的自定义二进制不存在了，改用内置版本…"
  echo "未检测到已安装二进制，使用内置版本…"
elif [ -n "$MVER" ] && [ "$MVER" = "$INST" ] && [ "$BVER" != "$INST" ]; then
  NEED=1
  echo "内置版本 $BVER 与已安装 $INST 不同，更新…"
fi

if [ "$NEED" = "1" ]; then
  if pgrep -x tailscaled >/dev/null 2>&1; then
    echo "停止 tailscaled…"
    pkill -x tailscaled 2>/dev/null
    i=0
    while pgrep -x tailscaled >/dev/null 2>&1 && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
  fi
  rm -f "$TS_DIR/sock" "$TS_DIR/tailscaled.pid"

  mkdir -p "$BIN_DIR"
  rm -f "$BIN_DIR/tailscale.new" "$BIN_DIR/tailscaled.new"
  echo "复制内置二进制 ($ARCH $BVER)…"
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
  # rename swap: avoids "text file busy" on a running daemon
  mv -f "$BIN_DIR/tailscale.new" "$BIN_DIR/tailscale" || exit 3
  mv -f "$BIN_DIR/tailscaled.new" "$BIN_DIR/tailscaled" || exit 3
  echo "$BVER" > "$BIN_DIR/.managed_version"
  rm -f "$BIN_DIR/.custom"
fi

# tsdns：本地 DNS 转发器。静态 tailscaled 在 Android 上唯一的解析途径
# （/etc/resolv.conf 缺失时 Go 退回 127.0.0.1:53），独立于上面的版本升级逻辑。
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
echo "✓ 当前二进制: ${VER:-$BVER}"
