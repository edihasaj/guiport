import Foundation
import GuiportCore
#if canImport(AppKit)
import AppKit
#endif

/// Cross-platform-ish app lifecycle helpers. macOS uses NSWorkspace +
/// NSRunningApplication; other platforms throw "unsupported" until adapters
/// implement matching primitives.
enum Lifecycle {
    static func launch(app: String, timeout: Double) throws -> LifecycleCommand.LaunchResult {
        #if os(macOS)
        // Already running? No-op.
        if let existing = findRunning(matching: app).first {
            return LifecycleCommand.LaunchResult(
                app: app, pid: existing.processIdentifier,
                bundleId: existing.bundleIdentifier, launched: false)
        }

        let url: URL
        if app.hasPrefix("/") || app.hasSuffix(".app") {
            url = URL(fileURLWithPath: app)
        } else if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            url = resolved
        } else if let resolved = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/")),
                  resolved.lastPathComponent.lowercased().contains(app.lowercased()) {
            url = resolved
        } else {
            // Best-effort search /Applications by display name
            let fm = FileManager.default
            let candidates = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
            if let match = candidates.first(where: {
                $0.replacingOccurrences(of: ".app", with: "").lowercased() == app.lowercased()
            }) {
                url = URL(fileURLWithPath: "/Applications/\(match)")
            } else {
                throw GuiportError(code: "app_not_found",
                                   message: "could not resolve '\(app)' to a bundle id or .app path",
                                   hint: "pass a bundle id (com.x.y), a display name, or an absolute path to the .app")
            }
        }

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true

        var caught: Error?
        var launched: NSRunningApplication?
        let sem = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { running, error in
            launched = running
            caught = error
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)
        if let err = caught {
            throw GuiportError(code: "launch_failed", message: err.localizedDescription)
        }
        return LifecycleCommand.LaunchResult(
            app: app,
            pid: launched?.processIdentifier,
            bundleId: launched?.bundleIdentifier,
            launched: true
        )
        #else
        throw GuiportError(
            code: "unsupported",
            message: "lifecycle launch is only implemented on macOS",
            hint: "Windows/Linux app lifecycle is on the roadmap — track under the `windows` / `linux` labels."
        )
        #endif
    }

    static func activate(app: String, timeout: Double) throws -> LifecycleCommand.ActivateResult {
        #if os(macOS)
        guard let running = findRunning(matching: app).first else {
            throw GuiportError(code: "not_running",
                               message: "'\(app)' is not running — launch it first",
                               hint: "guiport lifecycle launch --app \(app)")
        }
        // Bring it to the front without relaunching or synthesizing a click.
        running.activate(options: [.activateAllWindows])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier
        return LifecycleCommand.ActivateResult(
            app: app, pid: running.processIdentifier,
            bundleId: running.bundleIdentifier, frontmost: frontmost)
        #else
        throw GuiportError(code: "unsupported", message: "lifecycle activate is only implemented on macOS")
        #endif
    }

    static func quit(app: String, force: Bool, timeout: Double) throws -> LifecycleCommand.QuitResult {
        #if os(macOS)
        let running = findRunning(matching: app)
        if running.isEmpty {
            return LifecycleCommand.QuitResult(
                action: force ? "kill" : "quit",
                app: app, pids: [], stopped: true)
        }

        let pids = running.map(\.processIdentifier)
        for proc in running {
            if force {
                _ = proc.forceTerminate()
            } else {
                _ = proc.terminate()
            }
        }

        // Poll for exit
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let still = findRunning(matching: app)
            if still.isEmpty {
                return LifecycleCommand.QuitResult(
                    action: force ? "kill" : "quit",
                    app: app, pids: pids, stopped: true)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        // Timeout: escalate to forceTerminate if we were polite, otherwise report failure.
        if !force {
            for proc in findRunning(matching: app) {
                _ = proc.forceTerminate()
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        let stillRunning = findRunning(matching: app)
        return LifecycleCommand.QuitResult(
            action: force ? "kill" : "quit",
            app: app, pids: pids,
            stopped: stillRunning.isEmpty
        )
        #else
        throw GuiportError(
            code: "unsupported",
            message: "lifecycle quit is only implemented on macOS",
            hint: "Windows/Linux app lifecycle is on the roadmap — track under the `windows` / `linux` labels."
        )
        #endif
    }

    #if os(macOS)
    private static func findRunning(matching needle: String) -> [NSRunningApplication] {
        let lc = needle.lowercased()
        return NSWorkspace.shared.runningApplications.filter { a in
            if let bid = a.bundleIdentifier, bid.lowercased() == lc { return true }
            if let name = a.localizedName, name.lowercased() == lc { return true }
            return false
        }
    }
    #endif
}
