#!/system/bin/sh
# Install a self-built / third-party tailscaled (and optionally the tailscale CLI).
#   sh install_custom.sh /sdcard/Download/tailscaled
#   sh install_custom.sh /sdcard/Download/ts/            # dir with tailscaled [+ tailscale]
#   sh install_custom.sh /sdcard/Download/tailscaled --cli /sdcard/Download/tailscale
#   sh install_custom.sh --delete                        # 删除外置安装，回滚内置
# Custom binaries are adopted as "user managed": the module never overwrites them
# on boot, and "安装内置" in the WebUI restores the bundled build.
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
BIN_DIR="$TS_DIR/bin"
SRC=""
CLI_SRC=""
DEL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --cli)    shift; CLI_SRC="$1" ;;
    --delete) DEL=1 ;;
    *)        [ -z "$SRC" ] && SRC="$1" ;;
  esac
  shift
done

# ---- 删除外置安装 ----------------------------------------------------------
# 外置/自定义安装是"用户自管"的：模块不会覆盖它，但也没有别的入口把它去掉。
# 这里统一处理：停 daemon → 删掉 bin 下的外置副本与标记 → 有内置包就回滚，
# 顺带清掉留在外置存储上的来源文件（那是用户最想删的，安装时只被复制了一份）。
if [ "$DEL" = "1" ]; then
  if [ ! -f "$BIN_DIR/.custom" ]; then
    echo "✗ 当前不是外置安装，无需删除"
    exit 0
  fi
  SRC_FILE=$(sed -n 's/^src=//p' "$BIN_DIR/.custom" 2>/dev/null | head -1)
  CLI_FILE=$(sed -n 's/^cli=//p' "$BIN_DIR/.custom" 2>/dev/null | head -1)

  if pgrep -x tailscaled >/dev/null 2>&1; then
    echo "停止 tailscaled…"
    pkill -x tailscaled 2>/dev/null
    i=0
    while pgrep -x tailscaled >/dev/null 2>&1 && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
  fi
  rm -f "$TS_DIR/sock" "$TS_DIR/tailscaled.pid"

  rm -f "$BIN_DIR/tailscaled" "$BIN_DIR/.custom"
  # CLI 只在当初确实被外置 CLI 替换过时才删，否则它可能还是内置那份
  [ -n "$CLI_FILE" ] && rm -f "$BIN_DIR/tailscale"
  echo "✓ 已删除外置二进制副本"

  # 来源文件只在外置存储/临时目录里删；模块目录、系统路径一律不动
  purge_src() {
    case "$1" in
      "") : ;;
      /sdcard/*|/storage/*|/mnt/media_rw/*|/mnt/user/*|/data/local/tmp/*)
        if [ -f "$1" ]; then
          rm -f "$1" && echo "✓ 已删除来源文件 $1"
        else
          echo "· 来源文件已不存在：$1"
        fi
        ;;
      *) echo "· 来源文件不在可删除范围，保留：$1" ;;
    esac
  }
  purge_src "$SRC_FILE"
  purge_src "$CLI_FILE"

  # 删完不能留成"未安装"：模块带内置包就直接回滚，否则提示重新安装
  if [ -f "$MODDIR/install_bins.sh" ]; then
    OUT=$(sh "$MODDIR/install_bins.sh" --force 2>&1)
    if [ $? -eq 0 ]; then
      echo "$OUT"
      echo "✓ 已回滚到内置版本"
      TS_SKIP_WAIT=1 sh "$MODDIR/service.sh" >/dev/null 2>&1
      echo "✓ 守护进程已重启"
      exit 0
    fi
  fi
  echo "✗ 回滚失败（当前安装包可能不含内置二进制），请在安装页重新安装"
  exit 3
fi

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

# ---- local package: accept the official .tgz as well -----------------------
SRC_ORIG="$SRC"
CLEANUP_DIR=""
case "$SRC" in
  *.tgz|*.tar.gz)
    CLEANUP_DIR="$BIN_DIR/.unpack"
    rm -rf "$CLEANUP_DIR"
    mkdir -p "$CLEANUP_DIR" || exit 3
    echo "解包 $(basename "$SRC") …"
    if ! tar -xzf "$SRC" -C "$CLEANUP_DIR" 2>/dev/null; then
      rm -rf "$CLEANUP_DIR"
      echo "✗ 解包失败（不是有效的 tar.gz 包）"
      exit 5
    fi
    D=$(find "$CLEANUP_DIR" -type f -name tailscaled 2>/dev/null | head -1)
    C=$(find "$CLEANUP_DIR" -type f -name tailscale 2>/dev/null | head -1)
    if [ -z "$D" ]; then
      rm -rf "$CLEANUP_DIR"
      echo "✗ 压缩包内未找到 tailscaled"
      exit 5
    fi
    [ -z "$CLI_SRC" ] && [ -n "$C" ] && CLI_SRC="$C"
    SRC="$D"
    ;;
esac

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

# Point the hosts path at /data/host before going live: Android's /etc/hosts has
# only localhost and /etc/resolv.conf cannot exist on a read-only /system.
sh "$MODDIR/ts_hosts.sh" --patch "$TMP_D" >/dev/null 2>&1
[ -n "$CLI_SRC" ] && sh "$MODDIR/ts_hosts.sh" --patch "$TMP_C" >/dev/null 2>&1

# rename swap keeps "text file busy" away and is atomic for path lookups
mv -f "$TMP_D" "$BIN_DIR/tailscaled" || { echo "✗ 替换 tailscaled 失败"; exit 3; }
if [ -n "$CLI_SRC" ]; then
  mv -f "$TMP_C" "$BIN_DIR/tailscale" || { echo "✗ 替换 tailscale 失败"; exit 3; }
fi

# user-owned build: the module must not replace it on boot
rm -f "$BIN_DIR/.managed_version"
{
  echo "src=$(printf '%s' "$SRC_ORIG")"
  # 记下是否替换过 CLI，--delete 时只删被替换过的那份
  [ -n "$CLI_SRC" ] && echo "cli=$(printf '%s' "$CLI_SRC")"
  echo "time=$(date '+%F %T')"
} > "$BIN_DIR/.custom"
[ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"

echo "✓ 已安装自定义 tailscaled（模块更新不会覆盖它）"
echo "  重启守护进程后生效；如自建版本需要额外参数，"
echo "  可在设置页的 TS_EXTRA_ARGS 中补充。"
echo "  恢复官方内置版本：安装页「安装内置」"
