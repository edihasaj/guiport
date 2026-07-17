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
        guard let hwnd = topLevelHwnd(forPid: DWORD(target.pid)) else {
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
            // Fall back to BitBlt; loses per-window framing for occluded windows
            // but at least produces output.
            _ = BitBlt(memDC, 0, 0, Int32(w), Int32(h), winDC, 0, 0, DWORD(SRCCOPY))
        }
        try writePng(bitmap: bmp, dc: memDC, width: w, height: h, to: path)
        return ScreenshotResult(path: path, width: w, height: h, scope: "window")
    }

    // MARK: - HWND lookup

    static func topLevelHwnd(forPid pid: DWORD) -> HWND? {
        let ctx = HwndCtx(pid: pid)
        let opaque = Unmanaged.passUnretained(ctx).toOpaque()
        _ = EnumWindows(guiportScreenshotEnumWindowsCallback, LPARAM(Int(bitPattern: opaque)))
        return ctx.found
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

private final class HwndCtx {
    let pid: DWORD
    var found: HWND?
    init(pid: DWORD) {
        self.pid = pid
    }
}

private func guiportScreenshotEnumWindowsCallback(_ hwnd: HWND?, _ lparam: LPARAM) -> WindowsBool {
    guard let hwnd else { return true }
    let ctx = Unmanaged<HwndCtx>
        .fromOpaque(UnsafeRawPointer(bitPattern: UInt(lparam))!)
        .takeUnretainedValue()
    var pid: DWORD = 0
    _ = GetWindowThreadProcessId(hwnd, &pid)
    if pid == ctx.pid, IsWindowVisible(hwnd) {
        ctx.found = hwnd
        return false
    }
    return true
}
#endif
