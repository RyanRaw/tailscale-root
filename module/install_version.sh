#!/system/bin/sh
# 单一版本的安装器。
#
# 本模块只维护**一份** tailscaled / tailscale（$TS_DIR/bin），不区分内置、在线、
# 本地来源 —— 三个入口最终都写同一个位置，来源只作为信息记在 bin/.installed 里。
#
#   sh install_version.sh --online                  装 GitHub 上最新的稳定版
#   sh install_version.sh --online 1.98.8           装指定版本（并锁定）
#   sh install_version.sh --online https://…tgz     装任意 URL 的官方包（并锁定）
#   sh install_version.sh --local /sdcard/Download/tailscaled
#   sh install_version.sh --local /sdcard/Download/ts/          目录（含 tailscaled [+ tailscale]）
#   sh install_version.sh --local pkg.tgz                       官方 .tgz / .tar.gz
#   sh install_version.sh --local <path> --cli <tailscale 路径>  一并替换 CLI
#   sh install_version.sh --pin on|off              只切换"锁定"标记
#
# 锁定（pinned）语义：用户明确指定了版本就不再动它 —— 只有不带版本的"更新到最新"
# 会被 pin 拦住；任何显式的版本 / 文件 / URL 安装，以及 install_bins.sh --force，
# 都是在指定版本，会照做并把 pin 设成对应状态。
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
BIN_DIR="$TS_DIR/bin"
STATE="$BIN_DIR/.installed"
ARCH_DIR="$MODDIR/bins"
LOG_LIMIT=4194304

MODE=""
ARG=""
CLI_SRC=""
PIN_ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --online) MODE=online; shift; case "$1" in ""|--*) ;; *) ARG="$1"; shift ;; esac ;;
    --local)  MODE=local;  shift; ARG="$1"; shift ;;
    --cli)    shift; CLI_SRC="$1"; shift ;;
    --pin)    shift; PIN_ONLY="$1"; shift ;;
    *)        [ -z "$ARG" ] && ARG="$1"; shift ;;
  esac
done

say() { echo "$*"; }

detect_arch() {
  case "$(getprop ro.product.cpu.abi 2>/dev/null)" in
    arm64-v8a*)            echo arm64 ;;
    armeabi-v7a*|armeabi*) echo arm ;;
    x86_64*)               echo x86_64 ;;
    x86*)                  echo x86 ;;
    *)                     uname -m 2>/dev/null | sed -e 's/^aarch64$/arm64/' -e 's/^armv.*/arm/' ;;
  esac
}
ARCH=$(detect_arch)

write_state() { # version source origin pinned
  mkdir -p "$BIN_DIR" 2>/dev/null
  {
    echo "version=$1"
    echo "source=$2"
    echo "origin=$3"
    echo "pinned=$4"
    echo "time=$(date '+%F %T')"
  } > "$STATE.tmp.$$" 2>/dev/null && mv -f "$STATE.tmp.$$" "$STATE"
  # 老标记不再使用，装完清掉，避免两套记录打架
  rm -f "$BIN_DIR/.managed_version" "$BIN_DIR/.custom"
}

installed_version() {
  [ -x "$BIN_DIR/tailscale" ] || return 0
  timeout 8 "$BIN_DIR/tailscale" --version 2>/dev/null | head -1 | awk '{print $1}'
}

state_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -1; }

# ---- 只切换锁定标记 --------------------------------------------------------
if [ -n "$PIN_ONLY" ]; then
  VER=$(installed_version)
  [ -n "$VER" ] || { say "✗ 尚未安装二进制，无从锁定"; exit 2; }
  CUR_SRC=$(state_get source); [ -n "$CUR_SRC" ] || CUR_SRC=unknown
  CUR_ORIGIN=$(state_get origin)
  case "$PIN_ONLY" in
    on)  write_state "$VER" "$CUR_SRC" "$CUR_ORIGIN" 1; say "✓ 已锁定 $VER（更新到最新不会覆盖它）" ;;
    off) write_state "$VER" "$CUR_SRC" "$CUR_ORIGIN" 0; say "✓ 已解除锁定 $VER" ;;
    *)   say "✗ --pin 只接受 on / off"; exit 2 ;;
  esac
  exit 0
fi

[ -n "$MODE" ] || { say "✗ 用法: install_version.sh --online [版本|URL] | --local <路径> [--cli <路径>] | --pin on|off"; exit 2; }

# ---- 决定要装什么、从哪里装、装完 pin 成什么 -------------------------------
WANT_PIN=1        # 显式指定版本 → 默认锁定
ORIGIN=""
URL=""
case "$MODE" in
  online)
    case "$ARG" in
      "")
        LATEST=$(curl -sL --max-time 15 https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null | grep '"tag_name"' | head -1 | sed -e 's/.*"v\{0,1\}\([0-9.]*\)".*/\1/')
        [ -n "$LATEST" ] || LATEST=$(curl -sL --max-time 15 -x http://127.0.0.1:7890 --http1.1 https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null | grep '"tag_name"' | head -1 | sed -e 's/.*"v\{0,1\}\([0-9.]*\)".*/\1/')
        [ -n "$LATEST" ] || { say "✗ 拿不到最新版本号（网络不通？）"; exit 4; }
        say "最新版本: $LATEST"
        VER="$LATEST"
        WANT_PIN=0          # "更新到最新"不该把自己锁住，否则下次就不动了
        ;;
      http://*|https://*|file://*)
        URL="$ARG"
        VER=""
        ;;
      *)
        VER=$(printf '%s' "$ARG" | sed -e 's/^v//')
        ;;
    esac
    ORIGIN="${URL:-$VER}"
    [ -n "$URL" ] || URL="https://pkgs.tailscale.com/stable/tailscale_${VER}_${ARCH}.tgz"
    ;;
  local)
    [ -n "$ARG" ] || { say "✗ 缺少文件路径"; exit 2; }
    [ -e "$ARG" ] || { say "✗ 找不到: $ARG"; exit 2; }
    ORIGIN="$ARG"
    WANT_PIN=1
    ;;
esac

# ---- 锁定的版本不会被"更新到最新"覆盖 -------------------------------------
# 这里是脚本层的兜底（WebUI 上那按钮也会变灰）：只要你指定过版本，自动更新就
# 不该悄悄把它换掉。换成别的版本必须显式操作，或先解除锁定。
if [ "$WANT_PIN" = "0" ]; then
  CURPIN=$(sed -n 's/^pinned=//p' "$STATE" 2>/dev/null | head -1)
  CURVER=$(installed_version)
  if [ "$CURPIN" = "1" ] && [ -n "$CURVER" ]; then
    say "✗ 当前版本 $CURVER 已锁定（指定版本不会被自动更新覆盖）"
    say "  确实要更新到最新请先解除锁定：install_version.sh --pin off"
    exit 6
  fi
fi

# ---- 下载（仅 online）------------------------------------------------------
TMP_TGZ="$TS_DIR/dl.tgz"
SRC_FILE=""
UNPACK_DIR=""
cleanup() {
  rm -f "$TMP_TGZ"
  [ -n "$UNPACK_DIR" ] && rm -rf "$UNPACK_DIR"
}
if [ "$MODE" = "online" ]; then
  say "下载: $URL"
  rm -f "$TMP_TGZ"
  if ! curl -fL --max-time 180 -o "$TMP_TGZ" "$URL" 2>&1 | tail -2; then
    say "直连失败，改走本机代理重试…"
    rm -f "$TMP_TGZ"
    if ! curl -fL --max-time 180 -x http://127.0.0.1:7890 --http1.1 -o "$TMP_TGZ" "$URL" 2>&1 | tail -2; then
      say "✗ 下载失败（$URL）"
      exit 4
    fi
  fi
  [ -s "$TMP_TGZ" ] || { say "✗ 下载结果为空"; exit 4; }
  say "✓ 下载完成"
  SRC_FILE="$TMP_TGZ"
else
  SRC_FILE="$ARG"
fi

# ---- 本地包也可能是官方 .tgz ----------------------------------------------
case "$SRC_FILE" in
  *.tgz|*.tar.gz)
    UNPACK_DIR="$BIN_DIR/.unpack"
    rm -rf "$UNPACK_DIR"
    mkdir -p "$UNPACK_DIR" || { say "✗ 无法创建解包目录"; exit 3; }
    say "解包 $(basename "$SRC_FILE") …"
    if ! tar -xzf "$SRC_FILE" -C "$UNPACK_DIR" 2>/dev/null; then
      say "✗ 解包失败（不是有效的 tar.gz 包）"
      cleanup
      exit 5
    fi
    D=$(find "$UNPACK_DIR" -type f -name tailscaled 2>/dev/null | head -1)
    C=$(find "$UNPACK_DIR" -type f -name tailscale 2>/dev/null | head -1)
    [ -n "$D" ] || { say "✗ 压缩包内未找到 tailscaled"; cleanup; exit 5; }
    [ -z "$CLI_SRC" ] && [ -n "$C" ] && CLI_SRC="$C"
    SRC_FILE="$D"
    ;;
esac

# 目录：取里面的 tailscaled（有 tailscale 就一并替换）
if [ -d "$SRC_FILE" ]; then
  [ -z "$CLI_SRC" ] && [ -f "$SRC_FILE/tailscale" ] && CLI_SRC="$SRC_FILE/tailscale"
  SRC_FILE="$SRC_FILE/tailscaled"
fi
[ -f "$SRC_FILE" ] || { say "✗ 找不到文件: $SRC_FILE"; cleanup; exit 2; }
[ -r "$SRC_FILE" ] || { say "✗ 文件不可读: $SRC_FILE"; cleanup; exit 2; }
if [ -n "$CLI_SRC" ] && [ ! -f "$CLI_SRC" ]; then
  say "✗ 找不到 CLI: $CLI_SRC"
  cleanup
  exit 2
fi

# ---- 暂存 + 试运行校验：不合格就原地放弃，不碰现有可用版本 ----------------
mkdir -p "$BIN_DIR" || exit 3
TMP_D="$BIN_DIR/.incoming.daemon"
TMP_C="$BIN_DIR/.incoming.cli"
rm -f "$TMP_D" "$TMP_C"

say "复制 $(basename "$SRC_FILE") → $TMP_D …"
if ! cp -f "$SRC_FILE" "$TMP_D"; then
  rm -f "$TMP_D"; cleanup
  say "✗ 复制失败（空间不足或无权限）"
  exit 3
fi
chmod 755 "$TMP_D"
DV=$("$TMP_D" --version 2>&1 | head -1)
case "$DV" in
  *[0-9].[0-9]*) say "守护进程版本: $DV" ;;
  *)
    rm -f "$TMP_D"; cleanup
    say "✗ 该文件无法在此设备运行（架构不匹配或不是 tailscaled）"
    [ -n "$DV" ] && say "  $DV"
    exit 4
    ;;
esac

if [ -n "$CLI_SRC" ]; then
  say "复制 $(basename "$CLI_SRC") → $TMP_C …"
  if ! cp -f "$CLI_SRC" "$TMP_C"; then
    rm -f "$TMP_D" "$TMP_C"; cleanup
    say "✗ 复制 CLI 失败"
    exit 3
  fi
  chmod 755 "$TMP_C"
  CV=$("$TMP_C" --version 2>&1 | head -1)
  case "$CV" in
    *[0-9].[0-9]*) say "CLI 版本: $CV" ;;
    *)
      rm -f "$TMP_D" "$TMP_C"; cleanup
      say "✗ CLI 无法在此设备运行"
      [ -n "$CV" ] && say "  $CV"
      exit 4
      ;;
  esac
fi

# ---- 换上：停守护进程 → rename 原子替换 → 记状态 → 拉起 --------------------
if pgrep -x tailscaled >/dev/null 2>&1; then
  say "停止守护进程…"
  pkill -x tailscaled 2>/dev/null
  i=0
  while pgrep -x tailscaled >/dev/null 2>&1 && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
  pgrep -x tailscaled >/dev/null 2>&1 && pkill -9 -x tailscaled 2>/dev/null
fi
rm -f "$TS_DIR/sock" "$TS_DIR/tailscaled.pid"

# 静态 Go 二进制只认 /etc/hosts 与 /etc/resolv.conf，两者在 Android 上都不可用，
# 装上之前先把 hosts 路径改到 /data/host
sh "$MODDIR/ts_hosts.sh" --patch "$TMP_D" >/dev/null 2>&1
[ -n "$CLI_SRC" ] && sh "$MODDIR/ts_hosts.sh" --patch "$TMP_C" >/dev/null 2>&1

mv -f "$TMP_D" "$BIN_DIR/tailscaled" || { say "✗ 替换 tailscaled 失败"; cleanup; exit 3; }
if [ -n "$CLI_SRC" ]; then
  mv -f "$TMP_C" "$BIN_DIR/tailscale" || { say "✗ 替换 tailscale 失败"; cleanup; exit 3; }
fi

NEWVER=$(installed_version)
[ -n "$VER" ] && [ -n "$NEWVER" ] && [ "$VER" != "$NEWVER" ] && say "⚠ 请求 $VER，实际装入 $NEWVER"
write_state "${NEWVER:-$VER}" "$([ "$MODE" = online ] && echo online || echo local)" "$ORIGIN" "$WANT_PIN"
cleanup

case "$WANT_PIN" in
  1) say "✓ 已安装 $NEWVER，并锁定（「更新到最新」不会覆盖它）" ;;
  0) say "✓ 已安装 $NEWVER" ;;
esac

say "启动守护进程…"
TS_SKIP_WAIT=1 sh "$MODDIR/service.sh" >/dev/null 2>&1
sleep 3
if pidof tailscaled >/dev/null 2>&1; then
  say "✓ 守护进程已启动"
else
  say "✗ 守护进程未启动，请查看日志页"
fi
