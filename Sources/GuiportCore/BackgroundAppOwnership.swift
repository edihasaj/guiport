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

    /// Return the executable path launchd should execute for a verified owner.
    ///
    /// Homebrew's `bin/guiport` is a stable CLI symlink, but Background Task
    /// Management can treat that generic CLI route differently from the app
    /// bundle even when the resolved executable has a valid Team ID. For a
    /// current Cellar bundle, use the stable `opt/guiport` route only when it
    /// resolves to the exact executable inside the verified bundle. For every
    /// other layout, return the direct bundle executable.
    ///
    /// The caller must obtain `owner` through `verifiedAndRegistered`; this
    /// function validates path identity, while that operation establishes the
    /// Developer ID identity and LaunchServices registration.
    public static func preferredProgramURL(
        owner: BackgroundAppOwner,
        executableURL: URL,
        homebrewFormula: String = "guiport"
    ) -> URL? {
        let executable = executableURL.resolvingSymlinksInPath().standardizedFileURL
        let expected = owner.bundleURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executable.lastPathComponent)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard expected == executable else { return nil }

        let components = executable.pathComponents
        guard
            let cellarIndex = components.lastIndex(of: "Cellar"),
            cellarIndex + 3 < components.count,
            components[cellarIndex + 1] == homebrewFormula,
            components[cellarIndex + 3] == owner.bundleURL.lastPathComponent
        else {
            return executable
        }

        let prefixComponents = components[..<cellarIndex]
        let homebrewPrefix = prefixComponents.joined(separator: "/")
        guard !homebrewPrefix.isEmpty else { return executable }

        let suffix = components[(cellarIndex + 3)...]
        let candidate = URL(fileURLWithPath: homebrewPrefix)
            .appendingPathComponent("opt")
            .appendingPathComponent(homebrewFormula)
            .appendingPathComponent(suffix.joined(separator: "/"))
            .standardizedFileURL

        guard candidate.resolvingSymlinksInPath().standardizedFileURL == executable else {
            return executable
        }
        return candidate
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
