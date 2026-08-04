import XCTest
@testable import GuiportCore

/// One selector, both platforms.
///
/// Selectors normalise `button` to `AXButton`, so the Windows adapter has to
/// emit `AXButton` too — otherwise `guiport click 'button[name="Send"]'` works
/// on a Mac and silently matches nothing on the VM, which is the worst kind of
/// difference: not an error, just no result.
final class UIARoleTests: XCTestCase {
    func testControlTypesMapOntoTheRolesSelectorsUse() {
        XCTAssertEqual(UIARole.ax(for: "Button"), "AXButton")
        XCTAssertEqual(UIARole.ax(for: "Edit"), "AXTextField")
        XCTAssertEqual(UIARole.ax(for: "Document"), "AXTextArea")
        XCTAssertEqual(UIARole.ax(for: "MenuItem"), "AXMenuItem")
        XCTAssertEqual(UIARole.ax(for: "Hyperlink"), "AXLink")
        XCTAssertEqual(UIARole.ax(for: "Text"), "AXStaticText")
    }

    func testEveryMappedRoleIsOneASelectorCanAskFor() throws {
        // The point of the mapping is that a parsed selector matches it. If a
        // role here is not what `Selector` normalises its friendly name to, the
        // mapping is decorative.
        let pairs = [("button", "Button"), ("textfield", "Edit"),
                     ("textarea", "Document"), ("checkbox", "CheckBox"),
                     ("menuitem", "MenuItem"), ("link", "Hyperlink"),
                     ("statictext", "Text"), ("list", "List"), ("row", "ListItem")]
        for (friendly, uia) in pairs {
            let sel = try Selector.parse(friendly)
            XCTAssertEqual(sel.role, UIARole.ax(for: uia),
                           "selector \(friendly) does not match UIA \(uia)")
        }
    }

    func testUnknownControlTypesKeepTheirOwnName() {
        // So a selector can always fall back to what the platform calls it.
        XCTAssertEqual(UIARole.ax(for: "Thumb"), "Thumb")
        XCTAssertEqual(UIARole.ax(for: "SemanticZoom"), "SemanticZoom")
    }

    func testPanesAndCustomElementsAreGroups() {
        // Electron and WebView2 apps are largely Pane/Custom; treating them as
        // groups keeps `group` selectors and tree walks meaningful there.
        XCTAssertEqual(UIARole.ax(for: "Pane"), "AXGroup")
        XCTAssertEqual(UIARole.ax(for: "Custom"), "AXGroup")
    }
}
