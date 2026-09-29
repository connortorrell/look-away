import AppKit
import LookAwayCore
import Observation

/// Keeps the menu's Install Updates item honest and runs the install.
///
/// `make bundle` records the checkout the app was built from and its commit in
/// Info.plist. An app built any other way has neither, and the feature stays
/// off.
@MainActor
@Observable
final class Updater {
    private static let staleAfter: TimeInterval = 15 * 60

    private(set) var availability: UpdateAvailability = .upToDate
    private(set) var isInstalling = false

    @ObservationIgnored private let checker: UpdateChecker?
    @ObservationIgnored private var lastChecked: Date?
    @ObservationIgnored private var isChecking = false

    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Look Away/update.log")

    init(bundle: Bundle = .main) {
        if let path = bundle.object(forInfoDictionaryKey: "LookAwaySourceDirectory") as? String,
           let commit = bundle.object(forInfoDictionaryKey: "LookAwayCommit") as? String {
            checker = UpdateChecker(sourceDirectory: URL(fileURLWithPath: path), builtCommit: commit)
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

    /// Pulls and runs `make install`, which quits this app and opens the new
    /// build. We only hear back if that fails before it gets that far.
    func install() {
        guard let checker, !isInstalling else { return }
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let pid = try Self.spawnDetached(
                "cd \"$1\" || exit",
                "printf '\\n== %s ==\\n' \"$(date)\"",
                "GIT_TERMINAL_PROMPT=0 git pull --ff-only origin \(UpdateChecker.branch) && make install",
                argument: checker.sourceDirectory.path,
                log: logURL.path
            )
            isInstalling = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var status: Int32 = 0
                waitpid(pid, &status, 0)
                Task { @MainActor in self?.installFinished(status: status) }
            }
        } catch {
            showFailure()
        }
    }

    private func installFinished(status: Int32) {
        isInstalling = false
        // Success ends with this process killed by `make install`; still here
        // with a clean exit means there was nothing to replace.
        guard status != 0 else { return check() }
        showFailure()
        check()
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

    /// Runs `/bin/sh -c` in its own session with output going to `log`.
    ///
    /// `make install` kills this app partway through. A plain child could go
    /// with it: a pipe back to us would break, and launchd tidies away the
    /// process group of an app that exits. A new session and a file for output
    /// leave it nothing to lose when we quit.
    private static func spawnDetached(_ lines: String..., argument: String, log: String) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // CLOEXEC_DEFAULT keeps our own open files out of the build.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&files, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&files, 1, 2)

        let arguments = ["/bin/sh", "-c", lines.joined(separator: "\n"), "sh", argument]
        let argv = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/sh", &files, &attributes, argv, environ)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }
}
