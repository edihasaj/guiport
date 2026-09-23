import ArgumentParser
import Foundation
import GuiportCore

#if canImport(GuiportMacAdapter)
import GuiportMacAdapter
#endif

/// A long-lived, pull-friendly visual feed for computer-use agents.
///
/// Each NDJSON event points at one stable image path. The file is replaced
/// atomically, so an agent can ignore frames until it needs fresh pixels and
/// then open the latest image without receiving a video firehose.
struct StreamCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stream",
        abstract: "Stream screen frames until interrupted or a limit is reached."
    )

    @OptionGroup var app: AppOption

    @Option(name: .long, help: "Maximum frames per second (0.1...60).")
    var fps: Double = 2

    @Option(name: .long, help: "Stop after this many seconds.")
    var seconds: Double?

    @Option(name: .long, help: "Stop after this many frames.")
    var frames: Int?

    @Option(name: [.customShort("o"), .long], help: "Stable PNG path updated atomically. Defaults to artifacts/.")
    var output: String?

    @Option(name: .long, help: "Also keep every frame as frame-NNNNNN-<epoch ms>.png in this directory.")
    var framesDir: String?

    @Flag(name: .long, help: "With --app, capture the window's screen region so other apps' overlays are included.")
    var withOverlays = false

    mutating func validate() throws {
        guard (0.1...60).contains(fps) else {
            throw ValidationError("--fps must be between 0.1 and 60")
        }
        if let seconds, seconds <= 0 {
            throw ValidationError("--seconds must be greater than zero")
        }
        if let frames, frames <= 0 {
            throw ValidationError("--frames must be greater than zero")
        }
    }

    func run() async throws {
        let target: AppTarget? = ScreenshotCommand.targetsWindow(app: app.app, window: app.window)
            ? try Adapter.current.resolveApp(name: app.app, windowTitle: app.window)
            : nil
        let path = output ?? Adapter.current.defaultScreenshotPath()
        let deadline = seconds.map { Date().addingTimeInterval($0) }
        let interval = 1 / fps
        var sequence = 0

        emit([
            "event": "started",
            "fps": fps,
            "output": path,
            "scope": target == nil ? "screen" : "window",
        ])

        #if canImport(GuiportMacAdapter)
        if #available(macOS 14.0, *) {
            try await runLive(target: target, path: path, deadline: deadline)
            return
        }
        #endif

        while deadline.map({ Date() < $0 }) ?? true {
            if let frames, sequence >= frames { break }
            let frameStarted = Date()
            let result = try captureAtomically(target: target, path: path)
            sequence += 1

            #if canImport(GuiportMacAdapter)
            // The overlay lifetime now matches the stream lifetime. No separate
            // demo/start command is needed, and the physical cursor remains live.
            SessionBridge.pingActivity(kind: "stream", point: nil)
            #endif

            emit([
                "event": "frame",
                "sequence": sequence,
                "captured_at": ISO8601DateFormatter().string(from: Date()),
                "path": result.path,
                "width": result.width,
                "height": result.height,
                "scope": result.scope,
            ])

            let remaining = interval - Date().timeIntervalSince(frameStarted)
            if remaining > 0 {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }

        emit(["event": "stopped", "frames": sequence, "path": path])
    }

    #if canImport(GuiportMacAdapter)
    /// One ScreenCaptureKit session for the whole run: frames arrive as the
    /// screen changes instead of restarting a capture per frame.
    @available(macOS 14.0, *)
    private func runLive(target: AppTarget?, path: String, deadline: Date?) async throws {
        let limit = frames
        var delivered = 0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try await LiveCapture.run(
            target: target,
            fps: fps,
            withOverlays: withOverlays,
            output: path,
            framesDir: framesDir,
            shouldStop: { sequence in
                if let limit, sequence >= limit { return true }
                return deadline.map { Date() >= $0 } ?? false
            },
            onFrame: { frame, sequence in
                delivered = sequence
                SessionBridge.pingActivity(kind: "stream", point: nil)
                var event: [String: Any] = [
                    "event": "frame",
                    "sequence": sequence,
                    "captured_at": formatter.string(from: frame.capturedAt),
                    "captured_at_ms": Int(frame.capturedAt.timeIntervalSince1970 * 1000),
                    "path": frame.path,
                    "width": frame.width,
                    "height": frame.height,
                    "scope": frame.scope,
                ]
                if let archived = frame.archivedPath { event["archived_path"] = archived }
                emit(event)
            }
        )
        emit(["event": "stopped", "frames": delivered, "path": path])
    }
    #endif

    private func captureAtomically(target: AppTarget?, path: String) throws -> ScreenshotResult {
        let destination = URL(fileURLWithPath: path)
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).next-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let captured = try Adapter.current.captureScreenshot(target: target, to: temporary.path)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
        return ScreenshotResult(
            path: destination.path,
            width: captured.width,
            height: captured.height,
            scope: captured.scope
        )
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
