import Foundation

enum L10n {
    static func languageName(_ language: AppLanguage, in displayLanguage: AppLanguage) -> String {
        if language == .system { return text("systemLanguage", displayLanguage) }
        let locale = Locale(identifier: effective(displayLanguage).rawValue)
        return locale.localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
    }

    static func text(_ key: String, _ selected: AppLanguage) -> String {
        let language = effective(selected)
        return tables[language]?[key]
            ?? historyActionTables[language]?[key]
            ?? menuActionTables[language]?[key]
            ?? tables[.english]?[key]
            ?? historyActionTables[.english]?[key]
            ?? menuActionTables[.english]?[key]
            ?? key
    }

    static func format(_ key: String, _ selected: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, selected), locale: Locale(identifier: effective(selected).rawValue), arguments: arguments)
    }

    static func effective(_ language: AppLanguage) -> AppLanguage {
        language == .system ? .detected() : language
    }

    static func missingTranslationKeys(for language: AppLanguage) -> [String] {
        let selected = effective(language)
        let reference = Set(
            (tables[.english]?.keys.map { $0 } ?? [])
                + (historyActionTables[.english]?.keys.map { $0 } ?? [])
                + (menuActionTables[.english]?.keys.map { $0 } ?? [])
        )
        let tableKeys = tables[selected]?.keys.map { $0 } ?? [String]()
        let actionKeys = historyActionTables[selected]?.keys.map { $0 } ?? [String]()
        let menuKeys = menuActionTables[selected]?.keys.map { $0 } ?? [String]()
        let translated = Set(tableKeys + actionKeys + menuKeys)
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
            "unsafeShutdowns": "Unsafe shutdowns", "mediaErrors": "Media errors", "internal": "Internal", "solidState": "Solid state",
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
            "unsafeShutdowns": "异常关机次数", "mediaErrors": "介质错误", "internal": "内置设备", "solidState": "固态硬盘",
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
            "health": "Состояние", "good": "Хорошо", "warning": "Внимание", "critical": "Критично", "unknown": "Недоступно", "model": "Модель", "capacity": "Ёмкость", "protocol": "Подключение", "firmware": "Прошивка", "serialNumber": "Серийный номер", "smartStatus": "Статус S.M.A.R.T.", "lifeRemaining": "Оценка остаточного ресурса", "temperature": "Температура", "powerOnHours": "Время работы", "powerCycles": "Циклы питания", "totalRead": "Всего прочитано", "totalWritten": "Всего записано", "unsafeShutdowns": "Небезопасные выключения", "mediaErrors": "Ошибки носителя", "internal": "Внутренний", "solidState": "SSD",
            "manufacturer": "Производитель", "chemistry": "Тип батареи", "designCapacity": "Проектная ёмкость", "fullChargeCapacity": "Полная ёмкость", "currentCharge": "Текущий заряд", "cycleCount": "Число циклов", "batteryVoltage": "Напряжение батареи", "charging": "Заряжается", "connected": "Питание подключено", "yes": "Да", "no": "Нет", "unavailable": "Нет данных", "hours": "%llu ч", "mAh": "%d мА·ч", "percent": "%.0f%%",
            "report": "Отчёт о состоянии", "generated": "Создан", "computer": "Компьютер", "systemNotes": "Примечания системы", "privacyNotice": "При включении серийные номера скрываются в интерфейсе, истории и экспортируемых отчётах.", "systemLimitations": "macOS не предоставляет обычным приложениям все счётчики NVMe/USB S.M.A.R.T.; недоступные значения не оцениваются.",
            "historyEmpty": "Нет сохранённых отчётов", "historyEmptyDetail": "Отчёты можно сохранять после обновления или только при экспорте.", "select": "Выбрать", "selectAll": "Выбрать все", "deselectAll": "Снять выбор", "exportSelected": "Экспортировать выбранные", "deleteSelected": "Удалить выбранные", "deleteSelectedConfirm": "Удалить выбранные отчёты?", "deleteSelectedDetail": "Выбранные отчёты будут удалены с этого Mac.", "batchExported": "Выбранные отчёты экспортированы", "sourceRefresh": "Сохранено после обновления", "sourceExport": "Сохранено при экспорте", "delete": "Удалить", "deleteConfirm": "Удалить этот отчёт?", "deleteDetail": "Сохранённая запись будет удалена; экспортированный файл останется.", "showInFinder": "Показать в Finder", "chooseFolder": "Выбрать…", "openFolder": "Открыть папку", "historyLocation": "Папка истории", "saveMode": "Сохранение отчётов", "saveOnRefresh": "После каждого обновления", "saveOnExport": "Только при экспорте", "language": "Язык", "hideSerials": "Скрывать серийные номера", "reportTextSize": "Размер текста отчёта", "appearance": "Вид и конфиденциальность", "storage": "Хранилище истории", "dataAccess": "Доступ к данным оборудования",
            "aboutSummary": "Лёгкая утилита только для чтения: состояние накопителей и батареи, история отчётов и изменения со временем.", "developer": "Разработчик", "author": "ChengXin", "projectHome": "Страница проекта", "issueFeedback": "Ошибки и предложения", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ-группа · 1040456137", "email": "Email · 2680149724@qq.com", "copyright": "© 2026 ChengXin. Все права защищены.", "version": "Версия %@", "changelog": "Журнал изменений", "license": "Лицензия GNU GPL v3", "readOnlyNote": "Приложение только читает данные и не выполняет тесты, запись, ремонт, стирание или обновление прошивки.", "permissionNote": "Некоторые внешние накопители и фирменные счётчики могут быть недоступны из-за macOS, контроллера или USB-корпуса.", "scanFailed": "Не удалось завершить сканирование: %@", "copied": "Отчёт скопирован", "exported": "Отчёт экспортирован", "done": "Готово", "cancel": "Отмена"
        ],
        .french: [
            "overviewLimitations": "L’app affiche toutes les informations fournies par macOS et l’appareil. La température, le temps de fonctionnement et les volumes lus/écrits peuvent manquer selon le disque ou la connexion.", "driveWorkingTimeExplanation": "Cette valeur est comptabilisée par le micrologiciel du disque et peut exclure les périodes où le contrôleur est en mode basse consommation. Elle ne correspond pas à la durée de mise sous tension ou d’utilisation réelle de l’ordinateur.", "batteryHealthExplanation": "La santé de la batterie utilise la capacité maximale étalonnée par macOS. Température, gestion de la charge, étalonnage et arrondi peuvent créer un léger écart avec le simple calcul capacité pleine ÷ capacité nominale.", "powerConnectedNotCharging": "L’alimentation est connectée. La batterie est pleine ou macOS alimente temporairement le Mac directement.", "internalBattery": "Batterie lithium-ion interne",
            "appName": "État des disques et de la batterie", "systemLanguage": "Langue du système", "overview": "Aperçu", "history": "Historique", "settings": "Réglages", "about": "À propos", "menuFile": "Fichier", "menuEdit": "Édition", "menuView": "Présentation", "menuWindow": "Fenêtre", "menuHelp": "Aide", "refresh": "Actualiser", "refreshing": "Analyse…", "exportReport": "Exporter le rapport", "copyReport": "Copier le rapport", "lastUpdated": "Mis à jour %@", "noScan": "Aucun rapport", "noScanDetail": "Actualisez pour lire les informations de ce Mac.", "drives": "Disques", "batteries": "Batterie", "noDrives": "Aucun disque physique signalé.", "noBattery": "Ce Mac ne possède pas de batterie.",
            "health": "Santé", "good": "Bon", "warning": "Attention", "critical": "Critique", "unknown": "Indisponible", "model": "Modèle", "capacity": "Capacité", "protocol": "Connexion", "firmware": "Micrologiciel", "serialNumber": "Numéro de série", "smartStatus": "État S.M.A.R.T.", "lifeRemaining": "Durée de vie restante estimée", "temperature": "Température", "powerOnHours": "Temps de fonctionnement", "powerCycles": "Cycles d’alimentation", "totalRead": "Total lu", "totalWritten": "Total écrit", "unsafeShutdowns": "Arrêts non sécurisés", "mediaErrors": "Erreurs du support", "internal": "Interne", "solidState": "SSD", "manufacturer": "Fabricant", "chemistry": "Type de batterie", "designCapacity": "Capacité nominale", "fullChargeCapacity": "Capacité à pleine charge", "currentCharge": "Charge actuelle", "cycleCount": "Nombre de cycles", "batteryVoltage": "Tension de la batterie", "charging": "En charge", "connected": "Alimentation connectée", "yes": "Oui", "no": "Non", "unavailable": "Non indiqué", "hours": "%llu heures", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "Rapport de santé", "generated": "Généré", "computer": "Ordinateur", "systemNotes": "Notes système", "privacyNotice": "Si activé, les numéros de série sont masqués dans l’interface, l’historique et les exports.", "systemLimitations": "macOS n’expose pas tous les compteurs S.M.A.R.T. NVMe/USB ; les valeurs indisponibles ne sont pas estimées.", "historyEmpty": "Aucun rapport enregistré", "historyEmptyDetail": "Enregistrez après chaque actualisation ou uniquement lors de l’export.", "sourceRefresh": "Enregistré après actualisation", "sourceExport": "Enregistré lors de l’export", "delete": "Supprimer", "deleteConfirm": "Supprimer ce rapport ?", "deleteDetail": "Le rapport enregistré sera supprimé, mais pas le fichier texte exporté.", "showInFinder": "Afficher dans le Finder", "chooseFolder": "Choisir…", "openFolder": "Ouvrir le dossier", "historyLocation": "Dossier de l’historique", "saveMode": "Enregistrer les rapports", "saveOnRefresh": "Après chaque actualisation", "saveOnExport": "Uniquement lors de l’export", "language": "Langue", "hideSerials": "Masquer les numéros de série", "reportTextSize": "Taille du rapport", "appearance": "Apparence et confidentialité", "storage": "Stockage de l’historique", "dataAccess": "Accès aux données matérielles", "aboutSummary": "Un utilitaire léger en lecture seule pour consulter l’état des disques et de la batterie et suivre leur évolution.", "developer": "Développeur", "author": "ChengXin", "projectHome": "Page du projet", "issueFeedback": "Problèmes et suggestions", "coolapk": "Coolapk · 程心ChengXin", "qq": "Groupe QQ · 1040456137", "email": "E-mail · 2680149724@qq.com", "copyright": "© 2026 ChengXin. Tous droits réservés.", "version": "Version %@", "changelog": "Notes de version", "license": "Licence GNU GPL v3", "readOnlyNote": "Cette app lit uniquement les informations ; aucun test, écriture, réparation, effacement ou micrologiciel.", "permissionNote": "Certains disques externes et compteurs constructeur peuvent être indisponibles selon macOS, le contrôleur ou le boîtier USB.", "scanFailed": "Analyse impossible : %@", "copied": "Rapport copié", "exported": "Rapport exporté", "done": "Terminé", "cancel": "Annuler"
        ],
        .german: [
            "overviewLimitations": "Die App zeigt alle von macOS und dem Gerät bereitgestellten Informationen. Temperatur, Betriebszeit und gesamte Lese-/Schreibmengen können je nach Laufwerk oder Verbindung fehlen.", "driveWorkingTimeExplanation": "Dieser Wert wird von der Laufwerksfirmware erfasst und kann Zeiten ausschließen, in denen sich der Controller im Energiesparmodus befindet. Er entspricht nicht der Einschalt- oder tatsächlichen Nutzungsdauer des Computers.", "batteryHealthExplanation": "Der Akkuzustand verwendet die von macOS kalibrierte Maximalkapazität. Temperatur, Lademanagement, Kalibrierung und Rundung können zu kleinen Abweichungen von Vollladung ÷ Designkapazität führen.", "powerConnectedNotCharging": "Das Netzteil ist verbunden. Der Akku ist voll oder macOS versorgt den Mac vorübergehend direkt mit Strom.", "internalBattery": "Interner Lithium-Ionen-Akku",
            "appName": "Laufwerks- und Akkuzustand", "systemLanguage": "Systemsprache", "overview": "Übersicht", "history": "Verlauf", "settings": "Einstellungen", "about": "Info", "menuFile": "Ablage", "menuEdit": "Bearbeiten", "menuView": "Darstellung", "menuWindow": "Fenster", "menuHelp": "Hilfe", "refresh": "Aktualisieren", "refreshing": "Analyse läuft…", "exportReport": "Bericht exportieren", "copyReport": "Bericht kopieren", "lastUpdated": "Aktualisiert %@", "noScan": "Noch kein Zustandsbericht", "noScanDetail": "Aktualisieren Sie die Laufwerks- und Akkuinformationen dieses Mac.", "drives": "Laufwerke", "batteries": "Akku", "noDrives": "Keine physischen Laufwerke gemeldet.", "noBattery": "Dieser Mac hat keinen Akku.",
            "health": "Zustand", "good": "Gut", "warning": "Achtung", "critical": "Kritisch", "unknown": "Nicht verfügbar", "model": "Modell", "capacity": "Kapazität", "protocol": "Verbindung", "firmware": "Firmware", "serialNumber": "Seriennummer", "smartStatus": "S.M.A.R.T.-Status", "lifeRemaining": "Geschätzte Restlebensdauer", "temperature": "Temperatur", "powerOnHours": "Betriebszeit", "powerCycles": "Einschaltvorgänge", "totalRead": "Insgesamt gelesen", "totalWritten": "Insgesamt geschrieben", "unsafeShutdowns": "Unsichere Abschaltungen", "mediaErrors": "Medienfehler", "internal": "Intern", "solidState": "SSD", "manufacturer": "Hersteller", "chemistry": "Akkutyp", "designCapacity": "Designkapazität", "fullChargeCapacity": "Volle Ladekapazität", "currentCharge": "Aktueller Ladestand", "cycleCount": "Ladezyklen", "batteryVoltage": "Akkuspannung", "charging": "Wird geladen", "connected": "Netzteil verbunden", "yes": "Ja", "no": "Nein", "unavailable": "Nicht gemeldet", "hours": "%llu Stunden", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "Zustandsbericht", "generated": "Erstellt", "computer": "Computer", "systemNotes": "Systemhinweise", "privacyNotice": "Bei Aktivierung werden Seriennummern in Oberfläche, Verlauf und Exporten verborgen.", "systemLimitations": "macOS stellt normalen Apps nicht alle NVMe/USB-S.M.A.R.T.-Werte bereit; fehlende Werte werden nicht geschätzt.", "historyEmpty": "Keine gespeicherten Berichte", "historyEmptyDetail": "Berichte nach jeder Aktualisierung oder nur beim Export speichern.", "sourceRefresh": "Nach Aktualisierung gespeichert", "sourceExport": "Beim Export gespeichert", "delete": "Löschen", "deleteConfirm": "Diesen Bericht löschen?", "deleteDetail": "Der gespeicherte Bericht wird gelöscht; exportierte Textdateien bleiben erhalten.", "showInFinder": "Im Finder zeigen", "chooseFolder": "Auswählen…", "openFolder": "Ordner öffnen", "historyLocation": "Verlaufsordner", "saveMode": "Berichte speichern", "saveOnRefresh": "Nach jeder Aktualisierung", "saveOnExport": "Nur beim Export", "language": "Sprache", "hideSerials": "Seriennummern ausblenden", "reportTextSize": "Berichtsschriftgröße", "appearance": "Darstellung und Datenschutz", "storage": "Verlaufsspeicher", "dataAccess": "Hardware-Datenzugriff", "aboutSummary": "Ein schlankes Nur-Lese-Werkzeug für Laufwerks- und Akkuzustand mit Berichtsverlauf.", "developer": "Entwickler", "author": "ChengXin", "projectHome": "Projektseite", "issueFeedback": "Probleme und Vorschläge", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ-Gruppe · 1040456137", "email": "E-Mail · 2680149724@qq.com", "copyright": "© 2026 ChengXin. Alle Rechte vorbehalten.", "version": "Version %@", "changelog": "Versionshinweise", "license": "GNU-GPL-v3-Lizenz", "readOnlyNote": "Die App liest nur Informationen und führt keine Tests, Schreib-, Reparatur-, Lösch- oder Firmwarevorgänge aus.", "permissionNote": "Einige externe Laufwerke und Herstellerwerte können wegen macOS, Controller oder USB-Gehäuse fehlen.", "scanFailed": "Analyse fehlgeschlagen: %@", "copied": "Bericht kopiert", "exported": "Bericht exportiert", "done": "Fertig", "cancel": "Abbrechen"
        ],
        .korean: [
            "overviewLimitations": "macOS와 장치가 제공하는 정보는 모두 표시합니다. 드라이브나 연결 방식에 따라 온도, 사용 시간, 누적 읽기·쓰기 양은 제공되지 않을 수 있습니다.", "driveWorkingTimeExplanation": "이 값은 드라이브 펌웨어가 집계하며 컨트롤러가 저전력 상태인 시간은 포함하지 않을 수 있습니다. 컴퓨터가 켜져 있거나 실제로 사용된 시간과 같지 않습니다.", "batteryHealthExplanation": "배터리 건강도는 macOS가 보정한 최대 용량을 따릅니다. 온도, 충전 관리, 시스템 보정 및 반올림 때문에 완전 충전 용량 ÷ 설계 용량 계산과 약간 다를 수 있습니다.", "powerConnectedNotCharging": "전원이 연결되어 있습니다. 배터리가 가득 찼거나 macOS가 일시적으로 Mac에 직접 전원을 공급합니다.", "internalBattery": "내장 리튬 이온 배터리",
            "appName": "드라이브 및 배터리 상태 보기", "systemLanguage": "시스템 언어", "overview": "개요", "history": "기록", "settings": "설정", "about": "정보", "menuFile": "파일", "menuEdit": "편집", "menuView": "보기", "menuWindow": "윈도우", "menuHelp": "도움말", "refresh": "새로 고침", "refreshing": "검사 중…", "exportReport": "보고서 내보내기", "copyReport": "보고서 복사", "lastUpdated": "%@ 업데이트", "noScan": "아직 상태 보고서가 없습니다", "noScanDetail": "새로 고쳐 이 Mac의 드라이브와 배터리 정보를 읽으십시오.", "drives": "드라이브", "batteries": "배터리", "noDrives": "보고된 물리 드라이브가 없습니다.", "noBattery": "이 Mac에는 배터리가 없습니다.",
            "health": "건강", "good": "좋음", "warning": "주의", "critical": "심각", "unknown": "사용할 수 없음", "model": "모델", "capacity": "용량", "protocol": "연결", "firmware": "펌웨어", "serialNumber": "일련번호", "smartStatus": "S.M.A.R.T. 상태", "lifeRemaining": "예상 남은 수명", "temperature": "온도", "powerOnHours": "사용 시간", "powerCycles": "전원 켠 횟수", "totalRead": "총 읽기", "totalWritten": "총 쓰기", "unsafeShutdowns": "비정상 종료", "mediaErrors": "미디어 오류", "internal": "내장", "solidState": "SSD", "manufacturer": "제조사", "chemistry": "배터리 유형", "designCapacity": "설계 용량", "fullChargeCapacity": "완전 충전 용량", "currentCharge": "현재 충전량", "cycleCount": "사이클 수", "batteryVoltage": "배터리 전압", "charging": "충전 중", "connected": "전원 연결", "yes": "예", "no": "아니요", "unavailable": "보고되지 않음", "hours": "%llu시간", "mAh": "%d mAh", "percent": "%.0f%%",
            "report": "상태 보고서", "generated": "생성", "computer": "컴퓨터", "systemNotes": "시스템 안내", "privacyNotice": "활성화하면 화면, 기록, 복사 및 내보낸 보고서에서 일련번호를 숨깁니다.", "systemLimitations": "macOS는 일반 앱에 모든 NVMe/USB S.M.A.R.T. 값을 공개하지 않으며, 누락된 값은 추정하지 않습니다.", "historyEmpty": "저장된 보고서 없음", "historyEmptyDetail": "새로 고칠 때마다 또는 내보낼 때만 저장할 수 있습니다.", "sourceRefresh": "새로 고침 후 저장", "sourceExport": "내보낼 때 저장", "delete": "삭제", "deleteConfirm": "이 보고서를 삭제할까요?", "deleteDetail": "저장된 기록만 삭제되며 내보낸 텍스트 파일은 유지됩니다.", "showInFinder": "Finder에서 보기", "chooseFolder": "선택…", "openFolder": "폴더 열기", "historyLocation": "기록 위치", "saveMode": "보고서 저장", "saveOnRefresh": "새로 고칠 때마다", "saveOnExport": "내보낼 때만", "language": "언어", "hideSerials": "일련번호 숨기기", "reportTextSize": "보고서 글자 크기", "appearance": "모양 및 개인정보", "storage": "기록 저장소", "dataAccess": "하드웨어 데이터 접근", "aboutSummary": "드라이브와 배터리 상태를 읽기 전용으로 확인하고 시간에 따른 변화를 기록하는 가벼운 도구입니다.", "developer": "개발자", "author": "ChengXin", "projectHome": "프로젝트 홈페이지", "issueFeedback": "문제 및 제안", "coolapk": "Coolapk · 程心ChengXin", "qq": "QQ 그룹 · 1040456137", "email": "이메일 · 2680149724@qq.com", "copyright": "© 2026 ChengXin. All rights reserved.", "version": "버전 %@", "changelog": "업데이트 기록", "license": "GNU GPL v3 라이선스", "readOnlyNote": "이 앱은 정보만 읽으며 테스트, 쓰기, 복구, 삭제 또는 펌웨어 업데이트를 하지 않습니다.", "permissionNote": "외장 드라이브와 제조사 전용 값은 macOS, 컨트롤러 또는 USB 케이스 때문에 제공되지 않을 수 있습니다.", "scanFailed": "검사를 완료할 수 없습니다: %@", "copied": "보고서를 복사했습니다", "exported": "보고서를 내보냈습니다", "done": "완료", "cancel": "취소"
        ],
        .japanese: [
            "overviewLimitations": "macOS とデバイスが提供できる情報をすべて表示しています。ドライブや接続方法によっては、温度、使用時間、累積読み書き量を取得できません。", "driveWorkingTimeExplanation": "この値はドライブのファームウェアが集計し、コントローラが低電力状態にある時間を含まない場合があります。コンピュータの起動時間や実際の使用時間とは一致しません。", "batteryHealthExplanation": "バッテリーの健康度は macOS が校正した最大容量に基づきます。温度、充電管理、校正、丸めにより、満充電容量÷設計容量の単純計算と少し異なる場合があります。", "powerConnectedNotCharging": "電源に接続されています。バッテリーが満充電か、macOS が一時的に Mac へ直接給電しています。", "internalBattery": "内蔵リチウムイオンバッテリー",
            "appName": "ドライブとバッテリーの状態", "systemLanguage": "システム言語", "overview": "概要", "history": "履歴", "settings": "設定", "about": "このアプリについて", "menuFile": "ファイル", "menuEdit": "編集", "menuView": "表示", "menuWindow": "ウインドウ", "menuHelp": "ヘルプ", "refresh": "更新", "refreshing": "検査中…", "exportReport": "レポートを書き出す", "copyReport": "レポートをコピー", "lastUpdated": "%@ に更新", "noScan": "健康レポートはまだありません", "noScanDetail": "更新して、この Mac のドライブとバッテリー情報を読み取ります。", "drives": "ドライブ", "batteries": "バッテリー", "noDrives": "物理ドライブが報告されませんでした。", "noBattery": "この Mac にバッテリーはありません。",
            "health": "健康状態", "good": "良好", "warning": "注意", "critical": "重大", "unknown": "利用不可", "model": "モデル", "capacity": "容量", "protocol": "接続", "firmware": "ファームウェア", "serialNumber": "シリアル番号", "smartStatus": "S.M.A.R.T. 状態", "lifeRemaining": "推定残り寿命", "temperature": "温度", "powerOnHours": "使用時間", "powerCycles": "電源投入回数", "totalRead": "総読み込み量", "totalWritten": "総書き込み量", "unsafeShutdowns": "安全でないシャットダウン", "mediaErrors": "メディアエラー", "internal": "内蔵", "solidState": "SSD", "manufacturer": "製造元", "chemistry": "バッテリー種類", "designCapacity": "設計容量", "fullChargeCapacity": "満充電容量", "currentCharge": "現在の充電量", "cycleCount": "充放電回数", "batteryVoltage": "バッテリー電圧", "charging": "充電中", "connected": "電源接続", "yes": "はい", "no": "いいえ", "unavailable": "報告なし", "hours": "%llu 時間", "mAh": "%d mAh", "percent": "%.0f%%",
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
}
