import ArgumentParser
import Foundation
import GuiportCore

/// FileSystem operations that go through Finder (AppleScript) rather than
/// the raw libc syscalls. Why: cloud-storage providers (iCloud Drive,
/// FileProvider extensions like Dropbox / OneDrive / EUnifyer) only see
/// user-intent deletes/renames when they flow through Finder. A raw
/// `rm` / `mv` in Terminal bypasses the FileProvider deleteItem hook and
/// produces orphaned mappings.
struct FsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fs",
        abstract: "Drive Finder for file operations (create / rename / move-to-trash / reveal).",
        subcommands: [Create.self, Rename.self, Trash.self, Reveal.self]
    )

    // MARK: - create (drop a file into a folder via Finder)

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Copy a file into a folder via Finder (triggers FileProvider createItem)."
        )
        @Option(name: .long, help: "Source file path (absolute).")
        var src: String
        @Option(name: .long, help: "Destination folder path (absolute).")
        var into: String

        func run() async throws {
            try Fs.requireMac()
            let dst = (into as NSString).appendingPathComponent((src as NSString).lastPathComponent)
            let script = """
            tell application "Finder"
                set srcFile to POSIX file "\(Fs.esc(src))" as alias
                set dstFolder to POSIX file "\(Fs.esc(into))" as alias
                duplicate srcFile to dstFolder with replacing
            end tell
            """
            try Fs.runAppleScript(script)
            try JSONOutput.print(["action": "create", "src": src, "dst": dst], pretty: false)
        }
    }

    // MARK: - rename

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rename",
            abstract: "Rename a file via Finder (triggers FileProvider modifyItem with .filename)."
        )
        @Option(name: .long, help: "Existing file path (absolute).")
        var path: String
        @Option(name: .long, help: "New leaf name (no path).")
        var to: String

        func run() async throws {
            try Fs.requireMac()
            let script = """
            tell application "Finder"
                set theFile to POSIX file "\(Fs.esc(path))" as alias
                set name of theFile to "\(Fs.esc(to))"
            end tell
            """
            try Fs.runAppleScript(script)
            try JSONOutput.print(["action": "rename", "path": path, "to": to], pretty: false)
        }
    }

    // MARK: - trash

    struct Trash: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "trash",
            abstract: "Move a file to Trash via Finder (triggers FileProvider deleteItem, unlike `rm`)."
        )
        @Option(name: .long, help: "Path to delete (absolute).")
        var path: String

        func run() async throws {
            try Fs.requireMac()
            let script = """
            tell application "Finder"
                set theFile to POSIX file "\(Fs.esc(path))" as alias
                delete theFile
            end tell
            """
            try Fs.runAppleScript(script)
            try JSONOutput.print(["action": "trash", "path": path], pretty: false)
        }
    }

    // MARK: - reveal

    struct Reveal: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reveal",
            abstract: "Reveal a file in Finder (forces enumeration of the parent FileProvider folder)."
        )
        @Option(name: .long, help: "Path to reveal (absolute).")
        var path: String

        func run() async throws {
            try Fs.requireMac()
            #if os(macOS)
            // NSWorkspace.activateFileViewerSelecting works without AppleScript permissions.
            // We still shell out to `open -R` to keep the dependency minimal.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-R", path]
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                throw GuiportError(code: "reveal_failed",
                                   message: "open -R exited \(task.terminationStatus)")
            }
            #endif
            try JSONOutput.print(["action": "reveal", "path": path], pretty: false)
        }
    }
}

enum Fs {
    static func requireMac() throws {
        #if !os(macOS)
        throw GuiportError(code: "unsupported", message: "fs subcommand is macOS-only (uses Finder/AppleScript)")
        #endif
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    #if os(macOS)
    static func runAppleScript(_ source: String) throws {
        // NSAppleScript would require linking AppleKit; osascript is the
        // pragmatic path and avoids permission-prompt timing issues.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let err = Pipe()
        task.standardError = err
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "osascript failed"
            throw GuiportError(code: "applescript_failed",
                               message: msg.trimmingCharacters(in: .whitespacesAndNewlines),
                               hint: "Grant Finder automation permission in System Settings → Privacy & Security → Automation.")
        }
    }
    #else
    static func runAppleScript(_ source: String) throws {
        throw GuiportError(code: "unsupported", message: "AppleScript is macOS-only")
    }
    #endif
}
