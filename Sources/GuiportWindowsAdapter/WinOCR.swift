#if os(Windows)
import Foundation
import WinSDK
import GuiportCore

/// On-screen text location via the built-in Windows.Media.Ocr (WinRT) engine.
/// Swift/WinRT COM interop is heavy, so we drive the engine through a short
/// PowerShell script (no install needed — the OCR engine ships with Windows)
/// and map the per-line boxes back to screen coordinates. This backs both
/// `find-text` and `click-text` (which clicks the returned centre).
enum WinOCR {
    private struct Line { let x, y, w, h: Int; let text: String }

    static func findText(in target: AppTarget?, query: String, exact: Bool, limit: Int) throws -> [OCRMatch] {
        let png = tempFile(ext: "png")
        defer { try? FileManager.default.removeItem(atPath: png) }
        let (originX, originY) = try capture(target: target, to: png)
        let lines = try runOCR(pngPath: png)

        let needle = query.lowercased()
        var matches: [OCRMatch] = []
        for line in lines {
            let hay = line.text.lowercased()
            let hit = exact ? hay == needle : hay.contains(needle)
            if !hit { continue }
            // Image pixels -> screen coordinates (add the capture origin).
            let sx = Double(originX + line.x)
            let sy = Double(originY + line.y)
            let w = Double(line.w), h = Double(line.h)
            matches.append(OCRMatch(
                text: line.text,
                confidence: 1.0,   // WinRT OCR exposes no per-line confidence
                bounds: Bounds(x: sx, y: sy, width: w, height: h),
                centerX: sx + w / 2.0,
                centerY: sy + h / 2.0
            ))
            if matches.count >= max(1, limit) { break }
        }
        return matches
    }

    /// Capture to `path`; return the top-left screen origin of the captured image
    /// so OCR pixel coords can be shifted into screen space.
    private static func capture(target: AppTarget?, to path: String) throws -> (Int, Int) {
        if let target {
            guard let hwnd = WinScreenshot.topLevelHwnd(forPid: DWORD(target.pid)) else {
                throw GuiportError(code: "no_window", message: "no top-level window for pid \(target.pid)")
            }
            var r = RECT()
            GetWindowRect(hwnd, &r)
            _ = try WinScreenshot.capture(target: target, to: path)
            return (Int(r.left), Int(r.top))
        }
        _ = try WinScreenshot.capture(target: nil, to: path)
        // Virtual-desktop capture starts at (SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN).
        return (Int(GetSystemMetrics(SM_XVIRTUALSCREEN)), Int(GetSystemMetrics(SM_YVIRTUALSCREEN)))
    }

    private static func runOCR(pngPath: String) throws -> [Line] {
        let scriptPath = tempFile(ext: "ps1")
        try OCR_BOXES_PS1.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: powershellPath())
        proc.arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, "-Path", pngPath]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            throw GuiportError(code: "ocr_failed", message: "could not launch PowerShell for OCR: \(error)")
        }
        proc.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            throw GuiportError(
                code: "ocr_failed",
                message: "WinRT OCR failed (exit \(proc.terminationStatus))",
                hint: "Ensure an OCR language pack is installed (Settings → Time & Language → Language)."
            )
        }
        var lines: [Line] = []
        for raw in out.split(whereSeparator: \.isNewline) {
            let parts = raw.split(separator: "\t", omittingEmptySubsequences: false)
            if parts.count < 5 { continue }
            guard let x = Int(parts[0]), let y = Int(parts[1]),
                  let w = Int(parts[2]), let h = Int(parts[3]) else { continue }
            let text = parts[4...].joined(separator: "\t")
            if text.isEmpty { continue }
            lines.append(Line(x: x, y: y, w: w, h: h, text: String(text)))
        }
        return lines
    }

    private static func powershellPath() -> String {
        let sys = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        return "\(sys)\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    }

    private static func tempFile(ext: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("guiport-ocr-\(UUID().uuidString).\(ext)")
            .path
    }
}

// WinRT OCR emitting one "x<TAB>y<TAB>w<TAB>h<TAB>text" line per recognised OCR
// line (boxes in image pixels). Uses [char]9 for the tab to keep the string
// backtick-free apart from the required IAsyncOperation`1 type name.
private let OCR_BOXES_PS1 = """
param([string]$Path)
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
[Windows.Storage.StorageFile,           Windows.Storage,                ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,       ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,           Windows.Media.Ocr,              ContentType=WindowsRuntime] | Out-Null
$file    = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
$stream  = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine  = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $engine) { Write-Error 'no OCR language installed'; exit 1 }
$res = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$tab = [char]9
foreach ($line in $res.Lines) {
  $ws = $line.Words; if ($ws.Count -eq 0) { continue }
  $minX = ($ws | ForEach-Object { $_.BoundingRect.X } | Measure-Object -Minimum).Minimum
  $minY = ($ws | ForEach-Object { $_.BoundingRect.Y } | Measure-Object -Minimum).Minimum
  $maxX = ($ws | ForEach-Object { $_.BoundingRect.X + $_.BoundingRect.Width } | Measure-Object -Maximum).Maximum
  $maxY = ($ws | ForEach-Object { $_.BoundingRect.Y + $_.BoundingRect.Height } | Measure-Object -Maximum).Maximum
  @([int]$minX, [int]$minY, [int]($maxX-$minX), [int]($maxY-$minY), $line.Text) -join $tab
}
"""
#endif
