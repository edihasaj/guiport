import Foundation
import CoreGraphics
import GuiportCore

/// Bridges synthetic input from a non-GUI (Background) launchd session into the
/// logged-in Aqua session.
///
/// macOS posts CGEvents into the *caller's* security session. A coding agent
/// usually runs in a Background session (e.g. launched by a daemon, an SSH
/// shell, or a CI runner), so its clicks/keystrokes never reach the on-screen
/// foreground app — even though AX *reads* work fine from anywhere.
///
/// guiport solves this with a tiny daemon (`guiport agent-daemon`) that runs in
/// the Aqua session via a LaunchAgent. The CLI does all the AX work locally
/// (resolving the element, computing the click point — all read-only and
/// session-agnostic) and forwards only the final low-level event over a Unix
/// socket. The daemon, being in Aqua, posts it where it lands.
/// Thrown internally to short-circuit an overlay-only request to a plain "ok".
private struct EarlyOK: Error {}

public enum SessionBridge {
    /// Socket the Aqua daemon listens on and the Background CLI dials.
    public static let socketPath: String =
        (NSHomeDirectory() as NSString).appendingPathComponent(".guiport/agent.sock")

    /// True inside the daemon process itself — set via env so forwarded events
    /// execute locally instead of looping back out to the socket.
    static var isDaemon: Bool {
        ProcessInfo.processInfo.environment["GUIPORT_AGENT_DAEMON"] == "1"
    }

    /// Whether this process can post events that reach the screen. Cached: a
    /// process's session membership doesn't change over its lifetime.
    static let hasGraphicAccess: Bool = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["managername"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return true } // fail open — assume direct works
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.trimmingCharacters(in: .whitespacesAndNewlines) == "Aqua"
    }()

    /// Forward input to the Aqua daemon when we lack graphic access and a daemon
    /// is listening. The daemon itself, and processes that already have graphic
    /// access (a Terminal in the Aqua session), post directly.
    static func shouldForward() -> Bool {
        if isDaemon { return false }
        if hasGraphicAccess { return false }
        return FileManager.default.fileExists(atPath: socketPath)
    }

    /// Tell the Aqua overlay daemon that guiport just acted on screen, so it can
    /// show the glow. Best-effort and non-fatal: used by processes that post
    /// input *directly* (they have graphic access) and therefore don't forward a
    /// real op the daemon would otherwise see. No-op inside the daemon itself
    /// (it notes activity locally) to avoid dialling its own socket mid-request.
    public static func pingActivity(kind: String, point: CGPoint?) {
        if isDaemon { return }
        if shouldForward() { return } // the forwarded op already drives the overlay
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        var payload: [String: Any] = ["op": "activity", "kind": kind]
        if let point { payload["x"] = Double(point.x); payload["y"] = Double(point.y) }
        try? send(payload)
    }

    /// Human-readable reason input can't be delivered, for error hints.
    static func unreachableHint() -> String {
        if FileManager.default.fileExists(atPath: socketPath) {
            return "the Aqua input agent socket exists but the daemon didn't respond — try `guiport agent restart`"
        }
        return "this process has no GUI session; install the Aqua input agent once with `guiport agent install`"
    }

    // MARK: - Client (Background CLI → daemon)

    /// Send one input op to the daemon and wait for its ack. Throws on a
    /// connection or op failure so callers surface a clear error.
    static func send(_ payload: [String: Any]) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw GuiportError(code: "bridge_socket", message: "could not open agent socket")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                for (i, b) in pathBytes.prefix(103).enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[min(pathBytes.count, 103)] = 0
            }
        }
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw GuiportError(code: "bridge_connect",
                               message: "Aqua input agent not reachable",
                               hint: unreachableHint())
        }

        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)
        try data.withUnsafeBytes { buf in
            var off = 0
            while off < data.count {
                let n = write(fd, buf.baseAddress!.advanced(by: off), data.count - off)
                if n <= 0 { throw GuiportError(code: "bridge_write", message: "agent socket write failed") }
                off += n
            }
        }

        var reply = [UInt8](repeating: 0, count: 8192)
        let n = read(fd, &reply, reply.count)
        if n > 0,
           let obj = try? JSONSerialization.jsonObject(with: Data(reply[0..<n])) as? [String: Any] {
            if let ok = obj["ok"] as? Bool, !ok {
                throw GuiportError(code: "bridge_op_failed",
                                   message: (obj["error"] as? String) ?? "agent op failed")
            }
        }
    }

    // MARK: - Server (Aqua daemon)

    /// Run the input daemon: bind the socket, accept one op per connection, and
    /// execute it locally (this process is in Aqua, so events land). Blocks.
    public static func runDaemon() throws {
        // Register for Accessibility so the daemon binary appears in System
        // Settings → Privacy → Accessibility and the user can grant it. The
        // daemon needs its OWN grant: launchd is its parent, so it can't
        // inherit AX from a granted terminal the way a foreground CLI does.
        // (A Developer-ID-signed build keeps this grant stable across upgrades.)
        let trusted = AXBridge.promptAccessibilityIfNeeded()
        FileHandle.standardError.write(Data("[guiport] agent-daemon accessibility trusted: \(trusted)\n".utf8))

        let dir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw GuiportError(code: "daemon_socket", message: "socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                for (i, b) in pathBytes.prefix(103).enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[min(pathBytes.count, 103)] = 0
            }
        }
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw GuiportError(code: "daemon_bind", message: "could not bind \(socketPath) (errno \(errno))")
        }
        chmod(socketPath, 0o600)
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw GuiportError(code: "daemon_listen", message: "listen() failed")
        }

        FileHandle.standardError.write(Data("[guiport] agent-daemon listening on \(socketPath)\n".utf8))

        // Clear any stale Stop signal left by a previous run/crash so the daemon
        // starts in a clean, actionable state.
        Cancellation.clear()

        // The socket accept loop moves to a background thread so the main thread
        // can host AppKit for the on-screen overlay (glow border, cursor halo,
        // Stop pill). Overlay updates are marshalled back to main.
        let acceptThread = Thread {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                handleClient(client)
                close(client)
            }
        }
        acceptThread.name = "com.edihasaj.guiport.daemon.accept"
        acceptThread.stackSize = 1 << 20
        acceptThread.start()

        OverlayHost.runMain()  // blocks forever, running the AppKit event loop
    }

    private static func handleClient(_ client: Int32) {
        var buf = [UInt8](repeating: 0, count: 8192)
        var collected = [UInt8]()
        while true {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            collected.append(contentsOf: buf[0..<n])
            if collected.contains(0x0A) { break }
        }
        guard let nl = collected.firstIndex(of: 0x0A) else { return }
        let line = Data(collected[0..<nl])
        var reply: [String: Any] = ["ok": true]
        do {
            guard let op = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw GuiportError(code: "daemon_parse", message: "bad request")
            }
            // Drive the on-screen overlay from every request (forwarded input and
            // bare activity pings alike) so the glow tracks what guiport is doing.
            let kind = (op["op"] as? String) ?? "activity"
            let point: CGPoint? = {
                if let x = op["x"] as? Double, let y = op["y"] as? Double { return CGPoint(x: x, y: y) }
                return nil
            }()
            OverlayHost.noteActivity(kind: kind, point: point)

            // An "activity" op is overlay-only — no input to post.
            if kind == "activity" { throw EarlyOK() }

            // Honour a Stop that landed between forwarding and execution.
            try Cancellation.throwIfCancelled()
            try Input.executeForwardedOp(op)
        } catch is EarlyOK {
            // overlay-only op; reply ok
        } catch let e as GuiportError {
            reply = ["ok": false, "error": e.message]
        } catch {
            reply = ["ok": false, "error": "\(error)"]
        }
        if var out = try? JSONSerialization.data(withJSONObject: reply) {
            out.append(0x0A)
            out.withUnsafeBytes { _ = write(client, $0.baseAddress, out.count) }
        }
    }
}
