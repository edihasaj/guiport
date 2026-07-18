import ArgumentParser
import GuiportCore

/// State assertions to place between flow steps. Exits nonzero when any
/// requested check fails, so shell flows can verify they're where they think
/// they are before typing/clicking. `--running` / `--frontmost` /
/// `--front-title-contains` are shallow depth-1 reads; `--focused` walks the
/// app's focused-window accessibility tree, so it's heavier on large Electron
/// UIs.
///
/// With no specific check flag, defaults to asserting the app is running.
struct AssertCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assert",
        abstract: "Assert app/window/focus state; nonzero exit when unmet."
    )

    @Option(name: .long, help: "Target app: bundle id (com.x.y) or display name.")
    var app: String

    @Flag(name: .long, help: "Assert the app is running.")
    var running: Bool = false

    @Flag(name: .long, help: "Assert the app is the frontmost application.")
    var frontmost: Bool = false

    @Option(name: .long, help: "Assert the app's front window title contains this substring (case-insensitive).")
    var frontTitleContains: String?

    @Option(name: .long, help: "Assert an element matching this selector is currently focused.")
    var focused: String?

    @OptionGroup var output: OutputOption

    func run() async throws {
        var checks: [AssertCheck] = []

        // Resolve once. A missing app fails every dependent check with a clear
        // reason instead of throwing and aborting the whole assertion.
        let target: AppTarget?
        var resolveError: String?
        do {
            target = try Adapter.current.resolveApp(name: app)
        } catch let e as GuiportError {
            target = nil
            resolveError = e.message
        }

        // No explicit check → assert the app is running.
        let wantRunning = running || (!frontmost && frontTitleContains == nil && focused == nil)
        if wantRunning {
            checks.append(AssertCheck(
                name: "running",
                passed: target != nil,
                detail: target != nil ? nil : (resolveError ?? "not running")
            ))
        }

        if frontmost {
            let front = Adapter.current.frontmostApp()
            let ok = target != nil && front?.pid == target?.pid
            checks.append(AssertCheck(
                name: "frontmost",
                passed: ok,
                detail: ok ? nil : "front app: \(front?.name ?? "unknown")"
            ))
        }

        if let needle = frontTitleContains {
            var ok = false
            var detail: String? = resolveError ?? "no front window"
            if let t = target {
                let title = (try? Adapter.current.observe(target: t))?.window?.title
                ok = title?.range(of: needle, options: .caseInsensitive) != nil
                detail = ok ? nil : "front title: \(title ?? "nil")"
            }
            checks.append(AssertCheck(name: "front-title-contains", passed: ok, detail: detail))
        }

        if let sel = focused {
            var ok = false
            var detail: String? = resolveError
            if let t = target {
                do {
                    let parsed = try Selector.parse(sel)
                    let tree = try Adapter.current.tree(target: t)
                    ok = parsed.match(tree).contains { $0.focused == true }
                    detail = ok ? nil : "no focused element matches \(sel)"
                } catch let e as GuiportError {
                    detail = e.message
                }
            }
            checks.append(AssertCheck(name: "focused", passed: ok, detail: detail))
        }

        let result = AssertResult(app: app, checks: checks)
        try JSONOutput.print(result, pretty: output.pretty)
        if !result.passed {
            throw ExitCode.failure
        }
    }
}
