<div align="center">

<img src="assets/banner.svg" alt="GeoFlagMenuBar" width="100%"/>

# 🌐 GeoFlagMenuBar

**The real country of your traffic — right in the macOS menu bar.**

[English](#-features) · [Русский](/README.ru.md) · [中文](/README.zh.md) · [العربية](/README.ar.md)

![platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![swift](https://img.shields.io/badge/Swift-AppKit-orange)
![arch](https://img.shields.io/badge/arch-universal%20%28arm64%20%2B%20x86__64%29-blue)
![deps](https://img.shields.io/badge/dependencies-0-success)
![license](https://img.shields.io/badge/license-MIT-informational)

</div>

---

## Why

VPN clients often say **"Connected"**, but they don't always tell you which country your traffic
**actually** exits from: split tunneling, DNS leaks, a stalled tunnel, or a "smart" re-route can
keep your traffic (or part of it) in the previous country.

GeoFlagMenuBar answers the only question that matters: **what does the outside Internet see right now?**
It checks your public IP against several independent geo-IP services and shows the resulting country
as a flag in the menu bar — updating instantly when the network changes.

## Features

- 🏳️ **Live country flag** in the macOS status bar (e.g. 🇬🇧 → 🇩🇪 the moment your route changes)
- 📋 **Click the flag for details**: public IP · country (ISO + flag) · city · last-check time, with a *"(changed!)"* marker when the exit point changes
- ⚡ **Instant reactions** — no polling latency:
  - `network_change` system event: VPN on/off, Wi-Fi ↔ Ethernet, docked cable, hotspot switch
  - `NWPathMonitor`: the moment connectivity drops, the badge flips to 🚫 — and back to the flag when it returns
  - wake from sleep, clock/timezone changes, opening the menu
- 🛰 **Triple-source consensus**: `ipinfo.io`, `ifconfig.co`, `api.myip.com` — first responder wins, 5 s timeout, 🚫 when everyone is unreachable
- 🪶 **Featherweight**: single Swift file, zero third-party dependencies, ~50 MB RAM, ~0% CPU, no background daemons, no installer
- 🔒 **Private by construction**: no analytics, no accounts, no storage — it only makes anonymous HTTPS GET requests to the three geo-IP services

## What you'll see

| Badge | Meaning |
|:---:|---|
| ⏳ | Checking right now (or network just came back) |
| 🇬🇧 🇩🇪 🇷🇺 … | Current exit country |
| 🚫 | No network / all services unreachable |

Menu (click the badge):

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

## Install

### Option 1 — download a ready build

1. Grab `GeoFlagMenuBar.zip` from the latest [**Release**](https://github.com/Uralmans/GeoFlagMenuBar/releases/latest) (~70 KB, universal binary: Apple Silicon + Intel)
2. Unzip → drag **GeoFlagMenuBar.app** anywhere you like (`/Applications` optional)
3. First launch: **right-click → Open** (ad-hoc signature; one-time confirmation, afterwards it opens normally)

*Tip: if you `git clone` or AirDrop the app, the quarantine attribute usually isn't added and it opens with a double-click.*

### Option 2 — build from source (one command)

Requires macOS 13+ and [Command Line Tools](https://developer.apple.com/download/all/) (`xcode-select --install`); full Xcode is *not* needed:

```bash
git clone https://github.com/Uralmans/GeoFlagMenuBar.git
cd GeoFlagMenuBar
./build.sh
open build/GeoFlagMenuBar.app
```

The build produces a signed universal (arm64 + x86_64) `.app` — see `build.sh`, it's ~30 lines of plain zsh + `swiftc`.

### Autostart at login (optional)

Add the app to *System Settings → General → Login Items*, or:

```bash
cp -R build/GeoFlagMenuBar.app /Applications/
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/GeoFlagMenuBar.app", hidden:true}'
```

## How it works

```
┌──────────────┐   NWPathMonitor (instant up/down)      ┌───────────────────────┐
│ macOS events │ ─────────────────────────────────────▶ │      Debounce 1.5 s   │
└──────────────┘  network_change / wake / clock         └───────────┬───────────┘
┌──────────────┐                                                     ▼
│ 20 s poll    │ ───────────────────────────────▶ 3×HTTPS GET (race, 5 s TO)
└──────────────┘                                          │ first valid ISO-2 reply
                                                          ▼
                                          flag emoji ← ISO-2 → badge + menu
```

- Requests race in parallel; the fastest valid answer wins (reduces visibility of any one service's hiccup)
- Change detection compares `(ip, country)` with the previous check and marks the *changed* event in the menu + unified log
- While the network path is down (`NWPathMonitor`), HTTP polling is paused — zero useless timeouts
- Runs as `LSUIElement`: no Dock icon, only the status-bar badge

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Badge stays 🇺🇸 with VPN on | VPN client's kill-switch/split tunneling keeps some traffic direct — that's exactly what the app is designed to catch. Check the IP shown in the menu |
| 🚫 but the Internet works | All 3 geo services unreachable at once (firewall, Pi-hole, DoH outage). Open the menu → *Проверить сейчас* |
| Flag changed while IP didn't | Geo-DB updated your IP's country — happens; the flag is the source of truth |
| App didn't start after download | Re-do **right-click → Open** once, or: `xattr -dr com.apple.quarantine GeoFlagMenuBar.app` |
| Logs for debugging | `log show --last 5m --predicate 'process == "GeoFlagMenuBar"'` |

## Privacy

- **No tracking, no persistence**: the app writes nothing to disk (except the binary itself) and keeps no history
- **Outbound traffic**: HTTPS GET to `ipinfo.io`, `ifconfig.co`, `api.myip.com` — nothing else
- **No permissions** required: no notifications, no assistant, no disk, no keychain

## Project layout

```
GeoFlagMenuBar/
├── Sources/GeoFlagMenuBar.swift   # all the code (~200 lines)
├── Info.plist                     # LSUIElement, macOS 13+
├── build.sh                       # universal build: swiftc → lipo → codesign
├── assets/banner.svg              # README banner
└── README.{md,ru.md,zh.md,ar.md}  # this file + Русский/中文/العربية
```

## Contributing

Issues and PRs are welcome — it's a deliberately tiny tool, so please keep changes focused.
Good first contributions: new geo-IP endpoints, an improved offline icon, SF Symbol badge option, localization of the menu.

## License

[MIT](LICENSE) © 2026 [Oleg Artyugin (Uralmans)](https://github.com/Uralmans)
