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
    /// `frame-000042-1790170000123.png`: sequence first so names sort in capture order.
    public static func path(in dir: String, sequence: Int, capturedAt: Date) -> String {
        // Interpolate the 64-bit timestamp: `%d` truncates it to 32 bits on Linux.
        let ms = Int64(capturedAt.timeIntervalSince1970 * 1000)
        return (dir as NSString).appendingPathComponent("frame-\(String(format: "%06d", sequence))-\(ms).png")
    }
}
