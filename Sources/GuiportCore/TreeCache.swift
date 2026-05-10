import Foundation

/// Per-process tree cache. Keyed by (pid, focusedWindowTitle, maxDepth, includeHidden).
/// Entries auto-invalidate after `ttl` seconds; callers can also invalidate explicitly after actions.
public final class TreeCache: @unchecked Sendable {
    public static let shared = TreeCache()

    public var ttl: TimeInterval = 0.6
    public var hits = 0
    public var misses = 0

    private struct Entry {
        let tree: AXNode
        let storedAt: Date
    }

    private struct Key: Hashable {
        let pid: Int32
        let windowKey: String
        let maxDepth: Int
        let includeHidden: Bool
    }

    private var entries: [Key: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func tree(target: AppTarget, maxDepth: Int, includeHidden: Bool) throws -> AXNode {
        let key = Key(
            pid: target.pid,
            windowKey: target.windowTitleHint ?? "",
            maxDepth: maxDepth,
            includeHidden: includeHidden
        )

        lock.lock()
        if let cached = entries[key], Date().timeIntervalSince(cached.storedAt) < ttl {
            hits += 1
            lock.unlock()
            return cached.tree
        }
        misses += 1
        lock.unlock()

        let fresh = try Adapter.current.tree(target: target, maxDepth: maxDepth, includeHidden: includeHidden)
        lock.lock()
        entries[key] = Entry(tree: fresh, storedAt: Date())
        lock.unlock()
        return fresh
    }

    public func invalidate(pid: Int32? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let pid {
            entries = entries.filter { $0.key.pid != pid }
        } else {
            entries.removeAll()
        }
    }
}
