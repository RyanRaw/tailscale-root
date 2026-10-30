# Tailscale Root

一个 KernelSU / Magisk / APatch 模块：把 [Tailscale](https://tailscale.com) 以 root 守护进程的方式常驻运行在 Android 上，并附带内置 WebUI 进行管理。

## 特性

- **Root 守护进程**：`tailscaled` 直接以 root 运行，不占用系统 VPN 服务槽位
- **内置二进制**：官方 `tailscale` / `tailscaled`（arm64）随模块打包，开机自动部署，安装与升级全程离线
- **自建二进制**：可装入自己编译或第三方的 `tailscaled`，模块升级不会覆盖它
- **WebUI**：从 KernelSU 管理器直接打开
  - 状态总览（连接状态、账号、节点数、运行时长）
  - 节点列表与延迟测试（渐进式柱状图）
  - 版本管理：内置版本、在线版本、自定义二进制的安装与切换
  - 日志查看（按级别着色）
  - 设置：主题切换 + Tailscale 环境变量
  - 隐私开关（隐藏 IP、用户名）
  - KSU 模块描述随连接状态自动更新
- **Box for Root 集成**：自动探测 mihomo HTTP 代理用于控制面出网
- **src_valid_mark 守卫**：阻止 tailscaled 破坏 tproxy 类代理模块
- **唤醒锁**：可选的 CPU 唤醒锁，避免深度睡眠后数据面卡死
- **一键开关**：KSU 管理器的操作按钮可启动 / 停止

## 安装

1. 下载最新 release 的 zip
2. 通过 KernelSU / Magisk / APatch 管理器安装
3. 重启手机，内置二进制会自动部署到 `/data/adb/tailscale/bin/`
4. 从 KernelSU 管理器打开本模块的 WebUI，登录并连接

全部操作都可以在 WebUI 内完成，不需要命令行。

## WebUI 功能位置

| 页面 | 能做什么 |
| --- | --- |
| 状态 | 查看连接状态 / 账号 / 节点数；启动、停止、重启守护进程；获取登录链接；断开、登出；修复 `src_valid_mark`、启停守卫 |
| 节点 | 查看所有节点、测延迟 |
| 安装 | 安装 / 切换 / 重装内置版本；在线安装（指定版本或自定义 URL）；安装自定义二进制（可扫描设备文件） |
| 日志 | 查看 tailscaled 与登录日志 |
| 设置 | 主题；`TS_PROXY`、`TS_PORT`、`TS_HOSTNAME`、`TS_WAKELOCK`、`TS_TUN`、`TS_EXTRA_ARGS` |

## 配置

一般直接在 WebUI 的设置页修改即可，写入 `/data/adb/tailscale/env`：

```sh
TS_PROXY="http://127.0.0.1:7890"  # 控制面 / DERP 使用的 HTTP 代理
TS_PORT="41641"                    # WireGuard 监听端口
TS_HOSTNAME="my-phone"             # 覆盖自动获取的主机名
TS_WAKELOCK="1"                    # 持有 CPU 唤醒锁（1 开，0 关）
TS_TUN="tailscale0"                # TUN 网卡名
TS_EXTRA_ARGS=""                   # 追加给 tailscaled 的启动参数，如 --netfilter-mode=off
TS_DAEMON=""                       # 守护进程路径覆盖（留空即 /data/adb/tailscale/bin/tailscaled）
```

## 自建 / 第三方 tailscaled

支持运行自己编译的守护进程（自行打补丁、`--netfilter-mode=off`、userspace networking 等），全程在 WebUI 内操作：

1. 把二进制或官方 tgz 包放到手机上，例如 `/sdcard/Download/`
2. 打开 WebUI → 安装页 → **自定义二进制**
3. 点「扫描设备文件」自动列出常用目录（`/sdcard/Download`、`/sdcard`、`/data/local/tmp`）里的 tailscale 相关文件，点一下即可填入路径；也可以手动输入路径
4. 点「安装自定义」

支持的输入形式：

- 单个可执行文件 `tailscaled`（只替换守护进程，CLI 保持不变）
- 一个目录，内含 `tailscaled`，有 `tailscale` 时一并替换
- 官方 `.tgz` / `.tar.gz` 包（自动解包并取其中的 `tailscaled`、`tailscale`）
- 也可以单独填写「CLI 路径」来一并替换 `tailscale` 命令

安装过程会先复制到暂存文件并用 `--version` 试运行校验，架构不匹配或不是 tailscaled 的文件会被拒绝，不会破坏现有可用版本；校验通过后停止守护进程、原子替换并自动重启。

自定义版本会被标记为用户自管（`bin/.custom`），模块升级、开机自动部署都不会覆盖它；在安装页点「安装内置」即可随时回滚到官方内置版本。

自建版本如需额外参数，在设置页填 `TS_EXTRA_ARGS`；TUN 网卡名不同则改 `TS_TUN`。请保持进程名为 `tailscaled`（安装器已自动重命名），因为看门狗、KSU 操作按钮和状态检测都按该进程名匹配。

## 项目结构

```
module/                 # KSU 模块文件（打包发布的内容）
├── module.prop
├── bins/               # 内置二进制：bins/<arch>/{tailscale,tailscaled,VERSION}
├── install_bins.sh     # 部署 / 更新内置二进制
├── install_custom.sh   # 安装自建二进制（标记为用户自管）
├── service.sh          # 守护进程启动 + 模块描述更新
├── action.sh           # KSU 操作按钮：一键启停
├── svm_guard.sh        # src_valid_mark 看门狗 + 健康检查
├── update_desc.sh      # 模块描述状态刷新
├── post-fs-data.sh     # 目录初始化 + 内置二进制部署
└── webroot/index.html  # 构建后的 WebUI（单文件）

webui/                  # WebUI 源码（Vue 3 + Tailwind CSS + DaisyUI）
├── src/
│   ├── composables/useKsu.ts   # KSU exec 桥接与状态管理
│   ├── views/                  # 页面组件
│   └── ...
├── package.json
└── vite.config.ts
```

## 构建 WebUI

```sh
cd webui
npm install
npm run build
cp dist/index.html ../module/webroot/index.html
```

## 模块描述

模块会每 30 秒刷新一次 KernelSU 管理器中的描述：

- `✅ 已连接 | hostname | 100.x.x.x | N 个在线 | vX.Y.Z`
- `⚠️ 需要登录 | vX.Y.Z`
- `❌ 未运行`

## 许可

MIT
