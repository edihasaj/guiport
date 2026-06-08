import XCTest

final class FsCommandTests: XCTestCase {
    func testHelpListsAllVerbs() throws {
        let out = try CLI.run(["fs", "--help"])
        XCTAssertEqual(out.code, 0)
        for verb in ["create", "rename", "trash", "reveal"] {
            XCTAssertTrue(out.stdout.contains(verb),
                          "expected `\(verb)` in fs --help, got:\n\(out.stdout)")
        }
    }

    func testCreateRequiresSrcAndInto() throws {
        let out = try CLI.run(["fs", "create"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.lowercased().contains("--src") || out.stderr.lowercased().contains("--into"),
                      "expected usage to mention required flags, got:\n\(out.stderr)")
    }

    func testRenameRequiresPathAndTo() throws {
        let out = try CLI.run(["fs", "rename"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.lowercased().contains("--path") || out.stderr.lowercased().contains("--to"))
    }

    func testTrashRequiresPath() throws {
        let out = try CLI.run(["fs", "trash"])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.lowercased().contains("--path"))
    }

    func testTrashNonExistentFileReturnsAppleScriptError() throws {
        // Finder will refuse — we want the wrapper to surface that as an
        // `applescript_failed` error rather than crash or hang.
        let phantom = "/tmp/guiport-nonexistent-\(UUID().uuidString).txt"
        let out = try CLI.run(["fs", "trash", "--path", phantom])
        XCTAssertNotEqual(out.code, 0, "trashing a missing file must error")
        XCTAssertTrue(out.stderr.contains("applescript_failed")
                      || out.stderr.contains("can"),
                      "expected applescript_failed / Finder error, got:\n\(out.stderr)")
    }

    func testRevealNonExistentDoesNotHang() throws {
        // `open -R` on a missing path exits non-zero quickly. The wrapper
        // must surface the failure (and not hang).
        let phantom = "/tmp/guiport-nonexistent-\(UUID().uuidString).txt"
        let out = try CLI.run(["fs", "reveal", "--path", phantom])
        XCTAssertNotEqual(out.code, 0)
        XCTAssertTrue(out.stderr.contains("reveal_failed") || out.stderr.contains("open"))
    }
}
