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
TS_DIR=/data/adb/tailscale
MODDIR=/data/adb/modules/tailscale_root
LOG=$TS_DIR/log/tsdns.log

[ -e /etc/resolv.conf ] && exit 0
[ -x "$TS_DIR/bin/tsdns" ] || exit 0
pgrep -f "$TS_DIR/bin/tsdns -listen" >/dev/null 2>&1 && exit 0

TS_DNS_UPSTREAM="223.5.5.5:53,119.29.29.29:53"
[ -f "$TS_DIR/env" ] && . "$TS_DIR/env"
[ -z "$TS_DNS_UPSTREAM" ] && TS_DNS_UPSTREAM="223.5.5.5:53,119.29.29.29:53"

nohup "$TS_DIR/bin/tsdns" \
  -listen 127.0.0.1:53 \
  -upstream "$TS_DNS_UPSTREAM" \
  -v \
  </dev/null >>"$LOG" 2>&1 &
echo "$(date '+%F %T') started tsdns (pid $!) upstream=$TS_DNS_UPSTREAM" >>"$LOG"
exit 0
