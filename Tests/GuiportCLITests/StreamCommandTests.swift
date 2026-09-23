import XCTest

final class StreamCommandTests: XCTestCase {
    func testHelpDocumentsPersistentAndBoundedModes() throws {
        let out = try CLI.run(["stream", "--help"])
        XCTAssertEqual(out.code, 0, "stderr:\n\(out.stderr)")
        for option in ["--fps", "--seconds", "--frames", "--app", "--window", "--output", "--frames-dir", "--with-overlays"] {
            XCTAssertTrue(out.stdout.contains(option), "missing \(option):\n\(out.stdout)")
        }
        XCTAssertTrue(out.stdout.contains("until interrupted"), out.stdout)
    }

    func testRejectsUnsafeFrameRate() throws {
        let out = try CLI.run(["stream", "--fps", "0"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("between 0.1 and 60"), out.stderr)
    }

    func testRejectsNonPositiveFrameLimit() throws {
        let out = try CLI.run(["stream", "--frames", "0"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("greater than zero"), out.stderr)
    }
}
