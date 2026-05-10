# Contributing to guiport

Thanks for taking a look. guiport is small and opinionated — contributions that keep it that way are welcome.

## Wedge

guiport is **agent-facing developer/QA infra for desktop apps**. Not a generic Manus clone, not an RPA recorder. Keep PRs aligned with that wedge:

- Faster, more reliable AX inspection.
- Better selectors and replay determinism.
- Cleaner agent surfaces (CLI flags, MCP tools).
- Platform adapters (Windows UIA, Linux AT-SPI2) — but only after macOS is solid.

## Requirements

- macOS 13+
- Swift 5.9+ (install via `xcode-select --install` or Xcode)

## Build & test

```sh
swift build
swift test
swift run guiport doctor
```

End-to-end smoke:

```sh
open -a Calculator
swift run guiport run examples/calculator-smoke.yaml
```

## PR checklist

- [ ] `swift build` and `swift test` pass.
- [ ] If you changed behavior, update `examples/` or `README.md`.
- [ ] If you changed CLI surface, update `README.md` quick-start.
- [ ] Conventional commit subject (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`).
- [ ] No `--no-verify`, no `--amend` of pushed commits.

## Style

- Telegraph-style commit bodies — say *what* and *why*, skip filler.
- Keep files under ~500 LOC; split modules instead of monoliths.
- No comments restating the code; only document non-obvious *why*.
- Tests next to the code they cover (`Tests/GuiportCoreTests/...`).

## Reporting bugs

Use the issue templates. For AX-related bugs, include:

- macOS version (`sw_vers`)
- App name + version
- `guiport doctor --json` output
- `guiport tree --app "<App>" --pretty` excerpt around the failing element

## Security

See [`SECURITY.md`](SECURITY.md). Don't open public issues for security reports.

## License

MIT. By contributing you agree your contributions are licensed under MIT.
