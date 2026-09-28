<div align="center">

# 🌐 GeoFlagMenuBar

**你的流量的真实出口国家 —— 直接显示在 macOS 菜单栏。**

[English](/README.md) · [Русский](/README.ru.md) · [中文](#-功能) · [العربية](/README.ar.md)

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![swift](https://img.shields.io/badge/Swift-AppKit-orange)
![arch](https://img.shields.io/badge/arch-universal%20%28arm64%20%2B%20x86__64%29-blue)
![deps](https://img.shields.io/badge/dependencies-0-success)
![license](https://img.shields.io/badge/license-MIT-informational)

</div>

---

## 为什么需要它

VPN 客户端常常显示**「已连接」**，却不会告诉你流量**实际**从哪个国家出口：分流规则、DNS 泄漏、
隧道卡顿或「智能」改路 —— 都可能让全部或部分流量仍走原来的国家。

GeoFlagMenuBar 只回答一个关键问题：**此刻外部互联网看到你在哪个国家？**
它会向多个独立的地理 IP 服务查询你的公网出口 IP，并把结果以国旗形式显示在菜单栏 ——
网络一有变化立刻刷新。

## 功能

- 🏳️ **实时国旗** 显示在状态栏（例如路由切换的一瞬间 🇬🇧 → 🇩🇪）
- 📋 **点击国旗查看详情**：公网 IP · 国家（ISO 代码 + 国旗）· 城市 · 上次检测时间；出口点变化时标记 *「(已变化!)」*
- ⚡ **即时响应** —— 不依赖轮询延迟：
  - 系统事件 `network_change`：VPN 开/关、Wi-Fi ↔ 有线、插入网线、切换热点
  - `NWPathMonitor`：断网那一刻图标立即变为 🚫，恢复后回到国旗
  - Mac 唤醒、时间/时区变更、打开菜单
- 🛰 **三个独立数据源**：`ipinfo.io`、`ifconfig.co`、`api.myip.com` —— 谁先返回谁生效；5 秒超时；全部不可达时显示 🚫
- 🪶 **极轻量**：单个 Swift 文件，零第三方依赖，约 50 MB 内存，约 0% CPU，无后台守护进程，无安装器
- 🔒 **天生注重隐私**：无分析、无账号、无历史记录 —— 仅向三个地理 IP 服务发送匿名 HTTPS GET

## 图标含义

| 图标 | 含义 |
|:---:|---|
| ⏳ | 正在检测（或网络刚刚恢复） |
| 🇬🇧 🇩🇪 🇷🇺 … | 当前出口国家 |
| 🚫 | 无网络 / 所有服务不可达 |

菜单（点击图标）：

```
IP: 38.180.139.227
Страна: GB 🇬🇧
Город: Manchester
Обновлено: 20:09:31 (изменилось!)
────────────────────────
Проверить сейчас   ⌘R
────────────────────────
Выход              ⌘Q
```

## 安装

### 方式一 —— 下载现成的构建

1. 从最新的 [**Release**](https://github.com/Uralmans/GeoFlagMenuBar/releases/latest) 下载 `GeoFlagMenuBar.zip`（约 70 KB，通用二进制：Apple Silicon + Intel）
2. 解压 → 把 **GeoFlagMenuBar.app** 放到任意位置（`/Applications` 可选）
3. 首次启动：**右键 → 打开**（ad-hoc 签名；只需确认一次，之后正常双击打开）

*提示：如果通过 `git clone` 或 AirDrop 获取应用，通常不会带隔离属性，可直接双击打开。*

### 方式二 —— 从源码构建（一条命令）

需要 macOS 13+ 与 [Command Line Tools](https://developer.apple.com/download/all/)（`xcode-select --install`）；**无需**完整版 Xcode：

```bash
git clone https://github.com/Uralmans/GeoFlagMenuBar.git
cd GeoFlagMenuBar
./build.sh
open build/GeoFlagMenuBar.app
```

构建产物为已签名的通用二进制（arm64 + x86_64）—— 见 `build.sh`，只有约 30 行普通 zsh + `swiftc`。

### 登录时自启动（可选）

把应用加入 *系统设置 → 通用 → 登录项*，或：

```bash
cp -R build/GeoFlagMenuBar.app /Applications/
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/GeoFlagMenuBar.app", hidden:true}'
```

## 工作原理

```
┌──────────────┐   NWPathMonitor（瞬时通/断）           ┌───────────────────────┐
│ macOS 事件   │ ─────────────────────────────────────▶ │     去抖动 1.5 秒     │
└──────────────┘  network_change / wake / clock         └───────────┬───────────┘
┌──────────────┐                                                     ▼
│ 20 秒轮询    │ ───────────────────────────────▶ 3×HTTPS GET（竞速，5 秒超时）
└──────────────┘                                          │ 第一个有效的 ISO-2 回复
                                                          ▼
                                        国旗 emoji ← ISO-2 → 菜单栏图标 + 菜单
```

- 三个请求并行竞速：取第一个有效结果（屏蔽单一服务的抖动）
- 变化检测比较 `(IP, 国家)` 与上次结果；变化时在菜单中标记并写入系统日志
- 网络路径断开期间（`NWPathMonitor`）暂停 HTTP 轮询 —— 零无效超时
- 以 `LSUIElement` 运行：不占 Dock 图标，只有状态栏图标

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 开着 VPN 却显示 🇺🇸 | 客户端的 kill-switch / 分流让部分流量直连 —— 这正是本应用要抓的。查看菜单里的 IP |
| 显示 🚫 但网络正常 | 三个地理 IP 服务同时不可达（防火墙、Pi-hole、DoH 故障）。菜单 → *Проверить сейчас* |
| 国旗变了但 IP 没变 | 地理库更新了该 IP 的归属国 —— 正常现象；以显示的国旗为准 |
| 下载后无法启动 | 再做一次**右键 → 打开**，或：`xattr -dr com.apple.quarantine GeoFlagMenuBar.app` |
| 调试日志 | `log show --last 5m --predicate 'process == "GeoFlagMenuBar"'` |

## 隐私

- **无跟踪、不落盘**：除二进制本身外不向磁盘写入任何数据，不保存历史
- **对外流量**：仅向 `ipinfo.io`、`ifconfig.co`、`api.myip.com` 发送 HTTPS GET，别无其他
- **无需任何权限**：不请求通知、语音助手、磁盘或钥匙串访问

## 项目结构

```
GeoFlagMenuBar/
├── Sources/GeoFlagMenuBar.swift   # 全部代码（约 200 行）
├── Info.plist                     # LSUIElement，macOS 13+
├── build.sh                       # 通用构建：swiftc → lipo → codesign
├── assets/banner.svg              # README 横幅
└── README.{md,ru.md,zh.md,ar.md}  # 本文件 + Русский/English/العربية
```

## 参与贡献

欢迎 Issue 与 PR —— 这是一个刻意保持精小的工具，请让改动保持聚焦。
适合上手的点：新增地理 IP 服务端点、更美观的离线图标、基于 SF Symbols 的图标方案、菜单的多语言化。

## 许可证

[MIT](LICENSE) © 2026 [Oleg Artyugin (Uralmans)](https://github.com/Uralmans)
