import XCTest
import Foundation

/// Shell-out helper for CLI integration tests. Builds the guiport binary on
/// first use (via `swift build`) and spawns it for each test. Path can be
/// overridden by `GUIPORT_BIN` for CI / local runs against a release build.
enum CLI {
    struct Output {
        let code: Int32
        let stdout: String
        let stderr: String
    }

    private static let lock = NSLock()
    private static var cachedBinary: String?

    static func binaryPath() throws -> String {
        if let override = ProcessInfo.processInfo.environment["GUIPORT_BIN"], !override.isEmpty {
            return override
        }
        lock.lock(); defer { lock.unlock() }
        if let cached = cachedBinary { return cached }

        // Walk up from the test executable to the package root (contains Package.swift).
        let bundleURL = Bundle(for: BundleAnchor.self).bundleURL
        var dir = bundleURL.deletingLastPathComponent()
        var packageRoot: URL?
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                packageRoot = dir
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        guard let root = packageRoot else {
            throw NSError(domain: "CLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not locate Package.swift from test bundle"])
        }

        if let found = findBuiltBinary(in: root) {
            cachedBinary = found
            return found
        }

        throw NSError(
            domain: "CLI",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "guiport binary not found under .build; run `swift build --product guiport` first or set GUIPORT_BIN"
            ]
        )
    }

    private static func findBuiltBinary(in root: URL) -> String? {
        let buildDir = root.appendingPathComponent(".build")
        let triples = (try? FileManager.default.contentsOfDirectory(atPath: buildDir.path)) ?? []
        for triple in triples {
            let candidate = buildDir
                .appendingPathComponent(triple)
                .appendingPathComponent("debug")
                .appendingPathComponent("guiport")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }
        // Fall back to the canonical SwiftPM "debug" alias if the triple folder is missing.
        let alias = buildDir.appendingPathComponent("debug").appendingPathComponent("guiport")
        if FileManager.default.isExecutableFile(atPath: alias.path) {
            return alias.path
        }
        return nil
    }

    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 30) throws -> Output {
        let bin = try binaryPath()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        try task.run()

        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if task.isRunning {
            task.terminate()
            throw NSError(domain: "CLI", code: 4, userInfo: [NSLocalizedDescriptionKey: "command timed out after \(timeout)s: \(args)"])
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return Output(
            code: task.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

/// Anchor class used solely so Bundle(for:) can locate the test bundle.
final class BundleAnchor {}
