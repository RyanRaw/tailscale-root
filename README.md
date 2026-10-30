# Tailscale Root

A KernelSU / Magisk / APatch module that runs [Tailscale](https://tailscale.com) as a standalone root daemon on Android, with a built-in WebUI for management.

## Features

- **Root daemon**: Runs `tailscaled` directly as root — no VPN service slot needed
- **Bundled binaries**: official `tailscale` / `tailscaled` (arm64) ship inside the module and are deployed on boot — no network needed
- **WebUI**: Full management interface accessible from KernelSU Manager
  - Status overview with real-time uptime counter
  - Peer list with latency testing (progressive bar chart)
  - Bundled installer with optional online updater (non-blocking, background download)
  - Log viewer with level-based coloring
  - Settings: theme switching + Tailscale env configuration
  - Privacy toggle for sensitive info (IP, username)
  - KSU module description auto-updates with connection status
- **Box for Root integration**: Auto-detects mihomo HTTP proxy for control plane egress
- **src_valid_mark guard**: Prevents tailscaled from breaking tproxy-based proxy modules
- **Wake lock**: Optional CPU wake lock to prevent deep sleep data plane stalls
- **One-tap toggle**: KSU Action button to start/stop tailscaled

## Installation

1. Download the latest release zip
2. Install via KernelSU / Magisk / APatch manager
3. Reboot — the bundled binaries are deployed to `/data/adb/tailscale/bin/` automatically
4. Open the module WebUI from KernelSU Manager to configure and connect

Binaries are synced again on boot only when the module ships a new bundled
version; a binary you installed yourself (via the WebUI online installer) is
left untouched.

## Configuration

Edit `/data/adb/tailscale/env` to customize:

```sh
TS_PROXY="http://127.0.0.1:7890"  # HTTP proxy for control plane / DERP
TS_PORT="41641"                    # WireGuard listen port
TS_HOSTNAME="my-phone"             # Override auto-detected hostname
TS_WAKELOCK="1"                    # Hold CPU wake lock (1=on, 0=off)
TS_TUN="tailscale0"                # TUN interface name
TS_EXTRA_ARGS=""                   # extra tailscaled flags, e.g. --netfilter-mode=off
TS_DAEMON=""                       # daemon path override (empty = /data/adb/tailscale/bin/tailscaled)
```

These can also be edited from the WebUI Settings page.

## Self-built / third-party tailscaled

The module can run your own daemon build (patches, `--netfilter-mode=off`,
userspace networking, …):

- **WebUI** → Install page → *自定义二进制*: enter the path of `tailscaled` on the
  device (e.g. `/sdcard/Download/tailscaled`) or of a directory containing
  `tailscaled` (and optionally `tailscale`), then tap *安装自定义*. The binary is
  copied to `/data/adb/tailscale/bin/`, verified by running it (`--version`, so
  architecture mismatches are rejected) and the daemon is restarted.
- **Shell**: `sh /data/adb/modules/tailscale_root/install_custom.sh /sdcard/Download/tailscaled [--cli /sdcard/Download/tailscale]`

A custom binary is marked user-managed (`bin/.custom`): module updates never
overwrite it. Tap *安装内置* on the same page to return to the bundled build.
Keep the process name `tailscaled` (the installer does this for you) — the
watchdog and the KSU Action toggle match on that name.

Extra flags a custom build needs can be set with `TS_TUN` / `TS_EXTRA_ARGS`.
Note that the WebUI's online installer always pulls the official arm64 build and
marks the result as user-managed too.

## Project Structure

```
module/                 # KSU module files (deployable)
├── module.prop
├── bins/               # Bundled binaries: bins/<arch>/{tailscale,tailscaled,VERSION}
├── install_bins.sh     # Deploys / renews the bundled binaries
├── install_custom.sh   # Installs a self-built tailscaled (user-managed)
├── service.sh          # Daemon launcher + description updater
├── action.sh           # One-tap toggle
├── svm_guard.sh        # src_valid_mark watchdog + health check
├── update_desc.sh      # Module description status updater
├── post-fs-data.sh     # Directory init + bundled binary deploy
└── webroot/index.html  # Built WebUI (single-file)

webui/                  # WebUI source (Vue 3 + Tailwind CSS + DaisyUI)
├── src/
│   ├── composables/useKsu.ts   # KSU exec bridge + state management
│   ├── views/                  # Page components
│   └── ...
├── package.json
└── vite.config.ts
```

## Building the WebUI

```sh
cd webui
npm install
npm run build
cp dist/index.html ../module/webroot/index.html
```

## Module Description

The module automatically updates its description in KernelSU Manager every 30 seconds:

- `✅ 已连接 | hostname | 100.x.x.x | N 个在线 | vX.Y.Z`
- `⚠️ 需要登录 | vX.Y.Z`
- `❌ 未运行`

## License

MIT
