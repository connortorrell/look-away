import AppKit
import SwiftUI

/// Hosts the settings panel in a plain, single-instance window. The app has no
/// Dock icon or main menu, so opening it has to bring the app forward and the
/// window has to handle its own close shortcuts.
@MainActor
final class SettingsWindowController {
    private static let frameName = "Settings"
    /// Tall enough to show the sections expanded; the height can be resized.
    private static let openingHeight: CGFloat = 680
    private static let minimumHeight: CGFloat = 320

    private let model: AppModel
    private let focusGuard = ClickFocusGuard()
    private var window: SettingsWindow?
    /// The monitor lives as long as the controller does, which is as long as
    /// the app does, so there is no teardown to do. Kept in a property only so
    /// it stays alive; releasing it would stop the monitoring.
    private var clickMonitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // A window hands the keyboard to its first key view on opening, which
        // here is a time field — so the panel would come up mid-edit, with a
        // field lit and no obvious way out. Open with nothing focused instead.
        window.makeFirstResponder(nil)
    }

    private func makeWindow() -> SettingsWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model).environment(focusGuard))
        // The window owns its size: the panel scrolls, so the content's own
        // size is not the one to fit to, and a legacy scroll bar would
        // otherwise widen the window past the width the content asked for.
        hosting.sizingOptions = []
        let window = SettingsWindow(contentViewController: hosting)
        window.title = "Look Away Settings"
        // No `.fullSizeContentView`: that draws the content up behind the
        // titlebar, which a scrolling panel then slides its controls under.
        // A plain titlebar gives the content a hard edge to stop against.
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        // The panel scrolls, so it has no natural height to fit to. Open at a
        // size that shows the sections expanded and let the height be resized.
        window.contentMinSize = NSSize(width: SettingsView.width, height: Self.minimumHeight)
        window.contentMaxSize = NSSize(width: SettingsView.width, height: .greatestFiniteMagnitude)
        window.setContentSize(NSSize(width: SettingsView.width, height: Self.openingHeight))
        // Reopen where the user left it; only the very first open is centered.
        // The saved height is the user's and is kept. Only a frame saved by
        // the earlier fit-to-content panel, which was narrower and often
        // shorter than the minimum, needs bringing back into range.
        if window.setFrameUsingName(Self.frameName) {
            var size = window.contentRect(forFrameRect: window.frame).size
            size.width = SettingsView.width
            size.height = max(size.height, Self.minimumHeight)
            window.setContentSize(size)
        } else {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)
        watchForClicksOutsideFields()
        return window
    }

    /// Clicking anywhere that is not a field hands the keyboard back.
    ///
    /// Watched here rather than with a SwiftUI gesture because the fields that
    /// need this are AppKit controls: a gesture only fires when the click
    /// missed every control, so clicking a toggle or a day circle would leave
    /// a lit time field lit. The monitor sees every click in the window.
    private func watchForClicksOutsideFields() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated {
                if let window = self.window, event.window === window, !self.clickLandedOnAField(event) {
                    window.endEditing()
                }
            }
            return event
        }
    }

    private func clickLandedOnAField(_ event: NSEvent) -> Bool {
        let location = event.locationInWindow
        // SwiftUI draws its own controls into the hosting view, so `hitTest`
        // cannot tell a click on a search result from a click in empty space.
        // The views that must keep the keyboard through a click report their
        // own frames instead. SwiftUI's global space is the window frame with
        // the origin at the top left, titlebar included, so the click is
        // flipped against the frame's height to compare.
        if let window, let frameView = window.contentView?.superview {
            let clickInSwiftUISpace = CGPoint(x: location.x, y: frameView.bounds.height - location.y)
            if focusGuard.regions.values.contains(where: { $0.contains(clickInSwiftUISpace) }) { return true }
        }
        // `hitTest` takes a point in the receiver's *superview* coordinates,
        // and for the content view those are window coordinates — so the
        // location goes in as-is. Converting it first misses by the content
        // view's origin and reports every click as having hit nothing.
        guard let hit = window?.contentView?.hitTest(location) else { return false }
        // The field, its editor, and the stepper beside it are all one field
        // as far as the user is concerned.
        var view: NSView? = hit
        while let candidate = view {
            if candidate is NSText || candidate is NSTextField || candidate is NSDatePicker || candidate is NSStepper {
                return true
            }
            view = candidate.superview
        }
        return false
    }
}

/// Where in the panel a click should *not* take the keyboard away.
///
/// The app search field keeps its results open only while it has focus, and a
/// click on a result has to reach the row with the list still up and unchanged
/// — so the field and its dropdown each report their frame, and the window's
/// click monitor leaves clicks inside either alone. Frames are in SwiftUI's
/// global space.
@MainActor
@Observable
final class ClickFocusGuard {
    var regions: [String: CGRect] = [:]
}

/// With no main menu there is no File > Close, so Esc and ⌘W are handled here.
private final class SettingsWindow: NSWindow {
    /// Leaves nothing focused, and reports whether anything actually gave the
    /// keyboard up.
    ///
    /// SwiftUI's focus state only governs SwiftUI's own fields; the time
    /// pickers are AppKit controls, so the only thing they answer to is the
    /// window's first responder being taken away. Taking it away also clears
    /// SwiftUI's focus for the app search field, so one call covers both.
    ///
    /// Whether anything *had* focus is decided by watching the first responder
    /// move rather than by inspecting its type. A focused time field is an
    /// `NSDatePicker` subclass, not the field editor you would expect, so a
    /// type check quietly matches nothing. With nothing focused the responder
    /// is the window itself, and asking again is a no-op — which is exactly the
    /// signal Escape needs to know it should close the panel instead.
    @discardableResult
    func endEditing() -> Bool {
        let previous = firstResponder
        makeFirstResponder(nil)
        return firstResponder !== previous
    }

    /// Escape hands back whatever holds the keyboard; pressed again, with
    /// nothing focused, it closes the panel the way Escape usually does.
    override func cancelOperation(_ sender: Any?) {
        if !endEditing() { close() }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
