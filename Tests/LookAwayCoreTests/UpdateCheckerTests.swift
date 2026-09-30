import Foundation
import Testing
@testable import LookAwayCore

/// Answers each git command from a script and records what was asked.
private actor FakeGit: CommandRunning {
    private var replies: [String: CommandResult]
    private(set) var asked: [String] = []

    init(_ replies: [String: CommandResult]) {
        self.replies = replies
    }

    func run(_ arguments: [String], in directory: URL) async -> CommandResult {
        let command = arguments.joined(separator: " ")
        asked.append(command)
        return replies[command] ?? CommandResult(status: 128)
    }
}

struct UpdateCheckerTests {
    private static let built = "abc123"

    /// A clean checkout on main, `behind` commits past the build.
    private static func replies(
        fetch: Int32 = 0,
        branch: String = "main",
        changes: String = "",
        behind: String = "0"
    ) -> [String: CommandResult] {
        [
            "fetch --quiet origin main": CommandResult(status: fetch),
            "symbolic-ref --short HEAD": CommandResult(status: 0, output: branch),
            "status --porcelain --untracked-files=no": CommandResult(status: 0, output: changes),
            "rev-list --count \(built)..origin/main": CommandResult(status: 0, output: behind),
        ]
    }

    private static func check(_ git: FakeGit) async -> UpdateAvailability {
        await UpdateChecker(
            sourceDirectory: URL(fileURLWithPath: "/tmp/look-away"),
            builtCommit: built,
            runner: git
        ).check()
    }

    @Test func reportsTheNewCommitsOnACleanMain() async {
        let git = FakeGit(Self.replies(behind: "3"))
        #expect(await Self.check(git) == .available(commits: 3))
    }

    @Test func isUpToDateWhenNothingIsNew() async {
        let git = FakeGit(Self.replies(behind: "0"))
        #expect(await Self.check(git) == .upToDate)
    }

    @Test func stopsWhenTheFetchFails() async {
        let git = FakeGit(Self.replies(fetch: 128, behind: "3"))
        #expect(await Self.check(git) == .unavailable(.fetchFailed))
        #expect(await git.asked == ["fetch --quiet origin main"])
    }

    @Test func holdsBackOnAnotherBranch() async {
        let git = FakeGit(Self.replies(branch: "install-updates", behind: "3"))
        #expect(await Self.check(git) == .unavailable(.notOnMain))
    }

    @Test func holdsBackWithUncommittedChanges() async {
        let git = FakeGit(Self.replies(changes: " M Makefile", behind: "3"))
        #expect(await Self.check(git) == .unavailable(.uncommittedChanges))
    }

    @Test func holdsBackWhenTheBuildCommitIsUnknown() async {
        var replies = Self.replies()
        replies["rev-list --count \(Self.built)..origin/main"] = CommandResult(status: 128)
        let git = FakeGit(replies)
        #expect(await Self.check(git) == .unavailable(.unknownBuild))
    }

    @Test func countsFromTheBuiltCommitRatherThanHead() async {
        let git = FakeGit(Self.replies(behind: "1"))
        _ = await Self.check(git)
        #expect(await git.asked.last == "rev-list --count \(Self.built)..origin/main")
        #expect(await !git.asked.contains { $0.contains("HEAD..") })
    }
}
