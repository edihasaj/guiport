import XCTest

@testable import guiport

/// `guiport screenshot --window <title>` used to be a no-op flag: the target was
/// only resolved when `--app` was also passed, so the command silently captured
/// the whole virtual desktop instead of the named window. Callers had no way to
/// tell — they got a valid PNG, just of everything, including whatever window
/// happened to be covering the one they asked for.
final class ScreenshotCommandTests: XCTestCase {
    func testWindowAloneTargetsAWindow() {
        XCTAssertTrue(ScreenshotCommand.targetsWindow(app: nil, window: "Microsoft Teams"))
    }

    func testAppAloneTargetsAWindow() {
        XCTAssertTrue(ScreenshotCommand.targetsWindow(app: "ms-teams", window: nil))
    }

    func testBothTargetsAWindow() {
        XCTAssertTrue(ScreenshotCommand.targetsWindow(app: "ms-teams", window: "Chat | Bot"))
    }

    func testNeitherCapturesTheScreen() {
        XCTAssertFalse(ScreenshotCommand.targetsWindow(app: nil, window: nil))
    }

    func testEmptyStringsAreNotATarget() {
        XCTAssertFalse(ScreenshotCommand.targetsWindow(app: "", window: ""))
    }

    func testWindowIsAdvertisedInHelp() throws {
        let out = try CLI.run(["screenshot", "--help"])
        XCTAssertEqual(out.code, 0)
        XCTAssertTrue(out.stdout.contains("--window"),
                      "expected `--window` in screenshot help, got:\n\(out.stdout)")
    }
}
