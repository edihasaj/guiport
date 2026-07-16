import ArgumentParser
import GuiportCore

/// Frontmost safety net shared by keystroke commands (`type`, `hotkey`).
///
/// Without a guard, a keystroke lands in whatever app is frontmost — which may
/// be a terminal or chat app, not the intended target. Two modes:
///
///   - `--into <app>`      auto-activate: raise the app, verify it's frontmost,
///                         then send keys.
///   - `--require-frontmost <app>`  refuse: verify the app is *already*
///                         frontmost and exit nonzero if not (no activation).
struct FrontmostGuard: ParsableArguments {
    @Option(name: .long, help: "Activate this app and verify it's frontmost before sending keys (bundle id or name).")
    var into: String?

    @Option(name: .long, help: "Refuse to send keys unless this app is already frontmost (bundle id or name).")
    var requireFrontmost: String?

    /// Enforce whichever mode(s) were requested. Throws (nonzero exit) before any
    /// key is sent when the target can't be brought to / isn't at the front.
    func enforce() throws {
        if let app = into {
            let target = try Adapter.current.resolveApp(name: app)
            let r = try Adapter.current.activate(target: target)
            guard r.frontmost else {
                throw GuiportError(
                    code: "activate_failed",
                    message: "could not bring '\(target.name)' to the front before sending keys",
                    hint: "check the app isn't blocked by a modal or a different Space"
                )
            }
        }
        if let app = requireFrontmost {
            let target = try Adapter.current.resolveApp(name: app)
            // Snapshot once so the failure message names the app that actually
            // held the front, not whatever grabbed it a moment later.
            let front = Adapter.current.frontmostApp()
            guard let front, front.pid == target.pid else {
                throw GuiportError(
                    code: "not_frontmost",
                    message: "'\(target.name)' is not frontmost (front app: \(front?.name ?? "unknown")); refusing to send keys",
                    hint: "pass --into \"\(app)\" to auto-activate, or run `guiport activate --app \"\(app)\"` first"
                )
            }
        }
    }
}
