import Foundation
import CoreGraphics

public struct ScreenshotResult: Encodable {
    public let path: String
    public let width: Int
    public let height: Int
}

public enum Screenshot {
    public static func defaultPath() -> String {
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = "artifacts"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/screenshot-\(ts).png"
    }

    public static func hasScreenRecordingPermission() -> Bool {
        // CGPreflightScreenCaptureAccess returns true if granted; on first call without prompt it's safe.
        return CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    public static func capture(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        throw GuiportError(code: "not_implemented", message: "screenshot not implemented yet")
    }
}
