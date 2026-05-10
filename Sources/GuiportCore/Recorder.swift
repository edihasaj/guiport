import Foundation

/// MVP recorder: dumps a starter YAML test scaffolded against the current focused window.
/// Full event-recording is post-MVP — for now agents author/replay tests directly.
public enum Recorder {
    public static func record(target: AppTarget, to path: String) throws {
        let summary = try AXBridge.observe(target: target)
        let win = summary.window?.title ?? ""
        let yaml = """
        # guiport test scaffolded \(ISO8601DateFormatter().string(from: Date()))
        name: \(target.name) smoke
        app: "\(target.name)"
        timeout_ms: 5000
        steps:
          - wait: 200
          # Inspect tree first:
          #   guiport tree --app "\(target.name)" --pretty
          # Then add steps, e.g.:
          #   - find: 'AXButton[name="Save"]'
          #   - click: 'AXButton[name="Save"]'
          #   - type: "hello"
          #   - assert:
          #       find: 'AXStaticText[name~="Saved"]'
          #       exists: true
        # window seed: \(win)
        """
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        print("scaffold written → \(path)")
        print("next: edit steps, then `guiport run \(path)`")
    }
}
