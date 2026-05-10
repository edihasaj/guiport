#if os(Linux)
import Foundation
import GuiportCore

/// Thin wrapper around `Process` for the Linux adapter. We only call into a small
/// allowlist of well-known tools (xdotool/ydotool/wmctrl/grim/scrot/import/xrandr),
/// always using absolute resolution via `/usr/bin/env -- <tool> <args>`, never a
/// shell — so user-supplied strings (window titles, type text, selectors) are
/// passed as discrete argv entries and can't be interpreted as shell metacharacters.
enum Shell {
    struct Result {
        let exit: Int32
        let stdout: String
        let stderr: String
    }

    static func which(_ tool: String) -> Bool {
        let r = run("/usr/bin/env", ["--", "which", tool])
        return r.exit == 0 && !r.stdout.isEmpty
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            return Result(exit: 127, stdout: "", stderr: "spawn failed: \(error)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(
            exit: p.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Convenience: run via `env --` so PATH lookup works and we never invoke a shell.
    @discardableResult
    static func env(_ tool: String, _ args: [String]) -> Result {
        run("/usr/bin/env", ["--", tool] + args)
    }

    static func require(_ tool: String, hint: String) throws {
        if !which(tool) {
            throw GuiportError(
                code: "tool_missing",
                message: "required tool not on PATH: \(tool)",
                hint: hint
            )
        }
    }
}
#endif
