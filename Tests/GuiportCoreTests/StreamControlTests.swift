import XCTest
@testable import GuiportCore

final class StreamControlTests: XCTestCase {
    func testIdleStreamDeadlineDoesNotNeedFrames() {
        var now: TimeInterval = 20
        let control = StreamControl(seconds: 3, frames: nil, now: { now }, cancellation: { nil })
        XCTAssertNil(control.stopReason())
        now = 23
        XCTAssertEqual(control.stopReason(), .limit)
        XCTAssertFalse(control.needsForcedExit())
        now = 25
        XCTAssertTrue(control.needsForcedExit())
        control.finish()
        XCTAssertFalse(control.needsForcedExit())
    }

    func testUserStopIsStickyAndDoesNotNeedFrames() throws {
        var reason: String?
        let control = StreamControl(seconds: nil, frames: nil, cancellation: { reason })
        XCTAssertNil(control.stopReason())
        reason = "ESC"
        XCTAssertEqual(control.stopReason(), .cancelled("ESC"))
        reason = nil
        XCTAssertThrowsError(try control.throwIfCancelled()) {
            XCTAssertEqual(($0 as? GuiportError)?.code, "cancelled")
        }
    }

    func testContinuousStreamHasNoArbitraryDeadline() {
        var now: TimeInterval = 0
        let control = StreamControl(seconds: nil, frames: nil, now: { now }, cancellation: { nil })
        now = 365 * 24 * 60 * 60
        XCTAssertNil(control.stopReason())
        XCTAssertFalse(control.needsForcedExit())
    }

    func testFrameLimitStopsOnlyAfterDelivery() {
        let control = StreamControl(seconds: nil, frames: 2, cancellation: { nil })
        control.delivered(1)
        XCTAssertNil(control.stopReason())
        control.delivered(2)
        XCTAssertEqual(control.stopReason(), .limit)
    }

    func testArchiveNeverReservesMoreThanItsBudget() throws {
        var archive = StreamArchiveBudget(maximumBytes: 10)
        try archive.reserve(6)
        XCTAssertThrowsError(try archive.reserve(5)) {
            XCTAssertEqual(($0 as? GuiportError)?.code, "stream_archive_limit")
        }
        XCTAssertEqual(archive.bytesWritten, 6)
        try archive.reserve(4)
        XCTAssertEqual(archive.bytesWritten, 10)
        XCTAssertThrowsError(try archive.reserve(UInt64.max))
    }
}
