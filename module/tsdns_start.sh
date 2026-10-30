#!/system/bin/sh
# 域名解析兜底（默认不启用）。
#
# 首选路径是官方二进制自带的 androiddns 特性（1.104+）：它直接说 dnsproxyd
# 协议，和 bionic getaddrinfo 同一条路，自带 per-network DNS 与 Private DNS，
# 既不读 /etc/resolv.conf，也不占用任何端口。
#
# 只有在 androiddns 不可用时才需要本脚本：老版本二进制，或 ROM 没有
# /dev/socket/dnsproxyd。那时 Go 运行时会退回
#   defaultNS = ["127.0.0.1:53", "[::1]:53"]   (src/net/dnsconfig.go)
# 于是这里在回环上起一个转发器顶上。启用方式：env 里 TS_DNS_FALLBACK=1。
#
# 端口礼让：只监听回环 127.0.0.1，不碰 0.0.0.0 / 局域网。若该端口已被别的
# 程序（如 dnsmasq、AdGuard、某些代理模块）占用，直接让位不抢占 —— 对方是
# 可用 DNS 时 tailscaled 照样能解析；对方不是的话，日志里会留一行痕迹。
# 守护进程停止时 svm_guard 会把它一起收掉，端口随之释放。
TS_DIR=/data/adb/tailscale
MODDIR=/data/adb/modules/tailscale_root
LOG=$TS_DIR/log/tsdns.log

[ -e /etc/resolv.conf ] && exit 0
[ -x "$TS_DIR/bin/tsdns" ] || exit 0
pgrep -x tsdns >/dev/null 2>&1 && exit 0

TS_DNS_UPSTREAM="223.5.5.5:53,119.29.29.29:53"
TS_DNS_DISABLE=0
TS_DNS_FALLBACK=0
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"

# 默认关闭：1.104+ 的官方二进制自带 androiddns 特性，会直接说 dnsproxyd 协议
# （与 bionic getaddrinfo 同一条路），既不需要 resolv.conf，也不需要占回环 53。
# 只有在这条路不可用时才需要本兜底（老版本二进制、或 ROM 没有 dnsproxyd）：
#   env 里写 TS_DNS_FALLBACK=1
[ "$TS_DNS_FALLBACK" = "1" ] || exit 0
[ "$TS_DNS_DISABLE" = "1" ] && exit 0
[ -z "$TS_DNS_UPSTREAM" ] && TS_DNS_UPSTREAM="223.5.5.5:53,119.29.29.29:53"

# local address 为 127.0.0.1:53 或 0.0.0.0:53 才算占用（不误判以 53 为对端口的客户端）
if grep -Eq '(0100007F|00000000):0035' /proc/net/udp /proc/net/tcp 2>/dev/null; then
  echo "$(date '+%F %T') 127.0.0.1:53 already in use, skip" >>"$LOG"
  exit 0
fi

nohup "$TS_DIR/bin/tsdns" \
  -listen 127.0.0.1:53 \
  -upstream "$TS_DNS_UPSTREAM" \
  -v \
  </dev/null >>"$LOG" 2>&1 &
echo "$(date '+%F %T') started tsdns (pid $!) upstream=$TS_DNS_UPSTREAM" >>"$LOG"
exit 0
