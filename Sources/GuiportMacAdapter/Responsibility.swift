import Darwin
import Foundation

/// macOS attributes some TCC services to the *responsible* process rather than the
/// calling one. Accessibility is judged on the calling binary's own code identity
/// (so guiport's own grant counts), but **Screen Recording** is judged on the
/// responsible process — which, for a CLI, is the terminal that spawned it. When
/// that terminal lacks (or is denied) Screen Recording, every child inheriting its
/// responsibility is blocked too — including Apple's own `screencapture`, regardless
/// of the child's own grant.
///
/// The fix is to disclaim responsibility from our parent so guiport becomes its own
/// responsible process. Then macOS evaluates guiport's own (already-granted) identity
/// for Screen Recording, independent of which terminal launched it. We do this by
/// re-executing ourselves once via `posix_spawn` with
/// `responsibility_spawnattrs_setdisclaim`, then forwarding the child's exit status.
public enum Responsibility {

    /// Commands that actually touch Screen Recording. Only these pay the re-exec cost.
    private static let screenCaptureCommands: Set<String> = ["screenshot", "record", "doctor"]

    private static let marker = "GUIPORT_DISCLAIMED"

    /// Re-exec self as our own responsible process when running a screen-capture
    /// command under a parent (terminal) that owns TCC responsibility. Idempotent:
    /// guarded by an env marker so the re-exec'd child runs in-process. Best-effort —
    /// on any failure we simply continue in-process rather than abort.
    public static func disclaimIfNeeded(arguments: [String]) {
        let env = ProcessInfo.processInfo.environment
        if env[marker] != nil { return }

        // First non-flag token is the subcommand (e.g. `guiport --pretty screenshot`).
        guard let sub = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }),
              screenCaptureCommands.contains(sub) else { return }

        guard let exePath = Bundle.main.executablePath else { return }

        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else { return }
        defer { posix_spawnattr_destroy(&attr) }
        guard responsibility_spawnattrs_setdisclaim(&attr, 1) == 0 else { return }

        var argv: [UnsafeMutablePointer<CChar>?] = ([exePath] + arguments.dropFirst()).map { strdup($0) }
        argv.append(nil)

        var childEnv = env
        childEnv[marker] = "1"
        var envp: [UnsafeMutablePointer<CChar>?] = childEnv.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)

        defer {
            for p in argv where p != nil { free(p) }
            for p in envp where p != nil { free(p) }
        }

        var pid: pid_t = 0
        // stdio inherited by default (no file actions) → transparent passthrough.
        guard posix_spawn(&pid, exePath, nil, &attr, argv, envp) == 0 else { return }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR { continue }

        if status & 0x7f == 0 {           // exited normally → forward exit code
            exit((status >> 8) & 0xff)
        }
        exit(1)                            // killed by signal → generic failure
    }
}

/// Private libsystem entry point: mark a spawned process as its own responsible
/// process for TCC purposes. Stable since macOS 10.14; declared here because it has
/// no public header.
@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ disclaim: Int32
) -> Int32
