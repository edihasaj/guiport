import Foundation

/// Shared by the capture loop and a timer, so deadlines/Stop remain observable
/// when an app stops producing frames or an output pipe stops draining.
public final class StreamControl: @unchecked Sendable {
    public enum Stop: Equatable {
        case limit
        case cancelled(String)
    }

    private let lock = NSLock()
    private let deadline: TimeInterval?
    private let frameLimit: Int?
    private let now: () -> TimeInterval
    private let cancellation: () -> String?
    private var frames = 0
    private var stop: Stop?
    private var stopTime: TimeInterval?
    private var completed = false
    private var timer: DispatchSourceTimer?

    public init(seconds: Double?, frames: Int?,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                cancellation: @escaping () -> String? = { Cancellation.activeReason() }) {
        self.now = now
        self.deadline = seconds.map { now() + $0 }
        self.frameLimit = frames
        self.cancellation = cancellation
    }

    public func delivered(_ count: Int) {
        lock.lock()
        frames = max(frames, count)
        lock.unlock()
    }

    public var deliveredFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    public func stopReason() -> Stop? {
        let reason = cancellation()
        let time = now()
        lock.lock()
        defer { lock.unlock() }
        if stop == nil {
            if let reason { stop = .cancelled(reason) }
            else if deadline.map({ time >= $0 }) == true || frameLimit.map({ frames >= $0 }) == true {
                stop = .limit
            }
            if stop != nil { stopTime = time }
        }
        return stop
    }

    public func throwIfCancelled() throws {
        if case .cancelled(let reason) = stopReason() {
            throw GuiportError(code: "cancelled", message: "Stream stopped by the user (\(reason)).")
        }
    }

    /// The native loop normally finishes promptly. If native I/O or a full
    /// stdout pipe prevents cleanup, the CLI's independent timer can force exit.
    public func needsForcedExit(grace: TimeInterval = 2) -> Bool {
        _ = stopReason()
        lock.lock()
        defer { lock.unlock() }
        return !completed && stopTime.map { now() - $0 >= grace } == true
    }

    public func startWatchdog(onStall: @escaping @Sendable () -> Void) {
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "guiport.stream-control"))
        source.schedule(deadline: .now(), repeating: .milliseconds(100))
        source.setEventHandler { [weak self] in
            if self?.needsForcedExit() == true { onStall() }
        }
        lock.lock()
        timer = source
        lock.unlock()
        source.resume()
    }

    public func finish() {
        lock.lock()
        completed = true
        let source = timer
        timer = nil
        lock.unlock()
        source?.cancel()
    }

    deinit { timer?.cancel() }
}
