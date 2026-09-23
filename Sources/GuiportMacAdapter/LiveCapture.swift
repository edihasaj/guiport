import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import GuiportCore
import ScreenCaptureKit
import VideoToolbox

/// One ScreenCaptureKit stream kept open for the whole `guiport stream` run.
///
/// The one-shot path lists shareable content and captures a still for every
/// frame, which caps the feed at a few frames per second and adds jitter
/// between frames. A persistent `SCStream` delivers frames as the screen
/// changes, up to the requested rate, until the caller stops it.
@available(macOS 14.0, *)
public enum LiveCapture {
    /// Streams frames until `shouldStop` returns true.
    /// - Parameters:
    ///   - target: window to follow; nil streams the main display.
    ///   - withOverlays: for a window target, capture that region of the display
    ///     instead of the lone window, so floating panels drawn by other apps
    ///     (autocomplete ghosts, popovers) are included.
    ///   - framesDir: when set, every frame is also kept as `frame-NNNNNN-<ms>.png`.
    public static func run(
        _ request: LiveStreamRequest,
        shouldStop: @escaping @Sendable (Int) -> Bool,
        onFrame: @escaping (StreamFrame, Int) -> Void
    ) async throws {
        let (target, fps, withOverlays, output, framesDir) =
            (request.target, request.fps, request.withOverlays, request.output, request.framesDir)
        try Doctor.ensureScreenRecordingOrThrow()
        let (filter, sourceRect, pointSize, scope) = try await contentFilter(target: target, withOverlays: withOverlays)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(seconds: 1 / fps, preferredTimescale: 600)
        config.queueDepth = 5
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.width = Int(pointSize.width * scale)
        config.height = Int(pointSize.height * scale)
        if let sourceRect { config.sourceRect = sourceRect }
        if scope == "window" { config.ignoreShadowsSingleWindow = true }

        let receiver = FrameReceiver()
        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
        try await stream.startCapture()
        defer { Task { try? await stream.stopCapture() } }
        var sequence = 0
        for try await (image, capturedAt) in receiver.images {
            if shouldStop(sequence) { break }
            try writeAtomically(image, to: output)
            sequence += 1
            var archived: String?
            if let framesDir {
                let path = StreamArchive.path(in: framesDir, sequence: sequence, capturedAt: capturedAt)
                try writePNG(image, to: path)
                archived = path
            }
            onFrame(StreamFrame(path: output, archivedPath: archived, width: image.width, height: image.height,
                                scope: scope, capturedAt: capturedAt), sequence)
            if shouldStop(sequence) { break }
        }
        try? await stream.stopCapture()
        if let error = receiver.failure { throw error }
    }

    private static func contentFilter(
        target: AppTarget?, withOverlays: Bool
    ) async throws -> (SCContentFilter, CGRect?, CGSize, String) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target else {
            let mainID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
                throw GuiportError(code: "capture_failed", message: "no shareable display",
                                   hint: "Grant Screen Recording permission and retry.")
            }
            return (SCContentFilter(display: display, excludingWindows: []), nil,
                    CGSize(width: display.width, height: display.height), "screen")
        }
        guard let info = Screenshot.topWindowInfo(for: target.pid, titleHint: target.windowTitleHint),
              let window = content.windows.first(where: { $0.windowID == CGWindowID(info.windowNumber) }) else {
            throw GuiportError(code: "no_window", message: "could not find a window for \(target.name)",
                               hint: "Omit --app to stream the whole screen.")
        }
        guard withOverlays else {
            return (SCContentFilter(desktopIndependentWindow: window), nil, window.frame.size, "window")
        }
        // Display coordinates are global points with a top-left origin, like the
        // window frame, so the window's rectangle on its display is a subtraction.
        guard let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else {
            throw GuiportError(code: "capture_failed", message: "no display under \(target.name)")
        }
        let region = window.frame.intersection(display.frame)
            .offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        return (SCContentFilter(display: display, excludingWindows: []), region, region.size, "region")
    }

    private static func writeAtomically(_ image: CGImage, to path: String) throws {
        let destination = URL(fileURLWithPath: path)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).next-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try writePNG(image, to: temporary.path)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func writePNG(_ image: CGImage, to path: String) throws {
        try Screenshot.writePNG(image, to: path)
    }
}

/// Receives sample buffers on a private queue and hands complete frames to an
/// async sequence. Idle frames (nothing changed on screen) are skipped by
/// ScreenCaptureKit, so the feed only carries real changes.
@available(macOS 14.0, *)
private final class FrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "guiport.live-capture")
    private(set) var failure: Error?
    let images: AsyncThrowingStream<(CGImage, Date), Error>
    private let continuation: AsyncThrowingStream<(CGImage, Date), Error>.Continuation

    override init() {
        (images, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(2))
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image { continuation.yield((image, Date())) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failure = error
        continuation.finish(throwing: error)
    }
}
