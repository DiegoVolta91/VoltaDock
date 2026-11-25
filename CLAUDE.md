# VoltaDock — guide for AI coding agents

VoltaDock (an independent project that started as a fork of Coucou by Louis Raillé) is a native macOS app, with a Windows port in `windows/`: Volt, a small animated character living in the MacBook notch, shows Claude Code sessions and a few integrations, and lets the user approve, answer, chat and drop files from the notch.

## Where things are
- `NotchBuddy/Sources/App/` — all Swift code. `NotchBuddy/Resources/sounds/` — the 28 WAV sounds. `NotchBuddy/project.yml` — XcodeGen project (never edit the `.xcodeproj` by hand).
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
- `design/prototype/notch-buddy.html` — original prototype, the visual source of truth. `design/captures/` — target screenshots.
- `docs/*.html` — the GitHub Pages site (home, support, privacy, terms, legal notice, code signing policy).

## Build
```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```

## Rules
- Swift 6, SwiftUI + AppKit. No third-party dependencies unless truly unavoidable. The character is drawn in code (`Canvas` + `TimelineView`), no Rive/Lottie/images.
- Secrets live in the Keychain, never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app doesn't answer, the hook exits immediately.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, show the diff, write only after the user confirms.
- Never send an email or approve a Claude Code permission without an explicit click.
- Performance: 0 % CPU when the island is hidden.
- Keep the bundle identifiers `io.github.diegovolta91.VoltaDock` (Mac), `io.github.diegovolta91.VoltaDock.AppStore` (Mac App Store) and `io.github.diegovolta91.voltadock` (Windows): Keychain items, preferences and permissions depend on them. The Xcode project, scheme and `NotchBuddy/` folder keep their old internal name.
- The character is **Volt** (a battery with a lightning-bolt antenna), drawn from `NotchBuddy/Sources/App/VoltShape.swift` and `windows/src/mochi/volt.ts`: keep the two in step. Icons come from `windows/scripts/gen-icons.mjs`, sounds from `scripts/gen-sounds.py`. Code names like `Mochi`/`mochi` are leftovers from Coucou.
- `design/` still holds Coucou's artwork (not MIT, see `LICENSE-ASSETS.md`): don't publish it as VoltaDock's. `docs/media/` holds Volt captures taken from the Windows UI in a browser.
- The site (`docs/*.html`) is Spanish first with an English version on the same page (`data-lang` blocks, `docs/lang.js`); `README.md` is Spanish, `README.en.md` English: keep both in step.
- Island layouts and timings still follow the prototype and `design/captures/`; the character itself is Volt, so its look comes from the Volt drawing code, not from Mochi in those files.
