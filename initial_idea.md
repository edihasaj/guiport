# guiport initial idea

## Name

`guiport`

Meaning: a local port from desktop GUI state into agent-readable data and agent-safe actions.

CLI shape:

```sh
guiport observe
guiport tree --app "MyApp"
guiport find 'button[name="Save"]'
guiport click 'button[name="Save"]'
guiport type 'hello'
guiport run test.yaml
guiport serve --mcp
```

## Core idea

Agents should not drive desktop apps by guessing pixels first. `guiport` exposes the desktop as structured data:

- app/window list
- focused app/window
- accessibility tree
- element role/name/value/state/bounds/actions
- screenshots only when needed
- OCR/image fallback only when accessibility is missing
- deterministic replay scripts after exploration

Target users:

- developers testing local dev apps
- QA for production desktop apps
- agents like Claude, Codex, opencode, Gemini CLI
- CI workers running real desktop smoke tests

## Product shape

One agent-facing CLI and server. Multiple native adapters.

- Shared core: CLI, MCP server, planner bridge, recorder, replay runner.
- macOS adapter: Swift, Accessibility API, Screen Recording, Input Monitoring.
- Windows adapter: C#/.NET, Microsoft UI Automation, Win32 input/window APIs.
- Linux adapter: AT-SPI2 over D-Bus, X11/Xvfb first, Wayland later.

Do not pretend one automation backend is enough. The cross-platform surface should be ours; the OS integrations should be native.

## Fast path

Speed comes from avoiding full screenshot reasoning.

Use this order:

1. Native accessibility tree snapshot.
2. Cache element tree per window.
3. Incremental refresh after actions.
4. Selector match by automation id, role, name, text, value, bounds.
5. Screenshot crop for ambiguous elements.
6. OCR/image match only as fallback.
7. LLM only for exploration, recovery, and converting intent into selectors.
8. Replay without LLM whenever possible.

Expected speed:

- `observe`: 50-300 ms for window metadata, 200-1200 ms for full tree depending app.
- `find`: 5-50 ms against cached tree.
- `click/type`: OS event latency, usually under 100 ms plus app response.
- LLM exploration: seconds, not milliseconds. Use sparingly.

## Is it fully possible?

Mostly possible for developer and QA workflows. Not fully possible as a universal "any app, always fast, always reliable" operator.

Works well when:

- app exposes accessibility labels/roles/automation ids
- app has stable windows and controls
- tests run in a real desktop session
- workflows are converted into replayable scripts
- agent has screenshots plus structured tree

Weak when:

- app is custom-rendered canvas/OpenGL/game UI
- Electron/Chromium accessibility is disabled or poorly labeled
- Linux Wayland blocks global input/screen access
- macOS permissions are missing or reset after rebuild/signing changes
- Windows runs as service/session 0 instead of logged-in desktop
- app uses unstable generated element IDs
- animations/popovers make timing nondeterministic
- remote desktop, VMs, and scaled displays change coordinates

## Main drawbacks

- Native adapters are unavoidable.
- macOS permissions create onboarding friction.
- Windows GUI automation needs an interactive user session.
- Linux is split between X11, Wayland, GTK, Qt, Electron.
- Accessibility trees are inconsistent across apps.
- Vision fallback is slow and expensive.
- LLM-only actions are too flaky for production tests.
- Parallel desktop tests on one machine are hard; input devices and accessibility layers are shared.
- CI needs real runners or VMs with logged-in desktops.

## What it takes

Minimum viable quality:

- stable selector model
- fast tree extraction and caching
- screenshot + tree artifacts for every failed step
- wait/retry primitives
- record once, replay many times
- app-specific profiles for launch, permissions, selectors, ignore zones
- safety rules: allowlisted apps, blocked destructive keys/actions, max action loops

Good developer experience:

- installable single binary or npm/pip wrapper
- `guiport doctor`
- `guiport inspect` interactive selector picker
- MCP server for agents
- YAML/JSON test format
- concise terminal output
- artifacts folder with screenshots, tree JSON, action log

## Existing world

Useful references:

- OpenAI computer use: screenshot/action loop, good for exploration, beta reliability limits.
- Anthropic computer use: same general model, desktop control via screenshot/mouse/keyboard.
- Appium: proven protocol, official macOS and Windows desktop drivers, no first-class Linux native desktop driver.
- nut.js / PyAutoGUI: useful low-level cross-platform input/screenshot, not enough structured UI data.
- pywinauto/FlaUI: strong Windows UIA paths.
- Apple AXUIElement: right base for macOS.
- AT-SPI2: right base for Linux accessibility.

Positioning: `guiport` is not another RPA macro recorder. It is a fast desktop observation/control layer designed for coding agents.

