<div align="center">

<img src="NotchBuddy/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="96" alt="VoltaDock icon">

# VoltaDock

**English** · [Español](README.md)

**A tiny friend that lives in your MacBook's notch — or at the top of your screen on Windows — and keeps an eye on your Claude Code sessions.**

Approve permissions, watch your agents work, drop a file, chat with Claude — all without leaving what you're doing.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0A84FF)
![Tauri 2](https://img.shields.io/badge/Tauri-2-FFC131?logo=tauri&logoColor=black)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![GitHub stars](https://img.shields.io/github/stars/DiegoVolta91/VoltaDock?style=social)

<img src="docs/media/demo.gif" width="720" alt="Volt says hi, follows a Claude Code session, asks for permission and celebrates when it is done">

<sub>Recorded from the Windows version with sample data.</sub>

</div>

---

## Why

Some studios showed off gorgeous notch companions… and never let anyone use them.
**VoltaDock is an open one.** Every line of code is free to use, read, fork and remix.

Meet **Volt**: a little battery with a lightning-bolt antenna that pops out of your notch, waves hello, follows your cursor with its eyes, gets annoyed when you poke it (and dizzy if you insist). Its charge bar shows how Claude Code is doing, and its bolt sparks the moment Claude needs you.

## Features

- 🤖 **Claude Code, live** — see every session in your notch: what it reads, edits and runs, step by step. Finished? Volt does a happy little jump.
- ✅ **Approve from the notch** — Claude Code permission requests show up with **Allow / Deny**. One click, back to work.
- 🧑‍💻 **Jump to the right terminal** — open the exact terminal window of a session *(macOS)*.
- 💬 **Ask Claude anything** — built-in chat, straight from the notch.
- 📎 **Drop a file on the notch** — Volt turns into a box and swallows it, then ask a question about it or send it by email *(email: macOS, Mail.app)*.
- 🪟 **Drag Volt onto any window** — attach that window as context for Claude *(macOS)*.
- ⏱️ **Today** — a 25-minute focus timer with its countdown under the island, quick to-dos and reminders typed in plain words (“in 10 min stretch”, “tomorrow at 9 dentist”, “a las 17:30 gym”). Reminders that came due while the computer slept show up when it wakes. Reminders can repeat (“every Monday at 9 check mail”, “every 2 hours stretch”), and you can keep habits with streaks by typing “habit drink water”. Everything stays on your machine. Turn the **Today** pill on in Settings.
- 🗣️ **Optional voice** — Volt says “Claude is done” or “needs your permission” out loud, with your system voice. Off by default.
- 🔔 **New-version notice** — if you turn it on, it checks once at launch whether GitHub has a newer release. Off by default.
- 🧹 **Delete my data** — a button in Settings that erases what the app keeps on your computer (to-dos, habits, chat, file copies and keys).
- 🔌 **Integrations** — Stripe payments, n8n workflows, GitHub, Vercel deployments, Resend emails, Notion, Cal.com. Each one gets its own little colored Volt.
- 🎭 **A real character** — idle breathing, blinks, eyes on a sphere that follow your mouse, emotes, 28 handcrafted sounds, a greeting on launch.
- 📱 **iPad companion** *(in development)* — watch and approve from an iPad on the same Wi-Fi network.
- 🫥 **Invisible when idle** — hides away when nothing is running, peeks out when you hover the notch (the top edge of the screen on Windows).
- 🔒 **Private by design** — no telemetry, no account. Keys live in your macOS Keychain or Windows Credential Manager. The app only talks to the services you plug in.

<table>
<tr>
<td><img src="docs/media/volt-sesion.png" alt="A Claude Code session with the integrations next to it"></td>
<td><img src="docs/media/volt-permiso.png" alt="A Claude Code permission request"></td>
</tr>
<tr>
<td><img src="docs/media/volt-chat.png" alt="Chat with Claude"></td>
<td><img src="docs/media/volt-archivo.png" alt="Volt turned into a box, waiting for a file"></td>
</tr>
</table>

<sub>Real screenshots of the Windows version with sample data (its interface is in Spanish for now). Mac screenshots are coming.</sub>

## Install

### Download for macOS

1. Grab the latest `VoltaDock.zip` from [Releases](https://github.com/DiegoVolta91/VoltaDock/releases).
2. Unzip and move **VoltaDock.app** to `/Applications`.
3. Launch. This build isn't notarized by Apple yet, so the first time macOS says it can't verify the developer: open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** (only once).

### Windows

The Windows installer is **temporarily unavailable**. Microsoft Defender wrongly
flags the unsigned installer as malware; a false-positive report is under review
at Microsoft and the installer will come back once it is cleared and signed.
Until then you can [build it from source](#build-from-source).

#### Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io), certificate by
[SignPath Foundation](https://signpath.org). Only installers built by GitHub
Actions from this repository are signed, each one approved by hand. Roles and
details: [code signing policy](https://diegovolta91.github.io/VoltaDock/code-signing.html).

There is no notch on a PC, so the island slides out of the top edge of the screen
instead of hiding inside one. See [`windows/README.md`](windows/README.md) for the
rest of the differences.

### Build from source

**macOS** — requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/DiegoVolta91/VoltaDock.git
cd VoltaDock/NotchBuddy
xcodegen
open NotchBuddy.xcodeproj   # then ⌘R
```

**Windows** — requirements: [Rust](https://rustup.rs), Node 20+, MSVC build tools.

```powershell
git clone https://github.com/DiegoVolta91/VoltaDock.git
cd VoltaDock/windows
npm install
npm run pack                # installer lands in windows/release/
```

## Setup

Click the VoltaDock icon in the menu bar (macOS) or in the system tray (Windows) → **Settings…**

| What | Why | Where the key goes |
|---|---|---|
| **Claude Code hooks** | live sessions and approvals | **Install hooks** — VoltaDock backs up `~/.claude/settings.json`, merges its hooks and shows you the diff before writing anything |
| **Anthropic API key** | chat and questions about files | Keychain / Windows Credential Manager |
| Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com | the integration pills | Keychain / Windows Credential Manager, all optional |

If VoltaDock isn't running, the hook exits immediately: **Claude Code is never blocked.**

## Things to try

| Do this | Volt does that |
|---|---|
| Hover the notch (top edge on Windows) | peeks out and says hi 👋 |
| Click it | opens |
| Hover Volt | blinks, eyes grow |
| Click Volt | squish + annoyed |
| Click 3 times fast | 😵‍💫 dizzy for a few seconds |
| Drag a file onto the island | turns into a box and swallows it |
| Drag Volt onto a window *(macOS)* | attaches it as context |

## How it works

**macOS**

- **Island**: a borderless `NSPanel` hugging the notch, driven by a small state machine (`hidden → petit → home`).
- **Character**: Volt is drawn in SwiftUI `Canvas` + `TimelineView` at 60 fps (`VoltShape.swift`) — battery body, lightning-bolt antenna, charge bar, eyes that follow your cursor, spring animations. No Rive, no Lottie, no images.
- **Claude Code**: a tiny `nb-hook` script receives hook events and forwards them over a Unix socket to the app. For approvals it waits for your click, then answers the hook.
- **Integrations**: lightweight pollers, paused when nothing is watching.
- **Sounds**: 28 short WAVs played through preloaded `AVAudioPlayer`s.

The macOS app is native Swift 6 / SwiftUI / AppKit with **zero third-party dependencies**.

**Windows**

- A [Tauri 2](https://tauri.app) app (Rust + TypeScript): the island is a transparent, always-on-top window that never steals focus, Volt is drawn in Canvas 2D with the same shapes, timings and sounds as on the Mac.
- Claude Code hooks go through a tiny relay executable (still named `coucou-hook.exe`, after the original project) and a named pipe; keys live in Windows Credential Manager.
- Details and differences in [`windows/README.md`](windows/README.md).

## Contributing

Issues and PRs are very welcome — new integrations, new emotes, new sounds, bug fixes. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Built by Diego ([@DiegoVolta91](https://github.com/DiegoVolta91)) with Claude Code.
VoltaDock started as a fork of Coucou by Louis Raillé (MIT) and is now developed independently; the original copyright notice is kept in [LICENSE](LICENSE).
Inspired by the notch-companion concepts shared by design studios — this project is independent and not affiliated with any of them.

## License

- **Code:** [MIT](LICENSE) — use it, fork it, learn from it, just keep the copyright notice.
- **Character, icons and sounds:** Volt, the app icons and the sounds are VoltaDock's own, drawn and synthesised in code (MIT).
- **Screenshots and demo** in `docs/media/` are VoltaDock captures (MIT). The design references in `design/` still come from the original project and aren't covered by the MIT License — see [LICENSE-ASSETS.md](LICENSE-ASSETS.md).

<div align="center">

**If Volt made you smile, a ⭐ helps a lot.**

[Website](https://diegovolta91.github.io/VoltaDock/) · [Privacy](https://diegovolta91.github.io/VoltaDock/privacy.html) · [Terms](https://diegovolta91.github.io/VoltaDock/terms.html) · [Support](https://diegovolta91.github.io/VoltaDock/support.html) · [Code signing policy](https://diegovolta91.github.io/VoltaDock/code-signing.html)

</div>
