import Foundation

extension L10n {
    static let interface12Tables: [AppLanguage: [String: String]] = {
        let languages: [AppLanguage] = [.english, .simplifiedChinese, .russian, .french, .german, .korean, .japanese]
        let rows: [String: [String]] = [
            "chargeProtectionHoldingNotice": ["Power is connected. The charge limit is active, so charging is paused.", "已连接电源，充电上限保护正在生效，当前暂停充电。", "Питание подключено. Зарядка приостановлена действующим ограничением заряда.", "Alimentation branchée. La limite de charge est active et suspend la recharge.", "Netzteil angeschlossen. Die aktive Ladegrenze pausiert das Laden.", "전원이 연결되어 있습니다. 충전 상한 보호가 작동하여 충전이 일시 중지되었습니다.", "電源に接続されています。充電上限保護が働いているため、充電を一時停止しています。"],
            "helperAdapterObservation": [
                "The charge helper detects a power adapter.",
                "充电辅助程序检测到电源适配器。",
                "Помощник зарядки обнаружил адаптер питания.",
                "L’assistant de charge détecte un adaptateur secteur.",
                "Das Ladehilfsprogramm erkennt ein Netzteil.",
                "충전 도우미가 전원 어댑터를 감지했습니다.",
                "充電ヘルパーが電源アダプタを検出しています。"
            ],
            "helperStatusUnconfirmed": [
                "Waiting for a current report from the charge helper. Charge protection is unconfirmed.",
                "暂未收到充电辅助程序的有效状态，无法确认充电保护是否生效。",
                "Ожидаются актуальные данные от помощника зарядки. Работа защиты пока не подтверждена.",
                "En attente d’un état récent de l’assistant de charge. La protection reste à confirmer.",
                "Aktueller Status des Ladehilfsprogramms ausstehend. Der Ladeschutz ist noch nicht bestätigt.",
                "충전 도우미의 최신 상태를 기다리고 있습니다. 충전 보호가 작동 중인지 아직 확인할 수 없습니다.",
                "充電ヘルパーからの最新の報告を待っています。充電保護の状態は未確認です。"
            ],
            "privacyNotice": ["Hide serial numbers in the interface, history, and exported reports.", "在界面、历史及导出报告中隐藏序列号。", "Скрывать серийные номера в интерфейсе, истории и экспортированных отчётах.", "Masque les numéros de série dans l’interface, l’historique et les rapports exportés.", "Seriennummern in Oberfläche, Verlauf und exportierten Berichten ausblenden.", "화면, 기록 및 내보낸 보고서에서 일련번호를 숨깁니다.", "画面・履歴・書き出したレポートのシリアル番号を隠します。"],
            "displaySize": ["Display size", "显示大小", "Размер интерфейса", "Taille d’affichage", "Darstellungsgröße", "화면 표시 크기", "表示サイズ"],
            "displaySize_small": ["Small", "小", "Мелкий", "Petite", "Klein", "작게", "小"],
            "displaySize_standard": ["Standard", "标准", "Обычный", "Standard", "Standard", "기본", "標準"],
            "displaySize_large": ["Large", "大", "Крупный", "Grande", "Groß", "크게", "大"],
            "displaySize_extraLarge": ["Extra Large", "特大", "Очень крупный", "Très grande", "Sehr groß", "아주 크게", "特大"],
            "softwareUpdates": ["Software Updates", "软件更新", "Обновления", "Mises à jour", "Softwareupdates", "소프트웨어 업데이트", "ソフトウェアアップデート"],
            "increaseReportFont": ["Larger report text", "放大报告文字", "Увеличить текст отчёта", "Agrandir le texte du rapport", "Berichtstext vergrößern", "보고서 글자 크게", "レポートの文字を大きく"],
            "decreaseReportFont": ["Smaller report text", "缩小报告文字", "Уменьшить текст отчёта", "Réduire le texte du rapport", "Berichtstext verkleinern", "보고서 글자 작게", "レポートの文字を小さく"],
            "resetReportFont": ["Reset report text size", "恢复报告默认字号", "Сбросить размер текста", "Rétablir la taille du texte", "Berichtsschrift zurücksetzen", "보고서 기본 글자 크기", "レポートの文字サイズを戻す"],
            "aboutSummary": ["View drive and battery health, manage charge protection, and read saved reports.", "查看硬盘与电池健康，管理充电保护与历史报告。", "Состояние накопителей и батареи, защита зарядки и сохранённые отчёты.", "Consultez la santé des disques et de la batterie, gérez la charge et retrouvez vos rapports.", "Laufwerks- und Akkuzustand, Ladeschutz und gespeicherte Berichte im Überblick.", "디스크와 배터리 상태를 확인하고 충전 보호와 저장된 보고서를 관리합니다.", "ドライブとバッテリーの状態、充電保護、保存したレポートをまとめて管理。"],
            "overviewLimitations": ["Device information is provided by macOS and device firmware.", "设备信息由 macOS 与设备固件提供。", "Данные предоставлены macOS и прошивкой устройства.", "Les informations proviennent de macOS et du micrologiciel de l’appareil.", "Die Gerätedaten stammen von macOS und der Gerätefirmware.", "기기 정보는 macOS와 기기 펌웨어에서 제공합니다.", "デバイス情報は macOS とデバイスのファームウェアから取得します。"],
            "driveWorkingTimeExplanation": ["Drive operating time is the cumulative value reported by its firmware.", "工作时间来自硬盘固件的累计统计。", "Время работы — накопленный счётчик прошивки накопителя.", "Le temps de fonctionnement correspond au cumul du micrologiciel du disque.", "Die Betriebszeit ist der kumulierte Zähler der Laufwerksfirmware.", "작동 시간은 디스크 펌웨어의 누적 통계입니다.", "稼働時間はドライブのファームウェアによる累積値です。"],
            "batteryHealthExplanation": ["Battery health uses the calibrated value supplied by macOS.", "电池健康度采用 macOS 提供的校准值。", "Здоровье батареи основано на откалиброванном значении macOS.", "La santé de la batterie utilise la valeur étalonnée fournie par macOS.", "Der Akkuzustand verwendet den kalibrierten Wert von macOS.", "배터리 건강도는 macOS가 제공하는 보정값을 사용합니다.", "バッテリーの状態は macOS の校正値を使用します。"],
            "release12Display": ["Choose from four display sizes and adjust history report text independently.", "新增四档显示大小，并支持在历史报告中独立调节文字大小。", "Четыре размера интерфейса и независимая настройка текста отчётов из истории.", "Quatre tailles d’affichage et un réglage indépendant du texte des rapports de l’historique.", "Vier Darstellungsgrößen und eine unabhängige Schriftgröße für Verlaufsberichte.", "네 단계 화면 표시 크기와 기록 보고서의 독립적인 글자 크기 조절을 지원합니다.", "4段階の表示サイズと、履歴レポートの独立した文字サイズ調整に対応しました。"],
            "release12Settings": ["Simplified navigation and grouped About, release notes, and update checks in Settings.", "精简顶部导航，将关于信息、更新日志和检查更新集中到设置。", "Упрощена навигация; сведения о приложении, журнал изменений и обновления собраны в настройках.", "Navigation simplifiée ; À propos, les notes de version et la recherche de mises à jour sont réunis dans Réglages.", "Vereinfachte Navigation; App-Infos, Versionshinweise und Updates sind in den Einstellungen gebündelt.", "탐색을 간소화하고 앱 정보, 업데이트 기록, 업데이트 확인을 설정에 모았습니다.", "ナビゲーションを整理し、アプリ情報・更新履歴・更新確認を設定に集約しました。"],
            "release12Design": ["A new interface design improves information layout and typography across Overview, History, and Settings.", "采用全新界面设计，优化概览、历史和设置中的信息排布与文字呈现。", "Новый дизайн улучшает компоновку и типографику в обзоре, истории и настройках.", "Une nouvelle interface améliore la disposition des informations et la typographie dans Aperçu, Historique et Réglages.", "Ein neues Oberflächendesign verbessert Informationsaufteilung und Typografie in Übersicht, Verlauf und Einstellungen.", "새로운 인터페이스 디자인으로 개요, 기록, 설정의 정보 배치와 글자 표시를 개선했습니다.", "インターフェイスを一新し、概要・履歴・設定の情報配置と文字表示を改善しました。"],
            "release12QuitFix": ["Fixed normal quitting while release notes are open.", "修复打开更新日志时无法正常退出应用的问题。", "Исправлено завершение приложения при открытом журнале изменений.", "Correction de la fermeture de l’application lorsque les notes de version sont ouvertes.", "Normales Beenden ist auch bei geöffneten Versionshinweisen möglich.", "업데이트 기록을 연 상태에서 앱이 정상 종료되지 않던 문제를 수정했습니다.", "更新履歴を開いているとアプリを正常に終了できない問題を修正しました。"]
        ]
        var result: [AppLanguage: [String: String]] = [:]
        for (index, language) in languages.enumerated() {
            result[language] = rows.mapValues { $0[index] }
        }
        return result
    }()
}
