import XCTest

/// CLI-surface tests for `guiport activate` and `guiport lifecycle activate`.
/// We avoid asserting on a real activation (needs an interactive GUI session);
/// instead we pin the contract: the command exists, requires `--app`, and errors
/// cleanly when the target isn't running.
final class ActivateCommandTests: XCTestCase {
    func testTopLevelActivateInHelp() throws {
        let out = try CLI.run(["--help"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("activate"),
                      "expected `activate` in top-level help, got:\n\(out.stdout)")
    }

    func testLifecycleActivateInHelp() throws {
        let out = try CLI.run(["lifecycle", "--help"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("activate"),
                      "expected `activate` in lifecycle --help, got:\n\(out.stdout)")
    }

    func testActivateRequiresApp() throws {
        let out = try CLI.run(["activate"])
        XCTAssertNotEqual(out.code, 0, "missing --app must fail")
        XCTAssertTrue(out.stderr.lowercased().contains("--app"),
                      "expected usage to mention --app, got:\n\(out.stderr)")
    }

    func testActivateUnknownAppErrors() throws {
        let out = try CLI.run(["activate", "--app", "com.example.notrunning.\(UUID().uuidString)"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("app_not_found"),
                      "expected app_not_found, got:\n\(out.stderr)")
    }

    func testLifecycleActivateUnknownAppErrors() throws {
        let out = try CLI.run(["lifecycle", "activate", "--app", "com.example.notrunning.\(UUID().uuidString)"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("app_not_found"),
                      "expected app_not_found, got:\n\(out.stderr)")
    }
}
