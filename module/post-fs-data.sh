#!/system/bin/sh
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
mkdir -p "$TS_DIR/bin" "$TS_DIR/state" "$TS_DIR/log"
chmod 755 "$TS_DIR" "$TS_DIR/bin" "$TS_DIR/state" "$TS_DIR/log"

# 留一份干净的 module.prop 副本，供 update_desc.sh 在正式文件被写坏（异常重启后
# 整份变成 \0）时整份重建。每次开机都从模块目录刷新，升级后版本号自动跟上。
cp -f "$MODDIR/module.prop" "$TS_DIR/module.prop.default" 2>/dev/null

# Deploy the bundled binaries when missing or when the module shipped a new
# bundle. This is a no-op (a few stats + one --version call) once installed,
# so it does not affect boot time.
sh "$MODDIR/install_bins.sh" >"$TS_DIR/log/install_bins.log" 2>&1
