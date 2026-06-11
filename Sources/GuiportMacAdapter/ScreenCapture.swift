import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import GuiportCore

/// ScreenCaptureKit-backed capture.
///
/// The legacy CoreGraphics APIs (`CGDisplayCreateImage`, `CGWindowListCreateImage`)
/// are deprecated on macOS 14+ and, worse, make macOS attribute Screen Recording to
/// the *responsible* foreground app (e.g. the terminal hosting the CLI) instead of
/// guiport itself — so guiport never gets its own entry under System Settings →
/// Privacy & Security → Screen Recording.
///
/// ScreenCaptureKit enrols the *calling* binary (`com.edihasaj.guiport`) as its own
/// TCC subject and prompts for it by name. We use it whenever available (macOS 14+,
/// where `SCScreenshotManager` exists) and fall back to the legacy path on macOS 13.
enum ScreenCapture {

    /// Force TCC to enrol guiport as its own Screen Recording subject. Fetching
    /// shareable content triggers the system prompt and adds `com.edihasaj.guiport`
    /// to the Screen Recording list. Errors are intentionally swallowed — this is a
    /// best-effort side effect used by `doctor --fix`.
    static func enrol() {
        if #available(macOS 14.0, *) {
            // Must attempt a real frame capture, not just list shareable content:
            // SCShareableContent listing does NOT require Screen Recording and so
            // never triggers the TCC prompt or enrols the binary. SCScreenshotManager
            // capture does. Errors are swallowed — this is best-effort.
            _ = try? captureDisplay(CGMainDisplayID(), scale: 1.0)
        } else {
            _ = CGDisplayCreateImage(CGMainDisplayID())
        }
    }

    /// Capture a full display by its `CGDirectDisplayID`.
    static func captureDisplay(_ displayID: CGDirectDisplayID, scale: CGFloat) throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try runBlocking { try await captureDisplaySCK(displayID, scale: scale) }
        }
        guard let image = CGDisplayCreateImage(displayID) else {
            throw GuiportError(code: "capture_failed",
                               message: "CGDisplayCreateImage returned nil",
                               hint: "Grant Screen Recording permission and retry.")
        }
        return image
    }

    /// Capture a single window by its `CGWindowID`.
    static func captureWindow(_ windowID: CGWindowID, scale: CGFloat) throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try runBlocking { try await captureWindowSCK(windowID, scale: scale) }
        }
        let opts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, opts) else {
            throw GuiportError(code: "capture_failed",
                               message: "CGWindowListCreateImage returned nil",
                               hint: "Grant Screen Recording permission and retry.")
        }
        return image
    }

    // MARK: - ScreenCaptureKit (macOS 14+)

    @available(macOS 14.0, *)
    private static func captureDisplaySCK(_ displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw GuiportError(code: "capture_failed", message: "no shareable display for id \(displayID)",
                               hint: "Grant Screen Recording permission and retry.")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    @available(macOS 14.0, *)
    private static func captureWindowSCK(_ windowID: CGWindowID, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw GuiportError(code: "no_window", message: "no shareable window for id \(windowID)",
                               hint: "Grant Screen Recording permission and retry.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - async → sync bridge

    /// Run an async operation to completion from a synchronous (CLI) call site.
    /// Safe because the CLI's calling thread is not part of Swift's cooperative pool,
    /// so blocking it on the semaphore cannot deadlock the awaiting Task.
    private static func runBlocking<T>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task.detached(priority: .userInitiated) {
            do { box.value = .success(try await operation()) }
            catch { box.value = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        switch box.value {
        case .success(let v): return v
        case .failure(let e): throw e
        case .none:
            throw GuiportError(code: "capture_failed", message: "capture produced no result")
        }
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: Result<T, Error>?
    }
}
