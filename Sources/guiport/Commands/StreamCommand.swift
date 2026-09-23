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
        let limit = frames
        if let framesDir {
            try FileManager.default.createDirectory(atPath: framesDir, withIntermediateDirectories: true)
        }

        emit([
            "event": "started",
            "fps": fps,
            "output": path,
            "scope": target == nil ? "screen" : (withOverlays ? "region" : "window"),
        ])

        // Prefer one long-lived capture session (ScreenCaptureKit on macOS 14+,
        // ffmpeg x11grab on Linux X11); fall back to one capture per frame.
        let delivered = FrameCounter()
        let request = LiveStreamRequest(target: target, fps: fps, withOverlays: withOverlays,
                                        output: path, framesDir: framesDir)
        let live = try await Adapter.current.runLiveStream(request, shouldStop: { sequence in
            if let limit, sequence >= limit { return true }
            return deadline.map { Date() >= $0 } ?? false
        }, onFrame: { frame, sequence in
            delivered.value = sequence
            emitFrame(frame, sequence: sequence)
        })
        if live {
            emit(["event": "stopped", "frames": delivered.value, "path": path])
            return
        }

        let interval = 1 / fps
        var sequence = 0
        while deadline.map({ Date() < $0 }) ?? true {
            if let limit, sequence >= limit { break }
            let frameStarted = Date()
            let result = try captureAtomically(target: target, path: path)
            let capturedAt = Date()
            sequence += 1
            var archived: String?
            if let framesDir {
                let copy = StreamArchive.path(in: framesDir, sequence: sequence, capturedAt: capturedAt)
                try FileManager.default.copyItem(atPath: result.path, toPath: copy)
                archived = copy
            }
            emitFrame(StreamFrame(path: result.path, archivedPath: archived, width: result.width,
                                  height: result.height, scope: result.scope, capturedAt: capturedAt),
                      sequence: sequence)

            let remaining = interval - Date().timeIntervalSince(frameStarted)
            if remaining > 0 {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }

        emit(["event": "stopped", "frames": sequence, "path": path])
    }

    private func emitFrame(_ frame: StreamFrame, sequence: Int) {
        #if canImport(GuiportMacAdapter)
        // The overlay lifetime now matches the stream lifetime. No separate
        // demo/start command is needed, and the physical cursor remains live.
        SessionBridge.pingActivity(kind: "stream", point: nil)
        #endif
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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

    private func captureAtomically(target: AppTarget?, path: String) throws -> ScreenshotResult {
        let destination = URL(fileURLWithPath: path)
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).next-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let captured = try Adapter.current.captureScreenshot(target: target, to: temporary.path,
                                                               includeOverlays: withOverlays)
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

/// Frame count shared with the live-stream callback.
private final class FrameCounter: @unchecked Sendable {
    var value = 0
}
