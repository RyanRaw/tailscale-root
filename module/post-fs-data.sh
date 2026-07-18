#!/system/bin/sh
TS_DIR=/data/adb/tailscale
mkdir -p "$TS_DIR/bin" "$TS_DIR/state" "$TS_DIR/log"
chmod 755 "$TS_DIR" "$TS_DIR/bin" "$TS_DIR/state" "$TS_DIR/log"
