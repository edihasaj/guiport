#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// Capture via GDI BitBlt for full virtual desktop, or PrintWindow for a specific
/// window. Encodes to PNG via WIC. Per-window capture targets the foreground top-level
/// window of the resolved process.
enum WinScreenshot {
    static func defaultPath() -> String { "artifacts\\screenshot.png" }

    static func capture(target: AppTarget?, to path: String) throws -> ScreenshotResult {
        if let target {
            return try captureWindow(target: target, to: path)
        }
        return try captureVirtualDesktop(to: path)
    }

    // MARK: - Full virtual desktop

    private static func captureVirtualDesktop(to path: String) throws -> ScreenshotResult {
        let vx = GetSystemMetrics(SM_XVIRTUALSCREEN)
        let vy = GetSystemMetrics(SM_YVIRTUALSCREEN)
        let vw = GetSystemMetrics(SM_CXVIRTUALSCREEN)
        let vh = GetSystemMetrics(SM_CYVIRTUALSCREEN)
        guard vw > 0, vh > 0 else {
            throw GuiportError(code: "no_display", message: "no virtual desktop dimensions")
        }
        guard let screenDC = GetDC(nil) else {
            throw GuiportError(code: "getdc_failed", message: "GetDC returned nil")
        }
        defer { ReleaseDC(nil, screenDC) }
        guard let memDC = CreateCompatibleDC(screenDC) else {
            throw GuiportError(code: "compatible_dc_failed", message: "CreateCompatibleDC returned nil")
        }
        defer { DeleteDC(memDC) }
        guard let bmp = CreateCompatibleBitmap(screenDC, vw, vh) else {
            throw GuiportError(code: "bitmap_failed", message: "CreateCompatibleBitmap returned nil")
        }
        defer { DeleteObject(bmp) }
        let prev = SelectObject(memDC, bmp)
        defer { SelectObject(memDC, prev) }
        let ok = BitBlt(memDC, 0, 0, vw, vh, screenDC, vx, vy, DWORD(SRCCOPY) | DWORD(CAPTUREBLT))
        if !ok {
            throw GuiportError(code: "bitblt_failed", message: "BitBlt of virtual desktop failed")
        }
        try writePng(bitmap: bmp, dc: memDC, width: Int(vw), height: Int(vh), to: path)
        return ScreenshotResult(path: path, width: Int(vw), height: Int(vh), scope: "virtual-desktop")
    }

    // MARK: - Window

    private static func captureWindow(target: AppTarget, to path: String) throws -> ScreenshotResult {
        // Prefer the window the caller actually named: an app like Teams runs
        // several windows on one pid, and "first visible" picks an arbitrary one.
        guard let hwnd = hwnd(forPid: DWORD(target.pid), titleHint: target.windowTitleHint) else {
            throw GuiportError(code: "no_window", message: "no top-level window for pid \(target.pid)")
        }
        var rect = RECT()
        GetWindowRect(hwnd, &rect)
        let w = Int(rect.right - rect.left)
        let h = Int(rect.bottom - rect.top)
        guard w > 0, h > 0 else {
            throw GuiportError(code: "empty_window", message: "window has zero area")
        }
        guard let winDC = GetWindowDC(hwnd) else {
            throw GuiportError(code: "getdc_failed", message: "GetWindowDC returned nil")
        }
        defer { ReleaseDC(hwnd, winDC) }
        guard let memDC = CreateCompatibleDC(winDC) else {
            throw GuiportError(code: "compatible_dc_failed", message: "CreateCompatibleDC returned nil")
        }
        defer { DeleteDC(memDC) }
        guard let bmp = CreateCompatibleBitmap(winDC, Int32(w), Int32(h)) else {
            throw GuiportError(code: "bitmap_failed", message: "CreateCompatibleBitmap returned nil")
        }
        defer { DeleteObject(bmp) }
        let prev = SelectObject(memDC, bmp)
        defer { SelectObject(memDC, prev) }
        // PRINTWINDOW_FULL = 1 (PW_RENDERFULLCONTENT) — works for most modern apps;
        // some (Chromium) need an extra flag, but this is the safe default.
        let ok = PrintWindow(hwnd, memDC, UINT(PW_RENDERFULLCONTENT))
        if !ok {
            // Fall back to BitBlt; this copies screen pixels, so anything covering
            // the window lands in the image. Reported as a distinct scope so a
            // caller can tell a clean window capture from a contaminated one.
            _ = BitBlt(memDC, 0, 0, Int32(w), Int32(h), winDC, 0, 0, DWORD(SRCCOPY))
        }
        try writePng(bitmap: bmp, dc: memDC, width: w, height: h, to: path)
        return ScreenshotResult(path: path, width: w, height: h,
                                scope: ok ? "window" : "window-bitblt")
    }

    // MARK: - HWND lookup

    static func topLevelHwnd(forPid pid: DWORD) -> HWND? {
        hwnd(forPid: pid, titleHint: nil)
    }

    /// The window to capture for a pid. With a `titleHint`, the best title match
    /// wins; otherwise the largest visible window does. Multi-window apps (Teams
    /// runs a main window plus hidden helpers) made "first visible" a coin flip.
    static func hwnd(forPid pid: DWORD, titleHint: String?) -> HWND? {
        let ctx = HwndCtx(pid: pid)
        let opaque = Unmanaged.passUnretained(ctx).toOpaque()
        _ = EnumWindows(guiportScreenshotEnumWindowsCallback, LPARAM(Int(bitPattern: opaque)))
        guard !ctx.candidates.isEmpty else { return nil }
        if let hint = titleHint?.lowercased(), !hint.isEmpty {
            let matches = ctx.candidates.filter { $0.title.lowercased().contains(hint) }
            if let best = matches.max(by: { $0.area < $1.area }) { return best.hwnd }
        }
        return ctx.candidates.max(by: { $0.area < $1.area })?.hwnd
    }

    // MARK: - PNG encode

    /// Read the DIB into a 32bpp BGRA top-down buffer and write a real PNG at the
    /// exact `path` the caller asked for (matching the reported ScreenshotResult).
    private static func writePng(bitmap: HBITMAP, dc: HDC, width: Int, height: Int, to path: String) throws {
        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = LONG(width)
        bmi.bmiHeader.biHeight = -LONG(height)   // top-down
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = DWORD(BI_RGB)
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        let got = pixels.withUnsafeMutableBytes { rawBuf -> Int32 in
            GetDIBits(dc, bitmap, 0, UINT(height), rawBuf.baseAddress, &bmi, UINT(DIB_RGB_COLORS))
        }
        if got == 0 {
            throw GuiportError(code: "getdibits_failed", message: "GetDIBits returned 0")
        }
        let png = WinPng.encode(bgra: pixels, width: width, height: height)
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: url)
    }
}

struct HwndCandidate {
    let hwnd: HWND
    let title: String
    let area: Int
}

private final class HwndCtx {
    let pid: DWORD
    var candidates: [HwndCandidate] = []
    init(pid: DWORD) {
        self.pid = pid
    }
}

private func windowTitle(_ hwnd: HWND) -> String {
    let len = GetWindowTextLengthW(hwnd)
    guard len > 0 else { return "" }
    var buf = [WCHAR](repeating: 0, count: Int(len) + 1)
    let got = GetWindowTextW(hwnd, &buf, Int32(buf.count))
    guard got > 0 else { return "" }
    return String(decodingCString: buf, as: UTF16.self)
}

private func guiportScreenshotEnumWindowsCallback(_ hwnd: HWND?, _ lparam: LPARAM) -> WindowsBool {
    guard let hwnd else { return true }
    let ctx = Unmanaged<HwndCtx>
        .fromOpaque(UnsafeRawPointer(bitPattern: UInt(lparam))!)
        .takeUnretainedValue()
    var pid: DWORD = 0
    _ = GetWindowThreadProcessId(hwnd, &pid)
    // Collect every visible, non-minimised window: the caller picks by title or
    // size. Minimised windows have a bogus rect and PrintWindow to blank.
    if pid == ctx.pid, IsWindowVisible(hwnd), !IsIconic(hwnd) {
        var rect = RECT()
        guard GetWindowRect(hwnd, &rect) else { return true }
        let area = Int(rect.right - rect.left) * Int(rect.bottom - rect.top)
        guard area > 0 else { return true }
        ctx.candidates.append(HwndCandidate(hwnd: hwnd, title: windowTitle(hwnd), area: area))
    }
    return true
}
#endif
