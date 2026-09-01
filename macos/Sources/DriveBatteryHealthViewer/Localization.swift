import Foundation

enum L10n {
    static func languageName(_ language: AppLanguage, in displayLanguage: AppLanguage) -> String {
        if language == .system { return text("systemLanguage", displayLanguage) }
        let locale = Locale(identifier: effective(displayLanguage).rawValue)
        return locale.localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
    }

    static func text(_ key: String, _ selected: AppLanguage) -> String {
        let language = effective(selected)
        let selectedValues: [String?] = [
            safetyCopyTables[language]?[key], tables[language]?[key], historyActionTables[language]?[key],
            menuActionTables[language]?[key], updatePromptTables[language]?[key], featureTables[language]?[key]
        ]
        if let match = selectedValues.compactMap({ $0 }).first { return match }
        let fallbackValues: [String?] = [
            safetyCopyTables[.english]?[key], tables[.english]?[key], historyActionTables[.english]?[key],
            menuActionTables[.english]?[key], updatePromptTables[.english]?[key], featureTables[.english]?[key]
        ]
        return fallbackValues.compactMap({ $0 }).first ?? key
    }

    static func format(_ key: String, _ selected: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, selected), locale: Locale(identifier: effective(selected).rawValue), arguments: arguments)
    }

    static func effective(_ language: AppLanguage) -> AppLanguage {
        language == .system ? .detected() : language
    }

    static func missingTranslationKeys(for language: AppLanguage) -> [String] {
        let selected = effective(language)
        var referenceKeys = tables[.english]?.keys.map { $0 } ?? []
        referenceKeys.append(contentsOf: historyActionTables[.english]?.keys.map { $0 } ?? [])
        referenceKeys.append(contentsOf: menuActionTables[.english]?.keys.map { $0 } ?? [])
        referenceKeys.append(contentsOf: updatePromptTables[.english]?.keys.map { $0 } ?? [])
        referenceKeys.append(contentsOf: featureTables[.english]?.keys.map { $0 } ?? [])
        referenceKeys.append(contentsOf: safetyCopyTables[.english]?.keys.map { $0 } ?? [])
        let reference = Set(referenceKeys)
        let tableKeys = tables[selected]?.keys.map { $0 } ?? [String]()
        let actionKeys = historyActionTables[selected]?.keys.map { $0 } ?? [String]()
        let menuKeys = menuActionTables[selected]?.keys.map { $0 } ?? [String]()
        let updatePromptKeys = updatePromptTables[selected]?.keys.map { $0 } ?? [String]()
        let featureKeys = featureTables[selected]?.keys.map { $0 } ?? [String]()
        let safetyKeys = safetyCopyTables[selected]?.keys.map { $0 } ?? [String]()
        let translated = Set(tableKeys + actionKeys + menuKeys + updatePromptKeys + featureKeys + safetyKeys)
        return reference.subtracting(translated).sorted()
    }

    private static let tables: [AppLanguage: [String: String]] = [
        .english: [
            "appName": "Drive & Battery Health Viewer", "systemLanguage": "System Language",
            "overview": "Overview", "history": "History", "settings": "Settings", "about": "About",
            "menuFile": "File", "menuEdit": "Edit", "menuView": "View", "menuWindow": "Window", "menuHelp": "Help",
            "refresh": "Refresh", "refreshing": "Scanning…", "exportReport": "Export Report", "copyReport": "Copy Report",
            "lastUpdated": "Updated %@", "noScan": "No health report yet", "noScanDetail": "Refresh to read this Mac’s drive and battery information.",
            "drives": "Drives", "batteries": "Battery", "noDrives": "No physical drives were reported.", "noBattery": "No battery is installed on this Mac.",
            "health": "Health", "good": "Good", "warning": "Attention", "critical": "Critical", "unknown": "Unavailable",
            "model": "Model", "capacity": "Capacity", "protocol": "Connection", "firmware": "Firmware", "serialNumber": "Serial number",
            "smartStatus": "S.M.A.R.T. status", "lifeRemaining": "Estimated life remaining", "temperature": "Temperature",
            "powerOnHours": "Operating time", "powerCycles": "Power cycles", "totalRead": "Total read", "totalWritten": "Total written",
            "unsafeShutdowns": "Unsafe shutdowns", "mediaErrors": "Media errors", "errorLogEntries": "Error log entries", "internal": "Internal", "solidState": "Solid state",
            "manufacturer": "Manufacturer", "chemistry": "Chemistry", "designCapacity": "Design capacity", "fullChargeCapacity": "Full-charge capacity",
            "currentCharge": "Current charge", "cycleCount": "Cycle count", "batteryVoltage": "Battery voltage", "charging": "Charging", "connected": "Power connected",
            "yes": "Yes", "no": "No", "unavailable": "Not reported", "hours": "%llu hours", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "Health Report", "generated": "Generated", "computer": "Computer", "systemNotes": "System notes",
            "privacyNotice": "Serial numbers are hidden in the interface, copied text, history, and exported reports while this setting is enabled.",
            "systemLimitations": "macOS does not expose every NVMe/USB S.M.A.R.T. counter to ordinary apps. Unavailable values are left blank instead of estimated.",
            "overviewLimitations": "The app shows all information provided by macOS and the device. Temperature, operating time, and lifetime read/write totals may be unavailable on some drives or connections.",
            "driveWorkingTimeExplanation": "This value is reported by the drive firmware and may exclude time when the controller is in a low-power state. It does not equal the computer’s power-on or actual usage time.",
            "batteryHealthExplanation": "Battery health follows macOS’s calibrated maximum capacity. Temperature, charge management, system calibration, and rounding may cause a slight difference from the direct “full-charge capacity ÷ design capacity” calculation.",
            "powerConnectedNotCharging": "Power is connected. The battery is full, or macOS is temporarily powering the Mac directly.",
            "internalBattery": "Internal lithium-ion battery",
            "historyEmpty": "No saved reports", "historyEmptyDetail": "Reports can be saved after every refresh or only when exported.",
            "sourceRefresh": "Saved after refresh", "sourceExport": "Saved on export", "delete": "Delete", "deleteConfirm": "Delete this history report?",
            "deleteDetail": "The saved report will be removed from this Mac. An exported text file is not deleted.", "showInFinder": "Show in Finder",
            "chooseFolder": "Choose…", "openFolder": "Open Folder", "historyLocation": "History location", "saveMode": "Save reports",
            "saveOnRefresh": "After every refresh", "saveOnExport": "Only when exporting", "language": "Language", "hideSerials": "Hide serial numbers",
            "reportTextSize": "Report text size", "appearance": "Appearance & Privacy", "storage": "History Storage", "dataAccess": "Hardware Data Access",
            "aboutSummary": "A lightweight, read-only utility for checking drive status and battery health, saving reports, and following changes over time.",
            "developer": "Developer", "author": "ChengXin", "projectHome": "Project Homepage", "issueFeedback": "Issues & Feedback",
            "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ Group · 1040456137", "email": "Email · 2680149724@qq.com",
            "copyright": "© 2026 ChengXin. All rights reserved.", "version": "Version %@", "changelog": "What’s New", "license": "GNU GPL v3 License",
            "readOnlyNote": "This app only reads information. It does not benchmark, write, repair, erase, or update firmware.",
            "permissionNote": "Some external drives and vendor-specific counters may be unavailable because of macOS, the controller, or the USB enclosure.",
            "scanFailed": "The scan could not be completed: %@", "copied": "Report copied", "exported": "Report exported", "done": "Done", "cancel": "Cancel"
        ],
        .simplifiedChinese: [
            "appName": "硬盘与电池健康查看器", "systemLanguage": "跟随系统",
            "overview": "概览", "history": "历史记录", "settings": "设置", "about": "关于",
            "menuFile": "文件", "menuEdit": "编辑", "menuView": "显示", "menuWindow": "窗口", "menuHelp": "帮助",
            "refresh": "刷新", "refreshing": "正在检测…", "exportReport": "导出报告", "copyReport": "复制报告",
            "lastUpdated": "更新于 %@", "noScan": "还没有健康报告", "noScanDetail": "点击刷新，读取这台 Mac 的硬盘和电池信息。",
            "drives": "硬盘", "batteries": "电池", "noDrives": "系统未报告物理硬盘。", "noBattery": "这台 Mac 没有安装电池。",
            "health": "健康度", "good": "良好", "warning": "需要注意", "critical": "严重", "unknown": "不可用",
            "model": "型号", "capacity": "容量", "protocol": "连接方式", "firmware": "固件", "serialNumber": "序列号",
            "smartStatus": "S.M.A.R.T. 状态", "lifeRemaining": "预计剩余寿命", "temperature": "温度",
            "powerOnHours": "工作时间", "powerCycles": "通电次数", "totalRead": "总读取量", "totalWritten": "总写入量",
            "unsafeShutdowns": "非正常关机次数", "mediaErrors": "介质错误", "errorLogEntries": "错误日志条目", "internal": "内置设备", "solidState": "固态硬盘",
            "manufacturer": "制造商", "chemistry": "电池类型", "designCapacity": "设计容量", "fullChargeCapacity": "当前满充容量",
            "currentCharge": "当前电量", "cycleCount": "循环次数", "batteryVoltage": "电池电压", "charging": "正在充电", "connected": "已连接电源",
            "yes": "是", "no": "否", "unavailable": "系统未报告", "hours": "%llu 小时", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "健康检测报告", "generated": "生成时间", "computer": "电脑名称", "systemNotes": "系统说明",
            "privacyNotice": "启用后，界面、复制内容、历史记录和导出报告中的硬盘与电池序列号都会被隐藏。",
            "systemLimitations": "macOS 不会向普通应用开放所有 NVMe/USB S.M.A.R.T. 数据；无法读取的项目会明确留空，不会估算。",
            "overviewLimitations": "这里已显示 macOS 和设备能够提供的信息；部分硬盘的温度、工作时间或累计读写量可能因硬件与连接方式不同而无法读取。",
            "driveWorkingTimeExplanation": "硬盘工作时间由硬盘固件统计，可能不包含控制器处于低功耗状态的时间，不等同于电脑开机或实际使用时长。",
            "batteryHealthExplanation": "电池健康度以 macOS 校准后的最大容量为准，受温度、充电管理、系统校准和取整影响，它与“满充容量÷设计容量”的直接计算结果可能存在细微差异。",
            "powerConnectedNotCharging": "已连接电源；当前电池已充满，或 macOS 根据当前状态暂时采用直接供电。",
            "internalBattery": "内置锂离子电池",
            "historyEmpty": "还没有历史报告", "historyEmptyDetail": "可以设置为每次刷新后保存，或只在导出报告时保存。",
            "sourceRefresh": "刷新后自动保存", "sourceExport": "导出时保存", "delete": "删除", "deleteConfirm": "删除这条历史报告？",
            "deleteDetail": "将从这台 Mac 删除保存的记录，但不会删除已经导出的文本文件。", "showInFinder": "在访达中显示",
            "chooseFolder": "选择…", "openFolder": "打开文件夹", "historyLocation": "历史记录位置", "saveMode": "保存报告",
            "saveOnRefresh": "每次刷新后", "saveOnExport": "仅导出报告时", "language": "语言", "hideSerials": "隐藏序列号",
            "reportTextSize": "报告文字大小", "appearance": "外观与隐私", "storage": "历史记录存储", "dataAccess": "硬件数据读取",
            "aboutSummary": "一款只读查看硬盘状态与电池健康情况的轻量级工具，支持保存检测报告并了解健康状态随时间的变化。",
            "developer": "开发者", "author": "程心", "projectHome": "项目主页", "issueFeedback": "问题反馈",
            "coolapk": "酷安 · 程心ChengXin", "qq": "QQ 交流群 · 1040456137", "email": "联系邮箱 · 2680149724@qq.com",
            "copyright": "© 2026 程心，保留所有权利。", "version": "版本 %@", "changelog": "更新日志", "license": "GNU GPL v3 许可证",
            "readOnlyNote": "本应用只读取信息，不会测速、写入、修复、擦除或更新固件。",
            "permissionNote": "部分外接硬盘及厂商专用数据可能受 macOS、控制器或 USB 硬盘盒限制而无法读取。",
            "scanFailed": "无法完成检测：%@", "copied": "报告已复制", "exported": "报告已导出", "done": "完成", "cancel": "取消"
        ],
        .russian: [
            "overviewLimitations": "Приложение показывает все данные, доступные macOS и устройству. Температура, время работы и общий объём чтения/записи могут быть недоступны для некоторых дисков или подключений.", "driveWorkingTimeExplanation": "Этот показатель рассчитывается прошивкой накопителя и может не учитывать время, когда контроллер находится в режиме пониженного энергопотребления. Он не равен времени включения или фактического использования компьютера.", "batteryHealthExplanation": "Состояние батареи основано на откалиброванной macOS максимальной ёмкости. Температура, управление зарядом, калибровка и округление могут давать небольшое отличие от простого расчёта полной ёмкости к проектной.", "powerConnectedNotCharging": "Питание подключено. Батарея заряжена или macOS временно питает Mac напрямую.", "internalBattery": "Встроенная литий-ионная батарея",
            "appName": "Состояние накопителей и батареи", "systemLanguage": "Язык системы", "overview": "Обзор", "history": "История", "settings": "Настройки", "about": "О программе", "menuFile": "Файл", "menuEdit": "Правка", "menuView": "Вид", "menuWindow": "Окно", "menuHelp": "Справка",
            "refresh": "Обновить", "refreshing": "Сканирование…", "exportReport": "Экспорт отчёта", "copyReport": "Копировать отчёт", "lastUpdated": "Обновлено %@",
            "noScan": "Отчёта пока нет", "noScanDetail": "Обновите данные накопителей и батареи этого Mac.", "drives": "Накопители", "batteries": "Батарея", "noDrives": "Физические накопители не обнаружены.", "noBattery": "В этом Mac нет батареи.",
            "health": "Состояние", "good": "Хорошо", "warning": "Внимание", "critical": "Критично", "unknown": "Недоступно", "model": "Модель", "capacity": "Ёмкость", "protocol": "Подключение", "firmware": "Прошивка", "serialNumber": "Серийный номер", "smartStatus": "Статус S.M.A.R.T.", "lifeRemaining": "Оценка остаточного ресурса", "temperature": "Температура", "powerOnHours": "Время работы", "powerCycles": "Циклы питания", "totalRead": "Всего прочитано", "totalWritten": "Всего записано", "unsafeShutdowns": "Небезопасные выключения", "mediaErrors": "Ошибки носителя", "errorLogEntries": "Записи журнала ошибок", "internal": "Внутренний", "solidState": "SSD",
            "manufacturer": "Производитель", "chemistry": "Тип батареи", "designCapacity": "Проектная ёмкость", "fullChargeCapacity": "Полная ёмкость", "currentCharge": "Текущий заряд", "cycleCount": "Число циклов", "batteryVoltage": "Напряжение батареи", "charging": "Заряжается", "connected": "Питание подключено", "yes": "Да", "no": "Нет", "unavailable": "Нет данных", "hours": "%llu ч", "mAh": "%d мА·ч", "percent": "%.0f%%",
            "report": "Отчёт о состоянии", "generated": "Создан", "computer": "Компьютер", "systemNotes": "Примечания системы", "privacyNotice": "При включении серийные номера скрываются в интерфейсе, истории и экспортируемых отчётах.", "systemLimitations": "macOS не предоставляет обычным приложениям все счётчики NVMe/USB S.M.A.R.T.; недоступные значения не оцениваются.",
            "historyEmpty": "Нет сохранённых отчётов", "historyEmptyDetail": "Отчёты можно сохранять после обновления или только при экспорте.", "select": "Выбрать", "selectAll": "Выбрать все", "deselectAll": "Снять выбор", "exportSelected": "Экспортировать выбранные", "deleteSelected": "Удалить выбранные", "deleteSelectedConfirm": "Удалить выбранные отчёты?", "deleteSelectedDetail": "Выбранные отчёты будут удалены с этого Mac.", "batchExported": "Выбранные отчёты экспортированы", "sourceRefresh": "Сохранено после обновления", "sourceExport": "Сохранено при экспорте", "delete": "Удалить", "deleteConfirm": "Удалить этот отчёт?", "deleteDetail": "Сохранённая запись будет удалена; экспортированный файл останется.", "showInFinder": "Показать в Finder", "chooseFolder": "Выбрать…", "openFolder": "Открыть папку", "historyLocation": "Папка истории", "saveMode": "Сохранение отчётов", "saveOnRefresh": "После каждого обновления", "saveOnExport": "Только при экспорте", "language": "Язык", "hideSerials": "Скрывать серийные номера", "reportTextSize": "Размер текста отчёта", "appearance": "Вид и конфиденциальность", "storage": "Хранилище истории", "dataAccess": "Доступ к данным оборудования",
            "aboutSummary": "Лёгкая утилита только для чтения: состояние накопителей и батареи, история отчётов и изменения со временем.", "developer": "Разработчик", "author": "ChengXin", "projectHome": "Страница проекта", "issueFeedback": "Ошибки и предложения", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ-группа · 1040456137", "email": "Email · 2680149724@qq.com", "copyright": "© 2026 ChengXin. Все права защищены.", "version": "Версия %@", "changelog": "Журнал изменений", "license": "Лицензия GNU GPL v3", "readOnlyNote": "Приложение только читает данные и не выполняет тесты, запись, ремонт, стирание или обновление прошивки.", "permissionNote": "Некоторые внешние накопители и фирменные счётчики могут быть недоступны из-за macOS, контроллера или USB-корпуса.", "scanFailed": "Не удалось завершить сканирование: %@", "copied": "Отчёт скопирован", "exported": "Отчёт экспортирован", "done": "Готово", "cancel": "Отмена"
        ],
        .french: [
            "overviewLimitations": "L’app affiche toutes les informations fournies par macOS et l’appareil. La température, le temps de fonctionnement et les volumes lus/écrits peuvent manquer selon le disque ou la connexion.", "driveWorkingTimeExplanation": "Cette valeur est comptabilisée par le micrologiciel du disque et peut exclure les périodes où le contrôleur est en mode basse consommation. Elle ne correspond pas à la durée de mise sous tension ou d’utilisation réelle de l’ordinateur.", "batteryHealthExplanation": "La santé de la batterie utilise la capacité maximale étalonnée par macOS. Température, gestion de la charge, étalonnage et arrondi peuvent créer un léger écart avec le simple calcul capacité pleine ÷ capacité nominale.", "powerConnectedNotCharging": "L’alimentation est connectée. La batterie est pleine ou macOS alimente temporairement le Mac directement.", "internalBattery": "Batterie lithium-ion interne",
            "appName": "État des disques et de la batterie", "systemLanguage": "Langue du système", "overview": "Aperçu", "history": "Historique", "settings": "Réglages", "about": "À propos", "menuFile": "Fichier", "menuEdit": "Édition", "menuView": "Présentation", "menuWindow": "Fenêtre", "menuHelp": "Aide", "refresh": "Actualiser", "refreshing": "Analyse…", "exportReport": "Exporter le rapport", "copyReport": "Copier le rapport", "lastUpdated": "Mis à jour %@", "noScan": "Aucun rapport", "noScanDetail": "Actualisez pour lire les informations de ce Mac.", "drives": "Disques", "batteries": "Batterie", "noDrives": "Aucun disque physique signalé.", "noBattery": "Ce Mac ne possède pas de batterie.",
            "health": "Santé", "good": "Bon", "warning": "Attention", "critical": "Critique", "unknown": "Indisponible", "model": "Modèle", "capacity": "Capacité", "protocol": "Connexion", "firmware": "Micrologiciel", "serialNumber": "Numéro de série", "smartStatus": "État S.M.A.R.T.", "lifeRemaining": "Durée de vie restante estimée", "temperature": "Température", "powerOnHours": "Temps de fonctionnement", "powerCycles": "Cycles d’alimentation", "totalRead": "Total lu", "totalWritten": "Total écrit", "unsafeShutdowns": "Arrêts non sécurisés", "mediaErrors": "Erreurs du support", "errorLogEntries": "Entrées du journal d’erreurs", "internal": "Interne", "solidState": "SSD", "manufacturer": "Fabricant", "chemistry": "Type de batterie", "designCapacity": "Capacité nominale", "fullChargeCapacity": "Capacité à pleine charge", "currentCharge": "Charge actuelle", "cycleCount": "Nombre de cycles", "batteryVoltage": "Tension de la batterie", "charging": "En charge", "connected": "Alimentation connectée", "yes": "Oui", "no": "Non", "unavailable": "Non indiqué", "hours": "%llu heures", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "Rapport de santé", "generated": "Généré", "computer": "Ordinateur", "systemNotes": "Notes système", "privacyNotice": "Si activé, les numéros de série sont masqués dans l’interface, l’historique et les exports.", "systemLimitations": "macOS n’expose pas tous les compteurs S.M.A.R.T. NVMe/USB ; les valeurs indisponibles ne sont pas estimées.", "historyEmpty": "Aucun rapport enregistré", "historyEmptyDetail": "Enregistrez après chaque actualisation ou uniquement lors de l’export.", "sourceRefresh": "Enregistré après actualisation", "sourceExport": "Enregistré lors de l’export", "delete": "Supprimer", "deleteConfirm": "Supprimer ce rapport ?", "deleteDetail": "Le rapport enregistré sera supprimé, mais pas le fichier texte exporté.", "showInFinder": "Afficher dans le Finder", "chooseFolder": "Choisir…", "openFolder": "Ouvrir le dossier", "historyLocation": "Dossier de l’historique", "saveMode": "Enregistrer les rapports", "saveOnRefresh": "Après chaque actualisation", "saveOnExport": "Uniquement lors de l’export", "language": "Langue", "hideSerials": "Masquer les numéros de série", "reportTextSize": "Taille du rapport", "appearance": "Apparence et confidentialité", "storage": "Stockage de l’historique", "dataAccess": "Accès aux données matérielles", "aboutSummary": "Un utilitaire léger en lecture seule pour consulter l’état des disques et de la batterie et suivre leur évolution.", "developer": "Développeur", "author": "ChengXin", "projectHome": "Page du projet", "issueFeedback": "Problèmes et suggestions", "coolapk": "Coolapk · 程心ChengXin", "qq": "Groupe QQ · 1040456137", "email": "E-mail · 2680149724@qq.com", "copyright": "© 2026 ChengXin. Tous droits réservés.", "version": "Version %@", "changelog": "Notes de version", "license": "Licence GNU GPL v3", "readOnlyNote": "Cette app lit uniquement les informations ; aucun test, écriture, réparation, effacement ou micrologiciel.", "permissionNote": "Certains disques externes et compteurs constructeur peuvent être indisponibles selon macOS, le contrôleur ou le boîtier USB.", "scanFailed": "Analyse impossible : %@", "copied": "Rapport copié", "exported": "Rapport exporté", "done": "Terminé", "cancel": "Annuler"
        ],
        .german: [
            "overviewLimitations": "Die App zeigt alle von macOS und dem Gerät bereitgestellten Informationen. Temperatur, Betriebszeit und gesamte Lese-/Schreibmengen können je nach Laufwerk oder Verbindung fehlen.", "driveWorkingTimeExplanation": "Dieser Wert wird von der Laufwerksfirmware erfasst und kann Zeiten ausschließen, in denen sich der Controller im Energiesparmodus befindet. Er entspricht nicht der Einschalt- oder tatsächlichen Nutzungsdauer des Computers.", "batteryHealthExplanation": "Der Akkuzustand verwendet die von macOS kalibrierte Maximalkapazität. Temperatur, Lademanagement, Kalibrierung und Rundung können zu kleinen Abweichungen von Vollladung ÷ Designkapazität führen.", "powerConnectedNotCharging": "Das Netzteil ist verbunden. Der Akku ist voll oder macOS versorgt den Mac vorübergehend direkt mit Strom.", "internalBattery": "Interner Lithium-Ionen-Akku",
            "appName": "Laufwerks- und Akkuzustand", "systemLanguage": "Systemsprache", "overview": "Übersicht", "history": "Verlauf", "settings": "Einstellungen", "about": "Info", "menuFile": "Ablage", "menuEdit": "Bearbeiten", "menuView": "Darstellung", "menuWindow": "Fenster", "menuHelp": "Hilfe", "refresh": "Aktualisieren", "refreshing": "Analyse läuft…", "exportReport": "Bericht exportieren", "copyReport": "Bericht kopieren", "lastUpdated": "Aktualisiert %@", "noScan": "Noch kein Zustandsbericht", "noScanDetail": "Aktualisieren Sie die Laufwerks- und Akkuinformationen dieses Mac.", "drives": "Laufwerke", "batteries": "Akku", "noDrives": "Keine physischen Laufwerke gemeldet.", "noBattery": "Dieser Mac hat keinen Akku.",
            "health": "Zustand", "good": "Gut", "warning": "Achtung", "critical": "Kritisch", "unknown": "Nicht verfügbar", "model": "Modell", "capacity": "Kapazität", "protocol": "Verbindung", "firmware": "Firmware", "serialNumber": "Seriennummer", "smartStatus": "S.M.A.R.T.-Status", "lifeRemaining": "Geschätzte Restlebensdauer", "temperature": "Temperatur", "powerOnHours": "Betriebszeit", "powerCycles": "Einschaltvorgänge", "totalRead": "Insgesamt gelesen", "totalWritten": "Insgesamt geschrieben", "unsafeShutdowns": "Unsichere Abschaltungen", "mediaErrors": "Medienfehler", "errorLogEntries": "Fehlerprotokolleinträge", "internal": "Intern", "solidState": "SSD", "manufacturer": "Hersteller", "chemistry": "Akkutyp", "designCapacity": "Designkapazität", "fullChargeCapacity": "Volle Ladekapazität", "currentCharge": "Aktueller Ladestand", "cycleCount": "Ladezyklen", "batteryVoltage": "Akkuspannung", "charging": "Wird geladen", "connected": "Netzteil verbunden", "yes": "Ja", "no": "Nein", "unavailable": "Nicht gemeldet", "hours": "%llu Stunden", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "Zustandsbericht", "generated": "Erstellt", "computer": "Computer", "systemNotes": "Systemhinweise", "privacyNotice": "Bei Aktivierung werden Seriennummern in Oberfläche, Verlauf und Exporten verborgen.", "systemLimitations": "macOS stellt normalen Apps nicht alle NVMe/USB-S.M.A.R.T.-Werte bereit; fehlende Werte werden nicht geschätzt.", "historyEmpty": "Keine gespeicherten Berichte", "historyEmptyDetail": "Berichte nach jeder Aktualisierung oder nur beim Export speichern.", "sourceRefresh": "Nach Aktualisierung gespeichert", "sourceExport": "Beim Export gespeichert", "delete": "Löschen", "deleteConfirm": "Diesen Bericht löschen?", "deleteDetail": "Der gespeicherte Bericht wird gelöscht; exportierte Textdateien bleiben erhalten.", "showInFinder": "Im Finder zeigen", "chooseFolder": "Auswählen…", "openFolder": "Ordner öffnen", "historyLocation": "Verlaufsordner", "saveMode": "Berichte speichern", "saveOnRefresh": "Nach jeder Aktualisierung", "saveOnExport": "Nur beim Export", "language": "Sprache", "hideSerials": "Seriennummern ausblenden", "reportTextSize": "Berichtsschriftgröße", "appearance": "Darstellung und Datenschutz", "storage": "Verlaufsspeicher", "dataAccess": "Hardware-Datenzugriff", "aboutSummary": "Ein schlankes Nur-Lese-Werkzeug für Laufwerks- und Akkuzustand mit Berichtsverlauf.", "developer": "Entwickler", "author": "ChengXin", "projectHome": "Projektseite", "issueFeedback": "Probleme und Vorschläge", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ-Gruppe · 1040456137", "email": "E-Mail · 2680149724@qq.com", "copyright": "© 2026 ChengXin. Alle Rechte vorbehalten.", "version": "Version %@", "changelog": "Versionshinweise", "license": "GNU-GPL-v3-Lizenz", "readOnlyNote": "Die App liest nur Informationen und führt keine Tests, Schreib-, Reparatur-, Lösch- oder Firmwarevorgänge aus.", "permissionNote": "Einige externe Laufwerke und Herstellerwerte können wegen macOS, Controller oder USB-Gehäuse fehlen.", "scanFailed": "Analyse fehlgeschlagen: %@", "copied": "Bericht kopiert", "exported": "Bericht exportiert", "done": "Fertig", "cancel": "Abbrechen"
        ],
        .korean: [
            "overviewLimitations": "macOS와 장치가 제공하는 정보는 모두 표시합니다. 드라이브나 연결 방식에 따라 온도, 사용 시간, 누적 읽기·쓰기 양은 제공되지 않을 수 있습니다.", "driveWorkingTimeExplanation": "이 값은 드라이브 펌웨어가 집계하며 컨트롤러가 저전력 상태인 시간은 포함하지 않을 수 있습니다. 컴퓨터가 켜져 있거나 실제로 사용된 시간과 같지 않습니다.", "batteryHealthExplanation": "배터리 건강도는 macOS가 보정한 최대 용량을 따릅니다. 온도, 충전 관리, 시스템 보정 및 반올림 때문에 완전 충전 용량 ÷ 설계 용량 계산과 약간 다를 수 있습니다.", "powerConnectedNotCharging": "전원이 연결되어 있습니다. 배터리가 가득 찼거나 macOS가 일시적으로 Mac에 직접 전원을 공급합니다.", "internalBattery": "내장 리튬 이온 배터리",
            "appName": "드라이브 및 배터리 상태 보기", "systemLanguage": "시스템 언어", "overview": "개요", "history": "기록", "settings": "설정", "about": "정보", "menuFile": "파일", "menuEdit": "편집", "menuView": "보기", "menuWindow": "윈도우", "menuHelp": "도움말", "refresh": "새로 고침", "refreshing": "검사 중…", "exportReport": "보고서 내보내기", "copyReport": "보고서 복사", "lastUpdated": "%@ 업데이트", "noScan": "아직 상태 보고서가 없습니다", "noScanDetail": "새로 고쳐 이 Mac의 드라이브와 배터리 정보를 읽으십시오.", "drives": "드라이브", "batteries": "배터리", "noDrives": "보고된 물리 드라이브가 없습니다.", "noBattery": "이 Mac에는 배터리가 없습니다.",
            "health": "건강", "good": "좋음", "warning": "주의", "critical": "심각", "unknown": "사용할 수 없음", "model": "모델", "capacity": "용량", "protocol": "연결", "firmware": "펌웨어", "serialNumber": "일련번호", "smartStatus": "S.M.A.R.T. 상태", "lifeRemaining": "예상 남은 수명", "temperature": "온도", "powerOnHours": "사용 시간", "powerCycles": "전원 켠 횟수", "totalRead": "총 읽기", "totalWritten": "총 쓰기", "unsafeShutdowns": "비정상 종료", "mediaErrors": "미디어 오류", "errorLogEntries": "오류 로그 항목", "internal": "내장", "solidState": "SSD", "manufacturer": "제조사", "chemistry": "배터리 유형", "designCapacity": "설계 용량", "fullChargeCapacity": "완전 충전 용량", "currentCharge": "현재 충전량", "cycleCount": "사이클 수", "batteryVoltage": "배터리 전압", "charging": "충전 중", "connected": "전원 연결", "yes": "예", "no": "아니요", "unavailable": "보고되지 않음", "hours": "%llu시간", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "상태 보고서", "generated": "생성", "computer": "컴퓨터", "systemNotes": "시스템 안내", "privacyNotice": "활성화하면 화면, 기록, 복사 및 내보낸 보고서에서 일련번호를 숨깁니다.", "systemLimitations": "macOS는 일반 앱에 모든 NVMe/USB S.M.A.R.T. 값을 공개하지 않으며, 누락된 값은 추정하지 않습니다.", "historyEmpty": "저장된 보고서 없음", "historyEmptyDetail": "새로 고칠 때마다 또는 내보낼 때만 저장할 수 있습니다.", "sourceRefresh": "새로 고침 후 저장", "sourceExport": "내보낼 때 저장", "delete": "삭제", "deleteConfirm": "이 보고서를 삭제할까요?", "deleteDetail": "저장된 기록만 삭제되며 내보낸 텍스트 파일은 유지됩니다.", "showInFinder": "Finder에서 보기", "chooseFolder": "선택…", "openFolder": "폴더 열기", "historyLocation": "기록 위치", "saveMode": "보고서 저장", "saveOnRefresh": "새로 고칠 때마다", "saveOnExport": "내보낼 때만", "language": "언어", "hideSerials": "일련번호 숨기기", "reportTextSize": "보고서 글자 크기", "appearance": "모양 및 개인정보", "storage": "기록 저장소", "dataAccess": "하드웨어 데이터 접근", "aboutSummary": "드라이브와 배터리 상태를 읽기 전용으로 확인하고 시간에 따른 변화를 기록하는 가벼운 도구입니다.", "developer": "개발자", "author": "ChengXin", "projectHome": "프로젝트 홈페이지", "issueFeedback": "문제 및 제안", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ 그룹 · 1040456137", "email": "이메일 · 2680149724@qq.com", "copyright": "© 2026 ChengXin. All rights reserved.", "version": "버전 %@", "changelog": "업데이트 기록", "license": "GNU GPL v3 라이선스", "readOnlyNote": "이 앱은 정보만 읽으며 테스트, 쓰기, 복구, 삭제 또는 펌웨어 업데이트를 하지 않습니다.", "permissionNote": "외장 드라이브와 제조사 전용 값은 macOS, 컨트롤러 또는 USB 케이스 때문에 제공되지 않을 수 있습니다.", "scanFailed": "검사를 완료할 수 없습니다: %@", "copied": "보고서를 복사했습니다", "exported": "보고서를 내보냈습니다", "done": "완료", "cancel": "취소"
        ],
        .japanese: [
            "overviewLimitations": "macOS とデバイスが提供できる情報をすべて表示しています。ドライブや接続方法によっては、温度、使用時間、累積読み書き量を取得できません。", "driveWorkingTimeExplanation": "この値はドライブのファームウェアが集計し、コントローラが低電力状態にある時間を含まない場合があります。コンピュータの起動時間や実際の使用時間とは一致しません。", "batteryHealthExplanation": "バッテリーの健康度は macOS が校正した最大容量に基づきます。温度、充電管理、校正、丸めにより、満充電容量÷設計容量の単純計算と少し異なる場合があります。", "powerConnectedNotCharging": "電源に接続されています。バッテリーが満充電か、macOS が一時的に Mac へ直接給電しています。", "internalBattery": "内蔵リチウムイオンバッテリー",
            "appName": "ドライブとバッテリーの状態", "systemLanguage": "システム言語", "overview": "概要", "history": "履歴", "settings": "設定", "about": "このアプリについて", "menuFile": "ファイル", "menuEdit": "編集", "menuView": "表示", "menuWindow": "ウインドウ", "menuHelp": "ヘルプ", "refresh": "更新", "refreshing": "検査中…", "exportReport": "レポートを書き出す", "copyReport": "レポートをコピー", "lastUpdated": "%@ に更新", "noScan": "健康レポートはまだありません", "noScanDetail": "更新して、この Mac のドライブとバッテリー情報を読み取ります。", "drives": "ドライブ", "batteries": "バッテリー", "noDrives": "物理ドライブが報告されませんでした。", "noBattery": "この Mac にバッテリーはありません。",
            "health": "健康状態", "good": "良好", "warning": "注意", "critical": "重大", "unknown": "利用不可", "model": "モデル", "capacity": "容量", "protocol": "接続", "firmware": "ファームウェア", "serialNumber": "シリアル番号", "smartStatus": "S.M.A.R.T. 状態", "lifeRemaining": "推定残り寿命", "temperature": "温度", "powerOnHours": "使用時間", "powerCycles": "電源投入回数", "totalRead": "総読み込み量", "totalWritten": "総書き込み量", "unsafeShutdowns": "安全でないシャットダウン", "mediaErrors": "メディアエラー", "errorLogEntries": "エラーログエントリ", "internal": "内蔵", "solidState": "SSD", "manufacturer": "製造元", "chemistry": "バッテリー種類", "designCapacity": "設計容量", "fullChargeCapacity": "満充電容量", "currentCharge": "現在の充電量", "cycleCount": "充放電回数", "batteryVoltage": "バッテリー電圧", "charging": "充電中", "connected": "電源接続", "yes": "はい", "no": "いいえ", "unavailable": "報告なし", "hours": "%llu 時間", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "健康レポート", "generated": "生成日時", "computer": "コンピュータ", "systemNotes": "システム情報", "privacyNotice": "有効にすると、画面、履歴、コピーおよび書き出したレポートでシリアル番号を隠します。", "systemLimitations": "macOS は一般アプリにすべての NVMe/USB S.M.A.R.T. 値を公開しません。取得できない値は推測しません。", "historyEmpty": "保存済みレポートはありません", "historyEmptyDetail": "更新のたび、または書き出し時のみ保存できます。", "sourceRefresh": "更新後に保存", "sourceExport": "書き出し時に保存", "delete": "削除", "deleteConfirm": "この履歴レポートを削除しますか？", "deleteDetail": "Mac 内の保存記録を削除します。書き出したテキストファイルは削除しません。", "showInFinder": "Finder に表示", "chooseFolder": "選択…", "openFolder": "フォルダを開く", "historyLocation": "履歴の保存先", "saveMode": "レポートを保存", "saveOnRefresh": "更新のたび", "saveOnExport": "書き出し時のみ", "language": "言語", "hideSerials": "シリアル番号を隠す", "reportTextSize": "レポート文字サイズ", "appearance": "外観とプライバシー", "storage": "履歴ストレージ", "dataAccess": "ハードウェアデータへのアクセス", "aboutSummary": "ドライブとバッテリーの状態を読み取り専用で確認し、履歴から変化を追える軽量ツールです。", "developer": "開発者", "author": "ChengXin", "projectHome": "プロジェクトページ", "issueFeedback": "問題と提案", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ グループ · 1040456137", "email": "メール · 2680149724@qq.com", "copyright": "© 2026 ChengXin. All rights reserved.", "version": "バージョン %@", "changelog": "更新履歴", "license": "GNU GPL v3 ライセンス", "readOnlyNote": "本アプリは情報を読むだけで、テスト、書き込み、修復、消去、ファームウェア更新は行いません。", "permissionNote": "外付けドライブやメーカー固有の値は macOS、コントローラ、USB ケースにより取得できない場合があります。", "scanFailed": "検査を完了できませんでした：%@", "copied": "レポートをコピーしました", "exported": "レポートを書き出しました", "done": "完了", "cancel": "キャンセル"
        ]
    ]

    // Batch history actions are kept separately so the large legacy tables
    // remain stable while every supported language still has complete copy.
    private static let historyActionTables: [AppLanguage: [String: String]] = [
        .english: [
            "select": "Select", "selectAll": "Select All", "deselectAll": "Deselect All", "exportSelected": "Export Selected", "deleteSelected": "Delete Selected", "deleteSelectedConfirm": "Delete selected reports?", "deleteSelectedDetail": "The selected history reports will be removed from this Mac.", "batchExported": "Selected reports exported"
        ],
        .simplifiedChinese: [
            "select": "选择", "selectAll": "全选", "deselectAll": "取消全选", "exportSelected": "导出所选记录", "deleteSelected": "删除所选记录", "deleteSelectedConfirm": "删除所选历史记录？", "deleteSelectedDetail": "所选历史记录将从这台 Mac 中删除。", "batchExported": "所选记录已导出"
        ],
        .russian: [
            "select": "Выбрать", "selectAll": "Выбрать все", "deselectAll": "Снять выбор", "exportSelected": "Экспортировать выбранные", "deleteSelected": "Удалить выбранные", "deleteSelectedConfirm": "Удалить выбранные отчёты?", "deleteSelectedDetail": "Выбранные отчёты будут удалены с этого Mac.", "batchExported": "Выбранные отчёты экспортированы"
        ],
        .french: [
            "select": "Sélectionner", "selectAll": "Tout sélectionner", "deselectAll": "Tout désélectionner", "exportSelected": "Exporter la sélection", "deleteSelected": "Supprimer la sélection", "deleteSelectedConfirm": "Supprimer les rapports sélectionnés ?", "deleteSelectedDetail": "Les rapports sélectionnés seront supprimés de ce Mac.", "batchExported": "Rapports sélectionnés exportés"
        ],
        .german: [
            "select": "Auswählen", "selectAll": "Alle auswählen", "deselectAll": "Auswahl aufheben", "exportSelected": "Auswahl exportieren", "deleteSelected": "Auswahl löschen", "deleteSelectedConfirm": "Ausgewählte Berichte löschen?", "deleteSelectedDetail": "Die ausgewählten Berichte werden von diesem Mac entfernt.", "batchExported": "Ausgewählte Berichte exportiert"
        ],
        .korean: [
            "select": "선택", "selectAll": "모두 선택", "deselectAll": "모두 선택 해제", "exportSelected": "선택 항목 내보내기", "deleteSelected": "선택 항목 삭제", "deleteSelectedConfirm": "선택한 기록을 삭제할까요?", "deleteSelectedDetail": "선택한 기록이 이 Mac에서 삭제됩니다.", "batchExported": "선택한 기록을 내보냈습니다"
        ],
        .japanese: [
            "select": "選択", "selectAll": "すべて選択", "deselectAll": "選択を解除", "exportSelected": "選択項目を書き出す", "deleteSelected": "選択項目を削除", "deleteSelectedConfirm": "選択した履歴を削除しますか？", "deleteSelectedDetail": "選択した履歴をこの Mac から削除します。", "batchExported": "選択したレポートを書き出しました"
        ]
    ]

    private static let menuActionTables: [AppLanguage: [String: String]] = [
        .english: [
            "exportCurrentReport": "Export Current Report", "openReportFolder": "Open Reports Folder",
            "increaseReportText": "Increase Report Text Size", "decreaseReportText": "Decrease Report Text Size", "resetReportText": "Reset Report Text Size",
            "menuFeedback": "Report an Issue", "viewChangelog": "View Release Notes", "checkForUpdates": "Check for Updates…",
            "updateAvailableTitle": "A new version v%@ is available", "currentVersionLabel": "Current version: v%@", "latestVersionLabel": "Latest version: v%@",
            "later": "Later", "downloadFromGitHub": "Go to GitHub to Download", "alreadyLatestVersion": "You’re using the latest version (v%@).",
            "updateCheckFailed": "Unable to check for updates. Check your internet connection and try again."
        ],
        .simplifiedChinese: [
            "exportCurrentReport": "导出当前报告", "openReportFolder": "打开报告文件夹",
            "increaseReportText": "增大报告文字", "decreaseReportText": "减小报告文字", "resetReportText": "恢复默认文字大小",
            "menuFeedback": "反馈问题", "viewChangelog": "查看更新日志", "checkForUpdates": "检查更新…",
            "updateAvailableTitle": "发现新版本 v%@", "currentVersionLabel": "当前版本：v%@", "latestVersionLabel": "最新版本：v%@",
            "later": "稍后", "downloadFromGitHub": "前往 GitHub 下载", "alreadyLatestVersion": "当前已是最新版本（v%@）。",
            "updateCheckFailed": "无法检查更新，请检查网络连接后重试。"
        ],
        .russian: [
            "exportCurrentReport": "Экспортировать текущий отчёт", "openReportFolder": "Открыть папку отчётов",
            "increaseReportText": "Увеличить текст отчёта", "decreaseReportText": "Уменьшить текст отчёта", "resetReportText": "Восстановить размер текста",
            "menuFeedback": "Сообщить о проблеме", "viewChangelog": "Посмотреть журнал изменений", "checkForUpdates": "Проверить обновления…",
            "updateAvailableTitle": "Доступна новая версия v%@", "currentVersionLabel": "Текущая версия: v%@", "latestVersionLabel": "Последняя версия: v%@",
            "later": "Позже", "downloadFromGitHub": "Перейти на GitHub для загрузки", "alreadyLatestVersion": "Установлена последняя версия (v%@).",
            "updateCheckFailed": "Не удалось проверить обновления. Проверьте подключение к интернету и повторите попытку."
        ],
        .french: [
            "exportCurrentReport": "Exporter le rapport actuel", "openReportFolder": "Ouvrir le dossier des rapports",
            "increaseReportText": "Agrandir le texte du rapport", "decreaseReportText": "Réduire le texte du rapport", "resetReportText": "Rétablir la taille du texte",
            "menuFeedback": "Signaler un problème", "viewChangelog": "Voir les notes de version", "checkForUpdates": "Rechercher les mises à jour…",
            "updateAvailableTitle": "Une nouvelle version v%@ est disponible", "currentVersionLabel": "Version actuelle : v%@", "latestVersionLabel": "Dernière version : v%@",
            "later": "Plus tard", "downloadFromGitHub": "Télécharger depuis GitHub", "alreadyLatestVersion": "Vous utilisez la dernière version (v%@).",
            "updateCheckFailed": "Impossible de rechercher les mises à jour. Vérifiez votre connexion internet et réessayez."
        ],
        .german: [
            "exportCurrentReport": "Aktuellen Bericht exportieren", "openReportFolder": "Berichtsordner öffnen",
            "increaseReportText": "Berichtstext vergrößern", "decreaseReportText": "Berichtstext verkleinern", "resetReportText": "Standardtextgröße wiederherstellen",
            "menuFeedback": "Problem melden", "viewChangelog": "Versionshinweise anzeigen", "checkForUpdates": "Nach Updates suchen…",
            "updateAvailableTitle": "Eine neue Version v%@ ist verfügbar", "currentVersionLabel": "Aktuelle Version: v%@", "latestVersionLabel": "Neueste Version: v%@",
            "later": "Später", "downloadFromGitHub": "Auf GitHub herunterladen", "alreadyLatestVersion": "Sie verwenden die neueste Version (v%@).",
            "updateCheckFailed": "Die Suche nach Updates ist fehlgeschlagen. Prüfen Sie die Internetverbindung und versuchen Sie es erneut."
        ],
        .korean: [
            "exportCurrentReport": "현재 보고서 내보내기", "openReportFolder": "보고서 폴더 열기",
            "increaseReportText": "보고서 텍스트 크게", "decreaseReportText": "보고서 텍스트 작게", "resetReportText": "기본 텍스트 크기로 복원",
            "menuFeedback": "문제 신고", "viewChangelog": "업데이트 기록 보기", "checkForUpdates": "업데이트 확인…",
            "updateAvailableTitle": "새 버전 v%@을 사용할 수 있습니다", "currentVersionLabel": "현재 버전: v%@", "latestVersionLabel": "최신 버전: v%@",
            "later": "나중에", "downloadFromGitHub": "GitHub에서 다운로드", "alreadyLatestVersion": "최신 버전(v%@)을 사용 중입니다.",
            "updateCheckFailed": "업데이트를 확인할 수 없습니다. 인터넷 연결을 확인한 후 다시 시도하십시오."
        ],
        .japanese: [
            "exportCurrentReport": "現在のレポートを書き出す", "openReportFolder": "レポートフォルダを開く",
            "increaseReportText": "レポート文字を大きく", "decreaseReportText": "レポート文字を小さく", "resetReportText": "標準の文字サイズに戻す",
            "menuFeedback": "問題を報告", "viewChangelog": "更新履歴を表示", "checkForUpdates": "アップデートを確認…",
            "updateAvailableTitle": "新しいバージョン v%@ が見つかりました", "currentVersionLabel": "現在のバージョン：v%@", "latestVersionLabel": "最新バージョン：v%@",
            "later": "後で", "downloadFromGitHub": "GitHub からダウンロード", "alreadyLatestVersion": "最新バージョン（v%@）を使用しています。",
            "updateCheckFailed": "アップデートを確認できません。インターネット接続を確認して、もう一度お試しください。"
        ]
    ]

    private static let updatePromptTables: [AppLanguage: [String: String]] = [
        .english: [
            "versionUpdatePromptTitle": "Updated to version %@",
            "versionUpdatePromptMessage": "Would you like to see what’s new?",
            "dismissVersionUpdatePrompt": "Not Now"
        ],
        .simplifiedChinese: [
            "versionUpdatePromptTitle": "已更新至版本 %@",
            "versionUpdatePromptMessage": "要查看本次更新内容吗？",
            "dismissVersionUpdatePrompt": "暂不查看"
        ],
        .russian: [
            "versionUpdatePromptTitle": "Обновлено до версии %@",
            "versionUpdatePromptMessage": "Посмотреть, что нового?",
            "dismissVersionUpdatePrompt": "Не сейчас"
        ],
        .french: [
            "versionUpdatePromptTitle": "Mise à jour vers la version %@",
            "versionUpdatePromptMessage": "Souhaitez-vous voir les nouveautés ?",
            "dismissVersionUpdatePrompt": "Pas maintenant"
        ],
        .german: [
            "versionUpdatePromptTitle": "Auf Version %@ aktualisiert",
            "versionUpdatePromptMessage": "Möchten Sie die Neuerungen ansehen?",
            "dismissVersionUpdatePrompt": "Nicht jetzt"
        ],
        .korean: [
            "versionUpdatePromptTitle": "버전 %@(으)로 업데이트됨",
            "versionUpdatePromptMessage": "이번 업데이트 내용을 확인하시겠습니까?",
            "dismissVersionUpdatePrompt": "지금 안 함"
        ],
        .japanese: [
            "versionUpdatePromptTitle": "バージョン %@ にアップデートしました",
            "versionUpdatePromptMessage": "今回の変更内容を確認しますか？",
            "dismissVersionUpdatePrompt": "今はしない"
        ]
    ]

    private static let safetyCopyTables: [AppLanguage: [String: String]] = [
        .english: [
            "aboutSummary": "A lightweight utility for checking drive status and battery health, saving reports, and following changes over time.",
            "readOnlyNote": "Drive, S.M.A.R.T., and health-data access is read-only: no benchmarks, repair, erase, or firmware updates. On supported Apple Silicon Macs, optional charge protection changes only battery charging control after you enable it."
        ],
        .simplifiedChinese: [
            "aboutSummary": "一款查看硬盘状态与电池健康情况的轻量级工具，支持保存检测报告并了解健康状态随时间的变化。",
            "readOnlyNote": "硬盘、S.M.A.R.T. 与健康信息读取保持只读，不会测速、修复、擦除或更新固件。在受支持的 Apple Silicon Mac 上，仅当用户主动启用后，充电保护才会调整电池充电控制状态。"
        ],
        .russian: [
            "aboutSummary": "Лёгкая утилита для просмотра состояния накопителей и батареи, истории отчётов и изменений со временем.",
            "readOnlyNote": "Доступ к данным накопителя, S.M.A.R.T. и состоянию остаётся только для чтения: без тестов, ремонта, стирания и обновления прошивки. На поддерживаемых Mac с Apple Silicon защита зарядки изменяет только управление зарядкой и только после включения пользователем."
        ],
        .french: [
            "aboutSummary": "Un utilitaire léger pour consulter l’état des disques et de la batterie et suivre leur évolution.",
            "readOnlyNote": "L’accès aux données des disques, S.M.A.R.T. et de santé reste en lecture seule : aucun test, réparation, effacement ou micrologiciel. Sur les Mac Apple Silicon pris en charge, la protection optionnelle ne modifie que le contrôle de charge après son activation."
        ],
        .german: [
            "aboutSummary": "Ein schlankes Werkzeug für Laufwerks- und Akkuzustand mit Berichtsverlauf.",
            "readOnlyNote": "Der Zugriff auf Laufwerks-, S.M.A.R.T.- und Zustandsdaten bleibt schreibgeschützt: keine Tests, Reparaturen, Löschungen oder Firmwareupdates. Auf unterstützten Apple-Silicon-Macs ändert der optionale Ladeschutz nur nach Aktivierung die Ladesteuerung."
        ],
        .korean: [
            "aboutSummary": "드라이브와 배터리 상태를 확인하고 시간에 따른 변화를 기록하는 가벼운 도구입니다.",
            "readOnlyNote": "드라이브, S.M.A.R.T. 및 상태 정보는 읽기 전용으로 접근하며 테스트, 복구, 삭제 또는 펌웨어 업데이트를 하지 않습니다. 지원되는 Apple Silicon Mac에서는 사용자가 활성화한 경우에만 충전 보호가 배터리 충전 제어 상태를 변경합니다."
        ],
        .japanese: [
            "aboutSummary": "ドライブとバッテリーの状態を確認し、履歴から変化を追える軽量ツールです。",
            "readOnlyNote": "ドライブ、S.M.A.R.T.、健康情報へのアクセスは読み取り専用で、テスト、修復、消去、ファームウェア更新は行いません。対応する Apple Silicon Mac では、ユーザーが有効にした場合のみ充電保護がバッテリーの充電制御状態を変更します。"
        ]
    ]

    private static let featureTables: [AppLanguage: [String: String]] = [
        .english: [
            "chargeProtection": "Battery Charge Protection", "chargeProtectionEnabled": "Enable charge protection",
            "fixedChargeLimit": "Fixed charge limit", "chargeProtectionInstallNote": "The first activation installs a minimal helper and asks for administrator permission once.",
            "macOS158ChargeLimitNotice": "Current system: macOS 15.8. This system version supports only Apple’s native 80% charge limit.", "macOS158Only80DisabledHint": "Choose 80%, or 100% to turn charge protection off.",
            "chargeProtectionUnsupportedIntel": "Battery charge protection is unavailable on Intel Mac.",
            "chargeProtectionNativeNotice": "This version of macOS already supports charge limits. To avoid conflicts with system battery management, use the built-in charge limit feature.",
            "chargeProtectionNativePath": "System Settings → Battery → Info next to Charging → Charge Limit",
            "openBatterySettings": "Open Battery Settings", "chargeToFullOnce": "Charge to Full This Time",
            "cancelFullCharge": "Cancel Full Charge", "temporaryFullInProgress": "Charging to 100% this time; the fixed limit will resume automatically.",
            "chargeLimitReached": "Charge limit reached (%d%%)", "adjustFixedLimit": "Adjust fixed charge limit",
            "chargeHelperUnavailable": "This Mac’s firmware does not expose a supported charging control method.",
            "chargeOperationFailed": "Charge protection could not be applied. Normal system charging remains available.",
            "chargeHelperBusy": "Applying charge protection…", "uninstallChargeHelper": "Disable and Uninstall Charge Helper",
            "uninstallChargeHelperConfirm": "Disable and uninstall the charge helper?", "uninstallChargeHelperDetail": "Restores normal charging, then removes the privileged helper, its launchd job, the menu-bar Agent, and this app’s charge-control state.",
            "chargeHelperAuthorizationTitle": "Administrator Authorization Required", "continueAuthorization": "Continue",
            "chargeHelperInstallAuthorizationMessage": "To securely install or update the charge helper, macOS will ask for an administrator password next. The password is verified only by macOS; this app never reads or stores it.",
            "chargeHelperUninstallAuthorizationMessage": "After you continue, macOS will ask for an administrator password to remove the privileged helper. The password is verified only by macOS; this app never reads or stores it.",
            "desktopMacMode": "Desktop Mac Mode", "desktopMacPoweredTitle": "Plugged in and fully powered", "desktopMacPoweredDetail": "This Mac is a desktop computer and does not need battery health management.",
            "showChargeStatusInMenuBar": "Show charge protection in the menu bar", "uninstallApplication": "Uninstall Application…", "uninstallApplicationDetail": "Restores normal charging, removes installed helpers and menu-bar components, and moves the application to Trash.", "deleteAllHistoryOnUninstall": "Also delete all history reports",
            "expandChargeProtection": "Show charge protection controls", "collapseChargeProtection": "Hide charge protection controls",
            "intelChargingManagedTitle": "Battery charging on this Mac is managed by macOS", "intelChargingManagedDetail": "This app’s fixed charge limits currently apply to Mac computers with Apple silicon. macOS will continue to manage charging using its system battery policies.",
            "nativeChargingAvailableTitle": "macOS provides charge limits", "nativeChargingAvailableDetail": "This system supports fixed charge limits. Using the built-in macOS feature is recommended for the best system compatibility.",
            "preferSoftwareChargingQuestion": "Still want this app to manage the charge limit?", "useSoftwareCharging": "Use This App’s Charge Protection…",
            "softwareChargingPreparationTitle": "Use this app to manage charging", "softwareChargingPreparationIntro": "To prevent macOS and this app from controlling charging at the same time, first complete these settings:",
            "softwareChargingPreparationStep1": "1. Set the macOS Charge Limit to 100%", "softwareChargingPreparationStep2": "2. Turn off Optimized Battery Charging",
            "softwareChargingPreparationReason": "This lets the app act as the primary fixed-limit controller and avoids conflicting charging policies.", "softwareChargingPreparationConfirmed": "I have completed these settings",
            "continueSoftwareCharging": "Continue Using This App", "switchToSystemCharging": "Use macOS System Feature", "softwareManagedReminder": "This app is managing the charge limit. Keep the macOS limit at 100% and turn off Optimized Battery Charging.",
            "chargeMigrationTitle": "macOS now supports charge limits", "chargeMigrationMessage": "After the system update, macOS provides fixed charge limits. Using the system feature is recommended to avoid running two charging policies.",
            "exportDiagnosticLogs": "Export Diagnostic Logs…", "diagnosticExportTitle": "Export Diagnostic Logs",
            "diagnosticStartTime": "Start time", "diagnosticEndTime": "End time", "diagnosticExport": "Export…",
            "diagnosticLast15Minutes": "Last 15 Minutes", "diagnosticLastHour": "Last Hour", "diagnosticLast24Hours": "Last 24 Hours",
            "diagnosticInvalidRange": "The start time must not be later than the end time.",
            "diagnosticFutureEnd": "The end time cannot be later than the current time.",
            "diagnosticPartialRange": "Only log entries still available within the selected period will be exported.",
            "diagnosticExported": "Diagnostic logs exported", "diagnosticExportFailed": "Diagnostic logs could not be exported.",
            "driveWorkingTimeDetail": "\u{201c}Operating time\u{201d} is counted by the drive firmware and is not the same as the Mac\u{2019}s power-on or usage time. During everyday use, a drive may frequently enter low-power or standby states, and that time may not be counted. As a result, operating time shown on macOS devices can be noticeably shorter than on other computers; this is usually normal."
        ],
        .simplifiedChinese: [
            "chargeProtection": "电池充电保护", "chargeProtectionEnabled": "启用充电保护",
            "fixedChargeLimit": "固定充电上限", "chargeProtectionInstallNote": "首次启用会安装一个最小化辅助程序，并仅请求一次管理员权限。",
            "macOS158ChargeLimitNotice": "当前为macOS 15.8：此系统版本仅支持Apple原生的80%充电上限。", "macOS158Only80DisabledHint": "请选择 80%，或选择 100% 关闭充电保护。",
            "chargeProtectionUnsupportedIntel": "Intel Mac 不支持电池充电保护功能。",
            "chargeProtectionNativeNotice": "当前 macOS 已原生支持充电上限。为避免与系统电池管理发生冲突，请使用系统自带的充电上限功能。",
            "chargeProtectionNativePath": "系统设置 → 电池 →“充电”旁的信息按钮 → 充电上限",
            "openBatterySettings": "打开系统电池设置", "chargeToFullOnce": "本次充满", "cancelFullCharge": "取消本次充满",
            "temporaryFullInProgress": "本次将充至 100%，完成后会自动恢复固定上限。",
            "chargeLimitReached": "已到达设定电量（%d%%）", "adjustFixedLimit": "调整固定充电上限",
            "chargeHelperUnavailable": "这台 Mac 的固件未开放受支持的充电控制方式。",
            "chargeOperationFailed": "无法应用充电保护，系统正常充电功能仍可使用。",
            "chargeHelperBusy": "正在应用充电保护…", "uninstallChargeHelper": "停用并卸载充电辅助程序",
            "uninstallChargeHelperConfirm": "停用并卸载充电辅助程序？", "uninstallChargeHelperDetail": "将先恢复系统正常充电，再移除特权辅助程序、launchd 项、菜单栏控件以及本软件的充电控制状态。",
            "chargeHelperAuthorizationTitle": "需要管理员授权", "continueAuthorization": "继续",
            "chargeHelperInstallAuthorizationMessage": "为了安全安装或更新充电辅助程序，macOS 接下来会要求输入管理员密码。密码仅由 macOS 验证，本软件不会读取或保存。",
            "chargeHelperUninstallAuthorizationMessage": "继续后，macOS 会要求输入管理员密码，以移除特权辅助程序。密码仅由 macOS 验证，本软件不会读取或保存。",
            "desktopMacMode": "桌面 Mac 模式", "desktopMacPoweredTitle": "插电即满血", "desktopMacPoweredDetail": "这台 Mac 是桌面设备，不需要电池健康管理。",
            "showChargeStatusInMenuBar": "在菜单栏显示充电保护状态", "uninstallApplication": "卸载应用…", "uninstallApplicationDetail": "恢复系统正常充电，移除已安装的辅助程序与菜单栏组件，并将应用移到废纸篓。", "deleteAllHistoryOnUninstall": "同时删除全部历史记录",
            "expandChargeProtection": "展开充电保护设置", "collapseChargeProtection": "折叠充电保护设置",
            "intelChargingManagedTitle": "当前 Mac 的电池充电由 macOS 管理", "intelChargingManagedDetail": "本软件的固定充电上限功能目前适用于 Apple 芯片 Mac。macOS 会继续根据系统的电池管理策略管理充电状态。",
            "nativeChargingAvailableTitle": "macOS 已提供充电上限功能", "nativeChargingAvailableDetail": "当前系统已经原生支持固定充电上限。推荐优先使用 macOS 自带功能，以获得更好的系统兼容性。",
            "preferSoftwareChargingQuestion": "仍希望使用本软件管理充电上限？", "useSoftwareCharging": "使用本软件的充电保护…",
            "softwareChargingPreparationTitle": "使用本软件管理充电", "softwareChargingPreparationIntro": "为了避免 macOS 与本软件同时控制电池充电，请先完成以下设置：",
            "softwareChargingPreparationStep1": "1. 将 macOS“充电上限”设置为 100%", "softwareChargingPreparationStep2": "2. 关闭“优化电池充电”",
            "softwareChargingPreparationReason": "这样可以让本软件作为主要的固定充电上限控制器，避免两套充电策略互相干扰。", "softwareChargingPreparationConfirmed": "我已完成以上设置",
            "continueSoftwareCharging": "继续使用本软件", "switchToSystemCharging": "改用 macOS 系统功能", "softwareManagedReminder": "当前使用本软件管理充电上限。macOS 固定充电上限应保持为 100%，并建议关闭“优化电池充电”。",
            "chargeMigrationTitle": "macOS 现在已支持原生充电上限", "chargeMigrationMessage": "系统更新后，macOS 已提供自己的固定充电上限功能。推荐改用系统功能，以避免同时运行两套充电策略。",
            "exportDiagnosticLogs": "导出诊断日志…", "diagnosticExportTitle": "导出诊断日志",
            "diagnosticStartTime": "起始时间", "diagnosticEndTime": "截止时间", "diagnosticExport": "导出…",
            "diagnosticLast15Minutes": "最近 15 分钟", "diagnosticLastHour": "最近 1 小时", "diagnosticLast24Hours": "最近 24 小时",
            "diagnosticInvalidRange": "起始时间不能晚于截止时间。", "diagnosticFutureEnd": "截止时间不能晚于当前时间。",
            "diagnosticPartialRange": "只会导出所选时间段内仍保留的日志记录。", "diagnosticExported": "诊断日志已导出",
            "diagnosticExportFailed": "无法导出诊断日志。",
            "driveWorkingTimeDetail": "“工作时间”由硬盘固件统计，并不等同于 Mac 的开机时间或使用时间。硬盘在日常使用中可能经常处于低功耗或待机状态，这些时间不一定会被计入。因此，macOS 设备显示的工作时间可能明显短于其他电脑，这通常属于正常现象。"
        ],
        .russian: [
            "chargeProtection": "Защита зарядки батареи", "chargeProtectionEnabled": "Включить защиту зарядки",
            "fixedChargeLimit": "Постоянный предел заряда", "chargeProtectionInstallNote": "При первом включении устанавливается минимальный помощник и один раз запрашиваются права администратора.",
            "macOS158ChargeLimitNotice": "Текущая система — macOS 15.8. Эта версия поддерживает только нативный предел Apple 80%.", "macOS158Only80DisabledHint": "Выберите 80% или 100%, чтобы отключить защиту зарядки.",
            "chargeProtectionUnsupportedIntel": "Защита зарядки недоступна на Intel Mac.",
            "chargeProtectionNativeNotice": "Эта версия macOS уже поддерживает предел заряда. Во избежание конфликтов используйте встроенную функцию macOS.",
            "chargeProtectionNativePath": "Системные настройки → Батарея → Сведения рядом с «Зарядка» → Предел заряда",
            "openBatterySettings": "Открыть настройки батареи", "chargeToFullOnce": "Зарядить полностью один раз", "cancelFullCharge": "Отменить полный заряд",
            "temporaryFullInProgress": "В этот раз батарея зарядится до 100 %, затем постоянный предел восстановится автоматически.",
            "chargeLimitReached": "Достигнут предел заряда (%d%%)", "adjustFixedLimit": "Изменить постоянный предел",
            "chargeHelperUnavailable": "Прошивка этого Mac не предоставляет поддерживаемый способ управления зарядкой.", "chargeHelperBusy": "Применение защиты зарядки…",
            "chargeOperationFailed": "Не удалось применить защиту зарядки. Обычная системная зарядка остаётся доступной.",
            "uninstallChargeHelper": "Отключить и удалить помощник зарядки", "uninstallChargeHelperConfirm": "Отключить и удалить помощник зарядки?", "uninstallChargeHelperDetail": "Восстанавливает обычную зарядку, затем удаляет привилегированный помощник, задание launchd, агент строки меню и состояние управления зарядкой приложения.",
            "chargeHelperAuthorizationTitle": "Требуется авторизация администратора", "continueAuthorization": "Продолжить",
            "chargeHelperInstallAuthorizationMessage": "Для безопасной установки или обновления помощника macOS запросит пароль администратора. Пароль проверяет только macOS; приложение его не считывает и не сохраняет.",
            "chargeHelperUninstallAuthorizationMessage": "После продолжения macOS запросит пароль администратора для удаления привилегированного помощника. Пароль проверяет только macOS; приложение его не считывает и не сохраняет.",
            "desktopMacMode": "Режим настольного Mac", "desktopMacPoweredTitle": "Подключён — и полон сил", "desktopMacPoweredDetail": "Это настольный Mac, поэтому управление состоянием батареи ему не требуется.",
            "showChargeStatusInMenuBar": "Показывать защиту зарядки в строке меню", "uninstallApplication": "Удалить приложение…", "deleteAllHistoryOnUninstall": "Также удалить все отчёты истории", "uninstallApplicationDetail": "Восстанавливает обычную зарядку, удаляет помощники и компоненты строки меню, затем перемещает приложение в Корзину.", "expandChargeProtection": "Показать настройки защиты зарядки", "collapseChargeProtection": "Скрыть настройки защиты зарядки", "exportDiagnosticLogs": "Экспортировать журналы диагностики…",
            "intelChargingManagedTitle": "Зарядкой этого Mac управляет macOS", "intelChargingManagedDetail": "Фиксированные пределы этого приложения предназначены для Mac с Apple silicon. macOS продолжит управлять зарядкой по системным правилам.",
            "nativeChargingAvailableTitle": "macOS поддерживает предел заряда", "nativeChargingAvailableDetail": "Система поддерживает фиксированный предел. Для лучшей совместимости рекомендуется встроенная функция macOS.",
            "preferSoftwareChargingQuestion": "Всё же управлять пределом через приложение?", "useSoftwareCharging": "Использовать защиту приложения…",
            "softwareChargingPreparationTitle": "Управление зарядкой приложением", "softwareChargingPreparationIntro": "Чтобы macOS и приложение не управляли зарядкой одновременно, сначала:",
            "softwareChargingPreparationStep1": "1. Установите предел macOS на 100%", "softwareChargingPreparationStep2": "2. Отключите оптимизированную зарядку",
            "softwareChargingPreparationReason": "Приложение станет основным контроллером и стратегии не будут конфликтовать.", "softwareChargingPreparationConfirmed": "Я выполнил(а) эти настройки",
            "continueSoftwareCharging": "Продолжить с приложением", "switchToSystemCharging": "Использовать функцию macOS", "softwareManagedReminder": "Пределом управляет приложение. Оставьте предел macOS 100% и отключите оптимизированную зарядку.",
            "chargeMigrationTitle": "macOS теперь поддерживает предел заряда", "chargeMigrationMessage": "После обновления macOS предоставляет фиксированный предел. Рекомендуется системная функция, чтобы не запускать две стратегии.",
            "diagnosticExportTitle": "Экспорт журналов диагностики", "diagnosticStartTime": "Начало", "diagnosticEndTime": "Окончание", "diagnosticExport": "Экспорт…",
            "diagnosticLast15Minutes": "Последние 15 минут", "diagnosticLastHour": "Последний час", "diagnosticLast24Hours": "Последние 24 часа",
            "diagnosticInvalidRange": "Время начала не может быть позже времени окончания.", "diagnosticFutureEnd": "Время окончания не может быть позже текущего времени.",
            "diagnosticPartialRange": "Будут экспортированы только сохранившиеся записи выбранного периода.", "diagnosticExported": "Журналы диагностики экспортированы", "diagnosticExportFailed": "Не удалось экспортировать журналы диагностики.",
            "driveWorkingTimeDetail": "«Время работы» считается прошивкой накопителя и не равно времени включения или использования Mac. Накопитель часто переходит в энергосберегающий или ждущий режим, и это время может не учитываться. Поэтому на macOS значение может быть заметно меньше, чем на других компьютерах; обычно это нормально."
        ],
        .french: [
            "chargeProtection": "Protection de la charge", "chargeProtectionEnabled": "Activer la protection de la charge",
            "fixedChargeLimit": "Limite de charge fixe", "chargeProtectionInstallNote": "La première activation installe un assistant minimal et demande une seule fois l’autorisation administrateur.",
            "macOS158ChargeLimitNotice": "Système actuel : macOS 15.8. Cette version ne prend en charge que la limite native Apple de 80 %.", "macOS158Only80DisabledHint": "Choisissez 80 %, ou 100 % pour désactiver la protection.",
            "chargeProtectionUnsupportedIntel": "La protection de la charge n’est pas disponible sur les Mac Intel.",
            "chargeProtectionNativeNotice": "Cette version de macOS prend déjà en charge les limites de charge. Pour éviter les conflits, utilisez la fonction intégrée de macOS.",
            "chargeProtectionNativePath": "Réglages Système → Batterie → Infos en regard de Recharge → Limite de charge",
            "openBatterySettings": "Ouvrir les réglages de batterie", "chargeToFullOnce": "Charger complètement cette fois", "cancelFullCharge": "Annuler la charge complète",
            "temporaryFullInProgress": "La batterie sera chargée à 100 % cette fois, puis la limite fixe sera rétablie automatiquement.",
            "chargeLimitReached": "Limite de charge atteinte (%d%%)", "adjustFixedLimit": "Modifier la limite fixe",
            "chargeHelperUnavailable": "Le programme interne de ce Mac n’expose aucune méthode de contrôle prise en charge.", "chargeHelperBusy": "Application de la protection…",
            "chargeOperationFailed": "La protection de charge n’a pas pu être appliquée. La charge normale du système reste disponible.",
            "uninstallChargeHelper": "Désactiver et désinstaller l’assistant de charge", "uninstallChargeHelperConfirm": "Désactiver et désinstaller l’assistant de charge ?", "uninstallChargeHelperDetail": "Rétablit la charge normale, puis supprime l’assistant privilégié, sa tâche launchd, l’agent de barre des menus et l’état de contrôle de charge de l’app.",
            "chargeHelperAuthorizationTitle": "Autorisation administrateur requise", "continueAuthorization": "Continuer",
            "chargeHelperInstallAuthorizationMessage": "Pour installer ou mettre à jour l’assistant de charge en toute sécurité, macOS demandera ensuite un mot de passe administrateur. Seul macOS le vérifie ; l’app ne le lit ni ne l’enregistre.",
            "chargeHelperUninstallAuthorizationMessage": "Après avoir continué, macOS demandera un mot de passe administrateur pour supprimer l’assistant privilégié. Seul macOS le vérifie ; l’app ne le lit ni ne l’enregistre.",
            "desktopMacMode": "Mode Mac de bureau", "desktopMacPoweredTitle": "Branché et à pleine puissance", "desktopMacPoweredDetail": "Ce Mac est un ordinateur de bureau et n’a pas besoin de gestion de santé de batterie.",
            "showChargeStatusInMenuBar": "Afficher la protection de charge dans la barre des menus", "uninstallApplication": "Désinstaller l’application…", "deleteAllHistoryOnUninstall": "Supprimer aussi tous les rapports d’historique", "uninstallApplicationDetail": "Rétablit la charge normale, supprime les assistants et composants de barre des menus, puis place l’application dans la Corbeille.", "expandChargeProtection": "Afficher les réglages de protection", "collapseChargeProtection": "Masquer les réglages de protection", "exportDiagnosticLogs": "Exporter les journaux de diagnostic…",
            "intelChargingManagedTitle": "La charge de ce Mac est gérée par macOS", "intelChargingManagedDetail": "Les limites fixes de cette app s’appliquent actuellement aux Mac avec puce Apple. macOS continue de gérer la charge selon ses règles système.",
            "nativeChargingAvailableTitle": "macOS propose une limite de charge", "nativeChargingAvailableDetail": "Ce système prend en charge une limite fixe. La fonction intégrée de macOS est recommandée pour une meilleure compatibilité.",
            "preferSoftwareChargingQuestion": "Toujours confier la limite à cette app ?", "useSoftwareCharging": "Utiliser la protection de cette app…",
            "softwareChargingPreparationTitle": "Gérer la charge avec cette app", "softwareChargingPreparationIntro": "Pour éviter que macOS et l’app contrôlent la charge ensemble, effectuez d’abord ces réglages :",
            "softwareChargingPreparationStep1": "1. Réglez la limite macOS sur 100 %", "softwareChargingPreparationStep2": "2. Désactivez la recharge optimisée",
            "softwareChargingPreparationReason": "L’app devient ainsi le contrôleur principal sans conflit de stratégies.", "softwareChargingPreparationConfirmed": "J’ai effectué ces réglages",
            "continueSoftwareCharging": "Continuer avec cette app", "switchToSystemCharging": "Utiliser la fonction macOS", "softwareManagedReminder": "Cette app gère la limite. Gardez la limite macOS à 100 % et désactivez la recharge optimisée.",
            "chargeMigrationTitle": "macOS prend désormais en charge les limites", "chargeMigrationMessage": "Après la mise à jour, macOS propose une limite fixe. La fonction système est recommandée pour éviter deux stratégies simultanées.",
            "diagnosticExportTitle": "Exporter les journaux de diagnostic", "diagnosticStartTime": "Heure de début", "diagnosticEndTime": "Heure de fin", "diagnosticExport": "Exporter…",
            "diagnosticLast15Minutes": "15 dernières minutes", "diagnosticLastHour": "Dernière heure", "diagnosticLast24Hours": "Dernières 24 heures",
            "diagnosticInvalidRange": "L’heure de début ne peut pas être postérieure à l’heure de fin.", "diagnosticFutureEnd": "L’heure de fin ne peut pas être postérieure à l’heure actuelle.",
            "diagnosticPartialRange": "Seules les entrées encore disponibles dans la période choisie seront exportées.", "diagnosticExported": "Journaux de diagnostic exportés", "diagnosticExportFailed": "Impossible d’exporter les journaux de diagnostic.",
            "driveWorkingTimeDetail": "Le « temps de fonctionnement » est comptabilisé par le micrologiciel du disque et ne correspond pas au temps de démarrage ou d’utilisation du Mac. Le disque passe souvent en mode basse consommation ou veille, et ces périodes peuvent ne pas être comptées. La valeur affichée sous macOS peut donc être nettement inférieure à celle d’autres ordinateurs ; cela est généralement normal."
        ],
        .german: [
            "chargeProtection": "Batterieladeschutz", "chargeProtectionEnabled": "Ladeschutz aktivieren",
            "fixedChargeLimit": "Feste Ladegrenze", "chargeProtectionInstallNote": "Bei der ersten Aktivierung wird ein minimaler Helfer installiert und einmalig die Administratorberechtigung angefordert.",
            "macOS158ChargeLimitNotice": "Aktuelles System: macOS 15.8. Diese Systemversion unterstützt nur Apples native 80-%-Ladegrenze.", "macOS158Only80DisabledHint": "80 % wählen oder mit 100 % den Ladeschutz ausschalten.",
            "chargeProtectionUnsupportedIntel": "Der Batterieladeschutz ist auf Intel Macs nicht verfügbar.",
            "chargeProtectionNativeNotice": "Diese macOS-Version unterstützt Ladegrenzen bereits. Verwenden Sie zur Vermeidung von Konflikten die integrierte macOS-Funktion.",
            "chargeProtectionNativePath": "Systemeinstellungen → Batterie → Info neben „Laden“ → Ladegrenze",
            "openBatterySettings": "Batterieeinstellungen öffnen", "chargeToFullOnce": "Diesmal vollständig laden", "cancelFullCharge": "Vollständiges Laden abbrechen",
            "temporaryFullInProgress": "Diesmal wird bis 100 % geladen; anschließend wird die feste Grenze automatisch wiederhergestellt.",
            "chargeLimitReached": "Ladegrenze erreicht (%d%%)", "adjustFixedLimit": "Feste Ladegrenze anpassen",
            "chargeHelperUnavailable": "Die Firmware dieses Mac stellt keine unterstützte Ladesteuerung bereit.", "chargeHelperBusy": "Ladeschutz wird angewendet…",
            "chargeOperationFailed": "Der Ladeschutz konnte nicht angewendet werden. Das normale Laden durch das System bleibt verfügbar.",
            "uninstallChargeHelper": "Ladehelfer deaktivieren und deinstallieren", "uninstallChargeHelperConfirm": "Ladehelfer deaktivieren und deinstallieren?", "uninstallChargeHelperDetail": "Stellt normales Laden wieder her und entfernt danach den privilegierten Helfer, seinen launchd-Auftrag, den Menüleisten-Agent und den Ladesteuerungsstatus der App.",
            "chargeHelperAuthorizationTitle": "Administratorautorisierung erforderlich", "continueAuthorization": "Fortfahren",
            "chargeHelperInstallAuthorizationMessage": "Zur sicheren Installation oder Aktualisierung des Ladehelfers fragt macOS als Nächstes nach einem Administratorpasswort. Das Passwort wird nur von macOS geprüft; die App liest oder speichert es nicht.",
            "chargeHelperUninstallAuthorizationMessage": "Nach dem Fortfahren fragt macOS nach einem Administratorpasswort, um den privilegierten Helfer zu entfernen. Das Passwort wird nur von macOS geprüft; die App liest oder speichert es nicht.",
            "desktopMacMode": "Desktop-Mac-Modus", "desktopMacPoweredTitle": "Eingesteckt und voll einsatzbereit", "desktopMacPoweredDetail": "Dieser Mac ist ein Desktop-Computer und benötigt keine Batteriezustandsverwaltung.",
            "showChargeStatusInMenuBar": "Ladeschutzstatus in der Menüleiste anzeigen", "uninstallApplication": "App deinstallieren…", "deleteAllHistoryOnUninstall": "Auch alle Verlaufsberichte löschen", "uninstallApplicationDetail": "Stellt normales Laden wieder her, entfernt Helfer und Menüleistenkomponenten und bewegt die App in den Papierkorb.", "expandChargeProtection": "Ladeschutzeinstellungen einblenden", "collapseChargeProtection": "Ladeschutzeinstellungen ausblenden", "exportDiagnosticLogs": "Diagnoseprotokolle exportieren…",
            "intelChargingManagedTitle": "Das Laden dieses Mac wird von macOS verwaltet", "intelChargingManagedDetail": "Die festen Grenzen dieser App gelten derzeit für Macs mit Apple-Chip. macOS verwaltet das Laden weiterhin nach den Systemrichtlinien.",
            "nativeChargingAvailableTitle": "macOS bietet Ladegrenzen", "nativeChargingAvailableDetail": "Dieses System unterstützt feste Ladegrenzen. Für beste Systemkompatibilität wird die integrierte macOS-Funktion empfohlen.",
            "preferSoftwareChargingQuestion": "Soll weiterhin diese App die Ladegrenze verwalten?", "useSoftwareCharging": "Ladeschutz dieser App verwenden…",
            "softwareChargingPreparationTitle": "Laden mit dieser App verwalten", "softwareChargingPreparationIntro": "Damit macOS und die App das Laden nicht gleichzeitig steuern, führen Sie zuerst Folgendes aus:",
            "softwareChargingPreparationStep1": "1. macOS-Ladegrenze auf 100 % setzen", "softwareChargingPreparationStep2": "2. Optimiertes Laden deaktivieren",
            "softwareChargingPreparationReason": "So wird die App zum primären Controller und widersprüchliche Strategien werden vermieden.", "softwareChargingPreparationConfirmed": "Ich habe diese Einstellungen vorgenommen",
            "continueSoftwareCharging": "Mit dieser App fortfahren", "switchToSystemCharging": "macOS-Systemfunktion verwenden", "softwareManagedReminder": "Diese App verwaltet die Grenze. Lassen Sie macOS auf 100 % und deaktivieren Sie optimiertes Laden.",
            "chargeMigrationTitle": "macOS unterstützt jetzt Ladegrenzen", "chargeMigrationMessage": "Nach dem Update bietet macOS feste Ladegrenzen. Die Systemfunktion wird empfohlen, damit nicht zwei Strategien gleichzeitig laufen.",
            "diagnosticExportTitle": "Diagnoseprotokolle exportieren", "diagnosticStartTime": "Startzeit", "diagnosticEndTime": "Endzeit", "diagnosticExport": "Exportieren…",
            "diagnosticLast15Minutes": "Letzte 15 Minuten", "diagnosticLastHour": "Letzte Stunde", "diagnosticLast24Hours": "Letzte 24 Stunden",
            "diagnosticInvalidRange": "Die Startzeit darf nicht nach der Endzeit liegen.", "diagnosticFutureEnd": "Die Endzeit darf nicht nach der aktuellen Zeit liegen.",
            "diagnosticPartialRange": "Nur noch vorhandene Einträge im gewählten Zeitraum werden exportiert.", "diagnosticExported": "Diagnoseprotokolle exportiert", "diagnosticExportFailed": "Diagnoseprotokolle konnten nicht exportiert werden.",
            "driveWorkingTimeDetail": "Die „Betriebszeit“ wird von der Laufwerksfirmware gezählt und entspricht nicht der Einschalt- oder Nutzungsdauer des Mac. Im Alltag befindet sich das Laufwerk häufig im Energiespar- oder Bereitschaftsmodus; diese Zeit wird möglicherweise nicht erfasst. Daher kann die unter macOS angezeigte Betriebszeit deutlich kürzer sein als bei anderen Computern; dies ist normalerweise unbedenklich."
        ],
        .korean: [
            "chargeProtection": "배터리 충전 보호", "chargeProtectionEnabled": "충전 보호 활성화",
            "fixedChargeLimit": "고정 충전 한도", "chargeProtectionInstallNote": "처음 활성화할 때 최소 권한 도우미를 설치하며 관리자 권한을 한 번만 요청합니다.",
            "macOS158ChargeLimitNotice": "현재 시스템은 macOS 15.8입니다. 이 시스템 버전은 Apple의 기본 80% 충전 한도만 지원합니다.", "macOS158Only80DisabledHint": "80%를 선택하거나 100%로 충전 보호를 끄십시오.",
            "chargeProtectionUnsupportedIntel": "Intel Mac에서는 배터리 충전 보호를 사용할 수 없습니다.",
            "chargeProtectionNativeNotice": "현재 macOS는 충전 한도를 기본 지원합니다. 시스템 배터리 관리와의 충돌을 피하려면 macOS 내장 기능을 사용하십시오.",
            "chargeProtectionNativePath": "시스템 설정 → 배터리 → 충전 옆 정보 → 충전 한도",
            "openBatterySettings": "배터리 설정 열기", "chargeToFullOnce": "이번에 완전히 충전", "cancelFullCharge": "완전 충전 취소",
            "temporaryFullInProgress": "이번에는 100%까지 충전한 후 고정 한도가 자동으로 복원됩니다.",
            "chargeLimitReached": "설정한 충전량에 도달함(%d%%)", "adjustFixedLimit": "고정 충전 한도 조절",
            "chargeHelperUnavailable": "이 Mac의 펌웨어에서 지원되는 충전 제어 방법을 제공하지 않습니다.", "chargeHelperBusy": "충전 보호 적용 중…",
            "chargeOperationFailed": "충전 보호를 적용할 수 없습니다. 시스템의 정상 충전 기능은 계속 사용할 수 있습니다.",
            "uninstallChargeHelper": "충전 도우미 비활성화 및 제거", "uninstallChargeHelperConfirm": "충전 도우미를 비활성화하고 제거하시겠습니까?", "uninstallChargeHelperDetail": "정상 충전을 복원한 다음 권한 도우미, launchd 작업, 메뉴 막대 에이전트와 이 앱의 충전 제어 상태를 제거합니다.",
            "chargeHelperAuthorizationTitle": "관리자 승인 필요", "continueAuthorization": "계속",
            "chargeHelperInstallAuthorizationMessage": "충전 도우미를 안전하게 설치하거나 업데이트하기 위해 macOS가 다음 단계에서 관리자 암호를 요청합니다. 암호는 macOS만 확인하며 이 앱은 읽거나 저장하지 않습니다.",
            "chargeHelperUninstallAuthorizationMessage": "계속하면 특권 도우미를 제거하기 위해 macOS가 관리자 암호를 요청합니다. 암호는 macOS만 확인하며 이 앱은 읽거나 저장하지 않습니다.",
            "desktopMacMode": "데스크톱 Mac 모드", "desktopMacPoweredTitle": "전원만 연결하면 완전 충전", "desktopMacPoweredDetail": "이 Mac은 데스크톱 컴퓨터이므로 배터리 상태 관리가 필요하지 않습니다.",
            "showChargeStatusInMenuBar": "메뉴 막대에 충전 보호 상태 표시", "uninstallApplication": "앱 제거…", "deleteAllHistoryOnUninstall": "모든 기록 보고서도 삭제", "uninstallApplicationDetail": "정상 충전을 복원하고 설치된 도우미와 메뉴 막대 구성 요소를 제거한 다음 앱을 휴지통으로 이동합니다.", "expandChargeProtection": "충전 보호 설정 펼치기", "collapseChargeProtection": "충전 보호 설정 접기", "exportDiagnosticLogs": "진단 로그 내보내기…",
            "intelChargingManagedTitle": "이 Mac의 배터리 충전은 macOS가 관리합니다", "intelChargingManagedDetail": "이 앱의 고정 충전 한도는 현재 Apple Silicon Mac에 적용됩니다. macOS가 시스템 배터리 정책에 따라 충전을 계속 관리합니다.",
            "nativeChargingAvailableTitle": "macOS가 충전 한도를 제공합니다", "nativeChargingAvailableDetail": "현재 시스템은 고정 충전 한도를 지원합니다. 최상의 호환성을 위해 macOS 내장 기능을 우선 사용하는 것이 좋습니다.",
            "preferSoftwareChargingQuestion": "그래도 이 앱으로 충전 한도를 관리하시겠습니까?", "useSoftwareCharging": "이 앱의 충전 보호 사용…",
            "softwareChargingPreparationTitle": "이 앱으로 충전 관리", "softwareChargingPreparationIntro": "macOS와 앱이 동시에 충전을 제어하지 않도록 먼저 다음 설정을 완료하십시오:",
            "softwareChargingPreparationStep1": "1. macOS 충전 한도를 100%로 설정", "softwareChargingPreparationStep2": "2. 최적화된 배터리 충전 끄기",
            "softwareChargingPreparationReason": "이 앱을 주 제어기로 사용하여 충전 정책 충돌을 피할 수 있습니다.", "softwareChargingPreparationConfirmed": "위 설정을 완료했습니다",
            "continueSoftwareCharging": "이 앱 계속 사용", "switchToSystemCharging": "macOS 시스템 기능 사용", "softwareManagedReminder": "현재 이 앱이 충전 한도를 관리합니다. macOS 한도는 100%로 유지하고 최적화된 충전을 끄십시오.",
            "chargeMigrationTitle": "이제 macOS가 충전 한도를 지원합니다", "chargeMigrationMessage": "시스템 업데이트 후 macOS가 고정 충전 한도를 제공합니다. 두 정책의 동시 실행을 피하려면 시스템 기능을 권장합니다.",
            "diagnosticExportTitle": "진단 로그 내보내기", "diagnosticStartTime": "시작 시간", "diagnosticEndTime": "종료 시간", "diagnosticExport": "내보내기…",
            "diagnosticLast15Minutes": "최근 15분", "diagnosticLastHour": "최근 1시간", "diagnosticLast24Hours": "최근 24시간",
            "diagnosticInvalidRange": "시작 시간은 종료 시간보다 늦을 수 없습니다.", "diagnosticFutureEnd": "종료 시간은 현재 시간보다 늦을 수 없습니다.",
            "diagnosticPartialRange": "선택한 기간 중 보관 중인 로그 항목만 내보냅니다.", "diagnosticExported": "진단 로그를 내보냈습니다", "diagnosticExportFailed": "진단 로그를 내보낼 수 없습니다.",
            "driveWorkingTimeDetail": "‘사용 시간’은 드라이브 펌웨어가 집계하며 Mac의 실제 켜진 시간이나 사용 시간과 같지 않습니다. 일상적으로 드라이브는 저전력 또는 대기 상태에 자주 머물며 이 시간은 집계되지 않을 수 있습니다. 따라서 macOS에 표시되는 사용 시간이 다른 컴퓨터보다 현저히 짧을 수 있으며, 대개 정상입니다."
        ],
        .japanese: [
            "chargeProtection": "バッテリー充電保護", "chargeProtectionEnabled": "充電保護を有効にする",
            "fixedChargeLimit": "固定充電上限", "chargeProtectionInstallNote": "初回の有効化時に最小構成のヘルパーをインストールし、管理者権限を一度だけ求めます。",
            "macOS158ChargeLimitNotice": "現在のシステムは macOS 15.8 です。このシステムバージョンは Apple ネイティブの 80% 充電上限のみ対応します。", "macOS158Only80DisabledHint": "80% を選ぶか、100% で充電保護をオフにします。",
            "chargeProtectionUnsupportedIntel": "Intel Mac ではバッテリー充電保護を利用できません。",
            "chargeProtectionNativeNotice": "現在の macOS は充電上限に標準対応しています。システムのバッテリー管理との競合を避けるため、macOS の標準機能を使用してください。",
            "chargeProtectionNativePath": "システム設定 → バッテリー →「充電」の横の情報 → 充電上限",
            "openBatterySettings": "バッテリー設定を開く", "chargeToFullOnce": "今回だけ満充電", "cancelFullCharge": "満充電をキャンセル",
            "temporaryFullInProgress": "今回は 100% まで充電し、完了後に固定上限へ自動的に戻ります。",
            "chargeLimitReached": "設定した充電量に到達（%d%%）", "adjustFixedLimit": "固定充電上限を調整",
            "chargeHelperUnavailable": "この Mac のファームウェアは対応する充電制御方法を公開していません。", "chargeHelperBusy": "充電保護を適用中…",
            "chargeOperationFailed": "充電保護を適用できませんでした。システムの通常の充電機能は引き続き利用できます。",
            "uninstallChargeHelper": "充電ヘルパーを停止してアンインストール", "uninstallChargeHelperConfirm": "充電ヘルパーを停止してアンインストールしますか？", "uninstallChargeHelperDetail": "通常の充電を復元してから、特権ヘルパー、launchd ジョブ、メニューバー Agent、およびこのアプリの充電制御状態を削除します。",
            "chargeHelperAuthorizationTitle": "管理者の認証が必要です", "continueAuthorization": "続ける",
            "chargeHelperInstallAuthorizationMessage": "充電ヘルパーを安全にインストールまたは更新するため、次に macOS が管理者パスワードを求めます。パスワードは macOS のみが確認し、このアプリが読み取ったり保存したりすることはありません。",
            "chargeHelperUninstallAuthorizationMessage": "続けると、特権ヘルパーを削除するために macOS が管理者パスワードを求めます。パスワードは macOS のみが確認し、このアプリが読み取ったり保存したりすることはありません。",
            "desktopMacMode": "デスクトップ Mac モード", "desktopMacPoweredTitle": "電源接続でいつでも全開", "desktopMacPoweredDetail": "この Mac はデスクトップコンピュータのため、バッテリー健康管理は必要ありません。",
            "showChargeStatusInMenuBar": "充電保護の状態をメニューバーに表示", "uninstallApplication": "アプリをアンインストール…", "deleteAllHistoryOnUninstall": "すべての履歴レポートも削除", "uninstallApplicationDetail": "通常の充電を復元し、インストール済みのヘルパーとメニューバー項目を削除して、アプリをゴミ箱に移動します。", "expandChargeProtection": "充電保護設定を展開", "collapseChargeProtection": "充電保護設定を折りたたむ", "exportDiagnosticLogs": "診断ログを書き出す…",
            "intelChargingManagedTitle": "この Mac の充電は macOS が管理します", "intelChargingManagedDetail": "このアプリの固定充電上限は現在 Apple シリコン Mac が対象です。macOS がシステムのバッテリー方針に従って充電を管理します。",
            "nativeChargingAvailableTitle": "macOS は充電上限に対応しています", "nativeChargingAvailableDetail": "このシステムは固定充電上限に対応しています。最良の互換性のため macOS 標準機能を優先してください。",
            "preferSoftwareChargingQuestion": "引き続きこのアプリで充電上限を管理しますか？", "useSoftwareCharging": "このアプリの充電保護を使用…",
            "softwareChargingPreparationTitle": "このアプリで充電を管理", "softwareChargingPreparationIntro": "macOS とアプリが同時に制御しないよう、先に次の設定を完了してください：",
            "softwareChargingPreparationStep1": "1. macOS の充電上限を 100% に設定", "softwareChargingPreparationStep2": "2. バッテリー充電の最適化をオフ",
            "softwareChargingPreparationReason": "このアプリを主な固定上限コントローラとして使い、充電方針の競合を避けられます。", "softwareChargingPreparationConfirmed": "上記の設定を完了しました",
            "continueSoftwareCharging": "このアプリを使い続ける", "switchToSystemCharging": "macOS のシステム機能を使用", "softwareManagedReminder": "現在はこのアプリが上限を管理しています。macOS の上限を 100% に保ち、最適化充電をオフにしてください。",
            "chargeMigrationTitle": "macOS が充電上限に対応しました", "chargeMigrationMessage": "更新後の macOS は固定充電上限に対応しています。2つの方針を同時に動かさないため、システム機能を推奨します。",
            "diagnosticExportTitle": "診断ログを書き出す", "diagnosticStartTime": "開始時刻", "diagnosticEndTime": "終了時刻", "diagnosticExport": "書き出す…",
            "diagnosticLast15Minutes": "過去 15 分", "diagnosticLastHour": "過去 1 時間", "diagnosticLast24Hours": "過去 24 時間",
            "diagnosticInvalidRange": "開始時刻を終了時刻より後には設定できません。", "diagnosticFutureEnd": "終了時刻を現在より後には設定できません。",
            "diagnosticPartialRange": "選択した期間内で保持されているログだけを書き出します。", "diagnosticExported": "診断ログを書き出しました", "diagnosticExportFailed": "診断ログを書き出せませんでした。",
            "driveWorkingTimeDetail": "「使用時間」はドライブのファームウェアが集計する値で、Mac の起動時間や実際の使用時間とは同じではありません。日常使用中、ドライブは低電力または待機状態に頻繁に入り、その時間は集計されない場合があります。そのため macOS で表示される時間が他のコンピュータより明らかに短くても、通常は正常です。"
        ]
    ]
}
