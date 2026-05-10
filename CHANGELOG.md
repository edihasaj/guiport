# Changelog

All notable changes will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
