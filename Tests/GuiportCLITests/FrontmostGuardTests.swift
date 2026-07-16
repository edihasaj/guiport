import XCTest

/// Tests the frontmost guard on `type` / `hotkey`. The guard must resolve and
/// enforce the target BEFORE any key is sent, so pointing it at an absent app
/// fails fast (nonzero exit) without typing anything.
final class FrontmostGuardTests: XCTestCase {
    func testTypeHelpDocumentsGuardFlags() throws {
        let out = try CLI.run(["type", "--help"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("--into"), out.stdout)
        XCTAssertTrue(out.stdout.contains("--require-frontmost"), out.stdout)
    }

    func testHotkeyHelpDocumentsGuardFlags() throws {
        let out = try CLI.run(["hotkey", "--help"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("--into"), out.stdout)
        XCTAssertTrue(out.stdout.contains("--require-frontmost"), out.stdout)
    }

    func testTypeIntoUnknownAppRefusesBeforeTyping() throws {
        let out = try CLI.run(["type", "--into", "com.example.notrunning.\(UUID().uuidString)", "SHOULD_NOT_TYPE"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("app_not_found"),
                      "guard must resolve the target before typing, got:\n\(out.stderr)")
    }

    func testTypeRequireFrontmostUnknownAppRefuses() throws {
        let out = try CLI.run(["type", "--require-frontmost", "com.example.notrunning.\(UUID().uuidString)", "SHOULD_NOT_TYPE"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("app_not_found"),
                      "guard must refuse for an absent app, got:\n\(out.stderr)")
    }

    func testHotkeyRequireFrontmostUnknownAppRefuses() throws {
        let out = try CLI.run(["hotkey", "--require-frontmost", "com.example.notrunning.\(UUID().uuidString)", "cmd+s"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("app_not_found"),
                      "guard must refuse for an absent app, got:\n\(out.stderr)")
    }
}
