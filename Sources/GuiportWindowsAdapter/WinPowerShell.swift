#if os(Windows)
import Foundation
import GuiportCore

/// Running short PowerShell helpers, which is how this adapter reaches the
/// Windows APIs that Swift/WinRT COM interop would make expensive: WinRT OCR
/// (``WinOCR``) and UI Automation (``WinUIA``).
enum WinPowerShell {
    static func path() -> String {
        let sys = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        return "\(sys)\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
    }

    /// A temp path with native backslashes — not `URL.path`, which yields
    /// forward slashes that trip WinRT's StorageFile path parsing.
    static func tempFile(prefix: String, ext: String) -> String {
        let env = ProcessInfo.processInfo.environment
        let tmp = env["TEMP"] ?? env["TMP"] ?? "C:\\Windows\\Temp"
        return "\(tmp)\\guiport-\(prefix)-\(UUID().uuidString).\(ext)"
    }

    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Run a script file and return what it wrote.
    ///
    /// Output goes to regular files, not pipes. A pipe holds only tens of KB,
    /// so a script with more than that to say blocks in its own write while the
    /// parent blocks in `waitUntilExit()`, and neither side moves again — that
    /// deadlock wedged two guiport processes at once. Files cannot fill up, and
    /// both streams can be read after exit with no concurrent mutation at all.
    /// A UIA tree says far more than an OCR result, so this path would find
    /// that ceiling sooner rather than later.
    static func run(scriptPath: String, arguments: [String]) throws -> Output {
        let outPath = tempFile(prefix: "ps", ext: "stdout")
        let errPath = tempFile(prefix: "ps", ext: "stderr")
        FileManager.default.createFile(atPath: outPath, contents: nil)
        FileManager.default.createFile(atPath: errPath, contents: nil)
        guard let outFile = FileHandle(forUpdatingAtPath: outPath),
              let errFile = FileHandle(forUpdatingAtPath: errPath) else {
            throw GuiportError(code: "powershell_failed",
                               message: "could not create temporary output files")
        }
        defer {
            outFile.closeFile()
            errFile.closeFile()
            try? FileManager.default.removeItem(atPath: outPath)
            try? FileManager.default.removeItem(atPath: errPath)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path())
        proc.arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                          scriptPath.replacingOccurrences(of: "/", with: "\\")] + arguments
        proc.standardOutput = outFile
        proc.standardError = errFile
        try proc.run()
        proc.waitUntilExit()

        outFile.seek(toFileOffset: 0)
        errFile.seek(toFileOffset: 0)
        return Output(status: proc.terminationStatus,
                      stdout: String(data: outFile.readDataToEndOfFile(), encoding: .utf8) ?? "",
                      stderr: String(data: errFile.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }
}
#endif
