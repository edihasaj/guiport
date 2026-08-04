import Foundation

/// Cross-platform "stop" signal shared between the on-screen overlay (which the
/// user drives) and every guiport process that posts input.
///
/// When the user presses **Stop** in the overlay pill or hits **ESC**, the Aqua
/// agent-daemon calls `requestCancel`. That drops a small file at
/// `~/.guiport/cancel`. Every input op — locally or forwarded — calls
/// `throwIfCancelled()` first, so the very next click/type/hotkey aborts with a
/// clear `cancelled` error. That error propagates up as a failed tool call to
/// whatever agent (Claude, Codex, a YAML replay) is driving guiport, so it stops.
///
/// The signal is deliberately *sticky for a cool-down window* (default 10s): a
/// single Stop halts a whole burst of queued actions, not just the one in
/// flight, and a persistent agent that retries keeps getting cancelled until it
/// gives up. It auto-heals after the window so a forgotten flag never wedges
/// guiport permanently; `Cancellation.clear()` (via `guiport resume`) clears it
/// at once.
public enum Cancellation {
    /// `~/.guiport/cancel` — the presence + freshness of this file is the signal.
    public static var flagPath: String {
        flagURL.path
    }

    static var guiportDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".guiport")
    }

    private static var flagURL: URL {
        URL(fileURLWithPath: guiportDir).appendingPathComponent("cancel")
    }

    /// How long a Stop stays in effect before auto-healing, in milliseconds.
    /// Override with `GUIPORT_CANCEL_WINDOW_MS`.
    static var windowMs: Int {
        if let raw = ProcessInfo.processInfo.environment["GUIPORT_CANCEL_WINDOW_MS"],
           let v = Int(raw), v >= 0 { return v }
        return 10_000
    }

    /// Record a Stop. Called by the overlay (daemon) and by `guiport stop`.
    public static func requestCancel(reason: String) {
        requestCancel(reason: reason, at: flagURL, nowMs: currentTimeMs)
    }

    /// Internal dependency-injected form used by deterministic, parallel tests.
    static func requestCancel(reason: String, at flagURL: URL, nowMs: Int) {
        try? FileManager.default.createDirectory(
            at: flagURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let payload: [String: Any] = [
            "reason": reason,
            "ts": nowMs,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: flagURL)
        }
    }

    /// Clear any Stop immediately. Called by `guiport resume` and on daemon start.
    public static func clear() {
        clear(at: flagURL)
    }

    static func clear(at flagURL: URL) {
        try? FileManager.default.removeItem(at: flagURL)
    }

    /// The active Stop reason, or nil when guiport is free to act. Auto-clears an
    /// expired flag as a side effect so callers never observe a stale signal.
    public static func activeReason() -> String? {
        activeReason(at: flagURL, windowMs: windowMs, nowMs: currentTimeMs)
    }

    static func activeReason(at flagURL: URL, windowMs: Int, nowMs: Int) -> String? {
        guard let data = FileManager.default.contents(atPath: flagURL.path) else { return nil }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let ts = (obj?["ts"] as? Int) ?? 0
        let ageMs = nowMs - ts
        if ageMs > windowMs {
            clear(at: flagURL)
            return nil
        }
        return (obj?["reason"] as? String) ?? "stopped"
    }

    public static func isCancelled() -> Bool { activeReason() != nil }

    /// Throw a `cancelled` error if a Stop is in effect. Call at the top of every
    /// input op so the abort lands before anything touches the user's screen.
    public static func throwIfCancelled() throws {
        try throwIfCancelled(at: flagURL, windowMs: windowMs, nowMs: currentTimeMs)
    }

    static func throwIfCancelled(at flagURL: URL, windowMs: Int, nowMs: Int) throws {
        guard let reason = activeReason(at: flagURL, windowMs: windowMs, nowMs: nowMs) else { return }
        throw GuiportError(
            code: "cancelled",
            message: "GuiPort was stopped by the user (\(reason)).",
            hint: "The user pressed Stop (or ESC) in the GuiPort overlay. Halt the current task. Run `guiport resume` to re-enable, or it clears automatically after the cool-down window."
        )
    }

    private static var currentTimeMs: Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}
