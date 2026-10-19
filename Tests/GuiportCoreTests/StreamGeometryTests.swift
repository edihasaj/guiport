import XCTest
@testable import GuiportCore

final class StreamGeometryTests: XCTestCase {
    func testScalesLandscapeToPixelBudget() throws {
        let result = try StreamGeometry.dimensions(width: 5_120, height: 2_880)
        XCTAssertEqual(result.width, 3_840)
        XCTAssertEqual(result.height, 2_160)
    }

    func testLeavesSmallerLandscapeUnchanged() throws {
        let result = try StreamGeometry.dimensions(width: 1_920, height: 1_080)
        XCTAssertEqual(result.width, 1_920)
        XCTAssertEqual(result.height, 1_080)
    }

    func testPortraitKeepsOrientation() throws {
        let result = try StreamGeometry.dimensions(width: 2_880, height: 5_120)
        XCTAssertEqual(result.width, 2_160)
        XCTAssertEqual(result.height, 3_840)
    }

    func testRejectsInvalidDimensionsAndBudgets() {
        for (width, height) in [(Double.nan, 1080.0), (.infinity, 1080),
                                (1920, .infinity), (0, 1080), (0.5, 1080)] {
            XCTAssertThrowsError(try StreamGeometry.dimensions(width: width, height: height))
        }
        for budget in [0, -1, 16_777_217, Int.max] {
            XCTAssertThrowsError(try StreamGeometry.dimensions(width: 1920, height: 1080, maxPixels: budget))
        }
    }

    func testExtremeDimensionsCannotOverflowOrExceedBudget() throws {
        for (width, height) in [(1e300, 1.0), (1.0, 1e300), (1e300, 1e300),
                                (Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)] {
            let result = try StreamGeometry.dimensions(width: width, height: height)
            XCTAssertGreaterThan(result.width, 0)
            XCTAssertGreaterThan(result.height, 0)
            XCTAssertLessThanOrEqual(result.width * result.height, 8_294_400)
            XCTAssertLessThanOrEqual(Double(result.width), width)
            XCTAssertLessThanOrEqual(Double(result.height), height)
        }
    }
}
