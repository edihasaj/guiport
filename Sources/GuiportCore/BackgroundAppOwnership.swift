import Foundation

/// A bundle that macOS may use as the owner of a background Login Item.
///
/// Discovery deliberately starts from the executable that will run. Looking up
/// an application solely by identifier could associate a LaunchAgent with an
/// unrelated copy of an app elsewhere on disk.
public struct BackgroundAppOwner: Equatable {
    public let bundleURL: URL
    public let bundleIdentifier: String

    public init(bundleURL: URL, bundleIdentifier: String) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Finds and verifies the exact application bundle which owns a background
/// process. The filesystem portion is Foundation-only so it can be unit tested
/// with fixtures; platform code injects signing and LaunchServices operations.
public enum BackgroundAppOwnership {
    /// Return the app that directly contains `executableURL` when its bundle
    /// metadata matches the executable and expected identifier.
    public static func discover(
        executableURL: URL,
        expectedBundleIdentifier: String
    ) -> BackgroundAppOwner? {
        let executable = executableURL.resolvingSymlinksInPath().standardizedFileURL
        let macOSDirectory = executable.deletingLastPathComponent()
        guard macOSDirectory.lastPathComponent == "MacOS" else { return nil }

        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        guard contentsDirectory.lastPathComponent == "Contents" else { return nil }

        let bundleURL = contentsDirectory.deletingLastPathComponent()
        guard bundleURL.pathExtension.lowercased() == "app" else { return nil }

        let infoPlistURL = contentsDirectory.appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
            bundleIdentifier == expectedBundleIdentifier,
            let bundleExecutable = plist["CFBundleExecutable"] as? String,
            bundleExecutable == executable.lastPathComponent
        else {
            return nil
        }

        return BackgroundAppOwner(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier)
    }

    /// Find an owner, then verify and register that exact bundle. Each closure
    /// receives only a bundle that passed the strict on-disk layout checks.
    public static func verifiedAndRegistered(
        executableURL: URL,
        expectedBundleIdentifier: String,
        verifySignature: (URL) -> Bool,
        registerWithLaunchServices: (URL) -> Bool
    ) -> BackgroundAppOwner? {
        guard let owner = discover(
            executableURL: executableURL,
            expectedBundleIdentifier: expectedBundleIdentifier
        ) else {
            return nil
        }
        guard verifySignature(owner.bundleURL) else { return nil }
        guard registerWithLaunchServices(owner.bundleURL) else { return nil }
        return owner
    }

    /// Return the same plist when no verified owner exists. Repeated calls keep
    /// a single canonical association instead of accumulating duplicate values.
    public static func associating(
        _ plist: [String: Any],
        with owner: BackgroundAppOwner?
    ) -> [String: Any] {
        guard let owner else { return plist }
        var updated = plist
        updated["AssociatedBundleIdentifiers"] = [owner.bundleIdentifier]
        return updated
    }
}
