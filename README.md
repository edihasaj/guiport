<p align="center">
  <img src="assets/logo.svg" width="520" alt="guiport"/>
</p>

<p align="center"><em>Playwright for desktop apps, built for coding agents.</em></p>
<p align="center"><strong>Available on macOS · Windows · Linux.</strong></p>

<p align="center">
  <a href="https://github.com/edihasaj/guiport/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/edihasaj/guiport/actions/workflows/ci.yml/badge.svg"/></a>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"/>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Windows%2010%2B%20%7C%20Linux-black"/>
  <img alt="Swift" src="https://img.shields.io/badge/swift-5.9%2B-orange"/>
</p>

---

A fast CLI/MCP control layer that lets agents like Claude, Codex, opencode, and Gemini inspect and operate desktop apps through structured UI data, then save successful flows as replayable tests.

## Status

Available on macOS, Windows, and Linux. macOS is the primary target and runs the full stack — Accessibility tree first, screenshots as fallback.

Windows ships a standalone binary (bundled Swift runtime, no toolchain needed) with input/screenshot/apps (Win32 SendInput, GDI BitBlt/PrintWindow → real PNG, EnumWindows) and `find-text` / `click-text` via WinRT OCR. UIA-backed tree/observe/find/click-by-selector is pending — it throws a clear `uia_pending` error today. Track progress under the [`windows`](https://github.com/edihasaj/guiport/issues?q=label%3Awindows) label.

Linux ships a standalone binary (static Swift stdlib, glibc 2.35+) with the same shape: shell-out to `xdotool`/`wmctrl`/`scrot` on X11 and `ydotool`/`grim` on Wayland for input + screenshot, `/proc` + `wmctrl` for app enumeration. AT-SPI2-backed tree/observe/find and tesseract OCR throw `atspi_pending` / `ocr_pending` until those bindings land. Track under [`linux`](https://github.com/edihasaj/guiport/issues?q=label%3Alinux).

Prebuilt binaries for all three platforms are attached to every [release](https://github.com/edihasaj/guiport/releases/latest).

### Support matrix

Which verbs work on each platform today. Pending verbs don't crash — they exit
non-zero with a labeled, actionable error (the code is in the table), so agents
can branch on it. CI builds all three platforms and runs the platform-agnostic
unit tests on each.

| Verb / capability | macOS | Windows | Linux |
| --- | :---: | :---: | :---: |
| `apps` (list / resolve) | ✅ | ✅ | ✅¹ |
| `click-at` | ✅ | ✅ | ✅ |
| `type` | ✅ | ✅ | ✅ |
| `hotkey` | ✅ | ✅ | ✅ |
| `screenshot` (full screen) | ✅ | ✅² | ✅ |
| `screenshot` (single window) | ✅ | ✅² | ✅ X11 · ⏳ Wayland |
| `observe` / `tree` / `find` / `click` (by selector) | ✅ | ⏳ `uia_pending` | ⏳ `atspi_pending` |
| `find-text` / `click-text` (OCR) | ✅ | ✅³ | ⏳ `ocr_pending` |
| `record` | ✅ | ⏳ `recorder_pending` | ⏳ `recorder_pending` |
| `lifecycle` (launch / quit / kill / restart) | ✅ | ⏳ `unsupported` | ⏳ `unsupported` |

✅ implemented · ⏳ pending (throws a clear, labeled error)

¹ X11 gives full window counts via `wmctrl`; on Wayland `apps` falls back to a
`/proc` walk with no per-window data.
² Windows currently writes the capture as a 32-bpp BMP (a `.png` path is
rewritten to `.bmp`); PNG encoding via WIC is the follow-up.
³ Windows `find-text` / `click-text` are backed by WinRT OCR
(`Windows.Media.Ocr`).

## Why

Agents shouldn't drive desktop apps by guessing pixels. `guiport` exposes the desktop as structured data: app/window list, focused app/window, accessibility tree, element role/name/value/state/bounds/actions, screenshots only when needed, deterministic replay scripts after exploration.

## Install

macOS 13+. See [INSTALL.md](INSTALL.md) for full options + platform status.

```sh
# Homebrew (recommended) — universal binary, auto-updates with `brew upgrade`
brew install edihasaj/guiport/guiport

# Or install script
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh

# Or from source
swift build -c release && sudo cp .build/release/guiport /usr/local/bin/guiport
```

After install, grant the two macOS permissions and verify:

```sh
guiport doctor --fix   # opens the right Privacy panes
guiport doctor         # all green when ready
```

Homebrew ships (and runs the CLI from inside) a signed `guiport.app`, so macOS
shows guiport's real logo in Accessibility and Screen Recording and the grant
survives upgrades. For bare `swift build` runs, `doctor --fix` also registers
`~/Applications/guiport.app` so a real `guiport` app entry still appears instead
of only the invoking terminal.

Windows (input/screenshot/apps; UIA tree pending) — grab the prebuilt `guiport-<ver>-windows-x64.zip` from [releases](https://github.com/edihasaj/guiport/releases/latest), or install from source:

```powershell
iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
```

Linux (same shape; AT-SPI2 tree pending) — grab the prebuilt `guiport-<ver>-linux-x86_64.tar.gz` from [releases](https://github.com/edihasaj/guiport/releases/latest). Install xdotool+wmctrl+scrot (X11) or ydotool+grim (Wayland), then:

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

See [INSTALL.md](INSTALL.md) for full per-platform notes.

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

# Foreground an app without a click, guard keystrokes, and verify state:
guiport activate --app "Safari"                      # raise it (no relaunch, no click)
guiport type --into "Safari" "hello"                 # activate + verify, then type
guiport type --require-frontmost "Safari" "hello"    # refuse if Safari isn't frontmost
guiport assert --app "Safari" --frontmost \
  --front-title-contains "Start Page"                # nonzero exit when unmet

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
Run `guiport doctor --fix` to trigger the missing permission prompts (and, for
bare `swift build` runs, register `~/Applications/guiport.app`).

## Driving input from a background agent

macOS posts synthetic events into the *caller's* security session. A coding
agent (or SSH shell, or CI runner) usually runs in a **Background** launchd
session, so it can read AX trees from anywhere but its clicks/keystrokes never
reach the on-screen app — they go to the wrong session.

`guiport agent` solves this with a tiny daemon that runs in the logged-in
**Aqua** (GUI) session via a LaunchAgent. The CLI does all the AX work locally
(resolve the element, compute the point — session-agnostic) and forwards only
the final low-level event over a Unix socket; the daemon posts it where it
lands. A `guiport` invoked from a real Terminal in the GUI session skips the
bridge entirely (zero overhead).

```sh
guiport agent install     # run once; writes a LaunchAgent + starts the daemon
guiport agent status      # installed / running / socket
```

The daemon needs its **own** Accessibility grant — launchd is its parent, so
it can't inherit the grant from a granted terminal the way a foreground CLI
does. After `agent install`, enable **guiport** under System Settings →
Privacy & Security → Accessibility. A Developer-ID-signed build keeps that
grant stable across `brew upgrade`. Then `guiport click/type/hotkey` from any
background process lands on screen.

## Architecture

- Pure Swift, single binary.
- `GuiportCore` library: AX bridge, selector engine, input, screenshots, replay runner, MCP server.
- `guiport` CLI: thin wrapper using swift-argument-parser.

## Non-goals (MVP)

- No accessibility tree (UIA / AT-SPI2) on Windows/Linux yet — see the [support matrix](#support-matrix).
- No vision-first automation.
- No autonomous Manus clone.
- No background/session-0 automation.

## Related

- [**shotport**](https://github.com/edihasaj/shotport) — token-cheap screenshot capture for agents. Calls `guiport` for macOS app/desktop pixels and accessibility text, then extracts text first and budgets the image to a token limit.
- [**vmlab**](https://github.com/edihasaj/vmlab) — cross-OS verify orchestrator; drives `guiport` through its `guiport` transport.

## License

MIT — see LICENSE.

## Author

[Edi Hasaj](https://edihasaj.com)
