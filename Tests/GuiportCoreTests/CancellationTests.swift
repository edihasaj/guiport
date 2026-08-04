import XCTest
@testable import GuiportCore

/// Regression coverage for the Stop signal that backs the overlay's Stop button,
/// the ESC key, and `guiport stop` / `guiport resume`.
final class CancellationTests: XCTestCase {
    private let activeTime = 1_000
    private let activeWindow = 10_000

    private var flagURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("guiport-cancellation-tests")
            .appendingPathComponent(UUID().uuidString)
    }

    func testCleanStateIsNotCancelled() {
        let flagURL = flagURL
        XCTAssertNil(Cancellation.activeReason(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime))
        XCTAssertNoThrow(try Cancellation.throwIfCancelled(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime))
    }

    func testRequestCancelThrowsWithReason() {
        let flagURL = flagURL
        defer { Cancellation.clear(at: flagURL) }
        Cancellation.requestCancel(reason: "unit-test", at: flagURL, nowMs: activeTime)
        XCTAssertEqual(Cancellation.activeReason(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime), "unit-test")
        XCTAssertThrowsError(try Cancellation.throwIfCancelled(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime)) { err in
            let g = err as? GuiportError
            XCTAssertEqual(g?.code, "cancelled")
        }
    }

    func testResumeClearsTheSignal() {
        let flagURL = flagURL
        Cancellation.requestCancel(reason: "x", at: flagURL, nowMs: activeTime)
        XCTAssertEqual(Cancellation.activeReason(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime), "x")
        Cancellation.clear(at: flagURL)
        XCTAssertNil(Cancellation.activeReason(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime))
        XCTAssertNoThrow(try Cancellation.throwIfCancelled(
            at: flagURL, windowMs: activeWindow, nowMs: activeTime))
    }

    func testStopAutoHealsAfterWindow() {
        let flagURL = flagURL
        Cancellation.requestCancel(reason: "expired", at: flagURL, nowMs: activeTime)
        XCTAssertNil(Cancellation.activeReason(
            at: flagURL, windowMs: 1, nowMs: activeTime + 2),
            "an expired Stop should auto-heal")
        XCTAssertNoThrow(try Cancellation.throwIfCancelled(
            at: flagURL, windowMs: 1, nowMs: activeTime + 2))
    }
}
