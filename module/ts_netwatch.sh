#!/system/bin/sh
# 网络变化事件驱动：路由或接口地址一变，就重新解析控制服务器。
#
# 为什么不用定时轮询：换 Wi-Fi、切蜂窝、飞行模式恢复，内核都会通过 netlink
# 广播 RTM_NEWROUTE / RTM_NEWADDR，这里接住事件即可，既及时又没有空转开销。
# 只有 monitor 自己挂掉时才会退化成 10 秒重试。
#
# 注意：tailscaled 自己也监听 netlink，网络一变就会重连。它重连时会重新解析
# 域名，如果这时 /data/host 还是旧 IP，这一轮会失败，下一轮重试才拿到新地址。
# 所以这里越早刷新越好，节流窗口别开太大（默认 8 秒）。
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
HOSTS=/data/host

last=0

refresh() {
  now=$(date +%s 2>/dev/null || echo 0)
  # 一次换网会连着刷出几十条事件，节流成一次
  [ $((now - last)) -lt 8 ] && return 0
  last=$now
  sh "$MODDIR/ts_hosts.sh" --hosts >/dev/null 2>&1
}

while true; do
  # 只监听路由：换网必然伴随默认路由的增删，而邻居表/策略规则的抖动与解析
  # 无关，混进来只会让 read 循环被无关事件刷屏。
  # 注意 `ip monitor route address` 这种多对象写法在这个 ip 实现里会被拒，
  # 进程会立刻退出，导致"监听还活着但从不触发"。
  ip monitor route 2>/dev/null | while read -r line; do
    refresh
  done
  # monitor 退出（被 SELinux 拒、内核不支持）时不要空转
  sleep 10
done
