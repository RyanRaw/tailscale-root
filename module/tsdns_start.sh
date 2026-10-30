#!/system/bin/sh
# 静态 tailscaled 的域名解析兜底。
#
# tailscaled 是 CGO_ENABLED=0 的静态 Go 二进制：它不走 bionic/netd，只读
# /etc/resolv.conf。Android 没有这个文件，Go 运行时于是退回
#   defaultNS = ["127.0.0.1:53", "[::1]:53"]   (src/net/dnsconfig.go)
# 在这个地址上放一个转发器，解析立刻可用，且不需要改动 /system 下任何文件。
#
# 部分 ROM（HyperOS / ColorOS）的 /system/etc 已存在嵌套 overlay，内核会拒绝
# 模块叠加新文件（EINVAL），所以这里不再依赖 system/etc/resolv.conf 是否生效。
#
# 幂等：进程已在运行、或 /etc/resolv.conf 真的存在（系统原生支持）时直接返回。
#
# 端口礼让：只监听回环 127.0.0.1，不碰 0.0.0.0 / 局域网。若该端口已被别的
# 程序（如 dnsmasq、AdGuard、某些代理模块）占用，直接让位不抢占 —— 对方是
# 可用 DNS 时 tailscaled 照样能解析；对方不是的话，日志里会留一行痕迹。
# 守护进程停止时 svm_guard 会把它一起收掉，端口随之释放。
# 完全不想用它：env 里写 TS_DNS_DISABLE=1。
TS_DIR=/data/adb/tailscale
MODDIR=/data/adb/modules/tailscale_root
LOG=$TS_DIR/log/tsdns.log

[ -e /etc/resolv.conf ] && exit 0
[ -x "$TS_DIR/bin/tsdns" ] || exit 0
pgrep -x tsdns >/dev/null 2>&1 && exit 0

TS_DNS_UPSTREAM="223.5.5.5:53,119.29.29.29:53"
TS_DNS_DISABLE=0
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"
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
