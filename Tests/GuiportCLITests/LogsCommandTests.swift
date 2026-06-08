import XCTest

final class LogsCommandTests: XCTestCase {
    func testHelpDocumentsFilters() throws {
        let out = try CLI.run(["logs", "--help"])
        XCTAssertEqual(out.code, 0)
        for flag in ["--process", "--subsystem", "--category", "--last", "--limit"] {
            XCTAssertTrue(out.stdout.contains(flag),
                          "expected `\(flag)` in logs --help, got:\n\(out.stdout)")
        }
    }

    func testLogsRunsAndStopsAtLimit() throws {
        // No filters → log(1) emits a lot. We cap at 5 to keep the test fast
        // and verify the limit is enforced.
        let out = try CLI.run(["logs", "--last", "5s", "--limit", "5"])
        XCTAssertEqual(out.code, 0, "stderr:\n\(out.stderr)")
        let lines = out.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertLessThanOrEqual(lines.count, 5 + 1,
                                 "limit=5 should produce <=5 lines (+header), got \(lines.count)")
    }

    func testPredicateInjectionIsEscaped() throws {
        // Pass a subsystem with a quote and backslash. The command must not
        // crash log(1) — the escape() helper should sanitize the predicate.
        let evil = "com.example.\"escape\\test"
        let out = try CLI.run([
            "logs",
            "--subsystem", evil,
            "--last", "1s", "--limit", "1",
        ])
        // log(1) may legitimately exit non-zero if the predicate matches
        // nothing, but should NOT report a quoting / parse error.
        XCTAssertFalse(out.stderr.contains("predicate"),
                       "expected escape() to sanitize the predicate, got stderr:\n\(out.stderr)")
    }
}
