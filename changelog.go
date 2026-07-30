package main

import "strings"

type changeVersion struct {
	Version, Title string
	Sections       []changeSection
}

type changeSection struct {
	Heading string
	Bullets []string
}

var versionOrder = []string{
	"v1.0.4", "v1.0.3", "v1.0.2", "v1.0.1", "v1.0", "v0.1",
}

func changelogFor(code string) []changeVersion {
	switch code {
	case "zh-CN":
		return changelogZH()
	case "ru":
		return changelogRU()
	case "fr":
		return changelogFR()
	case "de":
		return changelogDE()
	case "ko":
		return changelogKO()
	case "ja":
		return changelogJA()
	default:
		return changelogEN()
	}
}

func renderChangeVersion(v changeVersion) string {
	var b strings.Builder
	b.WriteString(v.Version + " · " + v.Title + "\r\n\r\n")
	for _, s := range v.Sections {
		b.WriteString("【" + s.Heading + "】\r\n")
		for _, x := range s.Bullets {
			b.WriteString("• " + x + "\r\n")
		}
		b.WriteString("\r\n")
	}
	return strings.TrimSpace(b.String())
}

func cv(v, t string, ss ...changeSection) changeVersion { return changeVersion{v, t, ss} }
func cs(h string, b ...string) changeSection            { return changeSection{h, b} }

func changelogZH() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "历史记录、隐私与显示体验升级",
			cs("新增",
				"新增全新应用图标，在任务栏和高 DPI 屏幕上保持清晰显示。",
				"新增“隐藏序列号”功能，可同步隐藏主界面、复制内容、导出报告及历史报告中的硬盘和电池序列号。",
				"新增“关于”页面，可查看版本、开发者及问题反馈信息。",
			),
			cs("优化",
				"优化历史记录界面布局和信息层级，支持实时调节左右分栏宽度，并改善列表、报告预览、完整查看及空白状态的显示。",
				"优化历史记录的自动保存、保存位置访问和删除交互，删除报告时可选择是否同时删除本地文件。",
				"优化默认字体、底部状态栏及二级页面显示，字号可随主界面同步调整，并保留用户选择的语言设置。",
				"优化历史记录与更新日志窗口的尺寸适配，可在更小的窗口宽度下正常使用。",
			),
			cs("修复",
				"修复连续刷新、窗口缩放或语言切换时可能出现的文字重叠，以及部分窗口空白、异常缩小或最小化显示异常的问题。",
				"修复历史记录分栏拖动、删除操作和本地文件选项在部分场景下出现的残影、闪烁或显示异常问题。",
				"修复调整历史记录窗口大小时，按钮边框和右侧区域偶现线条残留的问题。",
			),
		),
		cv("v1.0.3", "自动历史记录与多语言体验升级",
			cs("新增", "新增自动历史记录，可选择每次刷新保存或仅导出时保存。", "新增历史记录预览、完整查看、删除和外部文件管理功能。"),
			cs("优化", "优化语言切换控件和窗口适配，支持跟随系统及七种语言。"),
		),
		cv("v1.0.2", "主界面与历史记录功能升级",
			cs("优化", "优化主界面布局，简化工具栏并将低频功能收纳至“更多”菜单。"),
			cs("新增", "新增内置历史记录浏览器和保存位置管理功能。"),
			cs("修复", "修复临时文件可能残留在下载目录或被占用的问题。"),
		),
		cv("v1.0.1", "高 DPI 显示与默认设置优化",
			cs("修复", "修复高 DPI 环境下标题、工具栏和内容重叠问题。"),
			cs("优化", "优化默认字体、常用按钮尺寸和窗口布局。"),
			cs("新增", "新增“跟随系统”语言选项，并完善旧版 Windows 无法读取部分信息时的提示。"),
		),
		cv("v1.0", "首个完整版本",
			cs("硬盘与电池", "完成硬盘型号、容量、接口、固件、序列号及 NVMe SMART 信息读取。", "支持查看硬盘健康状态、剩余寿命、温度、通电时间、通电次数、总读写量及错误信息。", "支持查看电池设计容量、满充容量、健康度和循环次数，并同时显示 mWh 与 Wh。"),
			cs("使用体验", "新增刷新、导出、复制、历史记录、字体调节和七种语言支持。"),
		),
		cv("v0.1", "首个可运行预览版本",
			cs("基础", "首个可正常运行的预览版本，支持读取和显示电池健康信息。"),
		),
	}
}

func changelogEN() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "History, privacy, and display improvements",
			cs("New",
				"Added a new app icon that remains clear on the taskbar and high-DPI displays.",
				"Added Hide serial numbers to mask drive and battery serials in the main view, copied text, exported reports, and History reports.",
				"Added an About page with version, developer, and feedback information.",
			),
			cs("Optimized",
				"Improved the History layout and information hierarchy, with live left-right pane resizing and clearer record lists, report previews, full views, and empty states.",
				"Improved automatic History saving, quick access to the save location, and deletion controls; exported files can optionally be deleted together with their records.",
				"Improved the default font, bottom status area, and secondary-page display; font sizes now scale with the main view while preserving the user's selected language.",
				"Improved History and Changelog window sizing so they remain usable at narrower widths.",
			),
			cs("Fixed",
				"Fixed text overlap after repeated refreshes, window resizing, or language changes, as well as blank, unusually small, or incorrectly minimized secondary windows.",
				"Fixed trails, flicker, and inconsistent display during History pane resizing, report deletion, and local-file option handling.",
				"Fixed occasional border trails around History controls and the right-side content area when resizing the window.",
			),
		),
		cv("v1.0.3", "Automatic History and multilingual improvements", cs("New", "Added automatic History saving with options to save after every refresh or only when exporting.", "Added History preview, full view, deletion, and external-file management."), cs("Optimized", "Improved language switching and window adaptation with Follow system and seven supported languages.")),
		cv("v1.0.2", "Main interface and History upgrades", cs("Optimized", "Simplified the main toolbar and moved less frequently used actions into More."), cs("New", "Added an in-app History browser and configurable save location."), cs("Fixed", "Fixed temporary files remaining in the Downloads folder or becoming locked.")),
		cv("v1.0.1", "High-DPI and default-setting improvements", cs("Fixed", "Fixed overlapping headings, toolbar controls, and content on high-DPI displays."), cs("Optimized", "Improved the default font, common button sizes, and window layout."), cs("New", "Added Follow system for language selection and clearer messages when older Windows versions cannot read some information.")),
		cv("v1.0", "First complete release", cs("Drive and battery", "Added drive model, capacity, interface, firmware, serial number, and NVMe SMART reading.", "Added drive health, remaining life, temperature, power-on time, power cycles, total reads and writes, and error information.", "Added battery design capacity, full-charge capacity, health, and cycle count in both mWh and Wh."), cs("Experience", "Added refresh, export, copy, History, font adjustment, and seven languages.")),
		cv("v0.1", "First runnable preview", cs("Foundation", "First working preview capable of reading and displaying battery-health information.")),
	}
}

func changelogRU() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "История, конфиденциальность и отображение",
			cs("Новое",
				"Добавлен новый значок приложения, который остаётся чётким на панели задач и экранах с высоким DPI.",
				"Добавлена функция скрытия серийных номеров дисков и аккумуляторов в основном окне, копируемом тексте, экспортируемых и исторических отчётах.",
				"Добавлена страница «О программе» с версией, данными разработчика и способами обратной связи.",
			),
			cs("Оптимизировано",
				"Улучшены макет и структура окна истории: доступно интерактивное изменение ширины панелей, а список, предварительный просмотр, полный отчёт и пустое состояние стали нагляднее.",
				"Улучшены автоматическое сохранение истории, быстрый переход к папке и удаление; при необходимости внешний файл отчёта можно удалить вместе с записью.",
				"Улучшены шрифт по умолчанию, нижняя строка состояния и дополнительные страницы; размер текста масштабируется вместе с главным окном, выбранный язык сохраняется.",
				"Окна истории и списка изменений теперь можно уменьшать до более компактной ширины.",
			),
			cs("Исправлено",
				"Исправлены наложение текста после повторного обновления, изменения размера или языка, а также пустые, слишком маленькие и некорректно свёрнутые дополнительные окна.",
				"Исправлены следы, мерцание и непоследовательное отображение при изменении ширины панелей истории, удалении отчётов и работе с параметром локального файла.",
				"Исправлены линии и следы рамок, иногда появлявшиеся при изменении размера окна истории.",
			),
		),
		cv("v1.0.3", "Автоматическая история и языки", cs("Новое", "Добавлено автоматическое сохранение истории после каждого обновления или только при экспорте.", "Добавлены предпросмотр, полный просмотр, удаление и управление внешними файлами."), cs("Оптимизировано", "Улучшены переключение языка и адаптация окон; поддерживаются системный язык и семь языков.")),
		cv("v1.0.2", "Главное окно и история", cs("Оптимизировано", "Упрощена панель инструментов, редко используемые действия перенесены в меню «Ещё»."), cs("Новое", "Добавлен встроенный просмотр истории и выбор папки сохранения."), cs("Исправлено", "Исправлено сохранение временных файлов в папке загрузок и их блокировка.")),
		cv("v1.0.1", "Высокий DPI и начальные настройки", cs("Исправлено", "Исправлено наложение заголовков, панели инструментов и содержимого на экранах с высоким DPI."), cs("Оптимизировано", "Улучшены шрифт по умолчанию, размеры основных кнопок и макет окна."), cs("Новое", "Добавлен режим языка системы и понятные сообщения об ограничениях старых версий Windows.")),
		cv("v1.0", "Первая полная версия", cs("Диск и аккумулятор", "Добавлено чтение модели, объёма, интерфейса, прошивки, серийного номера и NVMe SMART.", "Добавлены состояние диска, ресурс, температура, время работы, циклы питания, общий объём чтения и записи и ошибки.", "Добавлены проектная и полная ёмкость аккумулятора, состояние и циклы в mWh и Wh."), cs("Удобство", "Добавлены обновление, экспорт, копирование, история, настройка шрифта и семь языков.")),
		cv("v0.1", "Первая рабочая предварительная версия", cs("Основа", "Первая рабочая версия с чтением и отображением состояния аккумулятора.")),
	}
}

func changelogFR() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "Historique, confidentialité et affichage",
			cs("Nouveau",
				"Ajout d’une nouvelle icône d’application, nette dans la barre des tâches et sur les écrans à haute densité.",
				"Ajout de l’option Masquer les numéros de série pour les disques et la batterie dans l’écran principal, la copie, l’export et les rapports de l’historique.",
				"Ajout d’une page À propos avec la version, le développeur et les moyens de contact.",
			),
			cs("Optimisé",
				"Amélioration de la disposition et de la hiérarchie de l’historique, avec redimensionnement en temps réel des volets et affichage plus clair de la liste, de l’aperçu, du rapport complet et de l’état vide.",
				"Amélioration de l’enregistrement automatique, de l’accès au dossier et de la suppression ; le fichier exporté peut être supprimé avec son entrée si nécessaire.",
				"Amélioration de la police par défaut, de la barre d’état inférieure et des pages secondaires ; la taille du texte suit l’écran principal et la langue choisie est conservée.",
				"Les fenêtres Historique et Journal des modifications restent utilisables avec une largeur plus réduite.",
			),
			cs("Corrigé",
				"Correction des chevauchements de texte après plusieurs actualisations, redimensionnements ou changements de langue, ainsi que des fenêtres secondaires vides, trop petites ou mal réduites.",
				"Correction des traces, scintillements et affichages incohérents lors du redimensionnement des volets, de la suppression d’un rapport ou de la gestion du fichier local.",
				"Correction de lignes résiduelles autour des boutons et de la zone droite lors du redimensionnement de l’historique.",
			),
		),
		cv("v1.0.3", "Historique automatique et langues", cs("Nouveau", "Ajout de l’enregistrement automatique après chaque actualisation ou uniquement lors de l’export.", "Ajout de l’aperçu, de l’affichage complet, de la suppression et de la gestion des fichiers externes."), cs("Optimisé", "Amélioration du changement de langue et de l’adaptation des fenêtres avec le mode système et sept langues.")),
		cv("v1.0.2", "Interface principale et historique", cs("Optimisé", "Simplification de la barre d’outils et déplacement des actions secondaires dans le menu Plus."), cs("Nouveau", "Ajout d’un navigateur d’historique intégré et du choix du dossier de sauvegarde."), cs("Corrigé", "Correction des fichiers temporaires laissés ou verrouillés dans le dossier Téléchargements.")),
		cv("v1.0.1", "Haute résolution et réglages initiaux", cs("Corrigé", "Correction du chevauchement des titres, outils et contenus sur les écrans haute résolution."), cs("Optimisé", "Amélioration de la police par défaut, de la taille des boutons et de la disposition de la fenêtre."), cs("Nouveau", "Ajout du mode Suivre le système et de messages plus clairs pour les limites des anciennes versions de Windows.")),
		cv("v1.0", "Première version complète", cs("Disque et batterie", "Ajout de la lecture du modèle, de la capacité, de l’interface, du micrologiciel, du numéro de série et du SMART NVMe.", "Ajout de l’état, de la durée de vie, de la température, du temps d’utilisation, des cycles, des lectures/écritures et des erreurs du disque.", "Ajout des capacités nominale et pleine charge, de l’état et des cycles de batterie en mWh et Wh."), cs("Utilisation", "Ajout de l’actualisation, de l’export, de la copie, de l’historique, du réglage de police et de sept langues.")),
		cv("v0.1", "Première préversion fonctionnelle", cs("Base", "Première version fonctionnelle capable de lire et d’afficher l’état de la batterie.")),
	}
}

func changelogDE() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "Verlauf, Datenschutz und Anzeige verbessert",
			cs("Neu",
				"Ein neues App-Symbol bleibt in der Taskleiste und auf High-DPI-Bildschirmen klar erkennbar.",
				"Mit Seriennummern ausblenden lassen sich Laufwerks- und Akkuseriennummern in Hauptansicht, Kopie, Export und Verlaufsberichten maskieren.",
				"Eine Info-Seite zeigt Version, Entwickler und Kontaktmöglichkeiten.",
			),
			cs("Optimiert",
				"Layout und Informationsstruktur des Verlaufs wurden verbessert; die Bereiche lassen sich live anpassen und Liste, Vorschau, Vollansicht sowie Leerzustand sind übersichtlicher.",
				"Automatisches Speichern, Zugriff auf den Speicherort und Löschen wurden verbessert; exportierte Dateien können bei Bedarf zusammen mit dem Eintrag gelöscht werden.",
				"Standardschrift, untere Statusleiste und Nebenfenster wurden verbessert; die Schrift skaliert mit der Hauptansicht und die gewählte Sprache bleibt erhalten.",
				"Verlauf und Änderungsprotokoll lassen sich jetzt auf eine kompaktere Breite verkleinern.",
			),
			cs("Behoben",
				"Textüberlagerungen nach wiederholtem Aktualisieren, Größenänderungen oder Sprachwechseln sowie leere, zu kleine oder fehlerhaft minimierte Nebenfenster wurden behoben.",
				"Spuren, Flimmern und uneinheitliche Anzeigen beim Anpassen der Verlaufsbereiche, Löschen von Berichten und Verwalten lokaler Dateien wurden behoben.",
				"Gelegentliche Linienreste an Schaltflächen und am rechten Rand beim Ändern der Verlaufsfenstergröße wurden behoben.",
			),
		),
		cv("v1.0.3", "Automatischer Verlauf und Sprachen", cs("Neu", "Automatisches Speichern nach jeder Aktualisierung oder nur beim Export wurde hinzugefügt.", "Vorschau, Vollansicht, Löschen und Verwaltung externer Dateien wurden hinzugefügt."), cs("Optimiert", "Sprachwechsel und Fensteranpassung wurden mit Systemmodus und sieben Sprachen verbessert.")),
		cv("v1.0.2", "Hauptoberfläche und Verlauf", cs("Optimiert", "Die Werkzeugleiste wurde vereinfacht und seltene Aktionen in Mehr verschoben."), cs("Neu", "Ein integrierter Verlaufsbrowser und ein wählbarer Speicherort wurden hinzugefügt."), cs("Behoben", "Zurückbleibende oder gesperrte temporäre Dateien im Downloadordner wurden behoben.")),
		cv("v1.0.1", "High-DPI und Anfangseinstellungen", cs("Behoben", "Überlappende Titel, Werkzeugleiste und Inhalte auf High-DPI-Bildschirmen wurden behoben."), cs("Optimiert", "Standardschrift, Schaltflächengrößen und Fensterlayout wurden verbessert."), cs("Neu", "Systemsprache folgen und klarere Hinweise zu Einschränkungen älterer Windows-Versionen wurden hinzugefügt.")),
		cv("v1.0", "Erste vollständige Version", cs("Laufwerk und Akku", "Modell, Kapazität, Schnittstelle, Firmware, Seriennummer und NVMe SMART können gelesen werden.", "Zustand, Restlebensdauer, Temperatur, Betriebszeit, Einschaltzyklen, Lese-/Schreibmenge und Fehler werden angezeigt.", "Design- und Vollladekapazität, Zustand und Zyklen des Akkus werden in mWh und Wh angezeigt."), cs("Bedienung", "Aktualisieren, Export, Kopieren, Verlauf, Schriftanpassung und sieben Sprachen wurden hinzugefügt.")),
		cv("v0.1", "Erste lauffähige Vorschau", cs("Grundlage", "Erste lauffähige Vorschau zum Lesen und Anzeigen des Akkuzustands.")),
	}
}

func changelogKO() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "기록, 개인정보 보호 및 표시 개선",
			cs("신규",
				"작업 표시줄과 고 DPI 화면에서도 선명하게 보이는 새 앱 아이콘을 추가했습니다.",
				"메인 화면, 복사 내용, 내보낸 보고서 및 기록 보고서에서 디스크와 배터리 일련번호를 숨기는 기능을 추가했습니다.",
				"버전, 개발자 및 문의 정보를 확인할 수 있는 정보 페이지를 추가했습니다.",
			),
			cs("최적화",
				"기록 화면의 레이아웃과 정보 구조를 개선하고 좌우 영역 너비를 실시간으로 조절할 수 있도록 했으며, 목록·미리보기·전체 보기·빈 상태 표시를 더 명확하게 다듬었습니다.",
				"기록 자동 저장, 저장 위치 열기 및 삭제 동작을 개선했으며, 필요할 경우 내보낸 파일을 기록과 함께 삭제할 수 있습니다.",
				"기본 글꼴, 하단 상태 영역 및 보조 화면 표시를 개선했으며, 글자 크기는 메인 화면에 맞춰 조절되고 선택한 언어는 유지됩니다.",
				"기록 및 업데이트 내역 창을 더 좁은 너비에서도 사용할 수 있도록 개선했습니다.",
			),
			cs("수정",
				"반복 새로 고침, 창 크기 변경 또는 언어 전환 후 글자가 겹치는 문제와 보조 창이 비어 있거나 지나치게 작게 열리거나 잘못 최소화되는 문제를 수정했습니다.",
				"기록 영역 크기 조절, 보고서 삭제 및 로컬 파일 옵션 처리 중 발생하던 잔상, 깜박임과 표시 불일치를 수정했습니다.",
				"기록 창 크기 변경 시 버튼과 오른쪽 영역에 선이 남는 문제를 수정했습니다.",
			),
		),
		cv("v1.0.3", "자동 기록 및 다국어 개선", cs("신규", "새로 고칠 때마다 저장하거나 내보낼 때만 저장할 수 있는 자동 기록 기능을 추가했습니다.", "기록 미리보기, 전체 보기, 삭제 및 외부 파일 관리 기능을 추가했습니다."), cs("최적화", "시스템 설정 및 7개 언어를 지원하도록 언어 전환과 창 적응을 개선했습니다.")),
		cv("v1.0.2", "메인 화면과 기록 기능 개선", cs("최적화", "도구 모음을 간소화하고 자주 쓰지 않는 기능을 더보기 메뉴로 이동했습니다."), cs("신규", "앱 내 기록 브라우저와 저장 위치 관리 기능을 추가했습니다."), cs("수정", "임시 파일이 다운로드 폴더에 남거나 잠기는 문제를 수정했습니다.")),
		cv("v1.0.1", "고 DPI 및 기본 설정 개선", cs("수정", "고 DPI 환경에서 제목, 도구 모음 및 내용이 겹치는 문제를 수정했습니다."), cs("최적화", "기본 글꼴, 주요 버튼 크기 및 창 레이아웃을 개선했습니다."), cs("신규", "시스템 설정 따르기 언어 옵션과 이전 Windows에서 일부 정보를 읽지 못할 때의 안내를 추가했습니다.")),
		cv("v1.0", "첫 번째 완성 버전", cs("디스크 및 배터리", "디스크 모델, 용량, 인터페이스, 펌웨어, 일련번호 및 NVMe SMART 읽기를 지원합니다.", "디스크 상태, 남은 수명, 온도, 사용 시간, 전원 횟수, 총 읽기/쓰기 및 오류 정보를 표시합니다.", "배터리 설계 용량, 완전 충전 용량, 상태 및 사이클을 mWh와 Wh로 표시합니다."), cs("사용 경험", "새로 고침, 내보내기, 복사, 기록, 글꼴 조절 및 7개 언어를 추가했습니다.")),
		cv("v0.1", "첫 실행 가능 미리보기", cs("기본", "배터리 상태를 읽고 표시할 수 있는 첫 실행 가능 미리보기입니다.")),
	}
}

func changelogJA() []changeVersion {
	return []changeVersion{
		cv("v1.0.4", "履歴、プライバシー、表示を改善",
			cs("新規",
				"タスクバーと高 DPI 画面で鮮明に表示される新しいアプリアイコンを追加しました。",
				"メイン画面、コピー、書き出し、履歴レポートでドライブとバッテリーのシリアル番号を隠す機能を追加しました。",
				"バージョン、開発者、問い合わせ先を確認できる「このアプリについて」を追加しました。",
			),
			cs("最適化",
				"履歴画面のレイアウトと情報構造を改善し、左右ペインの幅をリアルタイムで調整できるようにするとともに、一覧、プレビュー、完全表示、空の状態を見やすくしました。",
				"履歴の自動保存、保存先へのアクセス、削除操作を改善し、必要に応じて書き出したファイルも記録と一緒に削除できるようにしました。",
				"既定の文字サイズ、下部ステータス領域、サブページの表示を改善し、文字サイズはメイン画面に連動し、選択した言語は保持されます。",
				"履歴と更新履歴のウィンドウを、より狭い幅でも利用できるようにしました。",
			),
			cs("修正",
				"連続更新、ウィンドウサイズ変更、言語切り替え後の文字重なりと、サブウィンドウが空白、極小、または正しく最小化されない問題を修正しました。",
				"履歴ペインのサイズ変更、レポート削除、ローカルファイル設定で発生する残像、ちらつき、表示の不一致を修正しました。",
				"履歴ウィンドウのサイズ変更時にボタンや右端へ線が残ることがある問題を修正しました。",
			),
		),
		cv("v1.0.3", "自動履歴と多言語機能を改善", cs("新規", "更新ごとに保存するか、書き出し時のみ保存するかを選べる自動履歴を追加しました。", "履歴のプレビュー、完全表示、削除、外部ファイル管理を追加しました。"), cs("最適化", "システム設定と 7 言語に対応するよう、言語切り替えとウィンドウ適応を改善しました。")),
		cv("v1.0.2", "メイン画面と履歴機能を改善", cs("最適化", "ツールバーを簡潔にし、使用頻度の低い機能をその他メニューに移動しました。"), cs("新規", "アプリ内履歴ブラウザーと保存先管理を追加しました。"), cs("修正", "一時ファイルがダウンロードフォルダーに残る、またはロックされる問題を修正しました。")),
		cv("v1.0.1", "高 DPI と初期設定を改善", cs("修正", "高 DPI 環境でタイトル、ツールバー、内容が重なる問題を修正しました。"), cs("最適化", "既定の文字サイズ、主要ボタンの大きさ、ウィンドウレイアウトを改善しました。"), cs("新規", "システム設定に従う言語オプションと、旧版 Windows で一部情報を取得できない場合の案内を追加しました。")),
		cv("v1.0", "最初の完成版", cs("ドライブとバッテリー", "ドライブのモデル、容量、接続方式、ファームウェア、シリアル番号、NVMe SMART の読み取りに対応しました。", "状態、残り寿命、温度、使用時間、電源投入回数、総読み書き量、エラー情報を表示します。", "バッテリーの設計容量、満充電容量、状態、サイクル数を mWh と Wh で表示します。"), cs("操作", "更新、書き出し、コピー、履歴、文字サイズ調整、7 言語を追加しました。")),
		cv("v0.1", "最初の実行可能なプレビュー", cs("基本", "バッテリー状態を読み取り、表示できる最初の実行可能なプレビューです。")),
	}
}
