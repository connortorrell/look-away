import Foundation

/// What a finished command printed and how it exited.
public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String = "") {
        self.status = status
        self.output = output
    }
}

/// Runs `git` in a directory. Injected so the checker can be tested without a
/// repository or a network.
public protocol CommandRunning: Sendable {
    func run(_ arguments: [String], in directory: URL) async -> CommandResult
}

public enum UpdateAvailability: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// Offline, or GitHub refused the fetch.
        case fetchFailed
        /// The checkout is on another branch, so pulling would update the
        /// wrong thing.
        case notOnMain
        /// Tracked files have edits a pull could trip over.
        case uncommittedChanges
        /// The commit the app was built from isn't in the checkout.
        case unknownBuild
    }

    case upToDate
    case available(commits: Int)
    case unavailable(Reason)
}

/// Asks the checkout the app was built from whether GitHub has anything newer.
///
/// "Newer" is measured from the commit the running app was built from, not the
/// checkout's HEAD, so a `git pull` done by hand without reinstalling still
/// counts as an update waiting to be installed.
public struct UpdateChecker: Sendable {
    public static let branch = "main"

    public let sourceDirectory: URL
    public let builtCommit: String
    private let runner: CommandRunning

    public init(sourceDirectory: URL, builtCommit: String, runner: CommandRunning = ProcessCommandRunner()) {
        self.sourceDirectory = sourceDirectory
        self.builtCommit = builtCommit
        self.runner = runner
    }

    public func check() async -> UpdateAvailability {
        guard await git("fetch", "--quiet", "origin", Self.branch).status == 0 else {
            return .unavailable(.fetchFailed)
        }
        let head = await git("symbolic-ref", "--short", "HEAD")
        guard head.status == 0, head.output == Self.branch else {
            return .unavailable(.notOnMain)
        }
        let changes = await git("status", "--porcelain", "--untracked-files=no")
        guard changes.status == 0, changes.output.isEmpty else {
            return .unavailable(.uncommittedChanges)
        }
        let behind = await git("rev-list", "--count", "\(builtCommit)..origin/\(Self.branch)")
        guard behind.status == 0, let count = Int(behind.output) else {
            return .unavailable(.unknownBuild)
        }
        return count > 0 ? .available(commits: count) : .upToDate
    }

    private func git(_ arguments: String...) async -> CommandResult {
        await runner.run(arguments, in: sourceDirectory)
    }
}

/// Runs `/usr/bin/git` as a child process.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ arguments: [String], in directory: URL) async -> CommandResult {
        await Task.detached(priority: .utility) { Self.runToCompletion(arguments, in: directory) }.value
    }

    private static func runToCompletion(_ arguments: [String], in directory: URL) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // A menu bar app has no terminal to ask for a password on; fail
        // instead of waiting for an answer that never comes.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1)
        }
        // Drain before waiting so a chatty command can't fill the pipe and stall.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(status: process.terminationStatus, output: text)
    }
}
