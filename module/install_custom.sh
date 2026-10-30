#!/system/bin/sh
# Install a self-built / third-party tailscaled (and optionally the tailscale CLI).
#   sh install_custom.sh /sdcard/Download/tailscaled
#   sh install_custom.sh /sdcard/Download/ts/            # dir with tailscaled [+ tailscale]
#   sh install_custom.sh /sdcard/Download/tailscaled --cli /sdcard/Download/tailscale
# Custom binaries are adopted as "user managed": the module never overwrites them
# on boot, and "安装内置" in the WebUI restores the bundled build.
TS_DIR=/data/adb/tailscale
BIN_DIR="$TS_DIR/bin"
SRC=""
CLI_SRC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cli) shift; CLI_SRC="$1" ;;
    *)     [ -z "$SRC" ] && SRC="$1" ;;
  esac
  shift
done

if [ -z "$SRC" ]; then
  echo "✗ 用法: install_custom.sh <tailscaled 路径|目录> [--cli <tailscale 路径>]"
  exit 2
fi
if [ -d "$SRC" ]; then
  [ -z "$CLI_SRC" ] && [ -f "$SRC/tailscale" ] && CLI_SRC="$SRC/tailscale"
  SRC="$SRC/tailscaled"
fi
[ -f "$SRC" ] || { echo "✗ 找不到文件: $SRC"; exit 2; }
[ -r "$SRC" ] || { echo "✗ 文件不可读: $SRC"; exit 2; }
if [ -n "$CLI_SRC" ] && [ ! -f "$CLI_SRC" ]; then
  echo "✗ 找不到 CLI: $CLI_SRC"
  exit 2
fi

mkdir -p "$BIN_DIR" || exit 3

# ---- stage + sanity check (arch mismatch / not a tailscaled build) ---------
TMP_D="$BIN_DIR/.incoming.daemon"
TMP_C="$BIN_DIR/.incoming.cli"
rm -f "$TMP_D" "$TMP_C"

echo "复制 $(basename "$SRC") → $TMP_D …"
if ! cp -f "$SRC" "$TMP_D"; then
  rm -f "$TMP_D"
  echo "✗ 复制失败（空间不足或无权限）"
  exit 3
fi
chmod 755 "$TMP_D"

DV=$("$TMP_D" --version 2>&1 | head -1)
case "$DV" in
  *[0-9].[0-9]*) echo "守护进程版本: $DV" ;;
  *)
    rm -f "$TMP_D"
    echo "✗ 该文件无法在此设备运行（架构不匹配或不是 tailscaled）"
    [ -n "$DV" ] && echo "  $DV"
    exit 4
    ;;
esac

if [ -n "$CLI_SRC" ]; then
  echo "复制 $(basename "$CLI_SRC") → $TMP_C …"
  if ! cp -f "$CLI_SRC" "$TMP_C"; then
    rm -f "$TMP_D" "$TMP_C"
    echo "✗ 复制 CLI 失败"
    exit 3
  fi
  chmod 755 "$TMP_C"
  CV=$("$TMP_C" --version 2>&1 | head -1)
  case "$CV" in
    *[0-9].[0-9]*) echo "CLI 版本: $CV" ;;
    *)
      rm -f "$TMP_D" "$TMP_C"
      echo "✗ CLI 无法在此设备运行"
      [ -n "$CV" ] && echo "  $CV"
      exit 4
      ;;
  esac
fi

# ---- swap in ---------------------------------------------------------------
if pgrep -x tailscaled >/dev/null 2>&1; then
  echo "停止 tailscaled…"
  pkill -x tailscaled 2>/dev/null
  i=0
  while pgrep -x tailscaled >/dev/null 2>&1 && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
fi
rm -f "$TS_DIR/sock" "$TS_DIR/tailscaled.pid"

# rename swap keeps "text file busy" away and is atomic for path lookups
mv -f "$TMP_D" "$BIN_DIR/tailscaled" || { echo "✗ 替换 tailscaled 失败"; exit 3; }
if [ -n "$CLI_SRC" ]; then
  mv -f "$TMP_C" "$BIN_DIR/tailscale" || { echo "✗ 替换 tailscale 失败"; exit 3; }
fi

# user-owned build: the module must not replace it on boot
rm -f "$BIN_DIR/.managed_version"
{
  echo "src=$(printf '%s' "$SRC")"
  echo "time=$(date '+%F %T')"
} > "$BIN_DIR/.custom"

echo "✓ 已安装自定义 tailscaled（模块更新不会覆盖它）"
echo "  重启守护进程后生效；如自建版本需要额外参数，"
echo "  可在设置页的 TS_EXTRA_ARGS 中补充。"
echo "  恢复官方内置版本：安装页「安装内置」"
