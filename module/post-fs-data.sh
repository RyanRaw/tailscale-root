#!/system/bin/sh
TS_DIR=/data/adb/tailscale
MODDIR=${0%/*}
mkdir -p "$TS_DIR/bin" "$TS_DIR/state" "$TS_DIR/log"
chmod 755 "$TS_DIR" "$TS_DIR/bin" "$TS_DIR/state" "$TS_DIR/log"

# Deploy the bundled binaries when missing or when the module shipped a new
# bundle. This is a no-op (a few stats + one --version call) once installed,
# so it does not affect boot time.
sh "$MODDIR/install_bins.sh" >"$TS_DIR/log/install_bins.log" 2>&1
