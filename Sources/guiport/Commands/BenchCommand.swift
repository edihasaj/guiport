import ArgumentParser
import Foundation
import GuiportCore

struct BenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Measure observe/tree/find latency."
    )

    @OptionGroup var app: AppOption

    @Option(name: .long, help: "Iterations.")
    var n: Int = 20

    @Option(name: .long, help: "Selector to benchmark for find.")
    var selector: String = "AXButton"

    func run() async throws {
        let target = try AppRegistry.resolve(name: app.app, windowTitle: app.window)

        var observeTimes: [Double] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try AXBridge.observe(target: target)
            observeTimes.append(Date().timeIntervalSince(t0) * 1000)
        }

        var treeTimes: [Double] = []
        for _ in 0..<n {
            TreeCache.shared.invalidate(pid: target.pid)
            let t0 = Date()
            _ = try AXBridge.tree(target: target, maxDepth: 30, includeHidden: false)
            treeTimes.append(Date().timeIntervalSince(t0) * 1000)
        }

        var cachedFindTimes: [Double] = []
        let parsed = try Selector.parse(selector)
        TreeCache.shared.invalidate(pid: target.pid)
        _ = try TreeCache.shared.tree(target: target, maxDepth: 30, includeHidden: false) // prime
        for _ in 0..<n {
            let t0 = Date()
            let tree = try TreeCache.shared.tree(target: target, maxDepth: 30, includeHidden: false)
            _ = parsed.match(tree)
            cachedFindTimes.append(Date().timeIntervalSince(t0) * 1000)
        }

        struct Stat: Encodable { let n: Int; let p50: Double; let p95: Double; let avg: Double; let min: Double; let max: Double }
        struct Report: Encodable {
            let app: String
            let observeMs: Stat
            let treeMs: Stat
            let cachedFindMs: Stat
            let cacheHits: Int
            let cacheMisses: Int
        }

        func stats(_ xs: [Double]) -> Stat {
            let s = xs.sorted()
            return Stat(
                n: xs.count,
                p50: s[s.count / 2],
                p95: s[min(s.count - 1, Int(Double(s.count) * 0.95))],
                avg: xs.reduce(0, +) / Double(xs.count),
                min: s.first ?? 0,
                max: s.last ?? 0
            )
        }

        let report = Report(
            app: target.name,
            observeMs: stats(observeTimes),
            treeMs: stats(treeTimes),
            cachedFindMs: stats(cachedFindTimes),
            cacheHits: TreeCache.shared.hits,
            cacheMisses: TreeCache.shared.misses
        )
        try JSONOutput.print(report, pretty: true)
    }
}
