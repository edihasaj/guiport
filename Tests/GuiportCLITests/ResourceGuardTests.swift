import Foundation
import XCTest
#if os(macOS)
import Darwin
#endif

final class ResourceGuardTests: XCTestCase {
    #if os(macOS)
    func testMemoryWatchdogStopsBlockedLongLivedCommand() throws {
        try verifyWatchdog(fullErrorPipe: false)
    }

    func testMemoryWatchdogExitsEvenWhenErrorPipeIsFull() throws {
        try verifyWatchdog(fullErrorPipe: true)
    }

    private func verifyWatchdog(fullErrorPipe: Bool) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: try CLI.binaryPath())
        // MCP waits for stdin. No AX permissions, screen capture, or input.
        task.arguments = ["serve", "--mcp"]
        var environment = ProcessInfo.processInfo.environment
        environment["GUIPORT_MEMORY_LIMIT_MB"] = "1"
        task.environment = environment
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        var retainedErrorFD = dup(errors.fileHandleForWriting.fileDescriptor)
        defer { if retainedErrorFD >= 0 { close(retainedErrorFD) } }
        if fullErrorPipe {
            let fd = errors.fileHandleForWriting.fileDescriptor
            let flags = fcntl(fd, F_GETFL)
            XCTAssertEqual(fcntl(fd, F_SETFL, flags | O_NONBLOCK), 0)
            var bytes = [UInt8](repeating: 120, count: 4096)
            while Darwin.write(fd, &bytes, bytes.count) > 0 {}
            XCTAssertEqual(fcntl(fd, F_SETFL, flags), 0)
        }
        task.standardInput = input
        task.standardOutput = output
        task.standardError = errors
        try task.run()
        defer { if task.isRunning { task.terminate() } }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while task.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !task.isRunning else { return XCTFail("Memory watchdog did not interrupt a blocked command") }
        XCTAssertEqual(task.terminationStatus, 75)
        XCTAssertEqual(fcntl(retainedErrorFD, F_GETFL) & O_NONBLOCK, 0)
        close(retainedErrorFD)
        retainedErrorFD = -1
        if !fullErrorPipe {
            let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(stderr.contains("resource_limit"), stderr)
        }
    }
    #endif
}
