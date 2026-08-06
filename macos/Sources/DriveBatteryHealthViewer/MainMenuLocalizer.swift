import AppKit

/// Localized metadata for the menus that the application owns.
///
/// AppKit owns the standard Edit, View, Window and Help menus.  Earlier
/// versions tried to discover those menus after SwiftUI had built them by
/// inserting marker items and repeatedly moving their submenus around.  That
/// is unsafe while AppKit is tracking a menu (and is the source of both the
/// marker leak and the stuck/duplicated menu sessions).  This type therefore
/// has no observers, delayed work, cached NSMenu instances or NSApp mutation.
@MainActor
enum MainMenuLocalizer {
    static let standardMenuKeys = ["menuEdit", "menuView", "menuWindow", "menuHelp"]
    static let menuKeys = ["menuEdit", "menuView", "report", "menuWindow", "menuHelp"]
    static let reportCommandKeys = ["refresh", "copyReport"]

    struct Definition: Equatable, Sendable {
        let key: String
        let title: String
        let isSystemOwned: Bool
    }

    private static var activeLanguage: AppLanguage = .system

    /// Returns the stable menu order used by the app-owned command surface.
    /// The standard menus are listed for diagnostics only; they are not
    /// rebuilt or reattached at runtime.
    static func definitions(for language: AppLanguage) -> [Definition] {
        [
            Definition(key: "menuEdit", title: L10n.text("menuEdit", language), isSystemOwned: true),
            Definition(key: "menuView", title: L10n.text("menuView", language), isSystemOwned: true),
            Definition(key: "report", title: L10n.text("report", language), isSystemOwned: false),
            Definition(key: "menuWindow", title: L10n.text("menuWindow", language), isSystemOwned: true),
            Definition(key: "menuHelp", title: L10n.text("menuHelp", language), isSystemOwned: true)
        ]
    }

    /// Kept as a compatibility hook for callers from older builds.  It only
    /// records state; it never touches the live AppKit menu hierarchy.
    static func apply(_ language: AppLanguage) {
        activeLanguage = language
    }

    static var language: AppLanguage { activeLanguage }

    /// Purely relocalizes a menu supplied by a caller.  It does not add,
    /// remove, reorder, detach or reattach any item and is safe for tests and
    /// for menus that are not being tracked.  The app no longer calls this on
    /// NSApp.mainMenu; SwiftUI/AppKit own the live menu lifecycle.
    static func apply(to mainMenu: NSMenu, language: AppLanguage) {
        let allTitles = Set(AppLanguage.allCases.flatMap { language in
            menuKeys.map { L10n.text($0, language) } + reportCommandKeys.map { L10n.text($0, language) }
        })

        for item in mainMenu.items {
            if let key = menuKeys.first(where: { key in
                let known = Set(AppLanguage.allCases.map { L10n.text(key, $0) })
                return known.contains(item.title) || known.contains(item.submenu?.title ?? "")
            }) {
                setTitle(L10n.text(key, language), on: item)
                if key == "report", let submenu = item.submenu {
                    for command in submenu.items where allTitles.contains(command.title) {
                        if let commandKey = reportCommandKeys.first(where: { key in
                            AppLanguage.allCases.map { L10n.text(key, $0) }.contains(command.title)
                        }) {
                            setTitle(L10n.text(commandKey, language), on: command, includeSubmenu: false)
                        }
                    }
                }
            }
        }
    }

    /// Defensive diagnostic used by tests and debug tooling.  No production
    /// menu item is ever created from this prefix.
    static func containsInternalMarker(in menu: NSMenu) -> Bool {
        menu.items.contains { item in
            item.title.hasPrefix("__DBHV_STANDARD_MENU_") ||
            item.submenu.map(containsInternalMarker(in:)) ?? false
        }
    }

    static func menuOrder(for language: AppLanguage) -> [String] {
        definitions(for: language).map(\.key)
    }

    private static func setTitle(_ title: String, on item: NSMenuItem, includeSubmenu: Bool = true) {
        if item.title != title { item.title = title }
        if item.attributedTitle?.string != title {
            item.attributedTitle = NSAttributedString(string: title)
        }
        if includeSubmenu, item.submenu?.title != title {
            item.submenu?.title = title
        }
    }
}
