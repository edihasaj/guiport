# Changelog

All notable changes will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- **Homebrew now ships a signed `guiport.app` and runs the CLI from inside it.**
  The release wraps the universal binary in a Developer-ID-signed `guiport.app`
  (`Contents/MacOS/guiport` + `.icns` + `Info.plist`) and the tap installs the
  bundle, symlinking `bin/guiport` into `Contents/MacOS/guiport`. Because the
  running process is now bundle-associated, macOS shows guiport's real logo in
  the Accessibility and Screen Recording panes (instead of the generic
  executable icon) and the TCC grant is keyed to a stable identity that survives
  `brew upgrade` — no manual `.app` step, no duplicate entries. Bundle assembly
  is centralised in `scripts/make-app-bundle.sh`, shared by the release workflow
  and the local/install-script path (which now symlinks into the app too).
  Closes #4.
- Release binaries are now signed with the team **Developer ID Application**
  certificate (Applifyer, LLC — team `T8J48M4QVY`) instead of ad-hoc. This gives
  guiport a stable certificate-based designated requirement, so macOS keeps
  Accessibility and Screen Recording (TCC) grants across `brew upgrade` instead
  of resetting them on every cdhash change. CI imports the cert from the
  `MACOS_CERT_P12_BASE64` / `MACOS_CERT_PASSWORD` secrets (sourced from the
  team's `apple-codesign` 1Password vault); unset secrets still fall back to a
  stable-identifier ad-hoc signature.

### Added
- `guiport doctor --fix` now self-registers `~/Applications/guiport.app` from
  the active binary before firing TCC prompts, so Accessibility and Screen
  Recording panes show a real `guiport` app entry even for Homebrew CLI installs.
  The wrapper now carries the guiport icon when the install includes `icon.icns`.
- **Windows beta.** New `GuiportWindowsAdapter` target backed by Win32: `apps` (EnumWindows + QueryFullProcessImageNameW), `click-at` / `type` / `hotkey` (SendInput, Unicode-aware including surrogate pairs), `screenshot` (GDI BitBlt for the virtual desktop, PrintWindow for a specific window). Wired into the executable via `#if os(Windows)`; non-Windows builds compile the target to nothing. CI now builds on `windows-2022` alongside macOS.
- `scripts/install.ps1` — real PowerShell installer (clones, `swift build -c release`, drops binary in `%LOCALAPPDATA%\Programs\guiport`, adds to user PATH).
- **Linux beta.** New `GuiportLinuxAdapter` target. Session-aware day-1 surface: `xdotool` + `wmctrl` + `scrot`/`import` on X11, `ydotool` + `grim` on Wayland. `apps` uses `wmctrl -lpG` on X11 and a `/proc` walk on Wayland. All shell-outs go through `Process` with discrete argv (never a shell), so user-supplied titles / type-text are safe even with metacharacters. CI now builds on `ubuntu-24.04` alongside macOS + Windows.
- `scripts/install.sh` now installs on Linux too (was a roadmap stub before).
- `scripts/install-macos-app.sh` installs a signed `guiport.app` wrapper with
  the project icon so macOS permission panes show the guiport logo.

### Fixed
- **Screen Recording now works regardless of the launching terminal.** macOS
  attributes Screen Recording *enforcement* to the responsible process — for a
  CLI, the terminal that spawned it — so a terminal lacking (or denied) the grant
  blocked guiport even when guiport's own identity was authorized (Accessibility
  was unaffected, since it is judged on the calling binary). Moving capture to
  ScreenCaptureKit enrolled `com.edihasaj.guiport` as its own TCC subject but did
  not change enforcement, so capture could still fail behind a denied terminal.
  guiport now disclaims responsibility from its parent and re-execs itself
  (`responsibility_spawnattrs_setdisclaim`) for the `screenshot`, `record`, and
  `doctor` commands, becoming its own responsible process so macOS evaluates
  guiport's own grant. The permission check also falls back to a ScreenCaptureKit
  probe (guiport's own identity) when the legacy `CGPreflightScreenCaptureAccess`
  (terminal identity) returns a false negative.
- `doctor --fix` now rebuilds `~/Applications/guiport.app` from scratch. A stale
  wrapper from an older version — e.g. a dangling `Contents/MacOS/guiport` symlink
  into a since-removed Cellar path — made `fileExists` (which follows symlinks)
  report the exec missing, so the copy threw "file exists" and the whole refresh
  was silently swallowed. The registration now removes any existing bundle first.
- macOS TCC identity now uses `com.edihasaj.guiport` consistently in the CLI
  binary and app wrapper, so Screen Recording grants apply to `guiport doctor`
  and screenshot commands.
- **Screen Recording is now attributed to `guiport`, not the host terminal.**
  Screenshot, screenshot-on-failure, OCR (`find-text`), and `doctor --fix`
  enrolment moved off the deprecated CoreGraphics capture APIs
  (`CGDisplayCreateImage` / `CGWindowListCreateImage`) onto ScreenCaptureKit on
  macOS 14+. Those legacy calls made macOS grant Screen Recording to the
  responsible foreground app (e.g. the terminal running the CLI), so `guiport`
  never got its own entry; ScreenCaptureKit enrols `com.edihasaj.guiport` as its
  own subject and prompts for it by name. Falls back to the legacy path on
  macOS 13. `doctor --fix` now attempts a real ScreenCaptureKit frame capture to
  trigger enrolment — listing shareable content alone does not require the
  permission and so never prompted.
- **Release binaries are now Developer-ID signed.** `release.yml` signs the
  universal binary with the Applifyer Developer ID (hardened runtime, stable
  `com.edihasaj.guiport` identifier) when `MACOS_CERT_P12_BASE64` /
  `MACOS_CERT_PASSWORD` secrets are set. A `swift build` binary is only ad-hoc
  signed, so its TCC identity (and any Screen Recording grant) reset on every
  `brew upgrade`; a stable Developer-ID identity persists across upgrades. See
  `docs/RELEASING.md`.

### Pending on Windows
- UIA-backed `tree` / `observe` / `find` / `click <selector>` and WinRT `find-text` / `record` — these throw `uia_pending` / `ocr_pending` / `recorder_pending` with a roadmap hint until COM/WinRT bindings land.

### Pending on Linux
- AT-SPI2 D-Bus tree (`observe` / `tree` / `find` / `click <selector>`), tesseract OCR (`find-text`), evdev/libei recorder, and per-window screenshots on Wayland — throw `atspi_pending` / `ocr_pending` / `recorder_pending` / `wayland_per_window_unsupported` until those backends land.

## [0.1.3] — 2026-05-10

### Added
- `guiport init` — friendly first-run command. Fires Accessibility + Screen Recording prompts, opens the right Settings panes, and prints clear "look for guiport in the list, toggle it on" guidance.

### Fixed
- `guiport doctor --fix` now forces an actual screen-capture attempt (`CGDisplayCreateImage`) when Screen Recording isn't granted, so macOS reliably adds `guiport` to System Settings → Privacy & Security → Screen Recording. Calling `CGRequestScreenCaptureAccess()` alone wasn't always enough on recent macOS; only a real capture attempt enrols the binary into TCC's UI list.

## [0.1.2] — 2026-05-10

### Fixed
- **TCC now tracks guiport as its own subject.** Embedded an `Info.plist` (with `CFBundleIdentifier com.edihasaj.guiport`, `NSAccessibilityUsageDescription`, `NSScreenCaptureUsageDescription`, `NSAppleEventsUsageDescription`) into the binary's `__TEXT,__info_plist` section via SwiftPM linker flags. Result: granting Screen Recording / Accessibility once for guiport is enough — works from Ghostty, Terminal.app, iTerm, opencode, or any other terminal. Previously TCC fell through to the parent terminal because no usage strings were present.

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
