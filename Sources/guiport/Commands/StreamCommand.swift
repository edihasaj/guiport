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

    @Option(name: .long, help: "Maximum frames per second (0.1...10).")
    var fps: Double = 2

    @Option(name: .long, help: "Stop after this many seconds.")
    var seconds: Double?

    @Option(name: .long, help: "Stop after this many frames.")
    var frames: Int?

    @Option(name: [.customShort("o"), .long], help: "Stable PNG path updated atomically. Defaults to artifacts/.")
    var output: String?

    mutating func validate() throws {
        guard (0.1...10).contains(fps) else {
            throw ValidationError("--fps must be between 0.1 and 10")
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
