import AppKit

/// Owns one stable AppKit menu tree for the lifetime of the process. Language
/// changes update titles in-place only while no menu is being tracked. The
/// hierarchy, actions and AppKit Window/Help/Services bindings never change.
@MainActor
enum MainMenuLocalizer {
    static let standardMenuKeys = ["menuFile", "menuView", "menuWindow", "menuHelp"]
    static let menuKeys = ["menuFile", "menuView", "report", "menuWindow", "menuHelp"]
    static let reportCommandKeys = ["refresh", "copyReport"]

    struct Definition: Equatable, Sendable {
        let key: String
        let title: String
        let isSystemOwned: Bool
    }

    private static var activeLanguage: AppLanguage = .system
    private static var isInstalled = false
    private static var trackingDepth = 0
    private static var updateScheduled = false
    private static var stableMainMenu: NSMenu?
    private static var observers: [NSObjectProtocol] = []
    private static let roleCache = NSMapTable<NSMenuItem, NSString>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )
    static func definitions(for language: AppLanguage) -> [Definition] {
        [
            Definition(key: "menuFile", title: L10n.text("menuFile", language), isSystemOwned: true),
            Definition(key: "menuView", title: L10n.text("menuView", language), isSystemOwned: true),
            Definition(key: "report", title: L10n.text("report", language), isSystemOwned: false),
            Definition(key: "menuWindow", title: L10n.text("menuWindow", language), isSystemOwned: true),
            Definition(key: "menuHelp", title: L10n.text("menuHelp", language), isSystemOwned: true)
        ]
    }

    /// Installs two tracking observers once. They only record menu tracking
    /// state; there are deliberately no item-change observers or feedback
    /// loops. A pending language update runs after tracking has ended.
    static func install(_ language: AppLanguage, model: AppModel) {
        MenuActionRouter.shared.model = model
        activeLanguage = language
        guard !isInstalled else {
            scheduleUpdate()
            return
        }
        isInstalled = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                trackingDepth += 1
            }
        })
        observers.append(center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                trackingDepth = max(0, trackingDepth - 1)
                if trackingDepth == 0 { scheduleUpdate() }
            }
        })
        reconcileNowIfSafe()
    }

    static func apply(_ language: AppLanguage) {
        activeLanguage = language
        reconcileNowIfSafe()
        scheduleUpdate()
    }

    static var language: AppLanguage { activeLanguage }

    /// Idempotently updates titles in-place. No item is inserted, removed,
    /// moved, detached, reattached, enabled or assigned a new action.
    static func apply(to mainMenu: NSMenu, language: AppLanguage) {
        let topItems = mainMenu.items
        for (index, item) in topItems.enumerated() where !item.isSeparatorItem {
            guard let role = topRole(for: item, index: index, itemCount: topItems.count) else { continue }
            remember(role, for: item)
            setTitle(title(for: role, language: language), on: item)
            if let submenu = item.submenu {
                localize(submenu, parent: role, language: language)
            }
        }
    }

    /// Applies the selected language to the application-owned AppKit menu.
    static func prepareForDisplay(_ mainMenu: NSMenu, language: AppLanguage) {
        activeLanguage = language
        apply(to: mainMenu, language: language)
    }

    static func containsInternalMarker(in menu: NSMenu) -> Bool {
        menu.items.contains { item in
            item.title.hasPrefix("__DBHV_STANDARD_MENU_") ||
            item.submenu.map(containsInternalMarker(in:)) ?? false
        }
    }

    static func menuOrder(for language: AppLanguage) -> [String] {
        definitions(for: language).map(\.key)
    }

    /// Exposes a detached production menu tree to structural tests. Installing
    /// and binding the process-wide menu remains private to `install`.
    static func makeMenuForTesting(language: AppLanguage) -> NSMenu {
        makeMainMenu(language: language)
    }

    private static func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                updateScheduled = false
                guard trackingDepth == 0, let menu = stableMenuIfAvailable() else { return }
                prepareForDisplay(menu, language: activeLanguage)
            }
        }
    }

    private static func reconcileNowIfSafe() {
        guard trackingDepth == 0, let menu = stableMenuIfAvailable() else { return }
        prepareForDisplay(menu, language: activeLanguage)
    }

    private static func stableMenuIfAvailable() -> NSMenu? {
        if let stableMainMenu {
            if NSApp.mainMenu !== stableMainMenu { NSApp.mainMenu = stableMainMenu }
            return stableMainMenu
        }
        let menu = makeMainMenu(language: activeLanguage)
        stableMainMenu = menu
        NSApp.mainMenu = menu
        bindApplicationMenus(in: menu)
        return menu
    }

    /// Services is bound once so macOS can populate third-party services. The
    /// app intentionally does not assign `NSApp.windowsMenu` or `NSApp.helpMenu`:
    /// AppKit can mutate those menus immediately before display by injecting
    /// system-language groups. The stable application-owned Window and Help
    /// menus keep their public actions without runtime insertion or duplicates.
    private static func bindApplicationMenus(in mainMenu: NSMenu) {
        for (index, item) in mainMenu.items.enumerated() {
            guard let submenu = item.submenu,
                  let role = topRole(for: item, index: index, itemCount: mainMenu.items.count) else { continue }
            switch role {
            case .windowMenu: break
            case .helpMenu: break
            case .appMenu:
                if let services = submenu.items.first(where: {
                    roleForKnownTitle($0.title, parent: .appMenu) == .services
                })?.submenu {
                    NSApp.servicesMenu = services
                }
            default: break
            }
        }
    }

    private static func makeMainMenu(language: AppLanguage) -> NSMenu {
        let router = MenuActionRouter.shared
        let main = NSMenu(title: "Main")

        func command(
            _ role: MenuRole,
            action: Selector?,
            key: String = "",
            modifiers: NSEvent.ModifierFlags = .command,
            target: AnyObject? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title(for: role, language: language), action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
            item.target = target
            remember(role, for: item)
            return item
        }

        func submenu(_ role: MenuRole, _ items: [NSMenuItem]) -> NSMenuItem {
            let title = title(for: role, language: language)
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            remember(role, for: item)
            return item
        }

        let servicesMenu = NSMenu(title: title(for: .services, language: language))
        let servicesItem = command(.services, action: nil)
        servicesItem.submenu = servicesMenu
        let app = submenu(.appMenu, [
            command(.about, action: #selector(MenuActionRouter.showAbout(_:)), target: router),
            command(.checkForUpdates, action: #selector(MenuActionRouter.checkForUpdates(_:)), target: router),
            command(.settings, action: #selector(MenuActionRouter.showSettings(_:)), key: ",", target: router),
            .separator(),
            servicesItem,
            .separator(),
            command(.hideApp, action: NSSelectorFromString("hide:"), key: "h"),
            command(.hideOthers, action: NSSelectorFromString("hideOtherApplications:"), key: "h", modifiers: [.command, .option]),
            command(.showAll, action: NSSelectorFromString("unhideAllApplications:")),
            .separator(),
            command(.quit, action: NSSelectorFromString("terminate:"), key: "q")
        ])

        let view = submenu(.viewMenu, [
            command(.toggleSidebar, action: #selector(MenuActionRouter.toggleSidebar(_:)), key: "s", modifiers: [.control, .command], target: router),
            command(.toggleToolbar, action: #selector(MenuActionRouter.toggleToolbar(_:)), target: router),
            command(.customizeToolbar, action: NSSelectorFromString("runToolbarCustomizationPalette:")),
            .separator(),
            command(.increaseReportText, action: #selector(MenuActionRouter.increaseReportText(_:)), key: "=", target: router),
            command(.decreaseReportText, action: #selector(MenuActionRouter.decreaseReportText(_:)), key: "-", target: router),
            command(.resetReportText, action: #selector(MenuActionRouter.resetReportText(_:)), key: "0", target: router),
            .separator(),
            command(.toggleFullScreen, action: #selector(MenuActionRouter.toggleFullScreen(_:)), key: "f", modifiers: [.control, .command], target: router)
        ])

        let report = submenu(.reportMenu, [
            command(.refresh, action: #selector(MenuActionRouter.refresh(_:)), key: "r", target: router),
            command(.copyReport, action: #selector(MenuActionRouter.copyReport(_:)), key: "c", modifiers: [.command, .shift], target: router)
        ])

        let file = submenu(.fileMenu, [
            command(.exportCurrentReport, action: #selector(MenuActionRouter.exportCurrentReport(_:)), key: "e", modifiers: [.command, .shift], target: router),
            command(.openReportFolder, action: #selector(MenuActionRouter.openReportFolder(_:)), target: router),
            .separator(),
            command(.closeWindow, action: NSSelectorFromString("performClose:"), key: "w")
        ])

        let window = submenu(.windowMenu, [
            command(.minimize, action: NSSelectorFromString("performMiniaturize:"), key: "m"),
            command(.zoom, action: NSSelectorFromString("performZoom:")),
            command(.toggleFullScreen, action: #selector(MenuActionRouter.toggleFullScreen(_:)), target: router),
            .separator(),
            command(.bringAllToFront, action: NSSelectorFromString("arrangeInFront:"))
        ])

        let help = submenu(.helpMenu, [
            command(.projectHome, action: #selector(MenuActionRouter.openProjectHome(_:)), target: router),
            command(.issueFeedback, action: #selector(MenuActionRouter.openIssueFeedback(_:)), target: router),
            command(.changelog, action: #selector(MenuActionRouter.showChangelog(_:)), target: router)
        ])

        [app, file, view, report, window, help].forEach(main.addItem)
        return main
    }

    private static func localize(_ menu: NSMenu, parent: MenuRole, language: AppLanguage) {
        for item in menu.items where !item.isSeparatorItem {
            let role = rememberedRole(for: item)
                ?? roleForKnownTitle(item.title, parent: parent)
                ?? roleForAction(item.action, parent: parent)

            if let role {
                remember(role, for: item)
                setTitle(title(for: role, language: language), on: item)
                if let submenu = item.submenu {
                    localize(submenu, parent: role, language: language)
                }
            } else if let submenu = item.submenu {
                // Dynamic document/window items stay untouched, but known
                // commands nested below an unfamiliar system container can
                // still be recognized by their selectors or prior titles.
                localize(submenu, parent: parent, language: language)
            }
        }
    }

    private static func topRole(for item: NSMenuItem, index: Int, itemCount: Int) -> MenuRole? {
        if let cached = rememberedRole(for: item), cached.isTopLevel { return cached }
        if let known = roleForKnownTitle(item.title, parent: nil), known.isTopLevel { return known }
        if index == 0 { return .appMenu }
        guard let submenu = item.submenu else { return nil }
        if NSApp.windowsMenu === submenu { return .windowMenu }
        if NSApp.helpMenu === submenu { return .helpMenu }

        let actions = recursiveActionNames(in: submenu)
        if actions.contains("cut:") && actions.contains("paste:") { return .editMenu }
        if actions.contains("toggleSidebar:") || actions.contains("toggleToolbarShown:") || actions.contains("toggleFullScreen:") {
            return .viewMenu
        }
        if actions.contains("performMiniaturize:") || actions.contains("performZoom:") { return .windowMenu }
        if actions.contains("showHelp:") { return .helpMenu }
        if submenu.items.contains(where: { $0.keyEquivalent.lowercased() == "r" }) &&
            submenu.items.contains(where: { $0.keyEquivalent.lowercased() == "c" }) {
            return .reportMenu
        }
        if index == itemCount - 1 { return .helpMenu }
        if index == itemCount - 2 { return .windowMenu }
        if index == 1 { return .fileMenu }
        return nil
    }

    private static func recursiveActionNames(in menu: NSMenu) -> Set<String> {
        var names = Set<String>()
        for item in menu.items {
            if let action = item.action { names.insert(NSStringFromSelector(action)) }
            if let submenu = item.submenu { names.formUnion(recursiveActionNames(in: submenu)) }
        }
        return names
    }

    private static func roleForAction(_ action: Selector?, parent: MenuRole) -> MenuRole? {
        guard let action else { return nil }
        switch NSStringFromSelector(action) {
        case "orderFrontStandardAboutPanel:": return .about
        case "showPreferencesWindow:", "showSettingsWindow:": return .settings
        case "hide:": return .hideApp
        case "hideOtherApplications:": return .hideOthers
        case "unhideAllApplications:": return .showAll
        case "terminate:": return .quit
        case "performClose:": return .closeWindow
        case "saveDocument:": return .save
        case "saveDocumentAs:", "saveDocumentTo:": return .saveAs
        case "revertDocumentToSaved:": return .revert
        case "runPageLayout:": return .pageSetup
        case "print:": return .print
        case "undo:": return .undo
        case "redo:": return .redo
        case "cut:": return .cut
        case "copy:": return parent == .reportMenu ? .copyReport : .copy
        case "paste:": return .paste
        case "pasteAsPlainText:", "pasteAndMatchStyle:": return .pasteMatchStyle
        case "delete:", "deleteBackward:": return .delete
        case "selectAll:": return .selectAll
        case "performFindPanelAction:": return roleForFindTag(parent: parent)
        case "checkSpelling:": return .checkDocumentNow
        case "showGuessPanel:": return .showSpelling
        case "toggleContinuousSpellChecking:": return .checkWhileTyping
        case "toggleGrammarChecking:": return .checkGrammar
        case "toggleAutomaticSpellingCorrection:": return .correctAutomatically
        case "orderFrontSubstitutionsPanel:": return .showSubstitutions
        case "toggleSmartInsertDelete:": return .smartCopyPaste
        case "toggleAutomaticQuoteSubstitution:": return .smartQuotes
        case "toggleAutomaticDashSubstitution:": return .smartDashes
        case "toggleAutomaticLinkDetection:": return .smartLinks
        case "toggleAutomaticDataDetection:": return .dataDetectors
        case "toggleAutomaticTextReplacement:": return .textReplacement
        case "uppercaseWord:": return .uppercase
        case "lowercaseWord:": return .lowercase
        case "capitalizeWord:": return .capitalize
        case "startSpeaking:": return .startSpeaking
        case "stopSpeaking:": return .stopSpeaking
        case "startDictation:": return .startDictation
        case "orderFrontCharacterPalette:": return .emojiSymbols
        case "toggleSidebar:": return .showSidebar
        case "toggleToolbarShown:": return .showToolbar
        case "runToolbarCustomizationPalette:": return .customizeToolbar
        case "toggleFullScreen:": return .enterFullScreen
        case "performMiniaturize:": return .minimize
        case "performZoom:": return .zoom
        case "arrangeInFront:": return .bringAllToFront
        case "showHelp:": return .appHelp
        case "exportCurrentReport:": return .exportCurrentReport
        case "openReportFolder:": return .openReportFolder
        case "increaseReportText:": return .increaseReportText
        case "decreaseReportText:": return .decreaseReportText
        case "resetReportText:": return .resetReportText
        case "openProjectHome:": return .projectHome
        case "openIssueFeedback:": return .issueFeedback
        case "showChangelog:": return .changelog
        case "checkForUpdates:": return .checkForUpdates
        default: return nil
        }
    }

    private static func roleForFindTag(parent: MenuRole) -> MenuRole {
        switch parent {
        case .findMenu: return .find
        default: return .find
        }
    }

    private static func roleForKnownTitle(_ value: String, parent: MenuRole?) -> MenuRole? {
        let normalized = normalize(value)
        let candidates = parent.map(MenuRole.children(of:)) ?? MenuRole.topLevel
        return candidates.first { role in
            aliases(for: role).contains { normalize($0) == normalized }
        }
    }

    private static func aliases(for role: MenuRole) -> [String] {
        var aliases = titleTable[role] ?? []
        if role == .appMenu {
            aliases.append(contentsOf: AppLanguage.allCases.map { L10n.text("appName", $0) })
        } else if role == .reportMenu {
            aliases.append(contentsOf: AppLanguage.allCases.map { L10n.text("report", $0) })
        } else if role == .refresh {
            aliases.append(contentsOf: AppLanguage.allCases.map { L10n.text("refresh", $0) })
        } else if role == .copyReport {
            aliases.append(contentsOf: AppLanguage.allCases.map { L10n.text("copyReport", $0) })
        } else if let key = role.localizationKey {
            aliases.append(contentsOf: AppLanguage.allCases.map { L10n.text(key, $0) })
        }
        return aliases
    }

    private static func normalize(_ title: String) -> String {
        title
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func remember(_ role: MenuRole, for item: NSMenuItem) {
        guard !role.isStateDependent else { return }
        roleCache.setObject(role.rawValue as NSString, forKey: item)
    }

    private static func rememberedRole(for item: NSMenuItem) -> MenuRole? {
        roleCache.object(forKey: item).flatMap { MenuRole(rawValue: $0 as String) }
    }

    private static func title(for role: MenuRole, language: AppLanguage) -> String {
        let effective = L10n.effective(language)
        let appName = L10n.text("appName", language)
        switch role {
        case .appMenu: return appName
        case .reportMenu: return L10n.text("report", language)
        case .refresh: return L10n.text("refresh", language)
        case .copyReport: return L10n.text("copyReport", language)
        case .exportCurrentReport: return L10n.text("exportCurrentReport", language)
        case .openReportFolder: return L10n.text("openReportFolder", language)
        case .increaseReportText: return L10n.text("increaseReportText", language)
        case .decreaseReportText: return L10n.text("decreaseReportText", language)
        case .resetReportText: return L10n.text("resetReportText", language)
        case .projectHome: return L10n.text("projectHome", language)
        case .issueFeedback: return L10n.text("menuFeedback", language)
        case .changelog: return L10n.text("viewChangelog", language)
        case .checkForUpdates: return L10n.text("checkForUpdates", language)
        case .about:
            switch effective {
            case .simplifiedChinese: return "关于“\(appName)”"
            case .russian: return "О программе «\(appName)»"
            case .french: return "À propos de \(appName)"
            case .german: return "Über \(appName)"
            case .korean: return "\(appName) 정보"
            case .japanese: return "\(appName) について"
            case .english, .system: return "About \(appName)"
            }
        case .hideApp:
            switch effective {
            case .simplifiedChinese: return "隐藏 \(appName)"
            case .russian: return "Скрыть \(appName)"
            case .french: return "Masquer \(appName)"
            case .german: return "\(appName) ausblenden"
            case .korean: return "\(appName) 가리기"
            case .japanese: return "\(appName) を隠す"
            case .english, .system: return "Hide \(appName)"
            }
        case .quit:
            switch effective {
            case .simplifiedChinese: return "退出 \(appName)"
            case .russian: return "Завершить \(appName)"
            case .french: return "Quitter \(appName)"
            case .german: return "\(appName) beenden"
            case .korean: return "\(appName) 종료"
            case .japanese: return "\(appName) を終了"
            case .english, .system: return "Quit \(appName)"
            }
        default:
            let values = titleTable[role] ?? [role.rawValue]
            return values[min(languageIndex(effective), values.count - 1)]
        }
    }

    private static func languageIndex(_ language: AppLanguage) -> Int {
        switch language {
        case .english, .system: return 0
        case .simplifiedChinese: return 1
        case .russian: return 2
        case .french: return 3
        case .german: return 4
        case .korean: return 5
        case .japanese: return 6
        }
    }

    private static func setTitle(_ title: String, on item: NSMenuItem) {
        if item.title != title { item.title = title }
        if let attributed = item.attributedTitle, attributed.string != title {
            let attributes = attributed.length > 0 ? attributed.attributes(at: 0, effectiveRange: nil) : [:]
            item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        }
        if let submenu = item.submenu, submenu.title != title { submenu.title = title }
    }

    // Values are ordered: English, Simplified Chinese, Russian, French,
    // German, Korean and Japanese. Only visible titles change; actions,
    // targets, tags, key equivalents, enabled state and submenus do not.
    private static let titleTable: [MenuRole: [String]] = [
        .fileMenu: ["File", "文件", "Файл", "Fichier", "Ablage", "파일", "ファイル"],
        .editMenu: ["Edit", "编辑", "Правка", "Édition", "Bearbeiten", "편집", "編集"],
        .viewMenu: ["View", "显示", "Вид", "Présentation", "Darstellung", "보기", "表示"],
        .windowMenu: ["Window", "窗口", "Окно", "Fenêtre", "Fenster", "윈도우", "ウインドウ"],
        .helpMenu: ["Help", "帮助", "Справка", "Aide", "Hilfe", "도움말", "ヘルプ"],
        .settings: ["Settings…", "设置…", "Настройки…", "Réglages…", "Einstellungen…", "설정…", "設定…"],
        .services: ["Services", "服务", "Службы", "Services", "Dienste", "서비스", "サービス"],
        .hideOthers: ["Hide Others", "隐藏其他", "Скрыть остальные", "Masquer les autres", "Andere ausblenden", "기타 가리기", "ほかを隠す"],
        .showAll: ["Show All", "全部显示", "Показать все", "Tout afficher", "Alle einblenden", "모두 보기", "すべてを表示"],
        .closeWindow: ["Close Window", "关闭窗口", "Закрыть окно", "Fermer la fenêtre", "Fenster schließen", "윈도우 닫기", "ウインドウを閉じる"],
        .save: ["Save", "存储", "Сохранить", "Enregistrer", "Sichern", "저장", "保存"],
        .saveAs: ["Save As…", "存储为…", "Сохранить как…", "Enregistrer sous…", "Sichern unter…", "다른 이름으로 저장…", "別名で保存…"],
        .revert: ["Revert To", "复原到", "Вернуть к версии", "Revenir à", "Zurücksetzen auf", "다음으로 복귀", "バージョンを戻す"],
        .pageSetup: ["Page Setup…", "页面设置…", "Параметры страницы…", "Format d’impression…", "Papierformat…", "페이지 설정…", "ページ設定…"],
        .print: ["Print…", "打印…", "Напечатать…", "Imprimer…", "Drucken…", "프린트…", "プリント…"],
        .undo: ["Undo", "撤销", "Отменить", "Annuler", "Widerrufen", "실행 취소", "取り消す"],
        .redo: ["Redo", "重做", "Повторить", "Rétablir", "Wiederholen", "다시 실행", "やり直す"],
        .cut: ["Cut", "剪切", "Вырезать", "Couper", "Ausschneiden", "오려두기", "カット"],
        .copy: ["Copy", "拷贝", "Копировать", "Copier", "Kopieren", "복사", "コピー"],
        .paste: ["Paste", "粘贴", "Вставить", "Coller", "Einsetzen", "붙여넣기", "ペースト"],
        .pasteMatchStyle: ["Paste and Match Style", "粘贴并匹配样式", "Вставить в текущем стиле", "Coller et adapter le style", "Einsetzen und Stil anpassen", "붙여넣고 스타일 일치시킴", "ペーストしてスタイルを合わせる"],
        .delete: ["Delete", "删除", "Удалить", "Supprimer", "Löschen", "삭제", "削除"],
        .selectAll: ["Select All", "全选", "Выбрать все", "Tout sélectionner", "Alles auswählen", "모두 선택", "すべてを選択"],
        .findMenu: ["Find", "查找", "Найти", "Rechercher", "Suchen", "찾기", "検索"],
        .find: ["Find…", "查找…", "Найти…", "Rechercher…", "Suchen…", "찾기…", "検索…"],
        .findNext: ["Find Next", "查找下一个", "Найти далее", "Rechercher le suivant", "Weitersuchen", "다음 찾기", "次を検索"],
        .findPrevious: ["Find Previous", "查找上一个", "Найти ранее", "Rechercher le précédent", "Vorheriges suchen", "이전 찾기", "前を検索"],
        .useSelectionForFind: ["Use Selection for Find", "使用所选内容查找", "Использовать выделение для поиска", "Rechercher la sélection", "Auswahl für Suche verwenden", "선택 부분으로 찾기", "選択部分を検索に使用"],
        .jumpToSelection: ["Jump to Selection", "跳到所选内容", "Перейти к выделенному", "Aller à la sélection", "Zur Auswahl", "선택 부분으로 이동", "選択部分へジャンプ"],
        .spellingMenu: ["Spelling and Grammar", "拼写和语法", "Правописание", "Orthographe et grammaire", "Rechtschreibung und Grammatik", "맞춤법 및 문법", "スペルと文法"],
        .showSpelling: ["Show Spelling and Grammar", "显示拼写和语法", "Показать правописание", "Afficher l’orthographe et la grammaire", "Rechtschreibung und Grammatik einblenden", "맞춤법 및 문법 보기", "スペルと文法を表示"],
        .checkDocumentNow: ["Check Document Now", "现在检查文稿", "Проверить документ", "Vérifier le document", "Dokument jetzt prüfen", "지금 도큐멘트 검사", "書類を今すぐチェック"],
        .checkWhileTyping: ["Check Spelling While Typing", "键入时检查拼写", "Проверять правописание при вводе", "Vérifier l’orthographe lors de la frappe", "Rechtschreibung während der Eingabe prüfen", "입력하는 동안 맞춤법 검사", "入力中にスペルチェック"],
        .checkGrammar: ["Check Grammar With Spelling", "随拼写检查语法", "Проверять грамматику", "Vérifier la grammaire et l’orthographe", "Grammatik zusammen mit Rechtschreibung prüfen", "맞춤법 검사 시 문법 검사", "スペルと一緒に文法をチェック"],
        .correctAutomatically: ["Correct Spelling Automatically", "自动纠正拼写", "Исправлять правописание автоматически", "Corriger l’orthographe automatiquement", "Rechtschreibung automatisch korrigieren", "자동으로 맞춤법 수정", "スペルを自動的に修正"],
        .substitutionsMenu: ["Substitutions", "替换", "Замены", "Substitutions", "Ersetzungen", "대체", "自動置換"],
        .showSubstitutions: ["Show Substitutions", "显示替换", "Показать замены", "Afficher les substitutions", "Ersetzungen einblenden", "대체 보기", "自動置換を表示"],
        .smartCopyPaste: ["Smart Copy/Paste", "智能拷贝/粘贴", "Смарт-копирование/вставка", "Copier-coller intelligent", "Intelligentes Kopieren/Einsetzen", "스마트 복사/붙여넣기", "スマートコピー/ペースト"],
        .smartQuotes: ["Smart Quotes", "智能引号", "Смарт-кавычки", "Guillemets intelligents", "Typografische Anführungszeichen", "스마트 인용", "スマート引用符"],
        .smartDashes: ["Smart Dashes", "智能破折号", "Смарт-тире", "Tirets intelligents", "Typografische Gedankenstriche", "스마트 대시", "スマートダッシュ"],
        .smartLinks: ["Smart Links", "智能链接", "Смарт-ссылки", "Liens intelligents", "Intelligente Links", "스마트 링크", "スマートリンク"],
        .dataDetectors: ["Data Detectors", "数据检测器", "Распознавание данных", "Détecteurs de données", "Datenerkennung", "데이터 감지기", "データ検出"],
        .textReplacement: ["Text Replacement", "文本替换", "Замена текста", "Remplacement de texte", "Textersetzung", "텍스트 대치", "テキスト置換"],
        .transformationsMenu: ["Transformations", "转换", "Преобразования", "Transformations", "Umwandlungen", "변환", "変換"],
        .uppercase: ["Make Upper Case", "设为大写", "Верхний регистр", "Mettre en majuscules", "Großbuchstaben", "대문자로", "大文字にする"],
        .lowercase: ["Make Lower Case", "设为小写", "Нижний регистр", "Mettre en minuscules", "Kleinbuchstaben", "소문자로", "小文字にする"],
        .capitalize: ["Capitalize", "首字母大写", "Начальные прописные", "Mettre une majuscule", "Wortanfänge groß", "단어를 대문자로 시작", "先頭を大文字にする"],
        .speechMenu: ["Speech", "语音", "Речь", "Parole", "Sprachausgabe", "말하기", "スピーチ"],
        .startSpeaking: ["Start Speaking", "开始朗读", "Начать озвучивание", "Commencer la lecture", "Sprachausgabe starten", "말하기 시작", "読み上げを開始"],
        .stopSpeaking: ["Stop Speaking", "停止朗读", "Остановить озвучивание", "Arrêter la lecture", "Sprachausgabe stoppen", "말하기 중단", "読み上げを停止"],
        .startDictation: ["Start Dictation…", "开始听写…", "Начать диктовку…", "Démarrer Dictée…", "Diktat starten…", "받아쓰기 시작…", "音声入力を開始…"],
        .emojiSymbols: ["Emoji & Symbols", "表情与符号", "Эмодзи и символы", "Emoji et symboles", "Emoji & Symbole", "이모티콘 및 기호", "絵文字と記号"],
        .showSidebar: ["Show Sidebar", "显示边栏", "Показать боковую панель", "Afficher la barre latérale", "Seitenleiste einblenden", "사이드바 보기", "サイドバーを表示"],
        .hideSidebar: ["Hide Sidebar", "隐藏边栏", "Скрыть боковую панель", "Masquer la barre latérale", "Seitenleiste ausblenden", "사이드바 가리기", "サイドバーを非表示"],
        .showToolbar: ["Show Toolbar", "显示工具栏", "Показать панель инструментов", "Afficher la barre d’outils", "Symbolleiste einblenden", "도구 막대 보기", "ツールバーを表示"],
        .hideToolbar: ["Hide Toolbar", "隐藏工具栏", "Скрыть панель инструментов", "Masquer la barre d’outils", "Symbolleiste ausblenden", "도구 막대 가리기", "ツールバーを非表示"],
        .toggleSidebar: ["Show/Hide Sidebar", "显示/隐藏边栏", "Показать/скрыть боковую панель", "Afficher/masquer la barre latérale", "Seitenleiste ein-/ausblenden", "사이드바 보기/가리기", "サイドバーの表示/非表示"],
        .toggleToolbar: ["Show/Hide Toolbar", "显示/隐藏工具栏", "Показать/скрыть панель инструментов", "Afficher/masquer la barre d’outils", "Symbolleiste ein-/ausblenden", "도구 막대 보기/가리기", "ツールバーの表示/非表示"],
        .customizeToolbar: ["Customize Toolbar…", "自定工具栏…", "Настроить панель инструментов…", "Personnaliser la barre d’outils…", "Symbolleiste anpassen…", "도구 막대 사용자화…", "ツールバーをカスタマイズ…"],
        .enterFullScreen: ["Enter Full Screen", "进入全屏幕", "Перейти в полноэкранный режим", "Activer le mode plein écran", "Vollbildmodus aktivieren", "전체 화면 시작", "フルスクリーンにする"],
        .exitFullScreen: ["Exit Full Screen", "退出全屏幕", "Выйти из полноэкранного режима", "Quitter le mode plein écran", "Vollbildmodus beenden", "전체 화면 종료", "フルスクリーンを解除"],
        .toggleFullScreen: ["Enter/Exit Full Screen", "进入/退出全屏幕", "Включить/выключить полноэкранный режим", "Activer/quitter le plein écran", "Vollbild ein-/ausschalten", "전체 화면 시작/종료", "フルスクリーンの開始/解除"],
        .minimize: ["Minimize", "最小化", "Свернуть", "Placer dans le Dock", "Im Dock ablegen", "최소화", "しまう"],
        .zoom: ["Zoom", "缩放", "Масштабировать", "Réduire/agrandir", "Zoomen", "확대/축소", "拡大/縮小"],
        .fill: ["Fill", "填充", "Заполнить", "Remplir", "Füllen", "채우기", "画面に合わせる"],
        .center: ["Center", "居中", "По центру", "Centrer", "Zentrieren", "가운데로", "中央に配置"],
        .moveResize: ["Move & Resize", "移动与调整大小", "Перемещение и изменение размера", "Déplacer et redimensionner", "Bewegen & Größe ändern", "이동 및 크기 조절", "移動とサイズ変更"],
        .fullScreenTile: ["Full Screen Tile", "全屏幕平铺", "Полноэкранная мозаика", "Mosaïque plein écran", "Vollbild-Kacheln", "전체 화면 타일", "フルスクリーンタイル"],
        .removeWindowSet: ["Remove Window from Set", "从窗口组中移除窗口", "Удалить окно из набора", "Retirer la fenêtre du groupe", "Fenster aus Gruppe entfernen", "윈도우를 세트에서 제거", "ウインドウをセットから削除"],
        .bringAllToFront: ["Bring All to Front", "前置全部窗口", "Все окна — на передний план", "Tout ramener au premier plan", "Alle nach vorne bringen", "모두 앞으로 가져오기", "すべてを手前に移動"],
        .left: ["Left", "左侧", "Слева", "Gauche", "Links", "왼쪽", "左"],
        .right: ["Right", "右侧", "Справа", "Droite", "Rechts", "오른쪽", "右"],
        .top: ["Top", "顶部", "Сверху", "Haut", "Oben", "상단", "上"],
        .bottom: ["Bottom", "底部", "Снизу", "Bas", "Unten", "하단", "下"],
        .topLeft: ["Top Left", "左上方", "Сверху слева", "En haut à gauche", "Oben links", "왼쪽 상단", "左上"],
        .topRight: ["Top Right", "右上方", "Сверху справа", "En haut à droite", "Oben rechts", "오른쪽 상단", "右上"],
        .bottomLeft: ["Bottom Left", "左下方", "Снизу слева", "En bas à gauche", "Unten links", "왼쪽 하단", "左下"],
        .bottomRight: ["Bottom Right", "右下方", "Снизу справа", "En bas à droite", "Unten rechts", "오른쪽 하단", "右下"],
        .returnPreviousSize: ["Return to Previous Size", "恢复到上次大小", "Вернуть предыдущий размер", "Revenir à la taille précédente", "Vorherige Größe wiederherstellen", "이전 크기로 돌아가기", "以前のサイズに戻す"],
        .leftOfScreen: ["Left of Screen", "屏幕左侧", "Левая часть экрана", "À gauche de l’écran", "Linke Bildschirmhälfte", "화면 왼쪽", "画面の左側"],
        .rightOfScreen: ["Right of Screen", "屏幕右侧", "Правая часть экрана", "À droite de l’écran", "Rechte Bildschirmhälfte", "화면 오른쪽", "画面の右側"],
        .appHelp: ["Drive & Battery Health Viewer Help", "硬盘与电池健康查看器帮助", "Справка по приложению", "Aide de l’app", "Hilfe zur App", "앱 도움말", "アプリのヘルプ"]
    ]
}

@MainActor
private final class MenuActionRouter: NSObject, NSMenuItemValidation {
    static let shared = MenuActionRouter()
    weak var model: AppModel?

    @objc func showAbout(_ sender: Any?) {
        model?.destination = .about
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings(_ sender: Any?) {
        model?.destination = .settings
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refresh(_ sender: Any?) { model?.refresh() }
    @objc func copyReport(_ sender: Any?) { model?.copyCurrentReport() }
    @objc func exportCurrentReport(_ sender: Any?) { model?.presentExportCurrentReportPanel() }
    @objc func openReportFolder(_ sender: Any?) { model?.openReportFolder() }
    @objc func increaseReportText(_ sender: Any?) { model?.increaseReportTextSize() }
    @objc func decreaseReportText(_ sender: Any?) { model?.decreaseReportTextSize() }
    @objc func resetReportText(_ sender: Any?) { model?.resetReportTextSize() }
    @objc func checkForUpdates(_ sender: Any?) { model?.checkForUpdates() }

    @objc func toggleSidebar(_ sender: Any?) {
        NSApp.sendAction(NSSelectorFromString("toggleSidebar:"), to: nil, from: sender)
    }

    @objc func performResponderAction(_ sender: NSMenuItem) {
        guard let selectorName = sender.representedObject as? String else { return }
        NSApp.sendAction(NSSelectorFromString(selectorName), to: nil, from: sender)
    }

    @objc func toggleToolbar(_ sender: Any?) {
        NSApp.sendAction(NSSelectorFromString("toggleToolbarShown:"), to: nil, from: sender)
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        NSApp.sendAction(NSSelectorFromString("toggleFullScreen:"), to: nil, from: sender)
    }

    @objc func openProjectHome(_ sender: Any?) {
        if let url = URL(string: "https://github.com/xincheng1237/drive-battery-health-viewer") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openIssueFeedback(_ sender: Any?) {
        if let url = URL(string: "https://github.com/xincheng1237/drive-battery-health-viewer/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showChangelog(_ sender: Any?) {
        guard let model else { return }
        model.destination = .about
        DispatchQueue.main.async {
            model.showsChangelog = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performResponderAction(_:)),
           let selectorName = menuItem.representedObject as? String {
            return NSApp.target(
                forAction: NSSelectorFromString(selectorName),
                to: nil,
                from: menuItem
            ) != nil
        }
        switch menuItem.action {
        case #selector(refresh(_:)): return model?.isScanning == false
        case #selector(copyReport(_:)): return model?.currentSnapshot != nil
        case #selector(exportCurrentReport(_:)): return model?.currentSnapshot != nil
        case #selector(increaseReportText(_:)): return (model?.reportTextSize ?? 22) < 22
        case #selector(decreaseReportText(_:)): return (model?.reportTextSize ?? 11) > 11
        case #selector(checkForUpdates(_:)): return model?.isCheckingForUpdates == false
        default: return true
        }
    }
}

private enum MenuRole: String {
    case appMenu, fileMenu, editMenu, viewMenu, reportMenu, windowMenu, helpMenu
    case about, checkForUpdates, settings, services, hideApp, hideOthers, showAll, quit
    case closeWindow, save, saveAs, revert, pageSetup, print, exportCurrentReport, openReportFolder
    case undo, redo, cut, copy, paste, pasteMatchStyle, delete, selectAll
    case findMenu, find, findNext, findPrevious, useSelectionForFind, jumpToSelection
    case spellingMenu, showSpelling, checkDocumentNow, checkWhileTyping, checkGrammar, correctAutomatically
    case substitutionsMenu, showSubstitutions, smartCopyPaste, smartQuotes, smartDashes, smartLinks, dataDetectors, textReplacement
    case transformationsMenu, uppercase, lowercase, capitalize
    case speechMenu, startSpeaking, stopSpeaking, startDictation, emojiSymbols
    case showSidebar, hideSidebar, toggleSidebar, showToolbar, hideToolbar, toggleToolbar, customizeToolbar
    case enterFullScreen, exitFullScreen, toggleFullScreen, increaseReportText, decreaseReportText, resetReportText
    case refresh, copyReport
    case minimize, zoom, fill, center, moveResize, fullScreenTile, removeWindowSet, bringAllToFront
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight, returnPreviousSize, leftOfScreen, rightOfScreen
    case appHelp, projectHome, issueFeedback, changelog

    var isTopLevel: Bool { Self.topLevel.contains(self) }
    var isStateDependent: Bool {
        switch self {
        case .showSidebar, .hideSidebar, .showToolbar, .hideToolbar, .enterFullScreen, .exitFullScreen:
            return true
        default:
            return false
        }
    }

    static let topLevel: [MenuRole] = [.appMenu, .fileMenu, .viewMenu, .reportMenu, .windowMenu, .helpMenu]

    var localizationKey: String? {
        switch self {
        case .exportCurrentReport: return "exportCurrentReport"
        case .openReportFolder: return "openReportFolder"
        case .increaseReportText: return "increaseReportText"
        case .decreaseReportText: return "decreaseReportText"
        case .resetReportText: return "resetReportText"
        case .projectHome: return "projectHome"
        case .issueFeedback: return "menuFeedback"
        case .changelog: return "viewChangelog"
        case .checkForUpdates: return "checkForUpdates"
        default: return nil
        }
    }

    static func children(of parent: MenuRole) -> [MenuRole] {
        switch parent {
        case .appMenu:
            return [.about, .checkForUpdates, .settings, .services, .hideApp, .hideOthers, .showAll, .quit]
        case .fileMenu:
            return [.exportCurrentReport, .openReportFolder, .closeWindow, .save, .saveAs, .revert, .pageSetup, .print]
        case .editMenu:
            return [.undo, .redo, .cut, .copy, .paste, .pasteMatchStyle, .delete, .selectAll, .findMenu, .spellingMenu, .substitutionsMenu, .transformationsMenu, .speechMenu, .startDictation, .emojiSymbols]
        case .findMenu:
            return [.find, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection]
        case .spellingMenu:
            return [.showSpelling, .checkDocumentNow, .checkWhileTyping, .checkGrammar, .correctAutomatically]
        case .substitutionsMenu:
            return [.showSubstitutions, .smartCopyPaste, .smartQuotes, .smartDashes, .smartLinks, .dataDetectors, .textReplacement]
        case .transformationsMenu:
            return [.uppercase, .lowercase, .capitalize]
        case .speechMenu:
            return [.startSpeaking, .stopSpeaking]
        case .viewMenu:
            return [.showSidebar, .hideSidebar, .toggleSidebar, .showToolbar, .hideToolbar, .toggleToolbar, .customizeToolbar, .increaseReportText, .decreaseReportText, .resetReportText, .enterFullScreen, .exitFullScreen, .toggleFullScreen]
        case .reportMenu:
            return [.refresh, .copyReport]
        case .windowMenu:
            return [.minimize, .zoom, .fill, .center, .moveResize, .fullScreenTile, .removeWindowSet, .bringAllToFront]
        case .moveResize:
            return [.left, .right, .top, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight, .returnPreviousSize]
        case .fullScreenTile:
            return [.leftOfScreen, .rightOfScreen, .top, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight]
        case .helpMenu:
            return [.projectHome, .issueFeedback, .changelog]
        default:
            return []
        }
    }
}
