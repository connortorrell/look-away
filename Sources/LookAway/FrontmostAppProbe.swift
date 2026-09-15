import AppKit
import LookAwayCore

/// Reads which app is in front, which is the whole of what the pause list
/// needs to know.
///
/// `NSWorkspace` answers this for any app on the Mac without asking for a
/// permission of any kind: it is the same thing the menu bar already shows.
/// Nothing about the microphone or the camera is touched here.
@MainActor
final class WorkspaceFrontmostAppProbe: FrontmostAppProbing {
    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
