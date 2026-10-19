import Darwin
import Foundation

/// Independent of AX and the AppKit run loop, so even a stuck native call
/// cannot keep allocating until macOS starts swapping the workstation.
public enum ResourceWatchdog {
    public static let maximumBytes: UInt64 = 512 * 1_024 * 1_024
    private static var timer: DispatchSourceTimer?

    public static func start() {
        // Allow a LOWER ceiling for tests and constrained hosts, never disable
        // protection or raise it beyond the production ceiling.
        let requested = ProcessInfo.processInfo.environment["GUIPORT_MEMORY_LIMIT_MB"].flatMap(UInt64.init)
        let megabytes = min(512, max(1, requested ?? 512))
        let limit = megabytes * 1_024 * 1_024
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "guiport.memory-guard", qos: .userInitiated))
        source.schedule(deadline: .now(), repeating: .milliseconds(100))
        source.setEventHandler {
            guard let bytes = physicalFootprint(), bytes > limit else { return }
            let message = "guiport: resource_limit: physical memory exceeded \(megabytes) MiB; stopped to protect the machine.\n"
            let flags = fcntl(STDERR_FILENO, F_GETFL)
            if flags >= 0, fcntl(STDERR_FILENO, F_SETFL, flags | O_NONBLOCK) == 0 {
                // Restore the shared descriptor flags even if the pipe reader
                // has gone away; SIGPIPE must not interrupt that cleanup.
                _ = Darwin.signal(SIGPIPE, SIG_IGN)
                message.withCString { pointer in
                    _ = Darwin.write(STDERR_FILENO, pointer, strlen(pointer))
                }
                _ = fcntl(STDERR_FILENO, F_SETFL, flags)
            }
            _exit(75)
        }
        timer = source
        source.resume()
    }

    /// phys_footprint includes compressed memory; RSS alone can look small
    /// while a leaking process fills the compressor and swap.
    static func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
