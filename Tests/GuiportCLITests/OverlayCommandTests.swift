import XCTest

final class OverlayCommandTests: XCTestCase {
    func testDemoHelpDescribesContinuousAndTimedModes() throws {
        let out = try CLI.run(["overlay", "demo", "--help"])
        XCTAssertEqual(out.code, 0, "stderr:\n\(out.stderr)")
        XCTAssertTrue(out.stdout.contains("until interrupted"), out.stdout)
        XCTAssertTrue(out.stdout.contains("animated"), out.stdout)
        XCTAssertTrue(out.stdout.contains("--seconds"), out.stdout)
    }

    func testDemoRejectsNonPositiveDuration() throws {
        let out = try CLI.run(["overlay", "demo", "--seconds", "0"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("greater than zero"), out.stderr)
    }
}
