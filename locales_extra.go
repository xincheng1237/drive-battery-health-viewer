package main

import "strings"

func init() {
	extras := map[string]map[string]string{
		"zh-CN": {
			"about": "关于", "aboutAppName": "硬盘与电池健康查看器", "aboutSummary": "一款用于查看电脑硬盘状态、电池健康情况等设备信息的轻量级工具，支持保存和查看历史检测情况。", "aboutVersion": "版本：v%s", "aboutBody": "开发者\r\n\r\n作者：程心\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\n酷安\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\n问题反馈与交流\r\n\r\n如果你在使用过程中遇到问题，或者有功能建议，欢迎通过以下方式联系：\r\n\r\nQQ 交流群：1040456137\r\n联系邮箱：2680149724@qq.com\r\n\r\n版权信息\r\n\r\n© 2026 程心。保留所有权利。",
			"systemLanguage": "跟随系统", "more": "更多", "languageMenu": "语言 · %s  ▾", "historyPath": "历史位置：", "fontStatus": "字体：%d pt", "hideSerial": "隐藏序列号",
			"scanCompleteRefresh": "读取完成：%d 块物理硬盘，%d 块电池。已自动保存到历史记录。", "scanCompleteNoSave": "读取完成：%d 块物理硬盘，%d 块电池。",
			"openHistoryDir": "打开历史报告位置", "changeHistoryDir": "更改历史保存位置", "historySaveMode": "历史保存方式", "saveOnRefresh": "每次刷新后保存", "saveOnExport": "仅导出报告时保存",
			"historyWindowTitle": "历史记录", "historyRecords": "检测记录", "reportPreview": "报告预览", "fullView": "完整查看", "delete": "删除", "noHistoryInline": "暂无历史记录。完成一次刷新后，记录会自动出现在这里。",
			"sourceRefresh": "刷新时自动保存", "sourceExport": "导出报告", "sourceLegacy": "旧版报告", "deleteConfirmTitle": "删除历史记录", "deleteConfirmText": "确定从历史记录中删除这条报告吗？", "deleteExternal": "同时删除关联的本地导出报告", "deleteExternalUnavailable": "这条记录没有关联的本地导出报告", "deleteFailed": "删除失败：%s",
			"historyOpenFailed": "无法打开历史位置：%s", "historyChangeFailed": "无法更改历史位置：%s", "selectHistoryFolder": "选择历史报告保存位置",
			"changelogSubtitle": "选择左侧版本，查看该版本的主要改进与修复内容。", "versions": "版本", "changes": "更新内容",
			"cancel": "取消", "legacyVersion": "旧版", "unknownComputer": "未知电脑", "exportHistoryFailed": "报告已导出，但历史记录保存失败：%s",
			"explainSerial":       "1. 报告包含硬盘和电池序列号；公开发布、转发或上传前，建议删除或隐藏序列号。",
			"explainSerialHidden": "1. 硬盘和电池序列号当前已隐藏；公开发布、转发或上传报告时建议保持此选项开启。",
			"explainReadonly":     "2. 本程序只读取信息，不执行测速、擦写、修复或固件更新；读取这些信息不会消耗或影响硬盘寿命。",
			"explainPassthrough":  "4. RAID、Intel VMD/RST、USB 转接盒或旧版 Windows 可能阻止标准 NVMe SMART 透传；这属于系统或控制器限制，不代表硬盘异常。",
		},
		"en": {
			"about": "About", "aboutAppName": "Drive & Battery Health Viewer", "aboutSummary": "A lightweight utility for viewing drive status, battery health, and other device information, with support for saving and reviewing previous scans.", "aboutVersion": "Version: v%s", "aboutBody": "Developer\r\n\r\nAuthor: ChengXin\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\nFeedback and discussion\r\n\r\nIf you encounter a problem or have a feature suggestion, feel free to contact us through the following channels:\r\n\r\nQQ group: 1040456137\r\nEmail: 2680149724@qq.com\r\n\r\nCopyright\r\n\r\n© 2026 ChengXin. All rights reserved.",
			"systemLanguage": "Follow system", "more": "More", "languageMenu": "Language · %s  ▾", "historyPath": "History location:", "fontStatus": "Font: %d pt", "hideSerial": "Hide serial numbers",
			"scanCompleteRefresh": "Complete: %d physical drive(s), %d battery/batteries. Saved to history automatically.", "scanCompleteNoSave": "Complete: %d physical drive(s), %d battery/batteries.",
			"openHistoryDir": "Open history location", "changeHistoryDir": "Change history location", "historySaveMode": "History save mode", "saveOnRefresh": "Save after every refresh", "saveOnExport": "Save only when exporting",
			"historyWindowTitle": "History", "historyRecords": "Scan records", "reportPreview": "Report preview", "fullView": "View full report", "delete": "Delete", "noHistoryInline": "No history yet. Refresh once and the result will appear here automatically.",
			"sourceRefresh": "Auto-saved after refresh", "sourceExport": "Exported report", "sourceLegacy": "Legacy report", "deleteConfirmTitle": "Delete history record", "deleteConfirmText": "Remove this report from history?", "deleteExternal": "Also delete the linked local export", "deleteExternalUnavailable": "This record has no linked local export", "deleteFailed": "Delete failed: %s",
			"historyOpenFailed": "Unable to open the history location: %s", "historyChangeFailed": "Unable to change the history location: %s", "selectHistoryFolder": "Choose a history report folder",
			"changelogSubtitle": "Select a version on the left to review its main improvements and fixes.", "versions": "Versions", "changes": "What changed",
			"cancel": "Cancel", "legacyVersion": "Legacy", "unknownComputer": "Unknown computer", "exportHistoryFailed": "The report was exported, but the history record could not be saved: %s",
			"explainSerial":       "1. Reports contain drive and battery serial numbers. Before publishing, forwarding, or uploading, consider deleting or hiding the serial numbers.",
			"explainSerialHidden": "1. Drive and battery serial numbers are currently hidden. Keep this option enabled when publishing, forwarding, or uploading a report.",
			"explainReadonly":     "2. This app only reads information; it does not benchmark, write, repair, or update firmware. Reading this information does not consume or affect drive lifespan.",
			"explainPassthrough":  "4. RAID, Intel VMD/RST, USB bridges, or older Windows versions may block standard NVMe SMART pass-through. This is a system or controller limitation, not a drive fault.",
		},
		"ru": {
			"about": "О программе", "aboutAppName": "Состояние дисков и батареи", "aboutSummary": "Лёгкая утилита для просмотра состояния дисков, аккумулятора и другой информации об устройстве с сохранением истории проверок.", "aboutVersion": "Версия: v%s", "aboutBody": "Разработчик\r\n\r\nАвтор: ChengXin\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\nОбратная связь\r\n\r\nQQ-группа: 1040456137\r\nEmail: 2680149724@qq.com\r\n\r\nАвторские права\r\n\r\n© 2026 ChengXin. Все права защищены.",
			"systemLanguage": "Как в системе", "more": "Ещё", "languageMenu": "Язык · %s  ▾", "historyPath": "Папка истории:", "fontStatus": "Шрифт: %d пт", "hideSerial": "Скрыть серийные номера",
			"scanCompleteRefresh": "Готово: дисков — %d, батарей — %d. Результат автоматически сохранён в истории.", "scanCompleteNoSave": "Готово: дисков — %d, батарей — %d.",
			"openHistoryDir": "Открыть папку истории", "changeHistoryDir": "Изменить папку истории", "historySaveMode": "Сохранение истории", "saveOnRefresh": "После каждого обновления", "saveOnExport": "Только при экспорте",
			"historyWindowTitle": "История", "historyRecords": "Записи проверок", "reportPreview": "Предпросмотр отчёта", "fullView": "Открыть полностью", "delete": "Удалить", "noHistoryInline": "История пока пуста. Выполните обновление — результат сохранится автоматически.",
			"sourceRefresh": "Автосохранение после обновления", "sourceExport": "Экспортированный отчёт", "sourceLegacy": "Старый отчёт", "deleteConfirmTitle": "Удаление записи", "deleteConfirmText": "Удалить этот отчёт из истории?", "deleteExternal": "Также удалить связанный локальный экспорт", "deleteExternalUnavailable": "У этой записи нет связанного локального экспорта", "deleteFailed": "Не удалось удалить: %s",
			"historyOpenFailed": "Не удалось открыть папку истории: %s", "historyChangeFailed": "Не удалось изменить папку истории: %s", "selectHistoryFolder": "Выберите папку для истории",
			"changelogSubtitle": "Выберите версию слева, чтобы увидеть основные улучшения и исправления.", "versions": "Версии", "changes": "Изменения",
			"cancel": "Отмена", "legacyVersion": "Старая версия", "unknownComputer": "Неизвестный компьютер", "exportHistoryFailed": "Отчёт экспортирован, но запись истории не сохранена: %s",
			"explainSerial":       "1. Отчёт содержит серийные номера дисков и батарей. Перед публикацией, пересылкой или загрузкой рекомендуется удалить или скрыть их.",
			"explainSerialHidden": "1. Серийные номера дисков и батарей сейчас скрыты. При публикации, пересылке или загрузке отчёта оставьте эту настройку включённой.",
			"explainReadonly":     "2. Программа только считывает данные и не выполняет тесты, запись, ремонт или обновление прошивки. Чтение данных не расходует и не влияет на ресурс накопителя.",
			"explainPassthrough":  "4. RAID, Intel VMD/RST, USB-мосты или старые версии Windows могут блокировать стандартный NVMe SMART. Это ограничение системы или контроллера, а не неисправность диска.",
		},
		"fr": {
			"about": "À propos", "aboutAppName": "État des disques et de la batterie", "aboutSummary": "Un utilitaire léger pour consulter l’état des disques, la santé de la batterie et d’autres informations de l’appareil, avec historique des analyses.", "aboutVersion": "Version : v%s", "aboutBody": "Développeur\r\n\r\nAuteur : ChengXin\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\nRetours et échanges\r\n\r\nGroupe QQ : 1040456137\r\nE-mail : 2680149724@qq.com\r\n\r\nDroits d’auteur\r\n\r\n© 2026 ChengXin. Tous droits réservés.",
			"systemLanguage": "Suivre le système", "more": "Plus", "languageMenu": "Langue · %s  ▾", "historyPath": "Dossier de l’historique :", "fontStatus": "Police : %d pt", "hideSerial": "Masquer les numéros de série",
			"scanCompleteRefresh": "Terminé : %d disque(s), %d batterie(s). Enregistré automatiquement dans l’historique.", "scanCompleteNoSave": "Terminé : %d disque(s), %d batterie(s).",
			"openHistoryDir": "Ouvrir le dossier de l’historique", "changeHistoryDir": "Changer le dossier de l’historique", "historySaveMode": "Mode d’enregistrement", "saveOnRefresh": "Après chaque actualisation", "saveOnExport": "Uniquement lors de l’exportation",
			"historyWindowTitle": "Historique", "historyRecords": "Enregistrements", "reportPreview": "Aperçu du rapport", "fullView": "Voir le rapport complet", "delete": "Supprimer", "noHistoryInline": "Aucun historique. Actualisez une fois pour enregistrer automatiquement le résultat.",
			"sourceRefresh": "Enregistré après actualisation", "sourceExport": "Rapport exporté", "sourceLegacy": "Ancien rapport", "deleteConfirmTitle": "Supprimer l’enregistrement", "deleteConfirmText": "Retirer ce rapport de l’historique ?", "deleteExternal": "Supprimer aussi l’export local associé", "deleteExternalUnavailable": "Aucun export local n’est associé à cet enregistrement", "deleteFailed": "Échec de la suppression : %s",
			"historyOpenFailed": "Impossible d’ouvrir le dossier : %s", "historyChangeFailed": "Impossible de changer le dossier : %s", "selectHistoryFolder": "Choisir le dossier de l’historique",
			"changelogSubtitle": "Sélectionnez une version à gauche pour consulter ses principales améliorations et corrections.", "versions": "Versions", "changes": "Modifications",
			"cancel": "Annuler", "legacyVersion": "Ancienne version", "unknownComputer": "Ordinateur inconnu", "exportHistoryFailed": "Le rapport a été exporté, mais l’historique n’a pas pu être enregistré : %s",
			"explainSerial":       "1. Les rapports contiennent les numéros de série des disques et batteries. Avant publication, transfert ou envoi, il est conseillé de les supprimer ou de les masquer.",
			"explainSerialHidden": "1. Les numéros de série des disques et batteries sont actuellement masqués. Conservez cette option lors de la publication, du transfert ou de l’envoi du rapport.",
			"explainReadonly":     "2. L’application lit uniquement les informations ; elle n’effectue ni test, ni écriture, ni réparation, ni mise à jour du micrologiciel. Cette lecture ne consomme ni n’affecte la durée de vie du disque.",
			"explainPassthrough":  "4. RAID, Intel VMD/RST, les ponts USB ou les anciennes versions de Windows peuvent bloquer le SMART NVMe standard. Il s’agit d’une limite du système ou du contrôleur, pas d’un défaut du disque.",
		},
		"de": {
			"about": "Info", "aboutAppName": "Laufwerks- und Akkuzustand", "aboutSummary": "Ein schlankes Werkzeug zur Anzeige von Laufwerksstatus, Akkuzustand und weiteren Geräteinformationen mit speicherbarer Prüfhistorie.", "aboutVersion": "Version: v%s", "aboutBody": "Entwickler\r\n\r\nAutor: ChengXin\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\nFeedback und Austausch\r\n\r\nQQ-Gruppe: 1040456137\r\nE-Mail: 2680149724@qq.com\r\n\r\nUrheberrecht\r\n\r\n© 2026 ChengXin. Alle Rechte vorbehalten.",
			"systemLanguage": "Systemsprache", "more": "Mehr", "languageMenu": "Sprache · %s  ▾", "historyPath": "Verlaufsordner:", "fontStatus": "Schrift: %d pt", "hideSerial": "Seriennummern ausblenden",
			"scanCompleteRefresh": "Fertig: %d Laufwerk(e), %d Akku(s). Automatisch im Verlauf gespeichert.", "scanCompleteNoSave": "Fertig: %d Laufwerk(e), %d Akku(s).",
			"openHistoryDir": "Verlaufsordner öffnen", "changeHistoryDir": "Verlaufsordner ändern", "historySaveMode": "Speichermodus", "saveOnRefresh": "Nach jeder Aktualisierung", "saveOnExport": "Nur beim Exportieren",
			"historyWindowTitle": "Verlauf", "historyRecords": "Prüfungen", "reportPreview": "Berichtsvorschau", "fullView": "Vollständigen Bericht öffnen", "delete": "Löschen", "noHistoryInline": "Noch kein Verlauf. Nach einer Aktualisierung wird das Ergebnis automatisch gespeichert.",
			"sourceRefresh": "Nach Aktualisierung gespeichert", "sourceExport": "Exportierter Bericht", "sourceLegacy": "Alter Bericht", "deleteConfirmTitle": "Verlaufseintrag löschen", "deleteConfirmText": "Diesen Bericht aus dem Verlauf entfernen?", "deleteExternal": "Auch den verknüpften lokalen Export löschen", "deleteExternalUnavailable": "Mit diesem Eintrag ist kein lokaler Export verknüpft", "deleteFailed": "Löschen fehlgeschlagen: %s",
			"historyOpenFailed": "Verlaufsordner konnte nicht geöffnet werden: %s", "historyChangeFailed": "Verlaufsordner konnte nicht geändert werden: %s", "selectHistoryFolder": "Verlaufsordner auswählen",
			"changelogSubtitle": "Wählen Sie links eine Version, um die wichtigsten Verbesserungen und Fehlerbehebungen anzuzeigen.", "versions": "Versionen", "changes": "Änderungen",
			"cancel": "Abbrechen", "legacyVersion": "Alte Version", "unknownComputer": "Unbekannter Computer", "exportHistoryFailed": "Der Bericht wurde exportiert, der Verlaufseintrag konnte jedoch nicht gespeichert werden: %s",
			"explainSerial":       "1. Berichte enthalten Seriennummern von Laufwerken und Akkus. Vor Veröffentlichung, Weitergabe oder Upload sollten sie gelöscht oder ausgeblendet werden.",
			"explainSerialHidden": "1. Die Seriennummern von Laufwerken und Akkus sind derzeit ausgeblendet. Lassen Sie diese Option beim Veröffentlichen, Weitergeben oder Hochladen aktiviert.",
			"explainReadonly":     "2. Die Anwendung liest nur Informationen und führt keine Tests, Schreibvorgänge, Reparaturen oder Firmware-Updates aus. Das Lesen verbraucht oder beeinflusst die Lebensdauer des Laufwerks nicht.",
			"explainPassthrough":  "4. RAID, Intel VMD/RST, USB-Bridges oder ältere Windows-Versionen können standardmäßiges NVMe SMART blockieren. Dies ist eine System- oder Controllergrenze und kein Laufwerksfehler.",
		},
		"ko": {
			"about": "정보", "aboutAppName": "드라이브 및 배터리 상태 보기", "aboutSummary": "드라이브 상태, 배터리 건강 및 기타 장치 정보를 확인하고 검사 기록을 저장·조회할 수 있는 가벼운 도구입니다.", "aboutVersion": "버전: v%s", "aboutBody": "개발자\r\n\r\n작성자: ChengXin\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\n문의 및 의견\r\n\r\nQQ 그룹: 1040456137\r\n이메일: 2680149724@qq.com\r\n\r\n저작권\r\n\r\n© 2026 ChengXin. 모든 권리 보유.",
			"systemLanguage": "시스템 설정 따름", "more": "더보기", "languageMenu": "언어 · %s  ▾", "historyPath": "기록 위치:", "fontStatus": "글꼴: %d pt", "hideSerial": "일련번호 숨기기",
			"scanCompleteRefresh": "완료: 물리 드라이브 %d개, 배터리 %d개. 기록에 자동 저장했습니다.", "scanCompleteNoSave": "완료: 물리 드라이브 %d개, 배터리 %d개.",
			"openHistoryDir": "기록 폴더 열기", "changeHistoryDir": "기록 저장 위치 변경", "historySaveMode": "기록 저장 방식", "saveOnRefresh": "새로 고칠 때마다 저장", "saveOnExport": "내보낼 때만 저장",
			"historyWindowTitle": "기록", "historyRecords": "검사 기록", "reportPreview": "보고서 미리보기", "fullView": "전체 보고서 보기", "delete": "삭제", "noHistoryInline": "아직 기록이 없습니다. 한 번 새로 고치면 결과가 자동 저장됩니다.",
			"sourceRefresh": "새로 고침 후 자동 저장", "sourceExport": "내보낸 보고서", "sourceLegacy": "이전 버전 보고서", "deleteConfirmTitle": "기록 삭제", "deleteConfirmText": "이 보고서를 기록에서 삭제하시겠습니까?", "deleteExternal": "연결된 로컬 내보내기 파일도 삭제", "deleteExternalUnavailable": "이 기록에는 연결된 로컬 내보내기 파일이 없습니다", "deleteFailed": "삭제 실패: %s",
			"historyOpenFailed": "기록 폴더를 열 수 없습니다: %s", "historyChangeFailed": "기록 폴더를 변경할 수 없습니다: %s", "selectHistoryFolder": "기록 저장 폴더 선택",
			"changelogSubtitle": "왼쪽에서 버전을 선택하여 주요 개선 및 수정 내용을 확인합니다.", "versions": "버전", "changes": "업데이트 내용",
			"cancel": "취소", "legacyVersion": "이전 버전", "unknownComputer": "알 수 없는 컴퓨터", "exportHistoryFailed": "보고서는 내보냈지만 기록을 저장하지 못했습니다: %s",
			"explainSerial":       "1. 보고서에는 드라이브와 배터리 일련번호가 포함됩니다. 공개, 전달 또는 업로드 전에 일련번호를 삭제하거나 숨기는 것이 좋습니다.",
			"explainSerialHidden": "1. 드라이브와 배터리 일련번호가 현재 숨겨져 있습니다. 보고서를 공개, 전달 또는 업로드할 때 이 옵션을 유지하십시오.",
			"explainReadonly":     "2. 이 프로그램은 정보만 읽으며 테스트, 쓰기, 복구 또는 펌웨어 업데이트를 수행하지 않습니다. 정보 읽기는 드라이브 수명을 소모하거나 영향을 주지 않습니다.",
			"explainPassthrough":  "4. RAID, Intel VMD/RST, USB 브리지 또는 이전 Windows는 표준 NVMe SMART 전달을 차단할 수 있습니다. 이는 시스템 또는 컨트롤러 제한이며 드라이브 이상이 아닙니다.",
		},
		"ja": {
			"about": "このアプリについて", "aboutAppName": "ドライブとバッテリーの状態", "aboutSummary": "ドライブの状態、バッテリーの健康状態などのデバイス情報を確認し、過去の検査結果を保存・閲覧できる軽量ツールです。", "aboutVersion": "バージョン：v%s", "aboutBody": "開発者\r\n\r\n作者：ChengXin\r\n\r\nGitHub\r\n@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk\r\n程心ChengXin\r\nhttps://www.coolapk.com/u/3594167\r\n\r\nフィードバック\r\n\r\nQQ グループ：1040456137\r\nメール：2680149724@qq.com\r\n\r\n著作権\r\n\r\n© 2026 ChengXin. All rights reserved.",
			"systemLanguage": "システムに従う", "more": "その他", "languageMenu": "言語 · %s  ▾", "historyPath": "履歴の保存先：", "fontStatus": "フォント：%d pt", "hideSerial": "シリアル番号を隠す",
			"scanCompleteRefresh": "完了：物理ドライブ %d 台、バッテリー %d 個。履歴に自動保存しました。", "scanCompleteNoSave": "完了：物理ドライブ %d 台、バッテリー %d 個。",
			"openHistoryDir": "履歴フォルダーを開く", "changeHistoryDir": "履歴の保存先を変更", "historySaveMode": "履歴の保存方法", "saveOnRefresh": "更新のたびに保存", "saveOnExport": "エクスポート時のみ保存",
			"historyWindowTitle": "履歴", "historyRecords": "検査記録", "reportPreview": "レポートのプレビュー", "fullView": "完全なレポートを表示", "delete": "削除", "noHistoryInline": "履歴はまだありません。一度更新すると結果が自動保存されます。",
			"sourceRefresh": "更新後に自動保存", "sourceExport": "エクスポートしたレポート", "sourceLegacy": "旧版レポート", "deleteConfirmTitle": "履歴を削除", "deleteConfirmText": "このレポートを履歴から削除しますか？", "deleteExternal": "関連付けられたローカル書き出しも削除", "deleteExternalUnavailable": "この記録には関連付けられたローカル書き出しがありません", "deleteFailed": "削除に失敗しました：%s",
			"historyOpenFailed": "履歴フォルダーを開けません：%s", "historyChangeFailed": "履歴フォルダーを変更できません：%s", "selectHistoryFolder": "履歴フォルダーを選択",
			"changelogSubtitle": "左側でバージョンを選択し、主な改善点と修正内容を確認します。", "versions": "バージョン", "changes": "更新内容",
			"cancel": "キャンセル", "legacyVersion": "旧版", "unknownComputer": "不明なコンピューター", "exportHistoryFailed": "レポートは保存されましたが、履歴を保存できませんでした：%s",
			"explainSerial":       "1. レポートにはドライブとバッテリーのシリアル番号が含まれます。公開、転送、アップロードの前に削除または非表示にすることを推奨します。",
			"explainSerialHidden": "1. ドライブとバッテリーのシリアル番号は現在非表示です。レポートを公開、転送、アップロードするときはこの設定を維持してください。",
			"explainReadonly":     "2. 本アプリは情報を読み取るだけで、テスト、書き込み、修復、ファームウェア更新は行いません。情報の読み取りはドライブ寿命を消費・低下させません。",
			"explainPassthrough":  "4. RAID、Intel VMD/RST、USB ブリッジ、または古い Windows では標準 NVMe SMART が転送されない場合があります。これはシステムまたはコントローラーの制限であり、ドライブ異常ではありません。",
		},
	}

	aboutSections := map[string]map[string]string{
		"zh-CN": {
			"aboutSummary":       "一款用于查看电脑硬盘状态、电池健康情况等设备信息的轻量级工具，支持保存和查看历史检测情况。",
			"aboutVersion":       "版本：v%s",
			"aboutDeveloper":     "开发者",
			"aboutDeveloperText": "作者：程心\r\n\r\nGitHub：@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\n酷安：程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "问题反馈与交流",
			"aboutFeedbackText":  "如果你在使用过程中遇到问题，或者有功能建议，欢迎通过以下方式联系：\r\n\r\nQQ 交流群：\t1040456137\r\n联系邮箱：\t2680149724@qq.com",
			"aboutCopyright":     "版权",
			"aboutCopyrightText": "© 2026 程心，保留所有权利。",
		},
		"en": {
			"aboutSummary":       "A lightweight utility for viewing drive status, battery health, and other device information, with support for saving and reviewing previous scans.",
			"aboutVersion":       "Version: v%s",
			"aboutDeveloper":     "Developer",
			"aboutDeveloperText": "Author: ChengXin\r\n\r\nGitHub: @xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk: 程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "Feedback and discussion",
			"aboutFeedbackText":  "If you encounter a problem or have a feature suggestion, feel free to contact us through the following channels:\r\n\r\nQQ group:\t1040456137\r\nEmail:\t2680149724@qq.com",
			"aboutCopyright":     "Copyright",
			"aboutCopyrightText": "© 2026 ChengXin. All rights reserved.",
		},
		"ru": {
			"aboutSummary":       "Лёгкая утилита для просмотра состояния дисков, аккумулятора и другой информации об устройстве с сохранением истории проверок.",
			"aboutVersion":       "Версия: v%s",
			"aboutDeveloper":     "Разработчик",
			"aboutDeveloperText": "Автор: ChengXin\r\n\r\nGitHub: @xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk: 程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "Обратная связь",
			"aboutFeedbackText":  "Если у вас возникла проблема или есть предложение, свяжитесь с нами:\r\n\r\nQQ-группа:\t1040456137\r\nEmail:\t2680149724@qq.com",
			"aboutCopyright":     "Авторские права",
			"aboutCopyrightText": "© 2026 ChengXin. Все права защищены.",
		},
		"fr": {
			"aboutSummary":       "Un utilitaire léger pour consulter l’état des disques, la santé de la batterie et d’autres informations de l’appareil, avec historique des analyses.",
			"aboutVersion":       "Version : v%s",
			"aboutDeveloper":     "Développeur",
			"aboutDeveloperText": "Auteur : ChengXin\r\n\r\nGitHub : @xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk : 程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "Retours et échanges",
			"aboutFeedbackText":  "Si vous rencontrez un problème ou avez une suggestion, contactez-nous :\r\n\r\nGroupe QQ :\t1040456137\r\nE-mail :\t2680149724@qq.com",
			"aboutCopyright":     "Droits d’auteur",
			"aboutCopyrightText": "© 2026 ChengXin. Tous droits réservés.",
		},
		"de": {
			"aboutSummary":       "Ein schlankes Werkzeug zur Anzeige von Laufwerksstatus, Akkuzustand und weiteren Geräteinformationen mit speicherbarer Prüfhistorie.",
			"aboutVersion":       "Version: v%s",
			"aboutDeveloper":     "Entwickler",
			"aboutDeveloperText": "Autor: ChengXin\r\n\r\nGitHub: @xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk: 程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "Feedback und Austausch",
			"aboutFeedbackText":  "Bei Problemen oder Funktionsvorschlägen können Sie uns hier erreichen:\r\n\r\nQQ-Gruppe:\t1040456137\r\nE-Mail:\t2680149724@qq.com",
			"aboutCopyright":     "Urheberrecht",
			"aboutCopyrightText": "© 2026 ChengXin. Alle Rechte vorbehalten.",
		},
		"ko": {
			"aboutSummary":       "드라이브 상태, 배터리 건강 및 기타 장치 정보를 확인하고 검사 기록을 저장·조회할 수 있는 가벼운 도구입니다.",
			"aboutVersion":       "버전: v%s",
			"aboutDeveloper":     "개발자",
			"aboutDeveloperText": "작성자: ChengXin\r\n\r\nGitHub: @xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk: 程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "문의 및 의견",
			"aboutFeedbackText":  "문제가 발생하거나 기능 제안이 있다면 다음 방법으로 연락해 주세요.\r\n\r\nQQ 그룹:\t1040456137\r\n이메일:\t2680149724@qq.com",
			"aboutCopyright":     "저작권",
			"aboutCopyrightText": "© 2026 ChengXin. 모든 권리 보유.",
		},
		"ja": {
			"aboutSummary":       "ドライブの状態、バッテリーの健康状態などのデバイス情報を確認し、過去の検査結果を保存・閲覧できる軽量ツールです。",
			"aboutVersion":       "バージョン：v%s",
			"aboutDeveloper":     "開発者",
			"aboutDeveloperText": "作者：ChengXin\r\n\r\nGitHub：@xincheng1237\r\nhttps://github.com/xincheng1237\r\n\r\nCoolapk：程心ChengXin\r\nhttps://www.coolapk.com/u/3594167",
			"aboutFeedback":      "フィードバック",
			"aboutFeedbackText":  "問題や機能のご提案がある場合は、次の方法でご連絡ください。\r\n\r\nQQ グループ：\t1040456137\r\nメール：\t2680149724@qq.com",
			"aboutCopyright":     "著作権",
			"aboutCopyrightText": "© 2026 ChengXin. All rights reserved.",
		},
	}

	for code, values := range extras {
		l := locales[code]
		if l.Text == nil {
			l.Text = map[string]string{}
		}
		for k, v := range values {
			l.Text[k] = v
		}
		if sections, ok := aboutSections[code]; ok {
			for k, v := range sections {
				l.Text[k] = v
			}
		}
		if l.Text["aboutSummary"] == "" || l.Text["aboutVersion"] == "" || l.Text["aboutBody"] == "" {
			parts := strings.SplitN(l.Text["aboutText"], "\r\n\r\n", 2)
			if l.Text["aboutVersion"] == "" && len(parts) > 0 {
				l.Text["aboutVersion"] = parts[0]
			}
			if len(parts) > 1 {
				if l.Text["aboutSummary"] == "" {
					parts2 := strings.SplitN(parts[1], "\r\n\r\n", 2)
					if len(parts2) > 0 {
						l.Text["aboutSummary"] = parts2[0]
					}
					if l.Text["aboutBody"] == "" {
						if len(parts2) > 1 {
							l.Text["aboutBody"] = parts2[1]
						} else {
							l.Text["aboutBody"] = parts[1]
						}
					}
				} else if l.Text["aboutBody"] == "" {
					l.Text["aboutBody"] = parts[1]
				}
			}
		}
		l.Text["reportTitle"] = l.Text["appTitle"] + " v" + appVersion
		locales[code] = l
	}
}

func languageDisplayName(code string) string {
	if code == languageSystem {
		return tr(effectiveLocale(), "systemLanguage")
	}
	if l, ok := locales[code]; ok {
		return l.NativeName
	}
	return code
}
