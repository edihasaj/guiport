import XCTest
@testable import GuiportCore

final class TraversalBudgetTests: XCTestCase {
    func testWideTreeCannotExceedNodeBudget() throws {
        var budget = TraversalBudget<Int>(nodeLimit: 3)
        for id in 0..<3 {
            try budget.enter(id)
            budget.leave(id)
        }
        XCTAssertThrowsError(try budget.enter(3)) {
            XCTAssertEqual(($0 as? GuiportError)?.code, "ax_node_limit")
        }
    }

    func testCycleIsRejectedButSharedSiblingIsAllowed() throws {
        var budget = TraversalBudget<Int>()
        try budget.enter(1)
        try budget.enter(2)
        XCTAssertThrowsError(try budget.enter(1)) {
            XCTAssertEqual(($0 as? GuiportError)?.code, "ax_cycle")
        }
        budget.leave(2)
        XCTAssertNoThrow(try budget.enter(2))
    }

    func testMonotonicDeadlineIncludesTimeInsideNativeCalls() throws {
        var now: TimeInterval = 100
        var budget = TraversalBudget<Int>(seconds: 10, now: { now })
        try budget.enter(1)
        now = 110
        XCTAssertThrowsError(try budget.checkTime()) {
            XCTAssertEqual(($0 as? GuiportError)?.code, "ax_timeout")
        }
    }

    func testTextLimitCountsUTF8BytesAcrossNodes() throws {
        var budget = TraversalBudget<Int>(textLimit: 5)
        try budget.chargeText("éé")
        try budget.chargeText(nil)
        XCTAssertThrowsError(try budget.chargeText("é")) {
            XCTAssertEqual(($0 as? GuiportError)?.code, "ax_text_limit")
        }
    }

    func testDepthMustRemainBounded() throws {
        XCTAssertNoThrow(try TraversalBudget<Int>.validateDepth(0))
        XCTAssertNoThrow(try TraversalBudget<Int>.validateDepth(60))
        XCTAssertThrowsError(try TraversalBudget<Int>.validateDepth(-1))
        XCTAssertThrowsError(try TraversalBudget<Int>.validateDepth(Int.max))
    }
}
