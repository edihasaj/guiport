<p align="center">
  <img src="assets/logo.svg" width="520" alt="guiport"/>
</p>

<p align="center"><em>Playwright for desktop apps, built for coding agents.</em></p>
<p align="center"><strong>macOS shipped · Windows beta · Linux coming.</strong></p>

<p align="center">
  <a href="https://github.com/edihasaj/guiport/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/edihasaj/guiport/actions/workflows/ci.yml/badge.svg"/></a>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"/>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Windows%2010%2B-black"/>
  <img alt="Swift" src="https://img.shields.io/badge/swift-5.9%2B-orange"/>
</p>

---

A fast CLI/MCP control layer that lets agents like Claude, Codex, opencode, and Gemini inspect and operate desktop apps through structured UI data, then save successful flows as replayable tests.

## Status

MVP. macOS is the primary target — Accessibility tree first, screenshots as fallback.

Windows is in beta with a day-1 input/screenshot/apps surface (Win32 SendInput, GDI BitBlt/PrintWindow, EnumWindows). UIA-backed tree/observe/find/click-by-selector and WinRT OCR are pending — they throw a clear `uia_pending` / `ocr_pending` error today. Track progress under the [`windows`](https://github.com/edihasaj/guiport/issues?q=label%3Awindows) label.

## Why

Agents shouldn't drive desktop apps by guessing pixels. `guiport` exposes the desktop as structured data: app/window list, focused app/window, accessibility tree, element role/name/value/state/bounds/actions, screenshots only when needed, deterministic replay scripts after exploration.

## Install

macOS 13+. See [INSTALL.md](INSTALL.md) for full options + platform status.

```sh
# Homebrew (once tap is published)
brew tap edihasaj/guiport && brew install guiport

# Or install script
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh

# Or from source
swift build -c release && sudo cp .build/release/guiport /usr/local/bin/guiport
```

Windows (beta — input/screenshot/apps; UIA tree pending):

```powershell
iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
```

Linux is roadmap — see [INSTALL.md](INSTALL.md).

## Quick start

```sh
guiport doctor                                       # check permissions
guiport apps --json                                  # list running apps with windows
guiport observe --app "Safari"                       # focused window summary
guiport tree --app "Safari" --json                   # full accessibility tree
guiport find --app "Safari" 'button[name="Save"]'    # match selector
guiport click --app "Safari" 'button[name="Save"]'
guiport type "hello"
guiport screenshot --app "Safari" -o safari.png

# Vision fallback for canvas / sparse-AX apps:
guiport find-text --app "Figma" "Save"               # OCR via Apple Vision
guiport click-text --app "Figma" "Save"              # OCR + click center
guiport click-at 420 180                             # raw coordinates
guiport record smoke.yaml                            # WIP
guiport run smoke.yaml
guiport serve --mcp                                  # MCP server over stdio
```

## Selector syntax

```
role[attr=value][attr~=substring][index]
```

Examples:

```
button[name="Save"]
textfield[identifier="search"]
AXButton[name~="Open"][index=0]
```

Supported attributes: `role`, `name` (title), `value`, `identifier`, `description`, `text` (matches name or value), `index`.

## Vision fallback (canvas / Electron apps)

For apps with sparse or absent accessibility (Figma, custom-rendered editors, hardened Electron), guiport falls back through three layers:

1. **`click-at X Y`** — raw screen coordinates. The agent reads coords off a screenshot.
2. **`find-text "Save"`** / **`click-text "Save"`** — Apple Vision (`VNRecognizeTextRequest`) OCRs the window and returns bounds + center for matched text. On-device, free, no extra deps.
3. **LLM vision** — out of scope for MVP; agents can call `screenshot` + their own model to get coords, then `click-at`.

OCR-found bounds drift across font/scale changes, so prefer AX selectors for replay and OCR for exploration.

## Permissions

`guiport` needs:

- **Accessibility** — required for AX tree + input events.
- **Screen Recording** — required for `screenshot` and screenshot-on-failure artifacts.

Run `guiport doctor` to check status and get System Settings deep links.

## Architecture

- Pure Swift, single binary.
- `GuiportCore` library: AX bridge, selector engine, input, screenshots, replay runner, MCP server.
- `guiport` CLI: thin wrapper using swift-argument-parser.

## Non-goals (MVP)

- No Windows/Linux yet.
- No vision-first automation.
- No autonomous Manus clone.
- No background/session-0 automation.

## License

MIT — see LICENSE.

## Author

[Edi Hasaj](https://edihasaj.com)
