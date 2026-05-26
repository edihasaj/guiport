import ArgumentParser
import Foundation
import GuiportCore

/// Wraps `log show` so callers don't have to wrestle with the predicate
/// language or zsh quoting. macOS only.
struct LogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Read recent unified-logging messages for an app, process, or subsystem."
    )

    @Option(name: .long, help: "Filter by process name (matches log's `process` field).")
    var process: String?

    @Option(name: .long, help: "Filter by os_log subsystem (e.g. com.example.app).")
    var subsystem: String?

    @Option(name: .long, help: "Filter by os_log category.")
    var category: String?

    @Option(name: .long, help: "Time window, e.g. 5m, 30s, 2h. Default 5m.")
    var last: String = "5m"

    @Option(name: .long, help: "Minimum level: default, info, debug. Default 'default'.")
    var level: String = "default"

    @Option(name: .long, help: "Max lines to return. Default 200.")
    var limit: Int = 200

    @Flag(name: .long, help: "Output one JSON object per entry to stdout (jsonl). Default is plain text from log(1).")
    var json: Bool = false

    func run() async throws {
        #if os(macOS)
        var predicateParts: [String] = []
        if let p = process { predicateParts.append("process == \"\(escape(p))\"") }
        if let s = subsystem { predicateParts.append("subsystem == \"\(escape(s))\"") }
        if let c = category { predicateParts.append("category == \"\(escape(c))\"") }
        let predicate = predicateParts.joined(separator: " AND ")

        var args = ["show", "--style", json ? "json" : "compact", "--last", last, "--info"]
        if level == "debug" { args.append("--debug") }
        if !predicate.isEmpty { args += ["--predicate", predicate] }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        // Cap memory by streaming line-by-line and trimming.
        let stdout = FileHandle.standardOutput
        var count = 0
        let handle = pipe.fileHandleForReading
        var carry = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            carry.append(chunk)
            while let nl = carry.firstIndex(of: 0x0a) {
                let line = carry.subdata(in: 0..<nl)
                carry.removeSubrange(0...nl)
                if count < limit {
                    stdout.write(line)
                    stdout.write(Data([0x0a]))
                    count += 1
                }
            }
        }
        task.waitUntilExit()
        if task.terminationStatus != 0 && count == 0 {
            throw GuiportError(code: "log_failed",
                               message: "log(1) exited with status \(task.terminationStatus)",
                               hint: "verify the --process / --subsystem filter matches a running process")
        }
        #else
        throw GuiportError(code: "unsupported", message: "logs subcommand is macOS-only (uses log(1))")
        #endif
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
