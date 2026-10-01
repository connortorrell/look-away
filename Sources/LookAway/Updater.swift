import AppKit
import LookAwayCore
import Observation
import Security

/// Keeps the menu's Install Update item honest and runs the install.
///
/// Only a Developer ID-signed release can update itself: the download has to
/// be signed by the same team before it replaces this app. A `make install`
/// build is signed ad hoc, has no team, and the feature stays off.
@MainActor
@Observable
final class Updater {
    private static let staleAfter: TimeInterval = 15 * 60

    private(set) var availability: UpdateAvailability = .upToDate
    private(set) var isInstalling = false

    @ObservationIgnored private let checker: UpdateChecker?
    @ObservationIgnored private let teamIdentifier: String?
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private var lastChecked: Date?
    @ObservationIgnored private var isChecking = false

    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Look Away/update.log")

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        teamIdentifier = Self.ownDeveloperIDTeam()
        if teamIdentifier != nil,
           let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            checker = UpdateChecker(currentVersion: version)
        } else {
            checker = nil
        }
    }

    var isSupported: Bool { checker != nil }

    /// Checks unless a check finished recently, for when the menu opens.
    func checkIfStale() {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.staleAfter { return }
        check()
    }

    func check() {
        guard let checker, !isChecking, !isInstalling else { return }
        isChecking = true
        Task {
            availability = await checker.check()
            lastChecked = Date()
            isChecking = false
        }
    }

    /// Downloads the release, checks it was signed by the same team as this
    /// app, swaps it in, and relaunches. We only come back here on failure.
    func install() {
        guard case .available(let release) = availability, let teamIdentifier, !isInstalling else { return }
        isInstalling = true
        Task {
            do {
                let app = try await download(release)
                try verify(app, version: release.version, team: teamIdentifier)
                _ = try FileManager.default.replaceItemAt(bundle.bundleURL, withItemAt: app)
                try relaunch()
            } catch {
                log("Couldn't install \(release.version): \(error)")
                isInstalling = false
                showFailure()
                check()
            }
        }
    }

    /// Fetches and unzips the release next to this app, on the same volume, so
    /// the swap is a rename rather than a copy.
    private func download(_ release: Release) async throws -> URL {
        let workDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: bundle.bundleURL,
            create: true
        )
        let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError("The download answered HTTP \(code).") }
        let zip = workDirectory.appendingPathComponent(UpdateChecker.assetName)
        try FileManager.default.moveItem(at: downloaded, to: zip)

        let unzip = try Process.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", zip.path, workDirectory.path])
        await Task.detached { unzip.waitUntilExit() }.value
        guard unzip.terminationStatus == 0 else { throw UpdateError("ditto couldn't unzip the download.") }

        let apps = try FileManager.default.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1 else { throw UpdateError("The download held \(apps.count) apps, not one.") }
        return apps[0]
    }

    /// Refuses anything not signed with Developer ID by this app's own team,
    /// under this app's bundle identifier, at the version GitHub promised.
    private func verify(_ app: URL, version: String, team: String) throws {
        guard let identifier = bundle.bundleIdentifier else { throw UpdateError("This app has no bundle identifier.") }
        let requirement = Self.developerIDRequirement
            + " and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        var code: SecStaticCode?
        var compiled: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess
        else { throw UpdateError("Couldn't read the download's signature.") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, compiled)
        guard status == errSecSuccess else { throw UpdateError("The download's signature was rejected (OSStatus \(status)).") }

        let downloaded = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard downloaded == version else {
            throw UpdateError("The download is version \(downloaded ?? "unknown"), not \(version).")
        }
    }

    /// Opens the new copy once this process has gone, then quits. Opening it
    /// while we're still exiting can fail with LaunchServices error -600.
    private func relaunch() throws {
        try Self.spawnDetached(
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done",
            "open \"$2\"",
            arguments: [String(ProcessInfo.processInfo.processIdentifier), bundle.bundlePath],
            log: logURL.path
        )
        NSApp.terminate(nil)
    }

    private func showFailure() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Couldn't install the update"
        alert.informativeText = "Look Away is still running the version you had. The log has the details."
        alert.addButton(withTitle: "Show Log")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(logURL)
        }
    }

    private func log(_ message: String) {
        let entry = "\n== \(Date()) ==\n\(message)\n"
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: logURL)
        }
    }

    // MARK: Signing

    /// Apple's designated requirement for Developer ID apps: an Apple-anchored
    /// chain through the Developer ID intermediate to a Developer ID
    /// Application leaf.
    private static let developerIDRequirement = "anchor apple generic"
        + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
        + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"

    /// This app's team, when it is signed with Developer ID; nil otherwise.
    private static func ownDeveloperIDTeam() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecRequirementCreateWithString(developerIDRequirement as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: Relaunch helper

    /// Runs `/bin/sh -c` in its own session with output going to `log`.
    ///
    /// The helper has to outlive this app. A plain child could go with it: a
    /// pipe back to us would break, and launchd tidies away the process group
    /// of an app that exits. A new session and a file for output leave it
    /// nothing to lose when we quit.
    @discardableResult
    private static func spawnDetached(_ lines: String..., arguments: [String], log: String) throws -> pid_t {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: log).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // CLOEXEC_DEFAULT keeps our own open files out of the helper.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&files, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&files, 1, 2)

        let argv = (["/bin/sh", "-c", lines.joined(separator: "\n"), "sh"] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/sh", &files, &attributes, argv, environ)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }
}

private struct UpdateError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
