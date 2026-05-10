import ArgumentParser
import GuiportCore

struct FindCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find elements by selector. Visual fallback kicks in automatically when needed."
    )

    @OptionGroup var app: AppOption
    @OptionGroup var output: OutputOption

    @Option(name: .long, help: "Maximum tree depth to search.")
    var maxDepth: Int = 30

    @Flag(name: .long, help: "Match all (default: only first).")
    var all: Bool = false

    @Flag(name: .long, help: "Bypass tree cache.")
    var noCache: Bool = false

    @Flag(name: .long, help: "Disable visual fallback — return [] if AX selector misses.")
    var strict: Bool = false

    @Flag(name: .long, help: "Search the app's menu-bar-extras (NSStatusItem tray) instead of a window.")
    var tray: Bool = false

    @Argument(help: "Selector, e.g. `button[name=\"Save\"]`.")
    var selector: String

    func run() async throws {
        let target = try Adapter.current.resolveApp(name: app.app, windowTitle: app.window)
        let parsed = try Selector.parse(selector)
        let scope: TreeScope = tray ? .tray : .auto

        let tree = noCache
            ? try Adapter.current.tree(target: target, maxDepth: maxDepth, includeHidden: false, scope: scope)
            : try TreeCache.shared.tree(target: target, maxDepth: maxDepth, includeHidden: false, scope: scope)

        struct Hit: Encodable { let path: String; let node: AXNode? ; let ocr: OCRMatch? }
        var hits: [Hit] = parsed.match(tree).map { Hit(path: "ax", node: $0, ocr: nil) }
        if !all { hits = Array(hits.prefix(1)) }

        // Auto visual fallback when AX misses, Screen Recording is granted, and not strict.
        if hits.isEmpty, !strict,
           Adapter.current.hasScreenRecordingPermission(),
           let q = parsed.ocrQuery
        {
            let limit = all ? 10 : 1
            let ocr = try Adapter.current.findText(in: target, query: q, exact: false, limit: limit)
            hits = ocr.map { Hit(path: "ocr", node: nil, ocr: $0) }
        }

        try JSONOutput.print(hits, pretty: output.pretty)
    }
}
