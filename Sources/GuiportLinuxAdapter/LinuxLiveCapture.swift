#if os(Linux)
import Foundation
import GuiportCore

/// One `ffmpeg -f x11grab` process kept open for the whole `guiport stream` run
/// on X11. The per-frame path starts scrot or ImageMagick for every frame; this
/// reads a continuous PNG stream from ffmpeg's stdout instead. Wayland has no
/// portable equivalent, so it keeps capturing frame by frame.
enum LinuxLiveCapture {
    static func isAvailable(for request: LiveStreamRequest) -> Bool {
        LinuxSession.current == .x11 && Shell.which("ffmpeg")
            && (request.target == nil || request.withOverlays)
    }

    static func run(
        _ request: LiveStreamRequest,
        shouldStop: @escaping @Sendable (Int) -> Bool,
        onFrame: @escaping (StreamFrame, Int) -> Void
    ) throws {
        let display = ProcessInfo.processInfo.environment["DISPLAY"] ?? ":0"
        var input = display
        var sizeArgs: [String] = []
        var scope = "screen"
        if let target = request.target {
            let g = try LinuxScreenshot.x11Geometry(for: target)
            input = "\(display)+\(g.x),\(g.y)"
            sizeArgs = ["-video_size", "\(g.width)x\(g.height)"]
            scope = "region"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["--", "ffmpeg", "-loglevel", "error", "-f", "x11grab",
                             "-framerate", String(format: "%.3f", request.fps)]
            + sizeArgs + ["-i", input, "-f", "image2pipe", "-vcodec", "png", "-"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        var buffer = Data()
        var sequence = 0
        let reader = out.fileHandleForReading
        while !shouldStop(sequence) {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let png = nextPNG(&buffer) {
                let capturedAt = Date()
                try writeAtomically(png, to: request.output)
                sequence += 1
                var archived: String?
                if let dir = request.framesDir {
                    let path = StreamArchive.path(in: dir, sequence: sequence, capturedAt: capturedAt)
                    try png.write(to: URL(fileURLWithPath: path))
                    archived = path
                }
                let (w, h) = LinuxScreenshot.pngDimensions(png) ?? (0, 0)
                onFrame(StreamFrame(path: request.output, archivedPath: archived, width: w, height: h,
                                    scope: scope, capturedAt: capturedAt), sequence)
                if shouldStop(sequence) { return }
            }
        }
        if sequence == 0 {
            process.terminate()
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GuiportError(code: "stream_failed", message: "ffmpeg x11grab produced no frames: \(detail.prefix(300))",
                               hint: "Check DISPLAY and that ffmpeg was built with x11grab.")
        }
    }

    /// Splits one complete PNG (signature through IEND chunk + CRC) off the front.
    static func nextPNG(_ buffer: inout Data) -> Data? {
        let iend: [UInt8] = [0x49, 0x45, 0x4E, 0x44]
        guard let range = buffer.range(of: Data(iend)) else { return nil }
        let end = range.upperBound + 4
        guard buffer.count >= end else { return nil }
        let png = buffer.prefix(upTo: end)
        buffer.removeSubrange(buffer.startIndex..<end)
        return Data(png)
    }

    private static func writeAtomically(_ png: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }
}
#endif
