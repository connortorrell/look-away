import AppKit

enum Sound {
    static func playChime() {
        NSSound(named: "Glass")?.play()
    }
}
