import XCTest

/// CLI-surface tests for `guiport assert`. These pin the exit-code contract
/// (nonzero when a check is unmet) using a guaranteed-absent app, so they don't
/// depend on any particular app being frontmost in CI.
final class AssertCommandTests: XCTestCase {
    func testHelpListsChecks() throws {
        let out = try CLI.run(["assert", "--help"])
        XCTAssertEqual(out.code, 0)
        for flag in ["--running", "--frontmost", "--front-title-contains", "--focused"] {
            XCTAssertTrue(out.stdout.contains(flag),
                          "expected `\(flag)` in assert --help, got:\n\(out.stdout)")
        }
    }

    func testAssertRequiresApp() throws {
        let out = try CLI.run(["assert"])
        XCTAssertNotEqual(out.code, 0, "missing --app must fail")
        XCTAssertTrue(out.stderr.lowercased().contains("--app"),
                      "expected usage to mention --app, got:\n\(out.stderr)")
    }

    func testAssertDefaultsToRunningAndFailsForAbsentApp() throws {
        // No explicit check flag → defaults to a running check, which must fail
        // (nonzero exit) for an app that isn't running.
        let out = try CLI.run(["assert", "--app", "com.example.notrunning.\(UUID().uuidString)"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("\"passed\":false"), out.stdout)
        XCTAssertTrue(out.stdout.contains("\"running\""), out.stdout)
    }

    func testAssertFrontmostFailsForAbsentApp() throws {
        let out = try CLI.run(["assert", "--app", "com.example.notrunning.\(UUID().uuidString)", "--frontmost"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("\"frontmost\""), out.stdout)
        XCTAssertTrue(out.stdout.contains("\"passed\":false"), out.stdout)
    }
}
