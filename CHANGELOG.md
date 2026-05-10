# Changelog

All notable changes will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Windows beta.** New `GuiportWindowsAdapter` target backed by Win32: `apps` (EnumWindows + QueryFullProcessImageNameW), `click-at` / `type` / `hotkey` (SendInput, Unicode-aware including surrogate pairs), `screenshot` (GDI BitBlt for the virtual desktop, PrintWindow for a specific window). Wired into the executable via `#if os(Windows)`; non-Windows builds compile the target to nothing. CI now builds on `windows-2022` alongside macOS.
- `scripts/install.ps1` — real PowerShell installer (clones, `swift build -c release`, drops binary in `%LOCALAPPDATA%\Programs\guiport`, adds to user PATH).

### Pending on Windows
- UIA-backed `tree` / `observe` / `find` / `click <selector>` and WinRT `find-text` / `record` — these throw `uia_pending` / `ocr_pending` / `recorder_pending` with a roadmap hint until COM/WinRT bindings land.

## [0.1.3] — 2026-05-10

### Added
- `guiport init` — friendly first-run command. Fires Accessibility + Screen Recording prompts, opens the right Settings panes, and prints clear "look for guiport in the list, toggle it on" guidance.

### Fixed
- `guiport doctor --fix` now forces an actual screen-capture attempt (`CGDisplayCreateImage`) when Screen Recording isn't granted, so macOS reliably adds `guiport` to System Settings → Privacy & Security → Screen Recording. Calling `CGRequestScreenCaptureAccess()` alone wasn't always enough on recent macOS; only a real capture attempt enrols the binary into TCC's UI list.

## [0.1.2] — 2026-05-10

### Fixed
- **TCC now tracks guiport as its own subject.** Embedded an `Info.plist` (with `CFBundleIdentifier dev.guiport.cli`, `NSAccessibilityUsageDescription`, `NSScreenCaptureUsageDescription`, `NSAppleEventsUsageDescription`) into the binary's `__TEXT,__info_plist` section via SwiftPM linker flags. Result: granting Screen Recording / Accessibility once for guiport is enough — works from Ghostty, Terminal.app, iTerm, opencode, or any other terminal. Previously TCC fell through to the parent terminal because no usage strings were present.

## [0.1.1] — 2026-05-10

### Changed
- **Visual fallback is now automatic.** `click` and `find` fall back to on-screen text matching when an AX selector misses, with no flag needed. If Screen Recording isn't granted, the fallback is silently skipped and the original `no_match` error surfaces with a hint to run `doctor --fix` — no surprise mid-action permission prompts.
- CLI: `--fallback <enum>` removed; `--strict` flag added for opt-out. Result reports `"path": "ax"` or `"path": "ocr"` so callers know which won.
- MCP `click` tool: new `strict: bool` arg. Legacy `fallback: "none"` still mapped to strict for back-compat.
- YAML runner: `click: { selector, strict: true }` for opt-out per step.
- examples/calculator-smoke.yaml: `AllClear` → `Clear` to match macOS 26 Calculator AX.

### Added
- macOS-first MVP: `doctor`, `apps`, `observe`, `tree`, `find`, `click`, `type`, `hotkey`, `screenshot`, `record`, `run`, `serve --mcp`, `bench`.
- Accessibility-tree-first inspection with stable path-based element IDs.
- Selector engine: `role[attr=value][attr~=substring][index]` with role aliases.
- Live recorder via CGEventTap → YAML test scaffold.
- YAML replay runner with wait/find/click/type/hotkey/screenshot/assert and per-failure artifacts (tree JSON + screenshot).
- Tree cache with TTL + explicit invalidation; cached find p50 ≈ 60µs on Finder.
- MCP server (stdio JSON-RPC) exposing the same tools to coding agents.
- Best-effort Electron coaxing (`AXManualAccessibility` + `AXEnhancedUserInterface`).
- Modern icon, hero README, MIT license, Homebrew formula, install scripts.

[Unreleased]: https://github.com/edihasaj/guiport/commits/main
