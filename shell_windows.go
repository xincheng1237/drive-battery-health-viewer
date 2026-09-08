//go:build windows

package main

import (
	"fmt"
	"math"
	"strings"
	"syscall"
	"unsafe"
)

const (
	ID_NAV_OVERVIEW = 8101
	ID_NAV_HISTORY  = 8102
	ID_NAV_SETTINGS = 8103
	ID_NAV_ABOUT    = 8104

	ID_SETTINGS_MODE         = 8201
	ID_SETTINGS_OPEN         = 8202
	ID_SETTINGS_CHANGE       = 8203
	ID_UPDATE_NOTICE_VIEW    = 8301
	ID_UPDATE_NOTICE_DISMISS = 8302
)

const (
	shellPageOverview = iota
	shellPageHistory
	shellPageSettings
	shellPageAbout
)

var (
	shellBrandHwnd, shellBrandVersionHwnd, shellTitleHwnd                 syscall.Handle
	shellPrivacyHwnd                                                      syscall.Handle
	shellUpdateNoticeHwnd, shellUpdateViewHwnd, shellUpdateDismissHwnd    syscall.Handle
	navOverviewHwnd, navHistoryHwnd, navSettingsHwnd, navAboutHwnd        syscall.Handle
	dashboardHwnd, settingsPageHwnd                                       syscall.Handle
	settingsPageTitleHwnd, settingsAppearanceTitleHwnd                    syscall.Handle
	settingsLanguageLabelHwnd                                             syscall.Handle
	settingsPrivacyNoteHwnd, settingsFontLabelHwnd                        syscall.Handle
	settingsStorageTitleHwnd, settingsModeLabelHwnd                       syscall.Handle
	settingsPathLabelHwnd, settingsReadTitleHwnd, settingsReadNoteHwnd    syscall.Handle
	settingsBridgeNoteHwnd, settingsModeHwnd, settingsOpenHwnd            syscall.Handle
	settingsChangeHwnd                                                    syscall.Handle
	shellTitleFont, shellBrandFont, shellNavFont, shellSmallFont          syscall.Handle
	shellIconFont                                                         syscall.Handle
	dashboardTitleFont, dashboardCardTitleFont, dashboardBodyFont         syscall.Handle
	dashboardSmallFont, dashboardPercentFont                              syscall.Handle
	shellSidebarBrush, shellCanvasBrush, shellCardBrush, shellNoticeBrush syscall.Handle
	shellPage                                                             = shellPageOverview
	dashboardScroll                                                       int32
	settingsScroll                                                        int32
	updateNoticeVisible                                                   bool
	settingsLayoutWidth, settingsLayoutHeight                             int32
	settingsLayoutDPI                                                     int
	settingsLayoutValid, settingsLayoutInProgress                         bool
)

func shellText(code, key string) string {
	texts := map[string]map[string]string{
		"en": {
			"overview": "Overview", "history": "History", "settings": "Settings", "about": "About",
			"updated": "Updated %s", "drives": "Drives", "batteries": "Batteries", "health": "Health",
			"appearance": "Appearance & privacy", "language": "Language", "fontSize": "Report text size",
			"storage": "History storage", "saveReport": "Save reports", "historyLocation": "History location",
			"hardware": "Information", "readOnly": "This app only reads information. It does not benchmark, write, repair, erase, or update firmware.",
			"bridge":    "Some external drives and vendor data may be unavailable because of Windows, controller, or USB enclosure limitations.",
			"onRefresh": "After every refresh", "onExport": "Only when exporting", "hideNote": "Hides drive and battery serial numbers in the interface, clipboard, history, and exported reports.",
			"healthy": "Good", "unknown": "Unknown", "systemNote": "Available details depend on Windows, the drive controller, and the connection type; some fields may not apply to this device.",
		},
		"zh-CN": {
			"overview": "概览", "history": "历史记录", "settings": "设置", "about": "关于",
			"updated": "更新于 %s", "drives": "硬盘", "batteries": "电池", "health": "健康度",
			"appearance": "外观与隐私", "language": "语言", "fontSize": "报告文字大小",
			"storage": "历史记录存储", "saveReport": "保存报告", "historyLocation": "历史记录位置",
			"hardware": "说明", "readOnly": "本应用只读取信息，不会测速、写入、修复、擦除或更新固件。",
			"bridge":    "部分外接硬盘及厂商专用数据可能受 Windows、控制器或 USB 硬盘盒限制而无法读取。",
			"onRefresh": "每次刷新后", "onExport": "仅导出时", "hideNote": "启用后，界面、复制内容、历史记录和导出报告中的硬盘与电池序列号都会被隐藏。",
			"healthy": "良好", "unknown": "未知", "systemNote": "数据来源取决于 Windows、硬盘控制器及连接方式，部分项目可能不适用于当前设备。",
		},
	}
	if values, ok := texts[code]; ok {
		if value := values[key]; value != "" {
			return value
		}
	}
	return texts["en"][key]
}

func createModernShell(hwnd syscall.Handle) {
	_, _, _ = procLoadLibraryW.Call(uintptr(unsafe.Pointer(utf16Ptr("Msftedit.dll"))))
	shellBrandHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	shellBrandVersionHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	navOverviewHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_NAV_OVERVIEW)
	navHistoryHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_NAV_HISTORY)
	navSettingsHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_NAV_SETTINGS)
	navAboutHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_NAV_ABOUT)
	historyButtonHwnd = navHistoryHwnd

	shellTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	refreshHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_REFRESH)
	exportHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_EXPORT)
	copyHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_COPY)
	shellPrivacyHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_HIDE_SERIAL)
	statusHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_STATUS)
	updateNoticeVisible = currentSettings().SeenChangelogBuild != appBuildID
	shellUpdateNoticeHwnd = createWindow(0, "STATIC", "", WS_CHILD|SS_LEFT|SS_CENTERIMAGE|SS_END_ELLIPSIS, 0, 0, 0, 0, hwnd, 0)
	shellUpdateViewHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_UPDATE_NOTICE_VIEW)
	shellUpdateDismissHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_UPDATE_NOTICE_DISMISS)
	// Keep the report control as a hidden text backing store for existing copy,
	// export, accessibility, and language-update paths.
	reportHwnd = createWindow(0, "RICHEDIT50W", "", WS_CHILD|ES_MULTILINE|ES_READONLY, 0, 0, 0, 0, hwnd, ID_REPORT)
	if reportHwnd == 0 {
		reportHwnd = createWindow(0, "EDIT", "", WS_CHILD|ES_MULTILINE|ES_READONLY, 0, 0, 0, 0, hwnd, ID_REPORT)
	}

	dashboardHwnd = createWindow(0, "HHVDashboard", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_CLIPCHILDREN, 0, 0, 0, 0, hwnd, 0)
	historyHwnd = createWindow(WS_EX_CONTROLPARENT, "HHVHistoryWindow", "", WS_CHILD|WS_CLIPCHILDREN, 0, 0, 0, 0, hwnd, 0)
	settingsPageHwnd = createWindow(WS_EX_CONTROLPARENT, "HHVSettingsPage", "", WS_CHILD|WS_CLIPCHILDREN|WS_VSCROLL, 0, 0, 0, 0, hwnd, 0)
	aboutHwnd = createWindow(WS_EX_CONTROLPARENT, "HHVAboutWindow", "", WS_CHILD|WS_VSCROLL|WS_CLIPCHILDREN, 0, 0, 0, 0, hwnd, 0)
	shellSidebarBrush = createBrush(rgb(244, 246, 249))
	shellCanvasBrush = createBrush(rgb(248, 249, 251))
	shellCardBrush = createBrush(rgb(255, 255, 255))
	shellNoticeBrush = createBrush(rgb(239, 246, 255))

	for _, control := range []syscall.Handle{refreshHwnd, exportHwnd, copyHwnd, shellPrivacyHwnd, shellUpdateViewHwnd, shellUpdateDismissHwnd, navOverviewHwnd, navHistoryHwnd, navSettingsHwnd, navAboutHwnd} {
		setWindowTheme(control, "Explorer")
	}
	recreateShellFonts()
	updateShellTexts()
}

func recreateShellFonts() {
	deleteFonts([]syscall.Handle{shellTitleFont, shellBrandFont, shellNavFont, shellSmallFont, shellIconFont, dashboardTitleFont, dashboardCardTitleFont, dashboardBodyFont, dashboardSmallFont, dashboardPercentFont})
	dpi := windowDPI(mainHwnd)
	// The report font preference must not resize the application chrome or
	// dashboard.  These roles form one fixed 18/12/11/10 pt UI scale.
	shellTitleFont = createUIFontHalfPointDPI(uiPageTitleHalfPoints, FW_SEMIBOLD, dpi)
	shellBrandFont = createUIFontHalfPointDPI(uiBrandHalfPoints, FW_SEMIBOLD, dpi)
	shellNavFont = createUIFontHalfPointDPI(uiNavigationHalfPoints, FW_NORMAL, dpi)
	shellSmallFont = createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_NORMAL, dpi)
	shellIconFont = createFontFaceDPI(12, FW_NORMAL, dpi, "Segoe MDL2 Assets")
	dashboardTitleFont = createUIFontHalfPointDPI(uiPageTitleHalfPoints, FW_SEMIBOLD, dpi)
	dashboardCardTitleFont = createUIFontHalfPointDPI(uiSectionHalfPoints, FW_SEMIBOLD, dpi)
	dashboardBodyFont = createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, dpi)
	dashboardSmallFont = createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_NORMAL, dpi)
	dashboardPercentFont = createUIFontHalfPointDPI(uiMetricHalfPoints, FW_SEMIBOLD, dpi)
	applyFont(shellBrandHwnd, shellBrandFont)
	applyFont(shellBrandVersionHwnd, shellSmallFont)
	applyFont(shellTitleHwnd, shellTitleFont)
	applyFont(statusHwnd, shellSmallFont)
	for _, control := range []syscall.Handle{navOverviewHwnd, navHistoryHwnd, navSettingsHwnd, navAboutHwnd} {
		applyFont(control, shellNavFont)
	}
	applyFont(shellUpdateNoticeHwnd, shellSmallFont)
	for _, control := range []syscall.Handle{refreshHwnd, exportHwnd, copyHwnd, shellPrivacyHwnd, shellUpdateViewHwnd, shellUpdateDismissHwnd} {
		applyFont(control, mainUIFont)
	}
	updateSettingsPageFonts()
}

func updateShellTexts() {
	code := effectiveLocale()
	setText(shellBrandHwnd, tr(code, "appTitle"))
	setText(shellBrandVersionHwnd, "v"+appVersion)
	setText(navOverviewHwnd, shellText(code, "overview"))
	setText(navHistoryHwnd, shellText(code, "history"))
	setText(navSettingsHwnd, shellText(code, "settings"))
	setText(navAboutHwnd, shellText(code, "about"))
	setText(refreshHwnd, tr(code, "refresh"))
	setText(exportHwnd, tr(code, "export"))
	setText(copyHwnd, tr(code, "copy"))
	setText(shellPrivacyHwnd, tr(code, "hideSerial"))
	setText(shellUpdateNoticeHwnd, updateNoticeText(code, "message"))
	setText(shellUpdateViewHwnd, updateNoticeText(code, "view"))
	setText(shellUpdateDismissHwnd, updateNoticeText(code, "dismiss"))
	updateSettingsPageTexts()
	updateShellPageTitle()
	refreshDashboard()
}

func updateShellPageTitle() {
	code := effectiveLocale()
	title := shellText(code, "overview")
	switch shellPage {
	case shellPageHistory:
		title = shellText(code, "history")
	case shellPageSettings:
		title = shellText(code, "settings")
	case shellPageAbout:
		title = shellText(code, "about")
	}
	setText(shellTitleHwnd, title)
}

func switchShellPage(page int) {
	if page < shellPageOverview || page > shellPageAbout {
		return
	}
	shellPage = page
	updateShellPageTitle()
	layoutMain()
	enforceShellPageVisibility()
	if page == shellPageHistory {
		recreateHistoryFonts()
		reloadHistoryRecords()
	}
	if page == shellPageSettings {
		updateSettingsPageTexts()
		// A hidden child can receive its first paint before the parent has
		// delivered a size notification.  Re-run the page layout after it is
		// selected so the title, card backgrounds, and controls share one
		// geometry snapshot on the very first frame.
		settingsLayoutValid = false
		layoutSettingsPage()
	}
	if page == shellPageAbout {
		recreateAboutFonts()
		layoutAbout()
	}
	invalidateShellNavigation()
	active := []syscall.Handle{dashboardHwnd, historyHwnd, settingsPageHwnd, aboutHwnd}[shellPage]
	procInvalidateRect.Call(uintptr(active), 0, 1)
	procRedrawWindow.Call(uintptr(mainHwnd), 0, 0, RDW_INVALIDATE|RDW_ERASE|RDW_UPDATENOW|RDW_ALLCHILDREN)
}

func invalidateShellNavigation() {
	for _, control := range []syscall.Handle{navOverviewHwnd, navHistoryHwnd, navSettingsHwnd, navAboutHwnd} {
		procInvalidateRect.Call(uintptr(control), 0, 1)
	}
}

func invalidateShellPrivacyButton() {
	if shellPrivacyHwnd != 0 {
		procInvalidateRect.Call(uintptr(shellPrivacyHwnd), 0, 1)
	}
}

func enforceShellPageVisibility() {
	pages := []syscall.Handle{dashboardHwnd, historyHwnd, settingsPageHwnd, aboutHwnd}
	for i, page := range pages {
		command := uintptr(SW_HIDE)
		if i == shellPage {
			command = SW_SHOW
		}
		procShowWindow.Call(uintptr(page), command)
	}
	command := uintptr(SW_HIDE)
	if shellPage == shellPageOverview {
		command = SW_SHOW
	}
	for _, control := range []syscall.Handle{shellTitleHwnd, refreshHwnd, exportHwnd, copyHwnd, shellPrivacyHwnd, statusHwnd} {
		procShowWindow.Call(uintptr(control), command)
	}
	noticeCommand := uintptr(SW_HIDE)
	if shellPage == shellPageOverview && updateNoticeVisible {
		noticeCommand = SW_SHOW
	}
	for _, control := range []syscall.Handle{shellUpdateNoticeHwnd, shellUpdateViewHwnd, shellUpdateDismissHwnd} {
		procShowWindow.Call(uintptr(control), noticeCommand)
	}
}

func dismissUpdateNotice(openChanges bool) {
	if !updateNoticeVisible {
		return
	}
	updateNoticeVisible = false
	updateSettings(func(s *appSettings) { s.SeenChangelogBuild = appBuildID })
	layoutMain()
	enforceShellPageVisibility()
	redrawWindowClean(mainHwnd, nil)
	if openChanges {
		openChangelog()
	}
}

func layoutModernShell() {
	if mainHwnd == 0 {
		return
	}
	r := clientRect(mainHwnd)
	dpi := windowDPI(mainHwnd)
	sidebar := scale(220, dpi)
	if r.Right < scale(820, dpi) {
		sidebar = scale(188, dpi)
	}
	margin := scale(24, dpi)
	procMoveWindow.Call(uintptr(shellBrandHwnd), uintptr(margin), uintptr(scale(14, dpi)), uintptr(sidebar-2*margin), uintptr(scale(28, dpi)), 1)
	procMoveWindow.Call(uintptr(shellBrandVersionHwnd), uintptr(margin), uintptr(scale(39, dpi)), uintptr(sidebar-2*margin), uintptr(scale(18, dpi)), 1)
	y := scale(76, dpi)
	for _, control := range []syscall.Handle{navOverviewHwnd, navHistoryHwnd, navSettingsHwnd, navAboutHwnd} {
		procMoveWindow.Call(uintptr(control), uintptr(scale(12, dpi)), uintptr(y), uintptr(sidebar-scale(24, dpi)), uintptr(scale(44, dpi)), 1)
		y += scale(48, dpi)
	}
	contentX := sidebar
	contentW := max32(scale(320, dpi), r.Right-contentX)
	if shellPage == shellPageOverview {
		top := scale(18, dpi)
		procMoveWindow.Call(uintptr(shellTitleHwnd), uintptr(contentX+margin), uintptr(top), uintptr(scale(260, dpi)), uintptr(scale(36, dpi)), 1)
		buttonW := scale(40, dpi)
		buttonH := scale(40, dpi)
		gap := scale(8, dpi)
		right := r.Right - margin
		for _, control := range []syscall.Handle{shellPrivacyHwnd, copyHwnd, exportHwnd, refreshHwnd} {
			procMoveWindow.Call(uintptr(control), uintptr(right-buttonW), uintptr(top), uintptr(buttonW), uintptr(buttonH), 1)
			right -= buttonW + gap
		}
		procMoveWindow.Call(uintptr(statusHwnd), uintptr(contentX+margin), uintptr(scale(56, dpi)), uintptr(max32(scale(160, dpi), contentW-2*margin)), uintptr(scale(22, dpi)), 1)
		dashboardTop := scale(88, dpi)
		if updateNoticeVisible {
			noticeTop := scale(88, dpi)
			noticeHeight := scale(42, dpi)
			dismissW := scale(66, dpi)
			viewW := scale(118, dpi)
			buttonGap := scale(8, dpi)
			noticeRight := r.Right - margin
			procMoveWindow.Call(uintptr(shellUpdateDismissHwnd), uintptr(noticeRight-dismissW), uintptr(noticeTop+scale(4, dpi)), uintptr(dismissW), uintptr(scale(34, dpi)), 1)
			procMoveWindow.Call(uintptr(shellUpdateViewHwnd), uintptr(noticeRight-dismissW-buttonGap-viewW), uintptr(noticeTop+scale(4, dpi)), uintptr(viewW), uintptr(scale(34, dpi)), 1)
			textRight := noticeRight - dismissW - buttonGap - viewW - scale(12, dpi)
			procMoveWindow.Call(uintptr(shellUpdateNoticeHwnd), uintptr(contentX+margin+scale(14, dpi)), uintptr(noticeTop), uintptr(max32(scale(120, dpi), textRight-(contentX+margin+scale(14, dpi)))), uintptr(noticeHeight), 1)
			dashboardTop = scale(140, dpi)
		}
		procMoveWindow.Call(uintptr(dashboardHwnd), uintptr(contentX), uintptr(dashboardTop), uintptr(contentW), uintptr(max32(scale(160, dpi), r.Bottom-dashboardTop)), 1)
	} else {
		pageH := max32(scale(200, dpi), r.Bottom)
		active := map[int]syscall.Handle{shellPageHistory: historyHwnd, shellPageSettings: settingsPageHwnd, shellPageAbout: aboutHwnd}[shellPage]
		if shellPage == shellPageSettings {
			settingsLayoutValid = false
		}
		procMoveWindow.Call(uintptr(active), uintptr(contentX), 0, uintptr(contentW), uintptr(pageH), 0)
		if shellPage == shellPageSettings {
			// MoveWindow with repaint disabled does not guarantee a WM_SIZE for
			// an unchanged child size.  Explicitly synchronize once more so a
			// first activation cannot paint stale child coordinates.
			layoutSettingsPage()
		}
	}
}

func paintModernShell(hwnd syscall.Handle) {
	var ps paintStruct
	hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
	if hdc == 0 {
		return
	}
	defer procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
	r := clientRect(hwnd)
	dpi := windowDPI(hwnd)
	sidebar := scale(220, dpi)
	if r.Right < scale(820, dpi) {
		sidebar = scale(188, dpi)
	}
	fillDC(syscall.Handle(hdc), rect{0, 0, sidebar, r.Bottom}, rgb(244, 246, 249))
	fillDC(syscall.Handle(hdc), rect{sidebar, 0, r.Right, r.Bottom}, rgb(248, 249, 251))
	fillDC(syscall.Handle(hdc), rect{sidebar - 1, 0, sidebar, r.Bottom}, rgb(222, 226, 232))
	if shellPage == shellPageOverview && updateNoticeVisible {
		margin := scale(24, dpi)
		drawRoundedSurface(syscall.Handle(hdc), rect{sidebar + margin, scale(88, dpi), r.Right - margin, scale(130, dpi)}, rgb(239, 246, 255), rgb(213, 227, 247), scale(8, dpi))
	}
}

func drawShellOwnerItem(dis *drawItemStruct) bool {
	if dis == nil {
		return false
	}
	if dis.CtlID == ID_UPDATE_NOTICE_VIEW || dis.CtlID == ID_UPDATE_NOTICE_DISMISS {
		r := dis.RcItem
		background, border, foreground := rgb(255, 255, 255), rgb(204, 219, 239), rgb(31, 82, 145)
		if dis.CtlID == ID_UPDATE_NOTICE_DISMISS {
			background, border, foreground = rgb(239, 246, 255), rgb(239, 246, 255), rgb(82, 101, 126)
		}
		if dis.ItemState&ODS_SELECTED != 0 {
			background = rgb(224, 236, 251)
		}
		drawRoundedSurface(dis.HDC, r, background, border, scale(7, windowDPI(mainHwnd)))
		drawText(dis.HDC, getText(syscall.Handle(dis.HwndItem)), &r, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, shellSmallFont, foreground)
		return true
	}
	if dis.CtlID == ID_REFRESH || dis.CtlID == ID_EXPORT || dis.CtlID == ID_COPY || dis.CtlID == ID_HIDE_SERIAL {
		dpi := windowDPI(mainHwnd)
		outer := dis.RcItem
		fillDC(dis.HDC, outer, rgb(248, 249, 251))
		// Keep the entire rounded frame inside the owner-draw paint region.
		// A stroke placed on RcItem's lower edge is clipped by Windows and looks
		// thinner than the other three sides, especially at fractional DPI scales.
		inset := max32(4, scale(3, dpi))
		r := rect{outer.Left + inset, outer.Top + inset, outer.Right - inset, outer.Bottom - inset}
		if r.Right <= r.Left || r.Bottom <= r.Top {
			return true
		}
		background := rgb(255, 255, 255)
		border := rgb(210, 217, 226)
		if dis.ItemState&ODS_SELECTED != 0 {
			background = rgb(231, 238, 248)
			border = rgb(166, 193, 228)
		}
		borderThickness := max32(2, scale(1, dpi))
		drawLayeredRoundedSurface(dis.HDC, r, background, border, scale(8, dpi), borderThickness)
		glyph := map[uint32]string{ID_REFRESH: "\uE72C", ID_EXPORT: "\uE74E", ID_COPY: "\uE8C8", ID_HIDE_SERIAL: "\uE890"}[dis.CtlID]
		if dis.CtlID == ID_HIDE_SERIAL && currentSettings().HideSerial {
			glyph = "\uED1A"
			background = rgb(220, 235, 255)
			border = rgb(160, 194, 238)
			drawLayeredRoundedSurface(dis.HDC, r, background, border, scale(8, dpi), borderThickness)
		}
		foreground := rgb(49, 61, 78)
		if dis.ItemState&ODS_DISABLED != 0 {
			foreground = rgb(151, 158, 168)
		}
		drawText(dis.HDC, glyph, &r, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, shellIconFont, foreground)
		if dis.ItemState&ODS_FOCUS != 0 {
			focusBrush := createBrush(rgb(37, 99, 180))
			focus := rect{r.Left + scale(3, dpi), r.Top + scale(3, dpi), r.Right - scale(3, dpi), r.Bottom - scale(3, dpi)}
			procFrameRect.Call(uintptr(dis.HDC), uintptr(unsafe.Pointer(&focus)), uintptr(focusBrush))
			procDeleteObject.Call(uintptr(focusBrush))
		}
		return true
	}
	if dis.CtlID < ID_NAV_OVERVIEW || dis.CtlID > ID_NAV_ABOUT {
		return false
	}
	page := int(dis.CtlID - ID_NAV_OVERVIEW)
	selected := page == shellPage
	background := rgb(244, 246, 249)
	foreground := rgb(40, 49, 62)
	if selected {
		background = rgb(220, 235, 255)
		foreground = rgb(15, 82, 174)
	} else if dis.ItemState&ODS_SELECTED != 0 {
		background = rgb(229, 235, 244)
	}
	fillDC(dis.HDC, dis.RcItem, rgb(244, 246, 249))
	brush := createBrush(background)
	pen := createPen(background, 1)
	oldBrush, _, _ := procSelectObject.Call(uintptr(dis.HDC), uintptr(brush))
	oldPen, _, _ := procSelectObject.Call(uintptr(dis.HDC), uintptr(pen))
	r := dis.RcItem
	procRoundRect.Call(uintptr(dis.HDC), uintptr(r.Left), uintptr(r.Top), uintptr(r.Right), uintptr(r.Bottom), uintptr(scale(8, windowDPI(mainHwnd))), uintptr(scale(8, windowDPI(mainHwnd))))
	procSelectObject.Call(uintptr(dis.HDC), oldBrush)
	procSelectObject.Call(uintptr(dis.HDC), oldPen)
	procDeleteObject.Call(uintptr(brush))
	procDeleteObject.Call(uintptr(pen))
	if selected {
		accent := rect{r.Left, r.Top + scale(7, windowDPI(mainHwnd)), r.Left + scale(4, windowDPI(mainHwnd)), r.Bottom - scale(7, windowDPI(mainHwnd))}
		fillDC(dis.HDC, accent, rgb(37, 99, 235))
	}
	glyph := map[uint32]string{ID_NAV_OVERVIEW: "\uE80F", ID_NAV_HISTORY: "\uE81C", ID_NAV_SETTINGS: "\uE713", ID_NAV_ABOUT: "\uE946"}[dis.CtlID]
	iconRect := r
	iconRect.Left += scale(14, windowDPI(mainHwnd))
	iconRect.Right = iconRect.Left + scale(24, windowDPI(mainHwnd))
	drawText(dis.HDC, glyph, &iconRect, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, shellIconFont, foreground)
	text := getText(syscall.Handle(dis.HwndItem))
	textRect := r
	textRect.Left += scale(50, windowDPI(mainHwnd))
	drawText(dis.HDC, text, &textRect, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, shellNavFont, foreground)
	return true
}

func refreshDashboard() {
	if dashboardHwnd != 0 {
		procInvalidateRect.Call(uintptr(dashboardHwnd), 0, 1)
	}
}

func diskHealthPercent(d diskDescriptor) (float64, bool) {
	if d.Health != nil {
		return math.Max(0, 100-float64(d.Health.PercentageUsed)), true
	}
	if d.Smartctl != nil && d.Smartctl.PercentageUsed != nil {
		return math.Max(0, 100-float64(*d.Smartctl.PercentageUsed)), true
	}
	if d.Reliability != nil && d.Reliability.Wear != nil {
		return math.Max(0, 100-float64(*d.Reliability.Wear)), true
	}
	return 0, false
}

func diskStatusText(d diskDescriptor, healthKnown bool) (string, bool) {
	code := effectiveLocale()
	if d.Smartctl != nil && d.Smartctl.SmartPassed != nil && !*d.Smartctl.SmartPassed {
		return tr(code, "warning"), false
	}
	if d.Reliability != nil && strings.TrimSpace(d.Reliability.HealthStatus) != "" {
		status := localizedHealthStatus(code, d.Reliability.HealthStatus)
		if status != tr(code, "good") {
			return status, false
		}
	}
	if healthKnown {
		return shellText(code, "healthy"), true
	}
	return shellText(code, "unknown"), false
}

func drawHealthBadge(hdc syscall.Handle, r rect, text string, good bool) {
	fill, foreground := rgb(239, 241, 244), rgb(86, 94, 106)
	if good {
		fill, foreground = rgb(232, 250, 237), rgb(16, 124, 16)
	}
	drawRoundedSurface(hdc, r, fill, fill, scale(10, windowDPI(dashboardHwnd)))
	drawText(hdc, text, &r, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardSmallFont, foreground)
}

func diskTemperature(d diskDescriptor) string {
	if d.Health != nil {
		return fmt.Sprintf("%d °C", d.Health.TemperatureC)
	}
	if d.Smartctl != nil && d.Smartctl.Temperature != nil {
		return fmt.Sprintf("%d °C", *d.Smartctl.Temperature)
	}
	if d.Reliability != nil && d.Reliability.Temperature != nil {
		return fmt.Sprintf("%d °C", *d.Reliability.Temperature)
	}
	return tr(effectiveLocale(), "notReported")
}

func diskPowerHours(d diskDescriptor) string {
	if d.Health != nil {
		return hoursWithDaysLocalized(effectiveLocale(), d.Health.PowerOnHours)
	}
	if d.Smartctl != nil && d.Smartctl.PowerOnHours != nil {
		return trf(effectiveLocale(), "hoursDays", fmt.Sprintf("%d", *d.Smartctl.PowerOnHours), float64(*d.Smartctl.PowerOnHours)/24)
	}
	if d.Reliability != nil && d.Reliability.PowerOnHours != nil {
		return trf(effectiveLocale(), "hoursDays", fmt.Sprintf("%d", *d.Reliability.PowerOnHours), float64(*d.Reliability.PowerOnHours)/24)
	}
	return tr(effectiveLocale(), "notReported")
}

func diskPowerCycles(d diskDescriptor) string {
	if d.Health != nil {
		return d.Health.PowerCycles
	}
	if d.Smartctl != nil && d.Smartctl.PowerCycles != nil {
		return fmt.Sprintf("%d", *d.Smartctl.PowerCycles)
	}
	return tr(effectiveLocale(), "notReported")
}

func diskUnsafeShutdowns(d diskDescriptor) string {
	if d.Health != nil {
		return d.Health.UnsafeShutdowns
	}
	if d.Smartctl != nil && d.Smartctl.UnsafeShutdowns != nil {
		return fmt.Sprintf("%d", *d.Smartctl.UnsafeShutdowns)
	}
	return tr(effectiveLocale(), "notReported")
}

func diskErrorLogEntries(d diskDescriptor) string {
	if d.Health != nil {
		return d.Health.ErrorLogEntries
	}
	if d.Smartctl != nil && d.Smartctl.ErrorLogEntries != nil {
		return fmt.Sprintf("%d", *d.Smartctl.ErrorLogEntries)
	}
	return tr(effectiveLocale(), "notReported")
}

func diskReadWrite(d diskDescriptor) (string, string) {
	if d.Health != nil {
		return formatDecimalTB(d.Health.DataReadTB), formatDecimalTB(d.Health.DataWrittenTB)
	}
	if d.Smartctl != nil {
		read, written := tr(effectiveLocale(), "notReported"), tr(effectiveLocale(), "notReported")
		if d.Smartctl.BytesRead != nil {
			read = formatDecimalTB(float64(*d.Smartctl.BytesRead) / 1e12)
		}
		if d.Smartctl.BytesWritten != nil {
			written = formatDecimalTB(float64(*d.Smartctl.BytesWritten) / 1e12)
		}
		return read, written
	}
	return tr(effectiveLocale(), "notReported"), tr(effectiveLocale(), "notReported")
}

func drawRoundedSurface(hdc syscall.Handle, r rect, fill, border uint32, radius int32) {
	brush := createBrush(fill)
	pen := createPen(border, 1)
	oldBrush, _, _ := procSelectObject.Call(uintptr(hdc), uintptr(brush))
	oldPen, _, _ := procSelectObject.Call(uintptr(hdc), uintptr(pen))
	procRoundRect.Call(uintptr(hdc), uintptr(r.Left), uintptr(r.Top), uintptr(r.Right), uintptr(r.Bottom), uintptr(radius), uintptr(radius))
	procSelectObject.Call(uintptr(hdc), oldBrush)
	procSelectObject.Call(uintptr(hdc), oldPen)
	procDeleteObject.Call(uintptr(brush))
	procDeleteObject.Call(uintptr(pen))
}

func drawLayeredRoundedSurface(hdc syscall.Handle, r rect, fill, border uint32, radius, thickness int32) {
	if thickness < 1 {
		thickness = 1
	}
	// Build the border from two filled shapes instead of a stroked path. The
	// centre strips are filled explicitly because GDI RoundRect can omit the
	// lower straight segment on DPI-scaled owner-draw button DCs.
	fillRoundedSurface(hdc, r, border, radius)
	inner := rect{r.Left + thickness, r.Top + thickness, r.Right - thickness, r.Bottom - thickness}
	if inner.Right <= inner.Left || inner.Bottom <= inner.Top {
		return
	}
	innerRadius := radius - 2*thickness
	if innerRadius < 1 {
		innerRadius = 1
	}
	fillRoundedSurface(hdc, inner, fill, innerRadius)
}

func fillRoundedSurface(hdc syscall.Handle, r rect, color uint32, radius int32) {
	if r.Right <= r.Left || r.Bottom <= r.Top {
		return
	}
	if radius < 2 {
		fillDC(hdc, r, color)
		return
	}
	drawRoundedSurface(hdc, r, color, color, radius)
	halfRadius := max32(1, radius/2)
	if r.Right-r.Left > 2*halfRadius {
		fillDC(hdc, rect{r.Left + halfRadius, r.Top, r.Right - halfRadius, r.Bottom}, color)
	}
	if r.Bottom-r.Top > 2*halfRadius {
		fillDC(hdc, rect{r.Left, r.Top + halfRadius, r.Right, r.Bottom - halfRadius}, color)
	}
}

func drawHealthRing(hdc syscall.Handle, x, y, size int32, percent float64, known bool) {
	dpi := windowDPI(dashboardHwnd)
	stroke := float32(scale(8, dpi))
	if withGDIPlus(hdc, func(graphics uintptr) {
		// Real-valued coordinates retain sub-pixel coverage on high-DPI displays.
		// The integer GDI+ entry points rounded both sides of the stroke and made
		// the outer edge appear toothed at fractional Windows scaling factors.
		inset := float32(scale(5, dpi)) + 0.5
		diameter := float32(size) - 2*inset
		left, top := float32(x)+inset, float32(y)+inset
		backgroundPen := createGDIPlusPen(argb(255, 226, 229, 234), stroke, true)
		if backgroundPen != 0 {
			procGdipDrawEllipse.Call(graphics, backgroundPen, gdipFloat(left), gdipFloat(top), gdipFloat(diameter), gdipFloat(diameter))
			procGdipDeletePen.Call(backgroundPen)
		}
		if known && percent > 0 {
			progressPen := createGDIPlusPen(argb(255, 34, 197, 94), stroke, true)
			if progressPen != 0 {
				if percent >= 99.5 {
					// A full ellipse has no rounded-cap overlap seam at twelve o'clock.
					procGdipDrawEllipse.Call(graphics, progressPen, gdipFloat(left), gdipFloat(top), gdipFloat(diameter), gdipFloat(diameter))
				} else {
					sweep := float32(math.Min(359, math.Max(0, percent)*3.6))
					procGdipDrawArc.Call(graphics, progressPen, gdipFloat(left), gdipFloat(top), gdipFloat(diameter), gdipFloat(diameter), gdipFloat(-90), gdipFloat(sweep))
				}
				procGdipDeletePen.Call(progressPen)
			}
		}
	}) {
		drawHealthRingText(hdc, x, y, size, percent, known, dpi)
		return
	}
	// Legacy fallback for systems where GDI+ cannot initialize.
	nullBrush, _, _ := procGetStockObject.Call(5)
	oldBrush, _, _ := procSelectObject.Call(uintptr(hdc), nullBrush)
	gray := createPen(rgb(223, 227, 233), scale(8, dpi))
	oldPen, _, _ := procSelectObject.Call(uintptr(hdc), uintptr(gray))
	procEllipse.Call(uintptr(hdc), uintptr(x), uintptr(y), uintptr(x+size), uintptr(y+size))
	procSelectObject.Call(uintptr(hdc), oldPen)
	procDeleteObject.Call(uintptr(gray))
	if known {
		green := createPen(rgb(34, 197, 94), scale(8, dpi))
		oldPen, _, _ = procSelectObject.Call(uintptr(hdc), uintptr(green))
		if percent >= 99.9 {
			procEllipse.Call(uintptr(hdc), uintptr(x), uintptr(y), uintptr(x+size), uintptr(y+size))
		} else if percent > 0 {
			centerX, centerY := x+size/2, y+size/2
			angle := -math.Pi/2 + 2*math.Pi*percent/100
			endX := centerX + int32(math.Cos(angle)*float64(size/2))
			endY := centerY + int32(math.Sin(angle)*float64(size/2))
			procSetArcDirection.Call(uintptr(hdc), 2)
			procArc.Call(uintptr(hdc), uintptr(x), uintptr(y), uintptr(x+size), uintptr(y+size), uintptr(centerX), uintptr(y), uintptr(endX), uintptr(endY))
		}
		procSelectObject.Call(uintptr(hdc), oldPen)
		procDeleteObject.Call(uintptr(green))
	}
	procSelectObject.Call(uintptr(hdc), oldBrush)
	drawHealthRingText(hdc, x, y, size, percent, known, dpi)
}

func drawHealthRingText(hdc syscall.Handle, x, y, size int32, percent float64, known bool, dpi int) {
	value := "—"
	if known {
		value = fmt.Sprintf("%.0f%%", percent)
	}
	valueRect := rect{x, y + size/2 - scale(18, dpi), x + size, y + size/2 + scale(18, dpi)}
	drawText(hdc, value, &valueRect, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardPercentFont, rgb(27, 34, 45))
	labelRect := rect{x, y + size + scale(8, dpi), x + size, y + size + scale(32, dpi)}
	drawText(hdc, shellText(effectiveLocale(), "health"), &labelRect, DT_CENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardSmallFont, rgb(99, 107, 119))
}

func drawSectionHeader(hdc syscall.Handle, kind, title string, count int, r rect) {
	dpi := windowDPI(dashboardHwnd)
	icon := rect{r.Left, r.Top + scale(5, dpi), r.Left + scale(22, dpi), r.Top + scale(27, dpi)}
	withGDIPlus(hdc, func(graphics uintptr) {
		pen := createGDIPlusPen(argb(255, 53, 67, 88), float32(scale(2, dpi)), true)
		if pen == 0 {
			return
		}
		defer procGdipDeletePen.Call(pen)
		if kind == "disk" {
			procGdipDrawRectangleI.Call(graphics, pen, uintptr(icon.Left+scale(1, dpi)), uintptr(icon.Top+scale(3, dpi)), uintptr(scale(19, dpi)), uintptr(scale(15, dpi)))
			procGdipDrawLineI.Call(graphics, pen, uintptr(icon.Left+scale(3, dpi)), uintptr(icon.Bottom-scale(7, dpi)), uintptr(icon.Right-scale(3, dpi)), uintptr(icon.Bottom-scale(7, dpi)))
			procGdipDrawEllipseI.Call(graphics, pen, uintptr(icon.Right-scale(6, dpi)), uintptr(icon.Bottom-scale(6, dpi)), uintptr(scale(2, dpi)), uintptr(scale(2, dpi)))
		} else {
			procGdipDrawRectangleI.Call(graphics, pen, uintptr(icon.Left+scale(1, dpi)), uintptr(icon.Top+scale(4, dpi)), uintptr(scale(17, dpi)), uintptr(scale(13, dpi)))
			procGdipDrawLineI.Call(graphics, pen, uintptr(icon.Right-scale(3, dpi)), uintptr(icon.Top+scale(8, dpi)), uintptr(icon.Right-scale(3, dpi)), uintptr(icon.Top+scale(13, dpi)))
			var brush uintptr
			if status, _, _ := procGdipCreateSolidFill.Call(uintptr(argb(255, 53, 67, 88)), uintptr(unsafe.Pointer(&brush))); status == 0 && brush != 0 {
				procGdipFillRectangleI.Call(graphics, brush, uintptr(icon.Left+scale(4, dpi)), uintptr(icon.Top+scale(7, dpi)), uintptr(scale(9, dpi)), uintptr(scale(7, dpi)))
				procGdipDeleteBrush.Call(brush)
			}
		}
	})
	textLeft := r.Left + scale(32, dpi)
	drawText(hdc, title, &rect{textLeft, r.Top, r.Right, r.Bottom}, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardCardTitleFont, rgb(34, 41, 53))
	textWidth := measureTextWidth(dashboardHwnd, title, dashboardCardTitleFont)
	badge := rect{textLeft + textWidth + scale(10, dpi), r.Top + scale(5, dpi), textLeft + textWidth + scale(34, dpi), r.Top + scale(27, dpi)}
	drawRoundedSurface(hdc, badge, rgb(232, 235, 240), rgb(232, 235, 240), scale(10, dpi))
	drawText(hdc, fmt.Sprintf("%d", count), &badge, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardSmallFont, rgb(76, 86, 101))
}

type dashboardField struct{ label, value string }

func drawDashboardFields(hdc syscall.Handle, fields []dashboardField, x, y, width, rowHeight int32) {
	columnWidth := width / 2
	dpi := windowDPI(dashboardHwnd)
	for i, field := range fields {
		column := int32(i % 2)
		row := int32(i / 2)
		left := x + column*columnWidth
		top := y + row*rowHeight
		labelRect := rect{left, top, left + columnWidth - scale(24, dpi), top + scale(17, dpi)}
		valueRect := rect{left, top + scale(18, dpi), left + columnWidth - scale(24, dpi), top + rowHeight}
		drawText(hdc, field.label, &labelRect, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, dashboardSmallFont, rgb(111, 119, 131))
		drawText(hdc, field.value, &valueRect, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, dashboardBodyFont, rgb(31, 38, 50))
	}
}

func batteryDashboardFields(battery BatteryInfo) []dashboardField {
	code := effectiveLocale()
	cycle := strings.TrimSpace(battery.CycleCount)
	if cycle == "" {
		cycle = tr(code, "deviceNotReported")
	}
	return []dashboardField{
		{tr(code, "manufacturer"), valueOrUnknownLocalized(code, battery.Manufacturer)},
		{tr(code, "chemistry"), valueOrUnknownLocalized(code, battery.Chemistry)},
		{tr(code, "serial"), serialDisplayValue(code, battery.SerialNumber, currentSettings().HideSerial)},
		{tr(code, "cycleCount"), cycle},
		{tr(code, "designCapacity"), func() string {
			if battery.DesignCapacityMWh > 0 {
				return formatBatteryCapacityWithVoltage(battery.DesignCapacityMWh, battery.DesignVoltageMillivolts)
			}
			return tr(code, "notReported")
		}()},
		{tr(code, "fullChargeCapacity"), func() string {
			if battery.FullChargeMWh > 0 {
				return formatBatteryCapacityWithVoltage(battery.FullChargeMWh, battery.DesignVoltageMillivolts)
			}
			return tr(code, "notReported")
		}()},
	}
}

func dashboardContentHeight(result *scanResult, dpi int) int32 {
	height := scale(88, dpi)
	height += scale(40, dpi) + int32(len(result.Disks))*scale(360, dpi)
	height += scale(40, dpi) + int32(len(result.Batteries))*scale(264, dpi)
	return height + scale(72, dpi)
}

func paintDashboard(hwnd syscall.Handle) {
	var ps paintStruct
	hdcValue, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
	if hdcValue == 0 {
		return
	}
	defer procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
	r := clientRect(hwnd)
	target := syscall.Handle(hdcValue)
	hdc := target
	memValue, _, _ := procCreateCompatibleDC.Call(uintptr(target))
	if memValue != 0 && r.Right > 0 && r.Bottom > 0 {
		bitmapValue, _, _ := procCreateCompatibleBitmap.Call(uintptr(target), uintptr(r.Right), uintptr(r.Bottom))
		if bitmapValue != 0 {
			oldBitmap, _, _ := procSelectObject.Call(memValue, bitmapValue)
			hdc = syscall.Handle(memValue)
			defer func() {
				procBitBlt.Call(uintptr(target), 0, 0, uintptr(r.Right), uintptr(r.Bottom), memValue, 0, 0, SRCCOPY)
				procSelectObject.Call(memValue, oldBitmap)
				procDeleteObject.Call(bitmapValue)
				procDeleteDC.Call(memValue)
			}()
		} else {
			procDeleteDC.Call(memValue)
		}
	}
	dpi := windowDPI(hwnd)
	fillDC(hdc, rect{0, 0, r.Right, r.Bottom}, rgb(248, 249, 251))
	result := getCurrentScan()
	if result == nil {
		message := tr(effectiveLocale(), "initializing")
		if scanInFlight {
			message = tr(effectiveLocale(), "scanning")
		}
		drawText(hdc, message, &rect{scale(28, dpi), scale(36, dpi), r.Right - scale(28, dpi), scale(100, dpi)}, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardTitleFont, rgb(54, 63, 75))
		return
	}
	contentHeight := dashboardContentHeight(result, dpi)
	si := scrollInfo{CbSize: uint32(unsafe.Sizeof(scrollInfo{})), FMask: SIF_RANGE | SIF_PAGE | SIF_POS, NMin: 0, NMax: contentHeight - 1, NPage: uint32(max32(1, r.Bottom)), NPos: dashboardScroll}
	procSetScrollInfo.Call(uintptr(hwnd), SB_VERT, uintptr(unsafe.Pointer(&si)), 1)
	offset := -dashboardScroll
	margin := scale(32, dpi)
	maxContent := scale(1180, dpi)
	contentW := min32(maxContent, r.Right-2*margin)
	if contentW < scale(440, dpi) {
		contentW = r.Right - 2*margin
	}
	left := (r.Right - contentW) / 2
	y := offset + scale(20, dpi)
	drawRoundedSurface(hdc, rect{left, y, left + scale(44, dpi), y + scale(44, dpi)}, rgb(229, 247, 234), rgb(229, 247, 234), scale(10, dpi))
	drawText(hdc, "✓", &rect{left, y, left + scale(44, dpi), y + scale(44, dpi)}, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, dashboardCardTitleFont, rgb(16, 124, 16))
	computer := strings.TrimSpace(result.Computer)
	if computer == "" {
		computer = tr(effectiveLocale(), "unknownComputer")
	}
	drawText(hdc, computer, &rect{left + scale(60, dpi), y - scale(2, dpi), left + contentW, y + scale(26, dpi)}, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, dashboardTitleFont, rgb(25, 31, 40))
	updated := fmt.Sprintf(shellText(effectiveLocale(), "updated"), result.GeneratedAt.Format("2006-01-02 15:04:05"))
	drawText(hdc, updated, &rect{left + scale(60, dpi), y + scale(28, dpi), left + contentW, y + scale(50, dpi)}, DT_LEFT|DT_SINGLELINE|DT_NOPREFIX, dashboardSmallFont, rgb(103, 111, 123))
	y += scale(72, dpi)
	drawSectionHeader(hdc, "disk", shellText(effectiveLocale(), "drives"), len(result.Disks), rect{left, y, left + contentW, y + scale(32, dpi)})
	y += scale(40, dpi)
	for _, disk := range result.Disks {
		card := rect{left, y, left + contentW, y + scale(340, dpi)}
		drawRoundedSurface(hdc, card, rgb(255, 255, 255), rgb(226, 229, 234), scale(14, dpi))
		percent, known := diskHealthPercent(disk)
		statusText, statusGood := diskStatusText(disk, known)
		drawHealthRing(hdc, card.Left+scale(28, dpi), card.Top+scale(62, dpi), scale(116, dpi), percent, known)
		textLeft := card.Left + scale(176, dpi)
		drawText(hdc, valueOrUnknownLocalized(effectiveLocale(), disk.Model), &rect{textLeft, card.Top + scale(20, dpi), card.Right - scale(90, dpi), card.Top + scale(48, dpi)}, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, dashboardCardTitleFont, rgb(26, 33, 44))
		drawText(hdc, fmt.Sprintf("PhysicalDrive%d", disk.Number), &rect{textLeft, card.Top + scale(47, dpi), card.Right - scale(90, dpi), card.Top + scale(70, dpi)}, DT_LEFT|DT_SINGLELINE|DT_NOPREFIX, dashboardSmallFont, rgb(117, 124, 136))
		drawHealthBadge(hdc, rect{card.Right - scale(88, dpi), card.Top + scale(18, dpi), card.Right - scale(20, dpi), card.Top + scale(46, dpi)}, statusText, statusGood)
		fillDC(hdc, rect{textLeft, card.Top + scale(76, dpi), card.Right - scale(20, dpi), card.Top + scale(77, dpi)}, rgb(233, 235, 239))
		read, written := diskReadWrite(disk)
		serial := serialDisplayValue(effectiveLocale(), disk.Serial, currentSettings().HideSerial)
		fields := []dashboardField{
			{tr(effectiveLocale(), "capacity"), func() string {
				if disk.Capacity > 0 {
					return formatCapacityBytes(disk.Capacity)
				}
				return tr(effectiveLocale(), "notReported")
			}()},
			{tr(effectiveLocale(), "bus"), valueOrUnknownLocalized(effectiveLocale(), disk.Bus)},
			{tr(effectiveLocale(), "serial"), serial}, {tr(effectiveLocale(), "temperature"), diskTemperature(disk)},
			{tr(effectiveLocale(), "firmware"), valueOrUnknownLocalized(effectiveLocale(), disk.Firmware)}, {tr(effectiveLocale(), "powerCycles"), diskPowerCycles(disk)},
			{tr(effectiveLocale(), "powerOnTime"), diskPowerHours(disk)}, {tr(effectiveLocale(), "totalWritten"), written},
			{tr(effectiveLocale(), "totalRead"), read}, {tr(effectiveLocale(), "healthStatus"), statusText},
			{tr(effectiveLocale(), "unsafeShutdowns"), diskUnsafeShutdowns(disk)}, {tr(effectiveLocale(), "errorLogEntries"), diskErrorLogEntries(disk)},
		}
		drawDashboardFields(hdc, fields, textLeft, card.Top+scale(88, dpi), card.Right-textLeft-scale(20, dpi), scale(40, dpi))
		y += scale(360, dpi)
	}
	drawSectionHeader(hdc, "battery", shellText(effectiveLocale(), "batteries"), len(result.Batteries), rect{left, y, left + contentW, y + scale(32, dpi)})
	y += scale(40, dpi)
	for _, battery := range result.Batteries {
		card := rect{left, y, left + contentW, y + scale(244, dpi)}
		drawRoundedSurface(hdc, card, rgb(255, 255, 255), rgb(226, 229, 234), scale(14, dpi))
		known := battery.HealthPercent > 0
		drawHealthRing(hdc, card.Left+scale(28, dpi), card.Top+scale(46, dpi), scale(116, dpi), battery.HealthPercent, known)
		textLeft := card.Left + scale(176, dpi)
		name := strings.TrimSpace(battery.Name)
		if name == "" {
			name = tr(effectiveLocale(), "internalBattery")
		}
		drawText(hdc, name, &rect{textLeft, card.Top + scale(20, dpi), card.Right - scale(90, dpi), card.Top + scale(48, dpi)}, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, dashboardCardTitleFont, rgb(26, 33, 44))
		batteryStatus := shellText(effectiveLocale(), "unknown")
		if known {
			batteryStatus = shellText(effectiveLocale(), "healthy")
		}
		drawHealthBadge(hdc, rect{card.Right - scale(88, dpi), card.Top + scale(18, dpi), card.Right - scale(20, dpi), card.Top + scale(46, dpi)}, batteryStatus, known)
		fillDC(hdc, rect{textLeft, card.Top + scale(64, dpi), card.Right - scale(20, dpi), card.Top + scale(65, dpi)}, rgb(233, 235, 239))
		fields := batteryDashboardFields(battery)
		drawDashboardFields(hdc, fields, textLeft, card.Top+scale(82, dpi), card.Right-textLeft-scale(20, dpi), scale(44, dpi))
		y += scale(264, dpi)
	}
	drawText(hdc, shellText(effectiveLocale(), "systemNote"), &rect{left, y + scale(12, dpi), left + contentW, y + scale(58, dpi)}, DT_LEFT|DT_NOPREFIX, dashboardSmallFont, rgb(112, 119, 130))
}

func dashboardProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		paintDashboard(hwnd)
		return 0
	case WM_VSCROLL:
		si := scrollInfo{CbSize: uint32(unsafe.Sizeof(scrollInfo{})), FMask: SIF_ALL}
		procGetScrollInfo.Call(uintptr(hwnd), SB_VERT, uintptr(unsafe.Pointer(&si)))
		position := dashboardScroll
		switch loword(wParam) {
		case SB_LINEUP:
			position -= scale(36, windowDPI(hwnd))
		case SB_LINEDOWN:
			position += scale(36, windowDPI(hwnd))
		case SB_PAGEUP:
			position -= int32(si.NPage)
		case SB_PAGEDOWN:
			position += int32(si.NPage)
		case SB_THUMBTRACK, SB_THUMBPOSITION:
			position = si.NTrackPos
		case SB_TOP:
			position = 0
		case SB_BOTTOM:
			position = si.NMax
		}
		maxPos := si.NMax - int32(si.NPage) + 1
		if maxPos < 0 {
			maxPos = 0
		}
		if position < 0 {
			position = 0
		}
		if position > maxPos {
			position = maxPos
		}
		if position != dashboardScroll {
			dashboardScroll = position
			procInvalidateRect.Call(uintptr(hwnd), 0, 1)
		}
		return 0
	case WM_MOUSEWHEEL:
		delta := int16(hiword(wParam))
		if delta > 0 {
			procSendMessageW.Call(uintptr(hwnd), WM_VSCROLL, SB_LINEUP, 0)
		} else if delta < 0 {
			procSendMessageW.Call(uintptr(hwnd), WM_VSCROLL, SB_LINEDOWN, 0)
		}
		return 0
	case WM_SIZE:
		procInvalidateRect.Call(uintptr(hwnd), 0, 1)
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func createSettingsControls(hwnd syscall.Handle) {
	settingsPageTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	settingsAppearanceTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	settingsLanguageLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	languageHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_LANGUAGE)
	hideSerialHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_AUTOCHECKBOX, 0, 0, 0, 0, hwnd, ID_HIDE_SERIAL)
	settingsPrivacyNoteHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT, 0, 0, 0, 0, hwnd, 0)
	settingsFontLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	zoomOutHwnd = createWindow(0, "BUTTON", "−", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_ZOOM_OUT)
	fontStatusHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_CENTER|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_FONTSTATUS)
	zoomInHwnd = createWindow(0, "BUTTON", "+", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_ZOOM_IN)
	settingsStorageTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	settingsModeLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	settingsModeHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_SETTINGS_MODE)
	settingsPathLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	pathHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE|SS_NOTIFY, 0, 0, 0, 0, hwnd, ID_PATH)
	settingsOpenHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_SETTINGS_OPEN)
	settingsChangeHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_SETTINGS_CHANGE)
	settingsReadTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
	settingsReadNoteHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT, 0, 0, 0, 0, hwnd, 0)
	settingsBridgeNoteHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT, 0, 0, 0, 0, hwnd, 0)
	pathLabelHwnd = settingsPathLabelHwnd
	for _, control := range []syscall.Handle{languageHwnd, hideSerialHwnd, zoomOutHwnd, zoomInHwnd, settingsModeHwnd, settingsOpenHwnd, settingsChangeHwnd} {
		setWindowTheme(control, "Explorer")
	}
}

func updateSettingsPageFonts() {
	if settingsPageHwnd == 0 {
		return
	}
	applyFont(settingsPageTitleHwnd, shellTitleFont)
	for _, control := range []syscall.Handle{settingsAppearanceTitleHwnd, settingsStorageTitleHwnd, settingsReadTitleHwnd} {
		applyFont(control, dashboardCardTitleFont)
	}
	for _, control := range []syscall.Handle{settingsLanguageLabelHwnd, languageHwnd, hideSerialHwnd, settingsFontLabelHwnd, zoomOutHwnd, fontStatusHwnd, zoomInHwnd, settingsModeLabelHwnd, settingsModeHwnd, settingsPathLabelHwnd, pathHwnd, settingsOpenHwnd, settingsChangeHwnd, settingsReadNoteHwnd, settingsBridgeNoteHwnd} {
		applyFont(control, dashboardBodyFont)
	}
	applyFont(settingsPrivacyNoteHwnd, dashboardSmallFont)
}

func updateSettingsPageTexts() {
	if settingsPageHwnd == 0 {
		return
	}
	code := effectiveLocale()
	settings := currentSettings()
	setText(settingsPageTitleHwnd, shellText(code, "settings"))
	setText(settingsAppearanceTitleHwnd, shellText(code, "appearance"))
	setText(settingsLanguageLabelHwnd, shellText(code, "language"))
	setText(languageHwnd, languageDisplayName(settings.Language)+"  ▾")
	setText(hideSerialHwnd, tr(code, "hideSerial"))
	setText(settingsPrivacyNoteHwnd, shellText(code, "hideNote"))
	setText(settingsFontLabelHwnd, shellText(code, "fontSize"))
	setText(fontStatusHwnd, fmt.Sprintf("%d pt", settings.FontSize))
	setText(settingsStorageTitleHwnd, shellText(code, "storage"))
	setText(settingsModeLabelHwnd, shellText(code, "saveReport"))
	mode := shellText(code, "onRefresh")
	if settings.HistoryMode == historyOnExport {
		mode = shellText(code, "onExport")
	}
	setText(settingsModeHwnd, mode+"  ▾")
	setText(settingsPathLabelHwnd, shellText(code, "historyLocation"))
	setText(pathHwnd, historyDirectory())
	setText(settingsOpenHwnd, tr(code, "openHistoryDir"))
	setText(settingsChangeHwnd, tr(code, "changeHistoryDir"))
	setText(settingsReadTitleHwnd, shellText(code, "hardware"))
	setText(settingsReadNoteHwnd, shellText(code, "readOnly"))
	setText(settingsBridgeNoteHwnd, shellText(code, "bridge"))
	check := uintptr(0)
	if settings.HideSerial {
		check = BST_CHECKED
	}
	procSendMessageW.Call(uintptr(hideSerialHwnd), BM_SETCHECK, check, 0)
}

// settingsContentGeometry is the single source of truth for the settings
// page's centered content column.  Both the child-control layout and the
// background card painter must use the same geometry; keeping a second copy
// of this calculation caused a subtle horizontal drift at narrow widths when
// the layout fallback used 16 px side padding while the painter still used
// 24 px.
func settingsContentGeometry(width int32, dpi int) (x, contentW int32) {
	if width < 0 {
		width = 0
	}
	maxW := scale(760, dpi)
	contentW = min32(maxW, width-scale(48, dpi))
	if contentW < scale(420, dpi) {
		contentW = width - scale(32, dpi)
	}
	if contentW < 0 {
		contentW = 0
	}
	if contentW > width {
		contentW = width
	}
	x = (width - contentW) / 2
	return
}

// settingsHeadingTextX optically aligns Win32 static text with the visible
// one-pixel edge of the antialiased card outline.  The controls and cards use
// the same geometry, but ClearType glyph overhang makes the text appear one
// device pixel farther left unless this final visual correction is applied.
func settingsHeadingTextX(cardX int32) int32 {
	return cardX + 1
}

func layoutSettingsPage() {
	if settingsPageHwnd == 0 || settingsLayoutInProgress {
		return
	}
	settingsLayoutInProgress = true
	defer func() { settingsLayoutInProgress = false }()
	r := clientRect(settingsPageHwnd)
	dpi := windowDPI(settingsPageHwnd)
	contentHeight := scale(610, dpi)
	si := scrollInfo{CbSize: uint32(unsafe.Sizeof(scrollInfo{})), FMask: SIF_RANGE | SIF_PAGE | SIF_POS, NMin: 0, NMax: contentHeight - 1, NPage: uint32(max32(1, r.Bottom)), NPos: settingsScroll}
	procSetScrollInfo.Call(uintptr(settingsPageHwnd), SB_VERT, uintptr(unsafe.Pointer(&si)), 1)
	// Showing the vertical scrollbar can reduce the child client width.  Read
	// the client rect again after SetScrollInfo; otherwise controls would use
	// the pre-scrollbar x coordinate while WM_PAINT would centre the cards in
	// the narrower post-scrollbar area (the intermittent ~10–14 px drift seen
	// on the first visit to Settings).
	r = clientRect(settingsPageHwnd)
	maxScroll := max32(0, contentHeight-r.Bottom)
	if settingsScroll > maxScroll {
		settingsScroll = maxScroll
	}
	settingsLayoutWidth = r.Right
	settingsLayoutHeight = r.Bottom
	settingsLayoutDPI = dpi
	settingsLayoutValid = true
	x, contentW := settingsContentGeometry(r.Right, dpi)
	headingX := settingsHeadingTextX(x)
	headingW := max32(0, contentW-(headingX-x))
	labelW := scale(170, dpi)
	rowH := scale(42, dpi)
	procMoveWindow.Call(uintptr(settingsPageTitleHwnd), uintptr(headingX), uintptr(scale(18, dpi)-settingsScroll), uintptr(headingW), uintptr(scale(38, dpi)), 1)
	y := scale(76, dpi) - settingsScroll
	procMoveWindow.Call(uintptr(settingsAppearanceTitleHwnd), uintptr(headingX), uintptr(y), uintptr(headingW), uintptr(scale(34, dpi)), 1)
	y += scale(42, dpi)
	procMoveWindow.Call(uintptr(settingsLanguageLabelHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(labelW), uintptr(rowH), 1)
	procMoveWindow.Call(uintptr(languageHwnd), uintptr(x+contentW-scale(220, dpi)), uintptr(y+scale(4, dpi)), uintptr(scale(206, dpi)), uintptr(scale(34, dpi)), 1)
	y += rowH
	procMoveWindow.Call(uintptr(hideSerialHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(contentW-scale(28, dpi)), uintptr(rowH), 1)
	y += rowH
	procMoveWindow.Call(uintptr(settingsPrivacyNoteHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(contentW-scale(28, dpi)), uintptr(scale(44, dpi)), 1)
	y += scale(48, dpi)
	procMoveWindow.Call(uintptr(settingsFontLabelHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(labelW), uintptr(rowH), 1)
	procMoveWindow.Call(uintptr(zoomOutHwnd), uintptr(x+contentW-scale(184, dpi)), uintptr(y+scale(4, dpi)), uintptr(scale(42, dpi)), uintptr(scale(34, dpi)), 1)
	procMoveWindow.Call(uintptr(fontStatusHwnd), uintptr(x+contentW-scale(136, dpi)), uintptr(y+scale(4, dpi)), uintptr(scale(76, dpi)), uintptr(scale(34, dpi)), 1)
	procMoveWindow.Call(uintptr(zoomInHwnd), uintptr(x+contentW-scale(54, dpi)), uintptr(y+scale(4, dpi)), uintptr(scale(42, dpi)), uintptr(scale(34, dpi)), 1)
	y += scale(70, dpi)
	procMoveWindow.Call(uintptr(settingsStorageTitleHwnd), uintptr(headingX), uintptr(y), uintptr(headingW), uintptr(scale(34, dpi)), 1)
	y += scale(42, dpi)
	procMoveWindow.Call(uintptr(settingsModeLabelHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(labelW), uintptr(rowH), 1)
	actionW := scale(206, dpi)
	procMoveWindow.Call(uintptr(settingsModeHwnd), uintptr(x+contentW-actionW-scale(14, dpi)), uintptr(y+scale(4, dpi)), uintptr(actionW), uintptr(scale(34, dpi)), 1)
	y += rowH
	procMoveWindow.Call(uintptr(settingsPathLabelHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(labelW), uintptr(rowH), 1)
	changeW := actionW
	procMoveWindow.Call(uintptr(pathHwnd), uintptr(x+labelW), uintptr(y), uintptr(contentW-labelW-changeW-scale(26, dpi)), uintptr(rowH), 1)
	procMoveWindow.Call(uintptr(settingsChangeHwnd), uintptr(x+contentW-changeW-scale(14, dpi)), uintptr(y+scale(4, dpi)), uintptr(changeW), uintptr(scale(34, dpi)), 1)
	y += rowH
	y += scale(28, dpi)
	procMoveWindow.Call(uintptr(settingsReadTitleHwnd), uintptr(headingX), uintptr(y), uintptr(headingW), uintptr(scale(34, dpi)), 1)
	y += scale(42, dpi)
	procMoveWindow.Call(uintptr(settingsReadNoteHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(contentW-scale(28, dpi)), uintptr(scale(28, dpi)), 1)
	y += scale(32, dpi)
	procMoveWindow.Call(uintptr(settingsBridgeNoteHwnd), uintptr(x+scale(14, dpi)), uintptr(y), uintptr(contentW-scale(28, dpi)), uintptr(scale(32, dpi)), 1)
}

func showSettingsModeMenu() {
	code := effectiveLocale()
	menu, _, _ := procCreatePopupMenu.Call()
	defer procDestroyMenu.Call(menu)
	first, second := uintptr(MF_STRING), uintptr(MF_STRING)
	if currentSettings().HistoryMode == historyOnRefresh {
		first |= MF_CHECKED
	} else {
		second |= MF_CHECKED
	}
	procAppendMenuW.Call(menu, first, MENU_MORE_REFRESH, uintptr(unsafe.Pointer(utf16Ptr(shellText(code, "onRefresh")))))
	procAppendMenuW.Call(menu, second, MENU_MORE_EXPORT, uintptr(unsafe.Pointer(utf16Ptr(shellText(code, "onExport")))))
	var position point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&position)))
	command, _, _ := procTrackPopupMenu.Call(menu, TPM_RETURNCMD|TPM_RIGHTALIGN|TPM_TOPALIGN, uintptr(position.X), uintptr(position.Y), 0, uintptr(settingsPageHwnd), 0)
	if command == MENU_MORE_REFRESH {
		updateSettings(func(s *appSettings) { s.HistoryMode = historyOnRefresh })
	}
	if command == MENU_MORE_EXPORT {
		updateSettings(func(s *appSettings) { s.HistoryMode = historyOnExport })
	}
	updateSettingsPageTexts()
}

func drawSettingsButton(dis *drawItemStruct) bool {
	if dis == nil {
		return false
	}
	switch dis.CtlID {
	case ID_LANGUAGE, ID_ZOOM_OUT, ID_ZOOM_IN, ID_SETTINGS_MODE, ID_SETTINGS_CHANGE:
	default:
		return false
	}
	dpi := windowDPI(settingsPageHwnd)
	background := rgb(255, 255, 255)
	border := rgb(218, 223, 231)
	foreground := rgb(42, 53, 70)
	if dis.ItemState&ODS_SELECTED != 0 {
		background = rgb(226, 237, 252)
		border = rgb(169, 194, 228)
		foreground = rgb(20, 91, 173)
	}
	if dis.ItemState&ODS_DISABLED != 0 {
		background = rgb(247, 248, 250)
		border = rgb(232, 235, 240)
		foreground = rgb(151, 158, 168)
	}
	drawRoundedSurface(dis.HDC, dis.RcItem, background, border, scale(8, dpi))
	r := dis.RcItem
	r.Left += scale(10, dpi)
	r.Right -= scale(10, dpi)
	drawText(dis.HDC, getText(syscall.Handle(dis.HwndItem)), &r, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, dashboardBodyFont, foreground)
	return true
}

func settingsPageProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		settingsPageHwnd = hwnd
		createSettingsControls(hwnd)
		updateSettingsPageFonts()
		updateSettingsPageTexts()
		return 0
	case WM_SIZE:
		layoutSettingsPage()
		return 0
	case WM_SHOWWINDOW:
		if wParam != 0 {
			// Showing the page is the first moment at which the child has its
			// final client width on some Windows/DPI combinations.  Reconcile
			// once after visibility changes before the first visible paint.
			settingsLayoutValid = false
			layoutSettingsPage()
		}
		return 0
	case WM_DPICHANGED:
		settingsLayoutValid = false
		updateSettingsPageFonts()
		layoutSettingsPage()
		procInvalidateRect.Call(uintptr(hwnd), 0, 1)
		return 0
	case WM_VSCROLL:
		si := scrollInfo{CbSize: uint32(unsafe.Sizeof(scrollInfo{})), FMask: SIF_ALL}
		procGetScrollInfo.Call(uintptr(hwnd), SB_VERT, uintptr(unsafe.Pointer(&si)))
		position := settingsScroll
		switch loword(wParam) {
		case SB_LINEUP:
			position -= scale(36, windowDPI(hwnd))
		case SB_LINEDOWN:
			position += scale(36, windowDPI(hwnd))
		case SB_PAGEUP:
			position -= int32(si.NPage)
		case SB_PAGEDOWN:
			position += int32(si.NPage)
		case SB_THUMBTRACK, SB_THUMBPOSITION:
			position = si.NTrackPos
		}
		maxPosition := max32(0, si.NMax-int32(si.NPage)+1)
		if position < 0 {
			position = 0
		}
		if position > maxPosition {
			position = maxPosition
		}
		if position != settingsScroll {
			settingsScroll = position
			layoutSettingsPage()
			procInvalidateRect.Call(uintptr(hwnd), 0, 1)
		}
		return 0
	case WM_MOUSEWHEEL:
		if int16(hiword(wParam)) > 0 {
			procSendMessageW.Call(uintptr(hwnd), WM_VSCROLL, SB_LINEUP, 0)
		} else {
			procSendMessageW.Call(uintptr(hwnd), WM_VSCROLL, SB_LINEDOWN, 0)
		}
		return 0
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			r := clientRect(hwnd)
			fillDC(syscall.Handle(hdc), rect{0, 0, r.Right, r.Bottom}, rgb(248, 249, 251))
			dpi := windowDPI(hwnd)
			if !settingsLayoutValid || settingsLayoutWidth != r.Right || settingsLayoutHeight != r.Bottom || settingsLayoutDPI != dpi {
				// Keep the painter and child controls synchronized even when the
				// first WM_PAINT arrives before WM_SIZE/WM_SHOWWINDOW processing.
				layoutSettingsPage()
				r = clientRect(hwnd)
				dpi = windowDPI(hwnd)
			}
			x, contentW := settingsContentGeometry(r.Right, dpi)
			offset := settingsScroll
			drawRoundedSurface(syscall.Handle(hdc), rect{x, scale(110, dpi) - offset, x + contentW, scale(292, dpi) - offset}, rgb(255, 255, 255), rgb(228, 231, 236), scale(8, dpi))
			drawRoundedSurface(syscall.Handle(hdc), rect{x, scale(354, dpi) - offset, x + contentW, scale(454, dpi) - offset}, rgb(255, 255, 255), rgb(228, 231, 236), scale(8, dpi))
			drawRoundedSurface(syscall.Handle(hdc), rect{x, scale(508, dpi) - offset, x + contentW, scale(590, dpi) - offset}, rgb(255, 255, 255), rgb(228, 231, 236), scale(8, dpi))
		}
		procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		return 0
	case WM_DRAWITEM:
		if drawSettingsButton((*drawItemStruct)(unsafe.Pointer(lParam))) {
			return 1
		}
	case WM_COMMAND:
		switch loword(wParam) {
		case ID_LANGUAGE:
			showLanguageMenu()
			updateShellTexts()
		case ID_HIDE_SERIAL:
			procSendMessageW.Call(uintptr(mainHwnd), WM_COMMAND, wParam, lParam)
		case ID_ZOOM_OUT, ID_ZOOM_IN:
			procSendMessageW.Call(uintptr(mainHwnd), WM_COMMAND, wParam, lParam)
			updateSettingsPageTexts()
		case ID_SETTINGS_MODE:
			showSettingsModeMenu()
		case ID_SETTINGS_OPEN:
			openHistoryDirectory()
		case ID_SETTINGS_CHANGE:
			changeHistoryDirectory()
			updateSettingsPageTexts()
		case ID_PATH:
			openHistoryDirectory()
		}
		return 0
	case WM_CTLCOLORSTATIC:
		procSetBkMode.Call(wParam, TRANSPARENT)
		procSetTextColor.Call(wParam, uintptr(rgb(38, 45, 57)))
		control := syscall.Handle(lParam)
		if control == pathHwnd {
			procSetTextColor.Call(wParam, uintptr(rgb(37, 99, 180)))
		}
		if control == settingsPageTitleHwnd || control == settingsAppearanceTitleHwnd || control == settingsStorageTitleHwnd || control == settingsReadTitleHwnd {
			return uintptr(shellCanvasBrush)
		}
		return uintptr(shellCardBrush)
	case WM_CTLCOLORBTN:
		procSetBkMode.Call(wParam, TRANSPARENT)
		return uintptr(shellCardBrush)
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func shellMainCommand(id uint16) bool {
	page, ok := shellPageForCommand(id)
	if !ok {
		return false
	}
	switchShellPage(page)
	return true
}

func shellPageForCommand(id uint16) (int, bool) {
	switch id {
	case ID_NAV_OVERVIEW:
		return shellPageOverview, true
	case ID_NAV_HISTORY, ID_HISTORY:
		return shellPageHistory, true
	case ID_NAV_SETTINGS:
		return shellPageSettings, true
	case ID_NAV_ABOUT:
		return shellPageAbout, true
	default:
		return 0, false
	}
}

// Keep imports used on old Windows builds where the standard settings path can
// resolve through environment variables only after the shell is initialized.
