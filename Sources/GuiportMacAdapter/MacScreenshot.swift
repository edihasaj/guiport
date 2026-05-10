import Foundation
import CoreGraphics
import ImageIO
import AppKit
import UniformTypeIdentifiers
import GuiportCore

enum Screenshot {
    static func defaultPath() -> String {
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = "artifacts"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/screenshot-\(ts).png"
    }

    static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    static func capture(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        try Doctor.ensureScreenRecordingOrThrow()
        if let target {
            return try captureWindow(target: target, to: path)
        }
        return try captureFullScreen(to: path)
    }

    private static func captureFullScreen(to path: String) throws -> ScreenshotResult {
        guard let main = NSScreen.main else {
            throw GuiportError(code: "no_screen", message: "no main screen")
        }
        let displayId = main.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayId) else {
            throw GuiportError(code: "capture_failed",
                               message: "CGDisplayCreateImage returned nil",
                               hint: "Grant Screen Recording permission and retry.")
        }
        try writePNG(image, to: path)
        return ScreenshotResult(path: path, width: image.width, height: image.height, scope: "screen")
    }

    private static func captureWindow(target: AppTarget, to path: String) throws -> ScreenshotResult {
        guard let info = topWindowInfo(for: target.pid, titleHint: target.windowTitleHint) else {
            throw GuiportError(code: "no_window", message: "could not find a window for \(target.name)")
        }
        let opts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let image = CGWindowListCreateImage(.null,
                                                  .optionIncludingWindow,
                                                  CGWindowID(info.windowNumber),
                                                  opts) else {
            throw GuiportError(code: "capture_failed",
                               message: "CGWindowListCreateImage returned nil",
                               hint: "Grant Screen Recording permission and retry.")
        }
        try writePNG(image, to: path)
        return ScreenshotResult(path: path, width: image.width, height: image.height, scope: "window")
    }

    private struct WindowDescriptor {
        let windowNumber: Int
        let title: String?
        let bounds: CGRect
    }

    private static func topWindowInfo(for pid: pid_t, titleHint: String?) -> WindowDescriptor? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let mine = arr.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
        let descriptors: [WindowDescriptor] = mine.compactMap { d in
            guard let n = d[kCGWindowNumber as String] as? Int else { return nil }
            let title = d[kCGWindowName as String] as? String
            var bounds = CGRect.zero
            if let bd = d[kCGWindowBounds as String] as? [String: CGFloat] {
                bounds = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0, width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
            }
            // Filter tiny / hidden surfaces.
            if bounds.width < 50 || bounds.height < 50 { return nil }
            return WindowDescriptor(windowNumber: n, title: title, bounds: bounds)
        }
        if let hint = titleHint, !hint.isEmpty {
            let lc = hint.lowercased()
            if let m = descriptors.first(where: { ($0.title ?? "").lowercased().contains(lc) }) {
                return m
            }
        }
        return descriptors.first
    }

    private static func writePNG(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let type = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw GuiportError(code: "write_failed", message: "could not create image destination at \(path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw GuiportError(code: "write_failed", message: "CGImageDestinationFinalize failed")
        }
    }
}
