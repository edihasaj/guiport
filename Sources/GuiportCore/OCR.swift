import AppKit
import CoreGraphics
import Foundation
import Vision

public struct OCRMatch: Encodable {
    public let text: String
    public let confidence: Double
    public let bounds: Bounds
    /// Center point in screen coordinates — feed straight to clickAt.
    public let centerX: Double
    public let centerY: Double
}

public enum OCR {
    /// Find text in the target app's frontmost window using Apple's Vision framework.
    /// Matches default to substring (case-insensitive). Pass `exact: true` to require equality.
    public static func findText(in target: AppTarget?,
                                query: String,
                                exact: Bool = false,
                                limit: Int = 10) throws -> [OCRMatch] {
        try Doctor.ensureScreenRecordingOrThrow()
        let (image, frame) = try captureForOCR(target: target)
        return try recognizeText(in: image,
                                 windowFrame: frame,
                                 query: query,
                                 exact: exact,
                                 limit: limit)
    }

    // MARK: - Capture

    /// Returns the image and the on-screen frame (top-left origin) of the captured region,
    /// so we can map normalized Vision coords back to screen coords.
    private static func captureForOCR(target: AppTarget?) throws -> (CGImage, CGRect) {
        if let target {
            return try captureWindow(target: target)
        }
        return try captureMain()
    }

    private static func captureWindow(target: AppTarget) throws -> (CGImage, CGRect) {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            throw GuiportError(code: "ocr_capture", message: "could not list windows")
        }
        let mine = arr.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == target.pid }

        var pickedNumber: CGWindowID = 0
        var pickedFrame = CGRect.zero
        for d in mine {
            guard let n = d[kCGWindowNumber as String] as? Int else { continue }
            guard let bd = d[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let frame = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0, width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
            if frame.width < 50 || frame.height < 50 { continue }
            if let hint = target.windowTitleHint, !hint.isEmpty {
                let title = (d[kCGWindowName as String] as? String) ?? ""
                if !title.lowercased().contains(hint.lowercased()) { continue }
            }
            pickedNumber = CGWindowID(n)
            pickedFrame = frame
            break
        }
        if pickedNumber == 0 {
            throw GuiportError(code: "no_window", message: "no window found for \(target.name)")
        }
        let imageOpts: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, pickedNumber, imageOpts) else {
            throw GuiportError(code: "ocr_capture",
                               message: "CGWindowListCreateImage failed",
                               hint: "Grant Screen Recording permission and retry.")
        }
        return (image, pickedFrame)
    }

    private static func captureMain() throws -> (CGImage, CGRect) {
        guard let main = NSScreen.main else {
            throw GuiportError(code: "no_screen", message: "no main screen")
        }
        let displayId = main.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayId) else {
            throw GuiportError(code: "ocr_capture",
                               message: "CGDisplayCreateImage failed",
                               hint: "Grant Screen Recording permission and retry.")
        }
        // NSScreen.frame uses bottom-left origin; convert to top-left for screen coords.
        let f = main.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? f.height
        let topLeftFrame = CGRect(x: f.origin.x,
                                  y: screenHeight - f.origin.y - f.height,
                                  width: f.width,
                                  height: f.height)
        return (image, topLeftFrame)
    }

    // MARK: - Vision

    private static func recognizeText(in image: CGImage,
                                      windowFrame: CGRect,
                                      query: String,
                                      exact: Bool,
                                      limit: Int) throws -> [OCRMatch] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? [])
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        var matches: [OCRMatch] = []
        let needle = query.lowercased()
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            let lc = text.lowercased()
            let hit = exact ? (lc == needle) : lc.contains(needle)
            if !hit { continue }

            // Vision bounding boxes are normalized with bottom-left origin.
            let nbox = obs.boundingBox
            let pxX = nbox.origin.x * imgW
            let pxY = (1 - nbox.origin.y - nbox.height) * imgH // flip y
            let pxW = nbox.width * imgW
            let pxH = nbox.height * imgH

            // Map captured-image pixels to screen coords via the window frame.
            let scaleX = windowFrame.width / imgW
            let scaleY = windowFrame.height / imgH
            let screenX = windowFrame.origin.x + pxX * scaleX
            let screenY = windowFrame.origin.y + pxY * scaleY
            let screenW = pxW * scaleX
            let screenH = pxH * scaleY

            matches.append(OCRMatch(
                text: text,
                confidence: Double(candidate.confidence),
                bounds: Bounds(x: Double(screenX), y: Double(screenY),
                               width: Double(screenW), height: Double(screenH)),
                centerX: Double(screenX + screenW / 2),
                centerY: Double(screenY + screenH / 2)
            ))
            if matches.count >= limit { break }
        }
        // Best-confidence first.
        return matches.sorted { $0.confidence > $1.confidence }
    }
}
