# Changelog

All notable changes will be documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
