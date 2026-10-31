#!/system/bin/sh
# Bring the backend up / start login, honouring the self-hosted control server
# settings from /data/adb/tailscale/env:
#   TS_LOGIN_SERVER  e.g. https://headscale.example.com   (empty = Tailscale SaaS)
#   TS_AUTHKEY       pre-auth key, skips the interactive login
#   TS_UP_ARGS       extra `tailscale up` flags, e.g. --advertise-routes=...
# 换控制面（自建 <-> 官方）不用再手工加 --reset：下面会比较 prefs 里存着的
# ControlURL，不一致时自动带上 --reset --force-reauth。
TS_DIR=/data/adb/tailscale
SOCK="$TS_DIR/sock"
OFFICIAL=https://controlplane.tailscale.com

TS_LOGIN_SERVER=""; TS_AUTHKEY=""; TS_UP_ARGS=""
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"

# 空 = 官方 SaaS。以前这里直接不传 --login-server，但 `tailscale up` 不带这个
# 参数只会沿用 prefs 里存着的 ControlURL —— 于是"清空自建地址 + 重启"永远切
# 不回官方，daemon 继续连 headscale。
DESIRED="${TS_LOGIN_SERVER:-$OFFICIAL}"

current_control() {
  # 读不到就返回空。调用方把空当"未知"：宁可这次不切，也不要在误判时用
  # --reset 把登录态清掉（状态文件里的 ControlURL 是 base64 编码的 profile，
  # 多 profile 时按它取会取错，所以不做那层兜底）。
  # localapi 卡住时 debug prefs 同样不返回，读不到就当"未知"处理
  timeout 8 "$TS_DIR/bin/tailscale" --socket="$SOCK" debug prefs 2>/dev/null \
    | sed -n 's/.*"ControlURL"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# service.sh 用这个判断要不要在开机时自愈（避免两边各写一份解析逻辑）
[ "$1" = "--current" ] && { current_control; echo; exit 0; }

# 换控制面必须 --reset --force-reauth：tailscaled 会直接拒绝
# "can't change --login-server without --force-reauth"，而 force-reauth 顺手把旧
# 控制面（headscale）的登录态作废，reset 再清掉它残留的偏好，避免带着旧设置连官方。
RESET_ARG=""
CUR_CONTROL=$(current_control)
# 只有确知不一致才动登录态；读不到（空）就不切，避免误清
if [ -n "$CUR_CONTROL" ] && [ "$CUR_CONTROL" != "$DESIRED" ]; then
  RESET_ARG="--reset --force-reauth"
fi

AUTH_ARG=""
[ -n "$TS_AUTHKEY" ] && AUTH_ARG="--authkey=$TS_AUTHKEY"

# word splitting of AUTH_ARG / RESET_ARG / TS_UP_ARGS is intentional
exec "$TS_DIR/bin/tailscale" --socket="$SOCK" up \
  --accept-routes --accept-dns=false \
  --login-server="$DESIRED" \
  $AUTH_ARG $RESET_ARG $TS_UP_ARGS
