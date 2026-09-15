import AppKit
import SwiftUI

/// Hosts the settings panel in a plain, single-instance window. The app has no
/// Dock icon or main menu, so opening it has to bring the app forward and the
/// window has to handle its own close shortcuts.
@MainActor
final class SettingsWindowController {
    private static let frameName = "Settings"

    private let model: AppModel
    private var window: NSWindow?
    private var clickMonitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    // The monitor lives as long as the controller does, which is as long as the
    // app does, so there is no teardown to do. Kept in a property only so it
    // stays alive; releasing it would stop the monitoring.

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

    /// Closes the panel without throwing the window away, so reopening keeps
    /// whatever was scrolled to and expanded.
    func close() {
        window?.performClose(nil)
    }

    /// Leaves nothing focused, and reports whether anything actually gave the
    /// keyboard up.
    ///
    /// SwiftUI's focus state only governs SwiftUI's own fields; the time
    /// pickers are AppKit controls, so the only thing they answer to is the
    /// window's first responder being taken away.
    ///
    /// Whether anything *had* focus is decided by watching the first responder
    /// move rather than by inspecting its type. A focused time field is an
    /// `NSDatePicker` subclass, not the field editor you would expect, so a
    /// type check quietly matches nothing. With nothing focused the responder
    /// is the window itself, and asking again is a no-op — which is exactly the
    /// signal Escape needs to know it should close the panel instead.
    @discardableResult
    func endEditing() -> Bool {
        guard let window else { return false }
        let previous = window.firstResponder
        window.makeFirstResponder(nil)
        return window.firstResponder !== previous
    }

    /// Clicking anywhere that is not a field hands the keyboard back.
    ///
    /// Watched here rather than with a SwiftUI gesture because the fields that
    /// need this are AppKit controls: a gesture only covers the area SwiftUI
    /// laid out, so clicks in the empty space below the content — the obvious
    /// place to click to mean "nothing" — would miss it entirely.
    private func watchForClicksOutsideFields() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated {
                if let window = self.window, event.window === window, !self.clickLandedOnAField(event) {
                    self.endEditing()
                }
            }
            return event
        }
    }

    private func clickLandedOnAField(_ event: NSEvent) -> Bool {
        // `hitTest` takes a point in the receiver's *superview* coordinates,
        // and for the content view those are window coordinates — so the
        // location goes in as-is. Converting it first misses by the content
        // view's origin and reports every click as having hit nothing.
        guard let hit = window?.contentView?.hitTest(event.locationInWindow) else { return false }
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

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView(
                model: model,
                endEditing: { [weak self] in self?.endEditing() ?? false },
                close: { [weak self] in self?.close() }
            )
        )
        let window = SettingsWindow(contentViewController: hosting)
        window.title = "Look Away Settings"
        // No `.fullSizeContentView`: that draws the content up behind the
        // titlebar, which a scrolling panel then slides its controls under.
        // A plain titlebar gives the content a hard edge to stop against.
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        // The panel scrolls, so it has no natural height to fit to. Open at a
        // size that shows both sections expanded and let it be resized.
        window.setContentSize(NSSize(width: SettingsView.width, height: 620))
        window.contentMinSize = NSSize(width: SettingsView.width, height: 320)
        window.contentMaxSize = NSSize(width: SettingsView.width, height: .greatestFiniteMagnitude)
        // Reopen where the user left it; only the very first open is centered.
        // A stale saved height is harmless now that the content scrolls.
        if !window.setFrameUsingName(Self.frameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)
        watchForClicksOutsideFields()
        return window
    }
}

/// With no main menu there is no File > Close, so ⌘W is handled here. Esc is
/// handled by the panel itself, which gives up focus before it closes; this is
/// only the fallback for when nothing in SwiftUI takes the key.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
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
