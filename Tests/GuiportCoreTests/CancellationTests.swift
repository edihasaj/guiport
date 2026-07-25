import XCTest
@testable import GuiportCore

/// Regression coverage for the Stop signal that backs the overlay's Stop button,
/// the ESC key, and `guiport stop` / `guiport resume`.
final class CancellationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Cancellation.clear()
        // Deterministic, generous cool-down for tests that assert "still stopped".
        setenv("GUIPORT_CANCEL_WINDOW_MS", "10000", 1)
    }

    override func tearDown() {
        Cancellation.clear()
        unsetenv("GUIPORT_CANCEL_WINDOW_MS")
        super.tearDown()
    }

    func testCleanStateIsNotCancelled() {
        XCTAssertFalse(Cancellation.isCancelled())
        XCTAssertNil(Cancellation.activeReason())
        XCTAssertNoThrow(try Cancellation.throwIfCancelled())
    }

    func testRequestCancelThrowsWithReason() {
        Cancellation.requestCancel(reason: "unit-test")
        XCTAssertTrue(Cancellation.isCancelled())
        XCTAssertEqual(Cancellation.activeReason(), "unit-test")
        XCTAssertThrowsError(try Cancellation.throwIfCancelled()) { err in
            let g = err as? GuiportError
            XCTAssertEqual(g?.code, "cancelled")
        }
    }

    func testResumeClearsTheSignal() {
        Cancellation.requestCancel(reason: "x")
        XCTAssertTrue(Cancellation.isCancelled())
        Cancellation.clear()
        XCTAssertFalse(Cancellation.isCancelled())
        XCTAssertNoThrow(try Cancellation.throwIfCancelled())
    }

    func testStopAutoHealsAfterWindow() {
        // 1ms window: after a short wait the Stop is stale and should self-clear.
        setenv("GUIPORT_CANCEL_WINDOW_MS", "1", 1)
        Cancellation.requestCancel(reason: "expired")
        Thread.sleep(forTimeInterval: 0.03)
        XCTAssertFalse(Cancellation.isCancelled(), "an expired Stop should auto-heal")
        XCTAssertNoThrow(try Cancellation.throwIfCancelled())
    }
}
