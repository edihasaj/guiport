import AppKit
import Foundation
import GuiportCore

/// Foreground / frontmost helpers for macOS. Raising an app uses
/// `NSRunningApplication.activate` — no relaunch, no synthetic click, so the
/// mouse never moves and nothing in the app's content gets hit as a side effect.
enum Activation {
    static func activate(target: AppTarget) throws -> ActivationResult {
        guard let running = NSRunningApplication(processIdentifier: target.pid) else {
            throw GuiportError(
                code: "app_not_running",
                message: "'\(target.name)' (pid \(target.pid)) is not running",
                hint: "launch it first: guiport lifecycle launch --app \"\(target.name)\""
            )
        }

        let alreadyFront = isFrontmost(pid: target.pid)
        var activated = false
        if !alreadyFront {
            // The raise was issued. `activate(options:)`'s Bool return is
            // unreliable on macOS 14+ (can report false even when the app comes
            // forward), so we record that we asked and let `frontmost` below
            // reflect the actual settled outcome.
            _ = running.activate(options: [])
            activated = true
            // Activation is asynchronous; poll briefly (≤0.5s) so a follow-up
            // assert/type observes the new frontmost app instead of racing it.
            for _ in 0..<25 {
                if isFrontmost(pid: target.pid) { break }
                usleep(20_000)
            }
        }

        return ActivationResult(
            app: target.name,
            pid: target.pid,
            bundleId: target.bundleId,
            alreadyFrontmost: alreadyFront,
            activated: activated,
            frontmost: isFrontmost(pid: target.pid)
        )
    }

    static func frontmostApp() -> AppInfo? {
        guard let a = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = a.processIdentifier
        return AppInfo(
            name: a.localizedName ?? a.bundleIdentifier ?? "pid:\(pid)",
            bundleId: a.bundleIdentifier,
            pid: pid,
            active: true,
            windowCount: AXBridge.windowCount(pid: pid)
        )
    }

    private static func isFrontmost(pid: Int32) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
}
