import Foundation

/// What `guiport stream` asks an adapter for.
public struct LiveStreamRequest: Sendable {
    public let target: AppTarget?
    public let fps: Double
    /// For a window target, capture that region of the screen so floating
    /// panels drawn by other apps (autocomplete suggestions, popovers) appear.
    public let withOverlays: Bool
    public let output: String
    public let framesDir: String?

    public init(target: AppTarget?, fps: Double, withOverlays: Bool, output: String, framesDir: String?) {
        self.target = target
        self.fps = fps
        self.withOverlays = withOverlays
        self.output = output
        self.framesDir = framesDir
    }
}

/// One delivered stream frame.
public struct StreamFrame: Sendable {
    public let path: String
    public let archivedPath: String?
    public let width: Int
    public let height: Int
    public let scope: String
    public let capturedAt: Date

    public init(path: String, archivedPath: String?, width: Int, height: Int, scope: String, capturedAt: Date) {
        self.path = path
        self.archivedPath = archivedPath
        self.width = width
        self.height = height
        self.scope = scope
        self.capturedAt = capturedAt
    }
}

public enum StreamArchive {
    public static let maximumBytes: UInt64 = 512 * 1_024 * 1_024

    /// `frame-000042-1790170000123.png`: sequence first so names sort in capture order.
    public static func path(in dir: String, sequence: Int, capturedAt: Date) -> String {
        // Interpolate the 64-bit timestamp: `%d` truncates it to 32 bits on Linux.
        let ms = Int64(capturedAt.timeIntervalSince1970 * 1000)
        return (dir as NSString).appendingPathComponent("frame-\(String(format: "%06d", sequence))-\(ms).png")
    }
}

/// Bound optional frame retention. This only counts files written by this run;
/// callers never remove a user's existing archive files.
public struct StreamArchiveBudget {
    public let maximumBytes: UInt64
    public private(set) var bytesWritten: UInt64 = 0

    public init(maximumBytes: UInt64 = StreamArchive.maximumBytes) {
        self.maximumBytes = maximumBytes
    }

    public mutating func reserve(_ bytes: UInt64) throws {
        guard bytes <= maximumBytes - bytesWritten else {
            throw GuiportError(code: "stream_archive_limit",
                               message: "Frame archive reached its \(maximumBytes) byte limit.",
                               hint: "Use the default latest-frame output for continuous streaming, or start another bounded archive.")
        }
        bytesWritten += bytes
    }

    public mutating func reserveFile(at path: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        try reserve(size)
    }
}
