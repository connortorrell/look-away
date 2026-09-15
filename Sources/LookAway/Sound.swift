import AppKit

enum Sound {
    /// The closest thing macOS ships to an XP orb.
    static func playLevelUp() {
        NSSound(named: "Glass")?.play()
    }
}
