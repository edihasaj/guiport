import Foundation

/// Mapping Windows UI Automation control types onto the role names selectors
/// already speak.
///
/// Selectors normalise `button` to `AXButton`, `textfield` to `AXTextField`
/// and so on — macOS names, because that is where guiport started. Emitting
/// those same names from the Windows adapter is what lets one selector work on
/// both platforms: `guiport click 'button[name="Send"]'` means the same thing
/// against a Mac app and against a Windows one, and a script does not have to
/// know which machine it is on.
///
/// Lives in Core rather than the Windows adapter so it is testable everywhere,
/// including on the macOS and Linux CI runners where the adapter is compiled
/// out entirely.
public enum UIARole {
    /// The AX role for a UIA control type. Unknown types keep their UIA name,
    /// so a selector can always fall back to what the platform calls the thing.
    public static func ax(for uia: String) -> String {
        table[uia] ?? uia
    }

    private static let table: [String: String] = [
        "Button": "AXButton",
        "SplitButton": "AXButton",
        "Edit": "AXTextField",
        "Document": "AXTextArea",
        "CheckBox": "AXCheckBox",
        "RadioButton": "AXRadioButton",
        "Menu": "AXMenu",
        "MenuBar": "AXMenu",
        "MenuItem": "AXMenuItem",
        "ComboBox": "AXPopUpButton",
        "Hyperlink": "AXLink",
        "Image": "AXImage",
        "List": "AXList",
        "ListItem": "AXRow",
        "DataItem": "AXRow",
        "DataGrid": "AXTable",
        "Table": "AXTable",
        "Text": "AXStaticText",
        "Group": "AXGroup",
        "Pane": "AXGroup",
        "Custom": "AXGroup",
        "Window": "AXWindow",
        "ToolBar": "AXToolbar",
        "Tab": "AXTabGroup",
        "TabItem": "AXTab",
        "Slider": "AXSlider",
        "Tree": "AXOutline",
        "TreeItem": "AXRow",
        "ScrollBar": "AXScrollBar",
    ]
}
