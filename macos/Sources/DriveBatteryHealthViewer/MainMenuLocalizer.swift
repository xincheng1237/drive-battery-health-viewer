import AppKit

@MainActor
enum MainMenuLocalizer {
    static let standardMenuKeys = ["menuEdit", "menuView", "menuWindow", "menuHelp"]
    static let menuKeys = ["menuEdit", "menuView", "report", "menuWindow", "menuHelp"]
    static let reportCommandKeys = ["refresh", "copyReport"]
    private static var pendingUpdate: Task<Void, Never>?
    private static var standardSubmenus: [String: NSMenu] = [:]
    private static var standardMenuIndexes: [String: Int] = [:]
    private static weak var observedMainMenu: NSMenu?
    private static var menuObservers: [NSObjectProtocol] = []
    private static var duplicateCleanupScheduled = false
    private static var currentLanguage: AppLanguage = .system

    static func marker(for key: String) -> String {
        "__DBHV_STANDARD_MENU_\(key)__"
    }

    static func apply(_ language: AppLanguage) {
        pendingUpdate?.cancel()
        applyNow(language)
        pendingUpdate = Task { @MainActor in
            for delay in [50_000_000, 250_000_000, 700_000_000] as [UInt64] {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                applyNow(language)
            }
        }
    }

    private static func applyNow(_ language: AppLanguage) {
        guard let mainMenu = NSApp.mainMenu else { return }
        currentLanguage = language
        observeMenuAdditions(in: mainMenu)
        installStandardMenuShells(in: mainMenu, language: language)
        apply(to: mainMenu, language: language)
        NSApp.windowsMenu = standardSubmenus["menuWindow"]
        NSApp.helpMenu = standardSubmenus["menuHelp"]
        removeUnmanagedStandardMenus(from: mainMenu)
    }

    static func apply(to mainMenu: NSMenu, language: AppLanguage) {
        for key in menuKeys {
            let knownTitles = Set(AppLanguage.allCases.map { L10n.text(key, $0) })
            guard let item = mainMenu.items.first(where: {
                knownTitles.contains($0.title) || knownTitles.contains($0.submenu?.title ?? "")
            }) else { continue }

            let title = L10n.text(key, language)
            setTitle(title, on: item)
        }

        guard let reportMenu = mainMenu.items.first(where: {
            $0.title == L10n.text("report", language)
        })?.submenu else { return }

        for key in reportCommandKeys {
            let knownTitles = Set(AppLanguage.allCases.map { L10n.text(key, $0) })
            guard let item = reportMenu.items.first(where: { knownTitles.contains($0.title) }) else { continue }
            let title = L10n.text(key, language)
            setTitle(title, on: item, includeSubmenu: false)
        }
    }

    private static func installStandardMenuShells(in mainMenu: NSMenu, language: AppLanguage) {
        for key in standardMenuKeys {
            let itemIdentifier = identifier(for: key)
            let markerTitle = marker(for: key)
            let managedItems = mainMenu.items.filter { item in
                item.identifier == itemIdentifier || item.submenu?.items.contains(where: { $0.title == markerTitle }) == true
            }
            guard let shell = managedItems.first(where: {
                $0.submenu?.items.contains(where: { $0.title == markerTitle }) == true
            }) ?? managedItems.first else { continue }

            shell.identifier = itemIdentifier
            shell.submenu?.items
                .filter { $0.title == markerTitle }
                .forEach { shell.submenu?.removeItem($0) }

            let knownTitles = Set(AppLanguage.allCases.map { L10n.text(key, $0) })
            if let systemItem = mainMenu.items.first(where: { item in
                item !== shell && item.identifier != itemIdentifier &&
                    (knownTitles.contains(item.title) || knownTitles.contains(item.submenu?.title ?? ""))
            }) {
                if standardMenuIndexes[key] == nil {
                    standardMenuIndexes[key] = mainMenu.index(of: systemItem)
                }
                if standardSubmenus[key] == nil {
                    standardSubmenus[key] = systemItem.submenu
                }
                systemItem.submenu = nil
                mainMenu.removeItem(systemItem)
            }

            for obsolete in managedItems where obsolete !== shell {
                if obsolete.submenu === standardSubmenus[key] {
                    obsolete.submenu = nil
                }
                mainMenu.removeItem(obsolete)
            }

            if let submenu = standardSubmenus[key] {
                shell.submenu = submenu
            }

            let title = L10n.text(key, language)
            setTitle(title, on: shell)

            if let destination = standardMenuIndexes[key], let current = mainMenu.items.firstIndex(where: { $0 === shell }), current != destination {
                mainMenu.removeItem(at: current)
                mainMenu.insertItem(shell, at: min(destination, mainMenu.items.count))
            }
        }
    }

    private static func identifier(for key: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("com.chengxin.drive-battery-health-viewer.\(key)")
    }

    private static func removeUnmanagedStandardMenus(from mainMenu: NSMenu) {
        for key in standardMenuKeys {
            let managedIdentifier = identifier(for: key)
            let knownTitles = Set(AppLanguage.allCases.map { L10n.text(key, $0) })
            for item in mainMenu.items where item.identifier != managedIdentifier &&
                (knownTitles.contains(item.title) || knownTitles.contains(item.submenu?.title ?? "")) {
                item.submenu = nil
                mainMenu.removeItem(item)
            }
        }
    }

    private static func observeMenuAdditions(in mainMenu: NSMenu) {
        guard observedMainMenu !== mainMenu else { return }
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers.removeAll()
        observedMainMenu = mainMenu
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: mainMenu,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    scheduleDuplicateCleanup()
                }
            }
            menuObservers.append(observer)
        }
    }

    private static func scheduleDuplicateCleanup() {
        guard !duplicateCleanupScheduled else { return }
        duplicateCleanupScheduled = true
        Task { @MainActor in
            await Task.yield()
            duplicateCleanupScheduled = false
            guard let mainMenu = observedMainMenu else { return }
            installStandardMenuShells(in: mainMenu, language: currentLanguage)
            apply(to: mainMenu, language: currentLanguage)
            NSApp.windowsMenu = standardSubmenus["menuWindow"]
            NSApp.helpMenu = standardSubmenus["menuHelp"]
            removeUnmanagedStandardMenus(from: mainMenu)
        }
    }

    private static func setTitle(_ title: String, on item: NSMenuItem, includeSubmenu: Bool = true) {
        if item.title != title {
            item.title = title
        }
        if item.attributedTitle?.string != title {
            item.attributedTitle = NSAttributedString(string: title)
        }
        if includeSubmenu, item.submenu?.title != title {
            item.submenu?.title = title
        }
    }
}
