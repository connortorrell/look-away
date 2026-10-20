import AppKit

/// The app's main menu, which is never seen but carries the standard keyboard
/// shortcuts.
///
/// Text fields do not handle ⌘C, ⌘V and the like themselves: AppKit matches
/// those keys against the main menu, and the matching item sends `paste:` and
/// friends to whatever holds the keyboard. A menu bar app has no menu bar to
/// show, so unless it installs a main menu anyway, every field in it silently
/// ignores copy, paste, select all and undo.
@MainActor
enum MainMenu {
    static func install() {
        // The first item is always the application menu, whatever it holds,
        // so an empty one keeps the Edit menu from being taken for it.
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(NSMenu(title: "Look Away")))
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(windowMenu()))
        NSApp.mainMenu = mainMenu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
