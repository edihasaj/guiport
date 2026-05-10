# guiport MVP goal

## Goal

Build a fast CLI/MCP desktop control layer that lets agents inspect and operate one local desktop app through structured UI data, then save actions as replayable tests.

## MVP scope

Platform first: macOS.

Why: fastest to validate locally, strong Accessibility API, direct fit for dev app testing.

## MVP commands

```sh
guiport doctor
guiport apps
guiport observe --app "App Name"
guiport tree --app "App Name" --json
guiport find --app "App Name" 'button[name="Save"]'
guiport click --app "App Name" 'button[name="Save"]'
guiport type "hello"
guiport screenshot --app "App Name"
guiport record smoke.yaml
guiport run smoke.yaml
guiport serve --mcp
```

## Implementation plan

1. Create CLI shell and JSON output contract.
2. Build macOS helper in Swift for app list, window list, AX tree, bounds, actions.
3. Add input actions: click, type, hotkey, scroll.
4. Add selector engine: role, name, value, identifier, text, index, bounds.
5. Add cache: tree snapshot per focused window with explicit refresh.
6. Add screenshots and artifacts on every command failure.
7. Add YAML replay runner with `wait`, `find`, `click`, `type`, `assert`.
8. Add MCP server wrapping the same commands.
9. Test on one native app and one Electron app.
10. Write `doctor` checks for permissions and missing capabilities.

## Non-goals

- No full autonomous Manus clone in MVP.
- No Windows/Linux adapter until macOS path works.
- No vision-first automation.
- No background service/session automation.
- No broad destructive system control.

## Success criteria

- Agent can inspect a running app in under 1 second.
- Agent can click/type by selector, not coordinates.
- A recorded 5-10 step smoke test replays 10 times with no LLM.
- Failures produce screenshot, tree JSON, and action log.
- Claude/Codex/opencode/Gemini can call it through CLI or MCP.

## Next platform order

1. macOS AX adapter.
2. Windows UIA adapter.
3. Linux AT-SPI2 adapter on X11/Xvfb.
4. Wayland support after core API stabilizes.

