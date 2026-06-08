import XCTest

/// CLI-surface tests for `guiport lifecycle`. We spawn the freshly-built
/// binary because the subcommand logic lives in the `guiport` executable
/// target (not importable into a SwiftPM test target).
final class LifecycleCommandTests: XCTestCase {
    func testHelpListsAllSubcommands() throws {
        let out = try CLI.run(["lifecycle", "--help"])
        XCTAssertEqual(out.code, 0)
        for verb in ["launch", "quit", "kill", "restart"] {
            XCTAssertTrue(out.stdout.contains(verb),
                          "expected `\(verb)` in lifecycle --help, got:\n\(out.stdout)")
        }
    }

    func testLaunchRejectsMissingApp() throws {
        let out = try CLI.run(["lifecycle", "launch"])
        XCTAssertNotEqual(out.code, 0, "missing --app must fail")
        XCTAssertTrue(out.stderr.lowercased().contains("--app"),
                      "expected usage to mention --app, got:\n\(out.stderr)")
    }

    func testLaunchUnknownAppReturnsAppNotFound() throws {
        let out = try CLI.run(["lifecycle", "launch", "--app", "com.example.definitelydoesnotexist.\(UUID().uuidString)"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("app_not_found") || out.stderr.contains("launch_failed"),
                      "expected app_not_found / launch_failed error, got:\n\(out.stderr)")
    }

    func testQuitOnNonRunningAppIsIdempotent() throws {
        // Quitting an app that isn't running should return stopped:true with
        // an empty pids list — the contract is "ensure not running" not
        // "fail if absent."
        let out = try CLI.run([
            "lifecycle", "quit",
            "--app", "com.example.notrunning.\(UUID().uuidString)",
            "--timeout", "1",
        ])
        XCTAssertEqual(out.code, 0, "stderr:\n\(out.stderr)")
        XCTAssertTrue(out.stdout.contains("\"stopped\":true"), out.stdout)
        XCTAssertTrue(out.stdout.contains("\"pids\":[]"), out.stdout)
    }
}
