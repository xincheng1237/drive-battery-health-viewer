//go:build windows

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const (
	ID_REFRESH     = 1001
	ID_EXPORT      = 1002
	ID_COPY        = 1003
	ID_HISTORY     = 1004
	ID_LANGUAGE    = 1005
	ID_ZOOM_OUT    = 1006
	ID_ZOOM_IN     = 1007
	ID_MORE        = 1008
	ID_REPORT      = 1101
	ID_STATUS      = 1102
	ID_PATH        = 1103
	ID_FONTSTATUS  = 1104
	ID_HIDE_SERIAL = 1105

	ID_H_OPEN_DIR   = 2001
	ID_H_CHANGE_DIR = 2002
	ID_H_LIST       = 2003
	ID_H_FULL       = 2004
	ID_H_EMPTY      = 2005
	ID_C_LIST       = 3001
	ID_C_CONTENT    = 3002
	ID_V_CONTENT    = 4001
	ID_D_CHECK      = 5001
	ID_D_DELETE     = 5002
	ID_D_CANCEL     = 5003

	ID_A_SUMMARY        = 7001
	ID_A_VERSION        = 7002
	ID_A_DEVELOPER      = 7003
	ID_A_FEEDBACK       = 7004
	ID_A_COPYRIGHT      = 7005
	ID_A_ACCENT         = 7006
	ID_A_AUTHOR         = 7007
	ID_A_GITHUB_INFO    = 7008
	ID_A_GITHUB_LINK    = 7009
	ID_A_COOLAPK_INFO   = 7010
	ID_A_COOLAPK_LINK   = 7011
	ID_A_FEEDBACK_INTRO = 7012
	ID_A_QQ_LABEL       = 7013
	ID_A_QQ_VALUE       = 7014
	ID_A_EMAIL_LABEL    = 7015
	ID_A_EMAIL_VALUE    = 7016
	ID_A_COPYRIGHT_TXT  = 7017

	MENU_LANG_BASE      = 6000
	MENU_MORE_OPEN      = 6101
	MENU_MORE_CHANGE    = 6102
	MENU_MORE_REFRESH   = 6103
	MENU_MORE_EXPORT    = 6104
	MENU_MORE_CHANGELOG = 6105
	MENU_MORE_ABOUT     = 6106
)

var (
	mainHwnd                                                                                              syscall.Handle
	refreshHwnd, exportHwnd, copyHwnd, historyButtonHwnd, languageHwnd, zoomOutHwnd, zoomInHwnd, moreHwnd syscall.Handle
	reportHwnd, statusHwnd, pathLabelHwnd, pathHwnd, fontStatusHwnd, hideSerialHwnd                       syscall.Handle
	mainUIFont, mainReportFont, mainStatusFont                                                            syscall.Handle
	mainDPI                                                                                               = 96

	scanMu         sync.RWMutex
	currentScan    *scanResult
	pendingScan    *scanResult
	scanInFlight   bool
	currentHistory *historyRecord

	historyHwnd                                                                                                                                                       syscall.Handle
	histTitleHwnd, histPathHwnd, histOpenHwnd, histChangeHwnd, histRecordsLabelHwnd, histPreviewLabelHwnd, histListHwnd, histPreviewHwnd, histFullHwnd, histEmptyHwnd syscall.Handle
	histSplitterHwnd, histDragOverlayHwnd                                                                                                                             syscall.Handle
	histFonts                                                                                                                                                         []syscall.Handle
	histSplitterBrush, histSplitterActiveBrush                                                                                                                        syscall.Handle
	histDragSnapshot                                                                                                                                                  syscall.Handle
	histDragSnapshotW, histDragSnapshotH                                                                                                                              int32
	histDragSourceLeftW, histDragSourceSplitW, histDragTargetLeftW, histDragLabelH                                                                                    int32
	histRecords                                                                                                                                                       []historyRecord
	histSelected                                                                                                                                                      = -1
	histHover                                                                                                                                                         = -1
	histHoverAlpha                                                                                                                                                    = 0
	histListOldProc, histSplitterOldProc                                                                                                                              uintptr
	histListCallback, histSplitterCallback                                                                                                                            uintptr
	histSplitRatio                                                                                                                                                    = 0.39
	histSplitDragging                                                                                                                                                 bool
	histSplitStartScreenX, histSplitStartLeftW                                                                                                                        int32
	histSplitPendingRatio                                                                                                                                             = 0.39
	histSplitLastRender                                                                                                                                               time.Time

	changelogHwnd                                                                                                           syscall.Handle
	changeTitleHwnd, changeSubtitleHwnd, changeVersionsLabelHwnd, changeContentLabelHwnd, changeListHwnd, changeContentHwnd syscall.Handle
	changeFonts                                                                                                             []syscall.Handle
	changeEntries                                                                                                           []changeVersion

	aboutHwnd, aboutTitleHwnd, aboutSummaryHwnd, aboutVersionHwnd            syscall.Handle
	aboutDeveloperTitleHwnd, aboutFeedbackTitleHwnd, aboutCopyrightTitleHwnd syscall.Handle
	aboutAccentHwnd, aboutAuthorHwnd, aboutGithubInfoHwnd                    syscall.Handle
	aboutGithubLinkHwnd, aboutCoolapkInfoHwnd, aboutCoolapkLinkHwnd          syscall.Handle
	aboutFeedbackIntroHwnd, aboutQQLabelHwnd, aboutQQValueHwnd               syscall.Handle
	aboutEmailLabelHwnd, aboutEmailValueHwnd, aboutCopyrightHwnd             syscall.Handle
	aboutFonts                                                               []syscall.Handle
	aboutAccentBrush                                                         syscall.Handle
	aboutLinkOldProc, aboutLinkCallback                                      uintptr
	aboutLastLinkHwnd                                                        syscall.Handle
	aboutLastLinkClick                                                       time.Time
	aboutScrollPos, aboutContentHeight                                       int32

	viewerHwnd, viewerEditHwnd syscall.Handle
	viewerFont                 syscall.Handle
	viewerText, viewerTitle    string

	deleteDialogHwnd, deleteTextHwnd, deleteCheckHwnd, deleteYesHwnd, deleteCancelHwnd syscall.Handle
	deleteDialogDone                                                                   bool
	deleteDialogConfirmed                                                              bool
	deleteDialogExternal                                                               bool
	deleteDialogShowExternal                                                           bool
	deleteDialogFont                                                                   syscall.Handle
	lastPathOpen                                                                       time.Time
)

func isAdmin() bool { r, _, _ := procIsUserAnAdmin.Call(); return r != 0 }
func relaunchElevated() bool {
	exe, e := os.Executable()
	if e != nil {
		return false
	}
	cwd, _ := os.Getwd()
	r, _, _ := procShellExecuteW.Call(0, uintptr(unsafe.Pointer(utf16Ptr("runas"))), uintptr(unsafe.Pointer(utf16Ptr(exe))), 0, uintptr(unsafe.Pointer(utf16Ptr(cwd))), SW_SHOWNORMAL)
	return r > 32
}

func detectLocale() string {
	r, _, _ := procGetUserDefaultUILanguage.Call()
	switch uint16(r) {
	case 0x0804, 0x1004, 0x0004:
		return "zh-CN"
	case 0x0419:
		return "ru"
	case 0x040c, 0x080c, 0x0c0c, 0x100c, 0x140c, 0x180c:
		return "fr"
	case 0x0407, 0x0807, 0x0c07, 0x1007, 0x1407:
		return "de"
	case 0x0412:
		return "ko"
	case 0x0411:
		return "ja"
	default:
		return "en"
	}
}

func setCurrentScan(r *scanResult) { scanMu.Lock(); currentScan = r; scanMu.Unlock() }
func getCurrentScan() *scanResult {
	scanMu.RLock()
	defer scanMu.RUnlock()
	if currentScan == nil {
		return nil
	}
	v := *currentScan
	return &v
}
func currentReportText() string {
	r := getCurrentScan()
	if r == nil {
		return ""
	}
	s := currentSettings()
	return renderReportWithOptions(*r, effectiveLocale(), s.HideSerial)
}

func historyDisplayText(text string) string {
	if currentSettings().HideSerial {
		return maskSerialLines(text)
	}
	return text
}

func cleanupLegacyTemporaryFiles() {
	dirs := []string{}
	if exe, e := os.Executable(); e == nil {
		dirs = append(dirs, filepath.Dir(exe))
	}
	if h, e := os.UserHomeDir(); e == nil {
		dirs = append(dirs, filepath.Join(h, "Downloads"))
	}
	for _, d := range dirs {
		for _, p := range []string{"battery-report-*.tmp", "get-disk-info-*.ps1", "hardware_health_battery_*.xml"} {
			matches, _ := filepath.Glob(filepath.Join(d, p))
			for _, m := range matches {
				_ = os.Remove(m)
			}
		}
	}
}

func deleteFonts(list []syscall.Handle) {
	for _, f := range list {
		if f != 0 {
			procDeleteObject.Call(uintptr(f))
		}
	}
}
func recreateMainFonts() {
	deleteFonts([]syscall.Handle{mainUIFont, mainReportFont, mainStatusFont})
	s := currentSettings()
	mainDPI = windowDPI(mainHwnd)
	uiPt := 9 + (s.FontSize-9)/3
	if uiPt < 9 {
		uiPt = 9
	}
	mainUIFont = createUIFontDPI(uiPt, FW_NORMAL, mainDPI)
	mainReportFont = createUIFontDPI(s.FontSize, FW_NORMAL, mainDPI)
	mainStatusFont = createUIFontDPI(maxInt(8, uiPt-1), FW_NORMAL, mainDPI)
	for _, h := range []syscall.Handle{refreshHwnd, exportHwnd, copyHwnd, historyButtonHwnd, languageHwnd, zoomOutHwnd, zoomInHwnd, moreHwnd} {
		applyFont(h, mainUIFont)
	}
	applyFont(reportHwnd, mainReportFont)
	applyFont(statusHwnd, mainStatusFont)
	applyFont(pathLabelHwnd, mainStatusFont)
	applyFont(pathHwnd, mainStatusFont)
	applyFont(fontStatusHwnd, mainStatusFont)
	applyFont(hideSerialHwnd, mainStatusFont)
	refreshSecondaryFonts()
}
func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func updateMainTexts() {
	code := effectiveLocale()
	setText(mainHwnd, tr(code, "reportTitle"))
	setText(refreshHwnd, tr(code, "refresh"))
	setText(exportHwnd, tr(code, "export"))
	setText(copyHwnd, tr(code, "copy"))
	setText(historyButtonHwnd, tr(code, "history"))
	setText(zoomOutHwnd, tr(code, "zoomOut"))
	setText(zoomInHwnd, tr(code, "zoomIn"))
	setText(moreHwnd, tr(code, "more"))
	s := currentSettings()
	setText(languageHwnd, trf(code, "languageMenu", languageDisplayName(s.Language)))
	setText(pathLabelHwnd, tr(code, "historyPath"))
	setText(pathHwnd, historyDirectory())
	setText(fontStatusHwnd, trf(code, "fontStatus", s.FontSize))
	setText(hideSerialHwnd, tr(code, "hideSerial"))
	check := uintptr(0)
	if s.HideSerial {
		check = BST_CHECKED
	}
	procSendMessageW.Call(uintptr(hideSerialHwnd), BM_SETCHECK, check, 0)
	if r := getCurrentScan(); r != nil {
		setRichText(reportHwnd, renderReportWithOptions(*r, code, s.HideSerial))
	} else if scanInFlight {
		setRichText(reportHwnd, tr(code, "scanning"))
	} else {
		setRichText(reportHwnd, tr(code, "initializing"))
	}
	updateSecondaryTexts()
}

func refreshSecondaryFonts() {
	if historyHwnd != 0 {
		recreateHistoryFonts()
	}
	if changelogHwnd != 0 {
		recreateChangeFonts()
	}
	if aboutHwnd != 0 {
		recreateAboutFonts()
	}
	if viewerHwnd != 0 {
		if viewerFont != 0 {
			procDeleteObject.Call(uintptr(viewerFont))
		}
		viewerFont = createUIFontDPI(currentSettings().FontSize, FW_NORMAL, windowDPI(viewerHwnd))
		applyFont(viewerEditHwnd, viewerFont)
	}
}
func updateSecondaryTexts() {
	if historyHwnd != 0 {
		updateHistoryTexts()
		reloadHistoryRecords()
	}
	if changelogHwnd != 0 {
		updateChangelogTexts()
		reloadChangelog()
	}
	if aboutHwnd != 0 {
		updateAboutTexts()
	}
}

func startScan() {
	scanMu.Lock()
	if scanInFlight {
		scanMu.Unlock()
		return
	}
	scanInFlight = true
	scanMu.Unlock()
	enableWindow(refreshHwnd, false)
	code := effectiveLocale()
	setText(statusHwnd, tr(code, "scanning"))
	setRichText(reportHwnd, tr(code, "scanning"))
	go func() {
		r := scanHardware()
		scanMu.Lock()
		pendingScan = &r
		scanMu.Unlock()
		procPostMessageW.Call(uintptr(mainHwnd), WM_APP_SCAN_DONE, 0, 0)
	}()
}

func finishScan() {
	scanMu.Lock()
	r := pendingScan
	pendingScan = nil
	scanInFlight = false
	scanMu.Unlock()
	enableWindow(refreshHwnd, true)
	if r == nil {
		return
	}
	setCurrentScan(r)
	code := effectiveLocale()
	s := currentSettings()
	reportText := renderReportWithOptions(*r, code, s.HideSerial)
	setRichText(reportHwnd, reportText)
	saved := false
	if s.HistoryMode == historyOnRefresh {
		rec := historyRecord{Version: appVersion, GeneratedAt: r.GeneratedAt, Computer: r.Computer, Locale: code, Source: historyOnRefresh, Report: reportText}
		if e := saveHistoryRecord(&rec); e == nil {
			currentHistory = &rec
			saved = true
		} else {
			setText(statusHwnd, trf(code, "historyReadFailed", e.Error()))
		}
	} else {
		currentHistory = nil
	}
	if saved {
		setText(statusHwnd, trf(code, "scanCompleteRefresh", len(r.Disks), len(r.Batteries)))
	} else {
		setText(statusHwnd, trf(code, "scanCompleteNoSave", len(r.Disks), len(r.Batteries)))
	}
	setText(pathHwnd, historyDirectory())
	if historyHwnd != 0 {
		reloadHistoryRecords()
	}
}

func copyUnicodeText(s string) error {
	if strings.TrimSpace(s) == "" {
		return fmt.Errorf("%s", tr(effectiveLocale(), "noReport"))
	}
	ok, _, _ := procOpenClipboard.Call(uintptr(mainHwnd))
	if ok == 0 {
		return fmt.Errorf("clipboard unavailable")
	}
	defer procCloseClipboard.Call()
	procEmptyClipboard.Call()
	u, err := syscall.UTF16FromString(s)
	if err != nil {
		return err
	}
	size := uintptr(len(u) * 2)
	mem, _, _ := procGlobalAlloc.Call(GMEM_MOVEABLE, size)
	if mem == 0 {
		return fmt.Errorf("clipboard allocation failed")
	}
	p, _, _ := procGlobalLock.Call(mem)
	if p == 0 {
		procGlobalFree.Call(mem)
		return fmt.Errorf("clipboard lock failed")
	}
	procRtlMoveMemory.Call(p, uintptr(unsafe.Pointer(&u[0])), size)
	procGlobalUnlock.Call(mem)
	r, _, _ := procSetClipboardData.Call(CF_UNICODETEXT, mem)
	if r == 0 {
		procGlobalFree.Call(mem)
		return fmt.Errorf("clipboard write failed")
	}
	return nil
}

func exportReport() {
	code := effectiveLocale()
	text := currentReportText()
	if strings.TrimSpace(text) == "" {
		messageBox(mainHwnd, tr(code, "errorTitle"), tr(code, "noReport"), MB_OK|MB_ICONERROR)
		return
	}
	name := fmt.Sprintf("HardwareHealth_%s_%s.txt", sanitizeFileName(os.Getenv("COMPUTERNAME")), time.Now().Format("20060102_150405"))
	path, ok, e := saveFileDialog(mainHwnd, tr(code, "exportTitle"), name, "", tr(code, "textFiles"), tr(code, "allFiles"))
	if e != nil {
		messageBox(mainHwnd, tr(code, "errorTitle"), trf(code, "exportFailed", e.Error()), MB_OK|MB_ICONERROR)
		return
	}
	if !ok {
		return
	}
	if e = writeUTF8BOM(path, text); e != nil {
		messageBox(mainHwnd, tr(code, "errorTitle"), trf(code, "exportFailed", e.Error()), MB_OK|MB_ICONERROR)
		return
	}
	s := currentSettings()
	if s.HistoryMode == historyOnExport {
		r := getCurrentScan()
		if r != nil {
			rec := historyRecord{Version: appVersion, GeneratedAt: time.Now(), Computer: r.Computer, Locale: code, Source: historyOnExport, Report: text, ExportPath: path}
			if e = saveHistoryRecord(&rec); e != nil {
				messageBox(mainHwnd, tr(code, "errorTitle"), trf(code, "exportHistoryFailed", e.Error()), MB_OK|MB_ICONWARNING)
			} else {
				currentHistory = &rec
			}
		}
	} else if currentHistory != nil {
		currentHistory.ExportPath = path
		_ = saveHistoryRecord(currentHistory)
	}
	messageBox(mainHwnd, tr(code, "exportSuccessTitle"), trf(code, "exportSuccessText", path), MB_OK|MB_ICONINFORMATION)
	if historyHwnd != 0 {
		reloadHistoryRecords()
	}
}

func showLanguageMenu() {
	code := effectiveLocale()
	m, _, _ := procCreatePopupMenu.Call()
	defer procDestroyMenu.Call(m)
	s := currentSettings()
	items := append([]string{languageSystem}, localeOrder...)
	for i, c := range items {
		flags := uintptr(MF_STRING)
		if s.Language == c {
			flags |= MF_CHECKED
		}
		label := languageDisplayName(c)
		procAppendMenuW.Call(m, flags, MENU_LANG_BASE+uintptr(i), uintptr(unsafe.Pointer(utf16Ptr(label))))
	}
	var p point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&p)))
	cmd, _, _ := procTrackPopupMenu.Call(m, TPM_RETURNCMD|TPM_RIGHTALIGN|TPM_TOPALIGN, uintptr(p.X), uintptr(p.Y), 0, uintptr(mainHwnd), 0)
	if cmd >= MENU_LANG_BASE && cmd < MENU_LANG_BASE+uintptr(len(items)) {
		chosen := items[int(cmd-MENU_LANG_BASE)]
		updateSettings(func(s *appSettings) { s.Language = chosen })
		updateMainTexts()
		layoutMain()
	}
	_ = code
}

func showMoreMenu() {
	code := effectiveLocale()
	m, _, _ := procCreatePopupMenu.Call()
	defer procDestroyMenu.Call(m)
	procAppendMenuW.Call(m, MF_STRING, MENU_MORE_OPEN, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "openHistoryDir")))))
	procAppendMenuW.Call(m, MF_STRING, MENU_MORE_CHANGE, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "changeHistoryDir")))))
	procAppendMenuW.Call(m, MF_SEPARATOR, 0, 0)
	procAppendMenuW.Call(m, MF_GRAYED|MF_STRING, 0, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "historySaveMode")))))
	s := currentSettings()
	f1 := uintptr(MF_STRING)
	f2 := uintptr(MF_STRING)
	if s.HistoryMode == historyOnRefresh {
		f1 |= MF_CHECKED
	} else {
		f2 |= MF_CHECKED
	}
	procAppendMenuW.Call(m, f1, MENU_MORE_REFRESH, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "saveOnRefresh")))))
	procAppendMenuW.Call(m, f2, MENU_MORE_EXPORT, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "saveOnExport")))))
	procAppendMenuW.Call(m, MF_SEPARATOR, 0, 0)
	procAppendMenuW.Call(m, MF_STRING, MENU_MORE_CHANGELOG, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "changelogTitle")))))
	procAppendMenuW.Call(m, MF_STRING, MENU_MORE_ABOUT, uintptr(unsafe.Pointer(utf16Ptr(tr(code, "about")))))
	var p point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&p)))
	cmd, _, _ := procTrackPopupMenu.Call(m, TPM_RETURNCMD|TPM_RIGHTALIGN|TPM_TOPALIGN, uintptr(p.X), uintptr(p.Y), 0, uintptr(mainHwnd), 0)
	switch cmd {
	case MENU_MORE_OPEN:
		openHistoryDirectory()
	case MENU_MORE_CHANGE:
		changeHistoryDirectory()
	case MENU_MORE_REFRESH:
		updateSettings(func(s *appSettings) { s.HistoryMode = historyOnRefresh })
	case MENU_MORE_EXPORT:
		updateSettings(func(s *appSettings) { s.HistoryMode = historyOnExport })
	case MENU_MORE_CHANGELOG:
		openChangelog()
	case MENU_MORE_ABOUT:
		openAbout()
	}
}

func openHistoryDirectory() {
	if time.Since(lastPathOpen) < 500*time.Millisecond {
		return
	}
	lastPathOpen = time.Now()
	code := effectiveLocale()
	_ = os.MkdirAll(historyDirectory(), 0755)
	if e := openPath(historyDirectory()); e != nil {
		messageBox(mainHwnd, tr(code, "errorTitle"), trf(code, "historyOpenFailed", e.Error()), MB_OK|MB_ICONERROR)
	}
}
func changeHistoryDirectory() {
	code := effectiveLocale()
	p, ok := chooseFolder(mainHwnd, tr(code, "selectHistoryFolder"))
	if !ok {
		return
	}
	updateSettings(func(s *appSettings) { s.HistoryDir = p })
	setText(pathHwnd, p)
	if historyHwnd != 0 {
		setText(histPathHwnd, p)
		reloadHistoryRecords()
	}
}

func changeZoom(delta int) {
	s := currentSettings()
	n := s.FontSize + delta
	if n < 8 {
		n = 8
	}
	if n > 24 {
		n = 24
	}
	if n == s.FontSize {
		return
	}
	updateSettings(func(s *appSettings) { s.FontSize = n })
	recreateMainFonts()
	updateMainTexts()
	layoutMain()
	if historyHwnd != 0 {
		layoutHistory()
	}
	if changelogHwnd != 0 {
		layoutChangelog()
	}
	if aboutHwnd != 0 {
		layoutAbout()
	}
}

func layoutMain() {
	if mainHwnd == 0 {
		return
	}
	r := clientRect(mainHwnd)
	w, h := r.Right, r.Bottom
	dpi := windowDPI(mainHwnd)
	m := scale(16, dpi)
	gap := scale(10, dpi)
	bh := scale(38, dpi)
	top := scale(14, dpi)
	leftBW := scale(112, dpi)
	langW := scale(205, dpi)
	smallW := scale(64, dpi)
	moreW := scale(82, dpi)
	x := m
	for _, b := range []syscall.Handle{refreshHwnd, exportHwnd, copyHwnd, historyButtonHwnd} {
		procMoveWindow.Call(uintptr(b), uintptr(x), uintptr(top), uintptr(leftBW), uintptr(bh), 1)
		x += leftBW + gap
	}
	right := w - m
	procMoveWindow.Call(uintptr(moreHwnd), uintptr(right-moreW), uintptr(top), uintptr(moreW), uintptr(bh), 1)
	right -= moreW + gap
	procMoveWindow.Call(uintptr(zoomInHwnd), uintptr(right-smallW), uintptr(top), uintptr(smallW), uintptr(bh), 1)
	right -= smallW + gap
	procMoveWindow.Call(uintptr(zoomOutHwnd), uintptr(right-smallW), uintptr(top), uintptr(smallW), uintptr(bh), 1)
	right -= smallW + gap
	procMoveWindow.Call(uintptr(languageHwnd), uintptr(right-langW), uintptr(top), uintptr(langW), uintptr(bh), 1)
	toolbarBottom := top + bh + scale(12, dpi)
	if x+langW+smallW*2+moreW+gap*4 > w-m { // compact two-row toolbar
		row2 := top + bh + gap
		right = w - m
		procMoveWindow.Call(uintptr(moreHwnd), uintptr(right-moreW), uintptr(row2), uintptr(moreW), uintptr(bh), 1)
		right -= moreW + gap
		procMoveWindow.Call(uintptr(zoomInHwnd), uintptr(right-smallW), uintptr(row2), uintptr(smallW), uintptr(bh), 1)
		right -= smallW + gap
		procMoveWindow.Call(uintptr(zoomOutHwnd), uintptr(right-smallW), uintptr(row2), uintptr(smallW), uintptr(bh), 1)
		right -= smallW + gap
		procMoveWindow.Call(uintptr(languageHwnd), uintptr(max32(m, right-langW)), uintptr(row2), uintptr(min32(langW, right-m)), uintptr(bh), 1)
		toolbarBottom = row2 + bh + scale(12, dpi)
	}
	statusH := scale(48, dpi)
	procMoveWindow.Call(uintptr(reportHwnd), uintptr(m), uintptr(toolbarBottom), uintptr(max32(100, w-2*m)), uintptr(max32(100, h-toolbarBottom-statusH)), 1)
	stTop := h - statusH
	lineH := statusH / 2
	fontW := scale(110, dpi)
	labelW := scale(90, dpi)
	hideW := max32(scale(150, dpi), measureTextWidth(mainHwnd, tr(effectiveLocale(), "hideSerial"), mainStatusFont)+scale(38, dpi))
	procMoveWindow.Call(uintptr(statusHwnd), uintptr(m), uintptr(stTop), uintptr(max32(80, w-2*m-fontW)), uintptr(lineH), 1)
	procMoveWindow.Call(uintptr(fontStatusHwnd), uintptr(w-m-fontW), uintptr(stTop), uintptr(fontW), uintptr(lineH), 1)
	procMoveWindow.Call(uintptr(pathLabelHwnd), uintptr(m), uintptr(stTop+lineH), uintptr(labelW), uintptr(lineH), 1)
	procMoveWindow.Call(uintptr(hideSerialHwnd), uintptr(w-m-hideW), uintptr(stTop+lineH), uintptr(hideW), uintptr(lineH), 1)
	procMoveWindow.Call(uintptr(pathHwnd), uintptr(m+labelW), uintptr(stTop+lineH), uintptr(max32(80, w-2*m-labelW-hideW-gap)), uintptr(lineH), 1)
}
func max32(a, b int32) int32 {
	if a > b {
		return a
	}
	return b
}
func min32(a, b int32) int32 {
	if a < b {
		return a
	}
	return b
}

func mainWindowProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		mainHwnd = hwnd
		applyWindowIcons(hwnd)
		_, _, _ = procLoadLibraryW.Call(uintptr(unsafe.Pointer(utf16Ptr("Msftedit.dll"))))
		refreshHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_REFRESH)
		exportHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_EXPORT)
		copyHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_COPY)
		historyButtonHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_HISTORY)
		languageHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_LANGUAGE)
		zoomOutHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_ZOOM_OUT)
		zoomInHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_ZOOM_IN)
		moreHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_MORE)
		reportHwnd = createWindow(WS_EX_CLIENTEDGE, "RICHEDIT50W", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|WS_TABSTOP|ES_MULTILINE|ES_AUTOVSCROLL|ES_AUTOHSCROLL|ES_READONLY|ES_NOHIDESEL, 0, 0, 0, 0, hwnd, ID_REPORT)
		if reportHwnd == 0 {
			reportHwnd = createWindow(WS_EX_CLIENTEDGE, "EDIT", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY, 0, 0, 0, 0, hwnd, ID_REPORT)
		}
		statusHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_STATUS)
		pathLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		pathHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE|SS_NOTIFY, 0, 0, 0, 0, hwnd, ID_PATH)
		fontStatusHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_FONTSTATUS)
		hideSerialHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_AUTOCHECKBOX, 0, 0, 0, 0, hwnd, ID_HIDE_SERIAL)
		setWindowTheme(reportHwnd, "Explorer")
		recreateMainFonts()
		updateMainTexts()
		setText(statusHwnd, tr(effectiveLocale(), "initializing"))
		procPostMessageW.Call(uintptr(hwnd), WM_APP_SCAN_DONE-1, 0, 0)
		return 0
	case WM_SIZE:
		if wParam != SIZE_MINIMIZED {
			layoutMain()
		}
		return 0
	case WM_DPICHANGED:
		if lParam != 0 {
			rr := (*rect)(unsafe.Pointer(lParam))
			procSetWindowPos.Call(uintptr(hwnd), 0, uintptr(rr.Left), uintptr(rr.Top), uintptr(rr.Right-rr.Left), uintptr(rr.Bottom-rr.Top), SWP_NOZORDER|SWP_SHOWWINDOW)
		}
		recreateMainFonts()
		layoutMain()
		return 0
	case WM_GETMINMAXINFO:
		if lParam != 0 {
			m := (*minMaxInfo)(unsafe.Pointer(lParam))
			m.MinTrackSize.X = scale(620, windowDPI(hwnd))
			m.MinTrackSize.Y = scale(440, windowDPI(hwnd))
		}
		return 0
	case WM_COMMAND:
		id := loword(wParam)
		switch id {
		case ID_REFRESH:
			startScan()
		case ID_EXPORT:
			exportReport()
		case ID_COPY:
			code := effectiveLocale()
			if e := copyUnicodeText(currentReportText()); e != nil {
				messageBox(hwnd, tr(code, "errorTitle"), trf(code, "copyFailed", e.Error()), MB_OK|MB_ICONERROR)
			} else {
				messageBox(hwnd, tr(code, "copySuccessTitle"), tr(code, "copySuccessText"), MB_OK|MB_ICONINFORMATION)
			}
		case ID_HISTORY:
			openHistory()
		case ID_LANGUAGE:
			showLanguageMenu()
		case ID_ZOOM_OUT:
			changeZoom(-1)
		case ID_ZOOM_IN:
			changeZoom(1)
		case ID_MORE:
			showMoreMenu()
		case ID_PATH:
			openHistoryDirectory()
		case ID_HIDE_SERIAL:
			v, _, _ := procSendMessageW.Call(uintptr(hideSerialHwnd), BM_GETCHECK, 0, 0)
			hide := v == BST_CHECKED
			updateSettings(func(s *appSettings) { s.HideSerial = hide })
			updateMainTexts()
			if histSelected >= 0 && histSelected < len(histRecords) {
				setRichText(histPreviewHwnd, historyDisplayText(histRecords[histSelected].Report))
			}
			if viewerHwnd != 0 {
				setRichText(viewerEditHwnd, historyDisplayText(viewerText))
			}
		}
		return 0
	case WM_APP_SCAN_DONE - 1:
		startScan()
		return 0
	case WM_APP_SCAN_DONE:
		finishScan()
		return 0
	case WM_CTLCOLORSTATIC:
		if syscall.Handle(lParam) == pathHwnd {
			procSetTextColor.Call(wParam, uintptr(rgb(25, 99, 210)))
			procSetBkMode.Call(wParam, TRANSPARENT)
			b, _, _ := procGetSysColorBrush.Call(COLOR_WINDOW)
			return b
		}
		procSetBkMode.Call(wParam, TRANSPARENT)
		b, _, _ := procGetSysColorBrush.Call(COLOR_WINDOW)
		return b
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		if historyHwnd != 0 {
			procDestroyWindow.Call(uintptr(historyHwnd))
		}
		if changelogHwnd != 0 {
			procDestroyWindow.Call(uintptr(changelogHwnd))
		}
		if viewerHwnd != 0 {
			procDestroyWindow.Call(uintptr(viewerHwnd))
		}
		if aboutHwnd != 0 {
			procDestroyWindow.Call(uintptr(aboutHwnd))
		}
		deleteFonts([]syscall.Handle{mainUIFont, mainReportFont, mainStatusFont})
		releaseAppIcons()
		procPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

// ---------- History window ----------
func sourceText(code, source string) string {
	switch source {
	case historyOnRefresh:
		return tr(code, "sourceRefresh")
	case historyOnExport:
		return tr(code, "sourceExport")
	default:
		return tr(code, "sourceLegacy")
	}
}
func recreateHistoryFonts() {
	deleteFonts(histFonts)
	dpi := windowDPI(historyHwnd)
	base := currentSettings().FontSize
	// Keep the history window visually subordinate to the main report.
	// All history text uses a slightly smaller default scale while preserving
	// the existing hierarchy between titles, records and auxiliary text.
	histFonts = []syscall.Handle{createUIFontDPI(base+6, FW_SEMIBOLD, dpi), createUIFontDPI(maxInt(8, base-2), FW_SEMIBOLD, dpi), createUIFontDPI(maxInt(8, base-1), FW_NORMAL, dpi), createUIFontDPI(maxInt(7, base-3), FW_NORMAL, dpi), createUIFontDPI(maxInt(7, base-3), FW_SEMIBOLD, dpi)}
	applyFont(histTitleHwnd, histFonts[0])
	for _, h := range []syscall.Handle{histOpenHwnd, histChangeHwnd, histFullHwnd} {
		applyFont(h, histFonts[2])
	}
	for _, h := range []syscall.Handle{histPathHwnd, histRecordsLabelHwnd, histPreviewLabelHwnd, histEmptyHwnd} {
		applyFont(h, histFonts[2])
	}
	applyFont(histPreviewHwnd, histFonts[2])
	itemH := scale(int32(44+(base-9)*3), dpi)
	procSendMessageW.Call(uintptr(histListHwnd), LB_SETITEMHEIGHT, 0, uintptr(itemH))
}
func updateHistoryTexts() {
	code := effectiveLocale()
	setText(historyHwnd, tr(code, "historyWindowTitle"))
	setText(histTitleHwnd, tr(code, "historyWindowTitle"))
	setText(histPathHwnd, historyDirectory())
	setText(histOpenHwnd, tr(code, "openHistoryDir"))
	setText(histChangeHwnd, tr(code, "changeHistoryDir"))
	setText(histRecordsLabelHwnd, tr(code, "historyRecords"))
	setText(histPreviewLabelHwnd, tr(code, "reportPreview"))
	setText(histFullHwnd, tr(code, "fullView"))
	setText(histEmptyHwnd, tr(code, "noHistoryInline"))
}
func reloadHistoryRecords() {
	if histListHwnd == 0 {
		return
	}
	records, e := loadHistoryRecords()
	if e != nil {
		setText(histEmptyHwnd, e.Error())
		procShowWindow.Call(uintptr(histEmptyHwnd), SW_SHOW)
		return
	}
	histRecords = records
	procSendMessageW.Call(uintptr(histListHwnd), WM_SETREDRAW, 0, 0)
	procSendMessageW.Call(uintptr(histListHwnd), LB_RESETCONTENT, 0, 0)
	for range records {
		procSendMessageW.Call(uintptr(histListHwnd), LB_ADDSTRING, 0, uintptr(unsafe.Pointer(utf16Ptr(" "))))
	}
	if len(records) == 0 {
		histSelected = -1
		setRichText(histPreviewHwnd, "")
		procShowWindow.Call(uintptr(histEmptyHwnd), SW_SHOW)
	} else {
		procShowWindow.Call(uintptr(histEmptyHwnd), SW_HIDE)
		if histSelected < 0 || histSelected >= len(records) {
			histSelected = 0
		}
		procSendMessageW.Call(uintptr(histListHwnd), LB_SETCURSEL, uintptr(histSelected), 0)
		setRichText(histPreviewHwnd, historyDisplayText(records[histSelected].Report))
	}
	procSendMessageW.Call(uintptr(histListHwnd), WM_SETREDRAW, 1, 0)
	procRedrawWindow.Call(uintptr(histListHwnd), 0, 0, RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN)
}
func openHistory() {
	if historyHwnd != 0 {
		showWindowFront(historyHwnd)
		reloadHistoryRecords()
		return
	}
	dpi := mainDPI
	historyHwnd = createWindow(WS_EX_APPWINDOW|WS_EX_CONTROLPARENT, "HHVHistoryWindow", tr(effectiveLocale(), "historyWindowTitle"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, scale(1080, dpi), scale(700, dpi), 0, 0)
	if historyHwnd != 0 {
		showWindowFront(historyHwnd)
	}
}
func historyDeleteRect(item rect, dpi int) rect {
	w := scale(72, dpi)
	h := scale(int32(30+maxInt(0, currentSettings().FontSize-9)), dpi)
	return rect{item.Right - w - scale(12, dpi), item.Top + (item.Bottom-item.Top-h)/2, item.Right - scale(12, dpi), item.Top + (item.Bottom-item.Top+h)/2}
}

type windowMove struct {
	h      syscall.Handle
	x, y   int32
	w, hgt int32
}

type historyMetrics struct {
	w, h, dpi                             int32
	m, titleH, buttonTop, buttonH         int32
	buttonStart, buttonW, buttonGap       int32
	titleW, pathTop, pathH                int32
	bodyTop, bodyH, labelH, splitW, total int32
	minLeft, minRight                     int32
	wideHeader                            bool
}

func currentHistoryMetrics() historyMetrics {
	r := clientRect(historyHwnd)
	dpi := int32(windowDPI(historyHwnd))
	w, h := r.Right, r.Bottom
	m := scale(24, int(dpi))
	if w < scale(720, int(dpi)) {
		m = scale(16, int(dpi))
	}
	titleH := scale(44, int(dpi))
	buttonH := scale(36, int(dpi))
	buttonGap := scale(12, int(dpi))
	wide := w >= scale(760, int(dpi))
	buttonTop := m + scale(2, int(dpi))
	buttonW := scale(190, int(dpi))
	buttonStart := w - m - buttonW*2 - buttonGap
	titleW := max32(scale(150, int(dpi)), buttonStart-m-scale(18, int(dpi)))
	headerBottom := m + titleH
	if !wide {
		buttonTop = m + titleH + scale(8, int(dpi))
		buttonW = max32(scale(120, int(dpi)), (w-2*m-buttonGap)/2)
		buttonStart = m
		titleW = max32(scale(120, int(dpi)), w-2*m)
		headerBottom = buttonTop + buttonH
	}
	pathTop := headerBottom + scale(8, int(dpi))
	pathH := scale(28, int(dpi))
	bodyTop := pathTop + pathH + scale(18, int(dpi))
	bodyH := h - bodyTop - m
	if bodyH < scale(80, int(dpi)) {
		bodyH = scale(80, int(dpi))
	}
	labelH := scale(32, int(dpi))
	splitW := scale(8, int(dpi))
	total := max32(0, w-2*m-splitW)
	return historyMetrics{
		w: w, h: h, dpi: dpi, m: m, titleH: titleH,
		buttonTop: buttonTop, buttonH: buttonH, buttonStart: buttonStart,
		buttonW: buttonW, buttonGap: buttonGap, titleW: titleW,
		pathTop: pathTop, pathH: pathH, bodyTop: bodyTop, bodyH: bodyH,
		labelH: labelH, splitW: splitW, total: total,
		minLeft: scale(180, int(dpi)), minRight: scale(220, int(dpi)), wideHeader: wide,
	}
}

func applyWindowMoves(moves []windowMove) {
	hdwp, _, _ := procBeginDeferWindowPos.Call(uintptr(len(moves)))
	if hdwp != 0 {
		for _, mv := range moves {
			hdwp, _, _ = procDeferWindowPos.Call(hdwp, uintptr(mv.h), 0, uintptr(mv.x), uintptr(mv.y), uintptr(mv.w), uintptr(mv.hgt), SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOREDRAW|SWP_NOCOPYBITS)
			if hdwp == 0 {
				break
			}
		}
		if hdwp != 0 {
			procEndDeferWindowPos.Call(hdwp)
			return
		}
	}
	for _, mv := range moves {
		procSetWindowPos.Call(uintptr(mv.h), 0, uintptr(mv.x), uintptr(mv.y), uintptr(mv.w), uintptr(mv.hgt), SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOREDRAW|SWP_NOCOPYBITS)
	}
}

func redrawWindowClean(hwnd syscall.Handle, area *rect) {
	var ptr uintptr
	if area != nil {
		ptr = uintptr(unsafe.Pointer(area))
	}
	procRedrawWindow.Call(uintptr(hwnd), ptr, 0, RDW_INVALIDATE|RDW_ERASE|RDW_FRAME|RDW_UPDATENOW|RDW_ALLCHILDREN)
}

func historyPaneMoves() ([]windowMove, historyMetrics) {
	m := currentHistoryMetrics()
	leftW, rightW, normalized := splitPaneWidths(m.total, m.minLeft, m.minRight, histSplitRatio)
	histSplitRatio = normalized
	rx := m.m + leftW + m.splitW
	innerGap := scale(10, int(m.dpi))
	fullW := min32(scale(150, int(m.dpi)), max32(scale(100, int(m.dpi)), rightW/3))
	previewLabelW := max32(scale(60, int(m.dpi)), rightW-fullW-innerGap)
	moves := []windowMove{
		{histRecordsLabelHwnd, m.m, m.bodyTop, leftW, m.labelH},
		{histListHwnd, m.m, m.bodyTop + m.labelH, leftW, m.bodyH - m.labelH},
		{histEmptyHwnd, m.m + scale(18, int(m.dpi)), m.bodyTop + m.labelH + scale(18, int(m.dpi)), max32(scale(80, int(m.dpi)), leftW-scale(36, int(m.dpi))), scale(70, int(m.dpi))},
		{histSplitterHwnd, m.m + leftW, m.bodyTop, m.splitW, m.bodyH},
		{histPreviewLabelHwnd, rx, m.bodyTop, previewLabelW, m.labelH},
		{histFullHwnd, rx + rightW - fullW, m.bodyTop, fullW, m.labelH},
		{histPreviewHwnd, rx, m.bodyTop + m.labelH, rightW, m.bodyH - m.labelH},
	}
	return moves, m
}

func layoutHistoryPanes(redraw bool) {
	if historyHwnd == 0 {
		return
	}
	moves, metrics := historyPaneMoves()
	if redraw {
		procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	}
	applyWindowMoves(moves)
	if redraw {
		procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
		body := rect{metrics.m, metrics.bodyTop, metrics.w - metrics.m, metrics.bodyTop + metrics.bodyH}
		redrawWindowClean(historyHwnd, &body)
	}
}

func historySplitGeometry(ratio float64) (x, bodyTop, bodyH, splitW int32, normalized float64) {
	m := currentHistoryMetrics()
	leftW, _, normalized := splitPaneWidths(m.total, m.minLeft, m.minRight, ratio)
	x = m.m + leftW
	return x, m.bodyTop, m.bodyH, m.splitW, normalized
}

func releaseHistoryDragSnapshot() {
	if histDragSnapshot != 0 {
		procDeleteObject.Call(uintptr(histDragSnapshot))
		histDragSnapshot = 0
	}
	histDragSnapshotW = 0
	histDragSnapshotH = 0
}

func beginHistoryDragOverlay() bool {
	if historyHwnd == 0 || histDragOverlayHwnd == 0 {
		return false
	}
	releaseHistoryDragSnapshot()

	r := clientRect(historyHwnd)
	dpi := windowDPI(historyHwnd)
	metrics := currentHistoryMetrics()
	m := metrics.m
	x, bodyTop, bodyH, splitW, normalized := historySplitGeometry(histSplitRatio)
	bodyW := r.Right - 2*m
	if bodyW <= splitW || bodyH <= 0 {
		return false
	}
	leftW := x - m

	pt := point{X: m, Y: bodyTop}
	procClientToScreen.Call(uintptr(historyHwnd), uintptr(unsafe.Pointer(&pt)))
	screenDC, _, _ := procGetDC.Call(0)
	if screenDC == 0 {
		return false
	}
	memoryDC, _, _ := procCreateCompatibleDC.Call(screenDC)
	if memoryDC == 0 {
		procReleaseDC.Call(0, screenDC)
		return false
	}
	bitmap, _, _ := procCreateCompatibleBitmap.Call(screenDC, uintptr(bodyW), uintptr(bodyH))
	if bitmap == 0 {
		procDeleteDC.Call(memoryDC)
		procReleaseDC.Call(0, screenDC)
		return false
	}
	oldBitmap, _, _ := procSelectObject.Call(memoryDC, bitmap)
	copied, _, _ := procBitBlt.Call(memoryDC, 0, 0, uintptr(bodyW), uintptr(bodyH), screenDC, uintptr(pt.X), uintptr(pt.Y), SRCCOPY)
	procSelectObject.Call(memoryDC, oldBitmap)
	procDeleteDC.Call(memoryDC)
	procReleaseDC.Call(0, screenDC)
	if copied == 0 {
		procDeleteObject.Call(bitmap)
		return false
	}

	histDragSnapshot = syscall.Handle(bitmap)
	histDragSnapshotW = bodyW
	histDragSnapshotH = bodyH
	histDragSourceLeftW = leftW
	histDragSourceSplitW = splitW
	histDragTargetLeftW = leftW
	histDragLabelH = scale(32, dpi)
	histSplitPendingRatio = normalized

	procSetWindowPos.Call(uintptr(histDragOverlayHwnd), HWND_TOP, uintptr(m), uintptr(bodyTop), uintptr(bodyW), uintptr(bodyH), SWP_NOACTIVATE|SWP_SHOWWINDOW)
	procInvalidateRect.Call(uintptr(histDragOverlayHwnd), 0, 0)
	procUpdateWindow.Call(uintptr(histDragOverlayHwnd))
	return true
}

func fillDC(hdc syscall.Handle, r rect, color uint32) {
	brush := createBrush(color)
	if brush == 0 {
		return
	}
	procFillRect.Call(uintptr(hdc), uintptr(unsafe.Pointer(&r)), uintptr(brush))
	procDeleteObject.Call(uintptr(brush))
}

func paintHistoryDragOverlay(hwnd syscall.Handle, hdc syscall.Handle) {
	client := clientRect(hwnd)
	w, h := client.Right, client.Bottom
	if w <= 0 || h <= 0 {
		return
	}

	backDC, _, _ := procCreateCompatibleDC.Call(uintptr(hdc))
	if backDC == 0 {
		return
	}
	backBitmap, _, _ := procCreateCompatibleBitmap.Call(uintptr(hdc), uintptr(w), uintptr(h))
	if backBitmap == 0 {
		procDeleteDC.Call(backDC)
		return
	}
	oldBack, _, _ := procSelectObject.Call(backDC, backBitmap)
	back := syscall.Handle(backDC)

	fillDC(back, rect{0, 0, w, h}, rgb(255, 255, 255))
	leftW := histDragTargetLeftW
	if leftW < 1 {
		leftW = 1
	}
	if leftW > w-histDragSourceSplitW-1 {
		leftW = w - histDragSourceSplitW - 1
	}
	rightX := leftW + histDragSourceSplitW
	rightW := w - rightX

	// Prepare clean pane surfaces before copying the captured content. The
	// header tint and pane borders make expansion areas look like real native
	// panes rather than exposed blank canvas.
	headerColor := rgb(246, 247, 249)
	fillDC(back, rect{0, 0, leftW, histDragLabelH}, headerColor)
	fillDC(back, rect{rightX, 0, w, histDragLabelH}, headerColor)

	if histDragSnapshot != 0 {
		sourceDC, _, _ := procCreateCompatibleDC.Call(uintptr(hdc))
		if sourceDC != 0 {
			oldSource, _, _ := procSelectObject.Call(sourceDC, uintptr(histDragSnapshot))
			sourceLeftCopy := min32(max32(0, histDragSourceLeftW-scale(2, windowDPI(historyHwnd))), leftW)
			if sourceLeftCopy > 0 {
				procBitBlt.Call(backDC, 0, 0, uintptr(sourceLeftCopy), uintptr(h), sourceDC, 0, 0, SRCCOPY)
			}
			sourceRightX := histDragSourceLeftW + histDragSourceSplitW
			sourceRightW := histDragSnapshotW - sourceRightX
			rightCopy := min32(sourceRightW, rightW)
			if rightCopy > 0 {
				procBitBlt.Call(backDC, uintptr(rightX), 0, uintptr(rightCopy), uintptr(h), sourceDC, uintptr(sourceRightX), 0, SRCCOPY)
			}
			procSelectObject.Call(sourceDC, oldSource)
			procDeleteDC.Call(sourceDC)
		}
	}

	// Draw a subtle native-looking divider. It follows the pointer in real
	// time, but the expensive list and Rich Edit controls remain untouched
	// until release, eliminating the redraw trails seen in earlier builds.
	dividerColor := rgb(228, 232, 238)
	dividerLine := rgb(151, 161, 176)
	fillDC(back, rect{leftW, 0, rightX, h}, dividerColor)
	center := leftW + histDragSourceSplitW/2
	fillDC(back, rect{center, 0, center + max32(1, scale(1, windowDPI(historyHwnd))), h}, dividerLine)

	border := rgb(199, 205, 214)
	fillDC(back, rect{max32(0, leftW-1), 0, leftW, h}, border)
	fillDC(back, rect{rightX, 0, min32(w, rightX+1), h}, border)
	fillDC(back, rect{0, histDragLabelH - 1, leftW, histDragLabelH}, border)
	fillDC(back, rect{rightX, histDragLabelH - 1, w, histDragLabelH}, border)

	procBitBlt.Call(uintptr(hdc), 0, 0, uintptr(w), uintptr(h), backDC, 0, 0, SRCCOPY)
	procSelectObject.Call(backDC, oldBack)
	procDeleteObject.Call(backBitmap)
	procDeleteDC.Call(backDC)
}

func historyDragOverlayProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			paintHistoryDragOverlay(hwnd, syscall.Handle(hdc))
		}
		procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func updateHistoryDragOverlay(ratio float64, force bool) {
	if histDragOverlayHwnd == 0 || histDragSnapshot == 0 {
		return
	}
	if !force && time.Since(histSplitLastRender) < 10*time.Millisecond {
		return
	}
	_, _, _, _, normalized := historySplitGeometry(ratio)
	histSplitPendingRatio = normalized
	total := histDragSnapshotW - histDragSourceSplitW
	metrics := currentHistoryMetrics()
	leftW, _, normalized := splitPaneWidths(total, metrics.minLeft, metrics.minRight, normalized)
	histSplitPendingRatio = normalized
	histDragTargetLeftW = leftW
	procInvalidateRect.Call(uintptr(histDragOverlayHwnd), 0, 0)
	procUpdateWindow.Call(uintptr(histDragOverlayHwnd))
	histSplitLastRender = time.Now()
}

func finishHistorySplitDrag(releaseCapture bool) {
	if !histSplitDragging {
		return
	}
	histSplitDragging = false
	if releaseCapture {
		procReleaseCapture.Call()
	}

	// Keep the snapshot overlay visible while the real controls are moved once
	// underneath it. Hiding the overlay only after the final layout prevents a
	// one-frame flash of the old geometry.
	histSplitRatio = histSplitPendingRatio
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	layoutHistoryPanes(false)
	if histDragOverlayHwnd != 0 {
		procShowWindow.Call(uintptr(histDragOverlayHwnd), SW_HIDE)
	}
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
	releaseHistoryDragSnapshot()

	r := clientRect(historyHwnd)
	dpi := windowDPI(historyHwnd)
	m := scale(24, dpi)
	_, bodyTop, bodyH, _, _ := historySplitGeometry(histSplitRatio)
	body := rect{m, bodyTop, r.Right - m, bodyTop + bodyH}
	procRedrawWindow.Call(uintptr(historyHwnd), uintptr(unsafe.Pointer(&body)), 0, RDW_INVALIDATE|RDW_ERASE|RDW_UPDATENOW|RDW_ALLCHILDREN)
}

func historySplitterProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_SETCURSOR:
		c, _, _ := procLoadCursorW.Call(0, IDC_SIZEWE)
		procSetCursor.Call(c)
		return 1
	case WM_LBUTTONDOWN:
		var pt point
		procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
		histSplitDragging = true
		histSplitStartScreenX = pt.X
		var lr rect
		procGetWindowRect.Call(uintptr(histListHwnd), uintptr(unsafe.Pointer(&lr)))
		histSplitStartLeftW = lr.Right - lr.Left
		histSplitPendingRatio = histSplitRatio
		histSplitLastRender = time.Time{}
		procSetCapture.Call(uintptr(hwnd))
		if !beginHistoryDragOverlay() {
			// If screen capture is unavailable, retain a quiet, stable fallback:
			// the resize cursor remains active and the final width is still applied.
			histDragTargetLeftW = histSplitStartLeftW
		}
		return 0
	case WM_MOUSEMOVE:
		if histSplitDragging {
			var pt point
			procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
			metrics := currentHistoryMetrics()
			total := metrics.total
			if total > 0 {
				wanted := histSplitStartLeftW + pt.X - histSplitStartScreenX
				_, _, normalized := splitPaneWidths(total, metrics.minLeft, metrics.minRight, float64(wanted)/float64(total))
				histSplitPendingRatio = normalized
				updateHistoryDragOverlay(normalized, false)
			}
			return 0
		}
	case WM_LBUTTONUP:
		if histSplitDragging {
			updateHistoryDragOverlay(histSplitPendingRatio, true)
			finishHistorySplitDrag(true)
			return 0
		}
	case WM_CAPTURECHANGED:
		if histSplitDragging {
			finishHistorySplitDrag(false)
			return 0
		}
	}
	r, _, _ := procCallWindowProcW.Call(histSplitterOldProc, uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}
func historyListProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_MOUSEMOVE:
		x := int32(int16(loword(lParam)))
		ret, _, _ := procSendMessageW.Call(uintptr(hwnd), LB_ITEMFROMPOINT, 0, lParam)
		idx := int(loword(ret))
		outside := hiword(ret) != 0
		if outside || idx >= len(histRecords) {
			idx = -1
		} else {
			var itemRect rect
			procSendMessageW.Call(uintptr(hwnd), LB_GETITEMRECT, uintptr(idx), uintptr(unsafe.Pointer(&itemRect)))
			// The delete action is intentionally revealed only while the pointer is in
			// the right half of the record. The left half remains a quiet selection area.
			if !historyDeleteReveal(itemRect.Left, itemRect.Right, x) {
				idx = -1
			}
		}
		if idx != histHover {
			old := histHover
			histHover = idx
			histHoverAlpha = 0
			if old >= 0 {
				invalidateListItem(hwnd, old)
			}
			if idx >= 0 {
				invalidateListItem(hwnd, idx)
				procSetTimer.Call(uintptr(hwnd), 1, 16, 0)
			}
		}
		t := trackMouseEvent{CbSize: uint32(unsafe.Sizeof(trackMouseEvent{})), DwFlags: TME_LEAVE, HwndTrack: hwnd}
		procTrackMouseEvent.Call(uintptr(unsafe.Pointer(&t)))
	case WM_MOUSELEAVE:
		old := histHover
		histHover = -1
		histHoverAlpha = 0
		procKillTimer.Call(uintptr(hwnd), 1)
		if old >= 0 {
			invalidateListItem(hwnd, old)
		}
		return 0
	case WM_TIMER:
		if histHover >= 0 && histHoverAlpha < 255 {
			remaining := 255 - histHoverAlpha
			step := maxInt(12, int(float64(remaining)*0.32))
			histHoverAlpha += step
			if histHoverAlpha > 255 {
				histHoverAlpha = 255
			}
			invalidateListItem(hwnd, histHover)
			if histHoverAlpha >= 255 {
				procKillTimer.Call(uintptr(hwnd), 1)
			}
		}
		return 0
	case WM_LBUTTONUP:
		if histHover >= 0 && histHover < len(histRecords) {
			var rr rect
			procSendMessageW.Call(uintptr(hwnd), LB_GETITEMRECT, uintptr(histHover), uintptr(unsafe.Pointer(&rr)))
			x := int32(int16(loword(lParam)))
			y := int32(int16(hiword(lParam)))
			dr := historyDeleteRect(rr, windowDPI(historyHwnd))
			if x >= dr.Left && x <= dr.Right && y >= dr.Top && y <= dr.Bottom {
				deleteHistoryAt(histHover)
				return 0
			}
		}
	case WM_LBUTTONDBLCLK:
		idx, _, _ := procSendMessageW.Call(uintptr(hwnd), LB_GETCURSEL, 0, 0)
		if int(idx) >= 0 && int(idx) < len(histRecords) {
			showFullReport(histRecords[int(idx)])
		}
		return 0
	}
	r, _, _ := procCallWindowProcW.Call(histListOldProc, uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}
func invalidateListItem(h syscall.Handle, i int) {
	if i < 0 {
		return
	}
	var r rect
	procSendMessageW.Call(uintptr(h), LB_GETITEMRECT, uintptr(i), uintptr(unsafe.Pointer(&r)))
	procInvalidateRect.Call(uintptr(h), uintptr(unsafe.Pointer(&r)), 0)
}
func drawHistoryItem(dis *drawItemStruct) {
	i := int(dis.ItemID)
	if i < 0 || i >= len(histRecords) {
		return
	}
	r := dis.RcItem
	w, h := r.Right-r.Left, r.Bottom-r.Top
	mem, _, _ := procCreateCompatibleDC.Call(uintptr(dis.HDC))
	bmp, _, _ := procCreateCompatibleBitmap.Call(uintptr(dis.HDC), uintptr(w), uintptr(h))
	oldBmp, _, _ := procSelectObject.Call(mem, bmp)
	local := rect{0, 0, w, h}
	selected := dis.ItemState&ODS_SELECTED != 0
	hover := i == histHover
	bg := rgb(255, 255, 255)
	if selected {
		bg = rgb(235, 243, 255)
	} else if hover {
		bg = rgb(248, 251, 255)
	}
	brush := createBrush(bg)
	procFillRect.Call(mem, uintptr(unsafe.Pointer(&local)), uintptr(brush))
	procDeleteObject.Call(uintptr(brush))
	dpi := windowDPI(historyHwnd)
	pad := scale(14, dpi)
	dr := historyDeleteRect(local, dpi)
	textRight := local.Right - pad
	if hover {
		textRight = dr.Left - scale(10, dpi)
	}
	base := currentSettings().FontSize
	titleBottom := scale(int32(31+(base-9)*2), dpi)
	dateR := rect{pad, scale(6, dpi), textRight, titleBottom}
	subR := rect{pad, titleBottom - scale(2, dpi), textRight, local.Bottom - scale(4, dpi)}
	rec := histRecords[i]
	drawText(syscall.Handle(mem), rec.GeneratedAt.Format("2006-01-02 15:04:05"), &dateR, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, histFonts[1], rgb(22, 35, 55))
	computer := strings.TrimSpace(rec.Computer)
	if computer == "" {
		computer = tr(effectiveLocale(), "unknownComputer")
	}
	subtitle := computer + "  ·  " + sourceText(effectiveLocale(), rec.Source)
	drawText(syscall.Handle(mem), subtitle, &subR, DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, histFonts[3], rgb(83, 105, 140))
	if hover {
		a := histHoverAlpha
		ease := 255 - (255-a)*(255-a)/255
		red := byte(255)
		green := byte(255 - (18 * ease / 255))
		blue := byte(255 - (18 * ease / 255))
		b := createBrush(rgb(red, green, blue))
		p := createPen(rgb(218, 65, 65), 1)
		ob, _, _ := procSelectObject.Call(mem, uintptr(b))
		op, _, _ := procSelectObject.Call(mem, uintptr(p))
		procRoundRect.Call(mem, uintptr(dr.Left), uintptr(dr.Top), uintptr(dr.Right), uintptr(dr.Bottom), uintptr(scale(8, dpi)), uintptr(scale(8, dpi)))
		procSelectObject.Call(mem, ob)
		procSelectObject.Call(mem, op)
		procDeleteObject.Call(uintptr(b))
		procDeleteObject.Call(uintptr(p))
		drawText(syscall.Handle(mem), tr(effectiveLocale(), "delete"), &dr, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, histFonts[4], rgb(190, 35, 45))
	}
	sep := createBrush(rgb(229, 234, 241))
	sr := rect{0, h - 1, w, h}
	procFillRect.Call(mem, uintptr(unsafe.Pointer(&sr)), uintptr(sep))
	procDeleteObject.Call(uintptr(sep))
	procBitBlt.Call(uintptr(dis.HDC), uintptr(r.Left), uintptr(r.Top), uintptr(w), uintptr(h), mem, 0, 0, SRCCOPY)
	procSelectObject.Call(mem, oldBmp)
	procDeleteObject.Call(bmp)
	procDeleteDC.Call(mem)
}

func deleteHistoryAt(i int) {
	if i < 0 || i >= len(histRecords) {
		return
	}
	rec := histRecords[i]
	_, externalAvailable := linkedExternalReport(rec)
	confirmed, external := showDeleteDialog(externalAvailable)
	if !confirmed {
		return
	}
	if e := deleteHistoryRecord(rec, external); e != nil {
		messageBox(historyHwnd, tr(effectiveLocale(), "errorTitle"), trf(effectiveLocale(), "deleteFailed", e.Error()), MB_OK|MB_ICONERROR)
	}
	histSelected = -1
	reloadHistoryRecords()
}
func showDeleteDialog(showExternal bool) (bool, bool) {
	deleteDialogDone = false
	deleteDialogConfirmed = false
	deleteDialogExternal = false
	deleteDialogShowExternal = showExternal
	// Suppress redraw while the owner changes enabled state. This keeps the
	// history window visually stable instead of flashing when the confirmation
	// window is opened or closed.
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	enableWindow(historyHwnd, false)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
	dpi := windowDPI(historyHwnd)
	deleteDialogHwnd = createWindow(0, "HHVDeleteDialog", tr(effectiveLocale(), "deleteConfirmTitle"), WS_CAPTION|WS_SYSMENU|WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, scale(500, dpi), scale(230, dpi), historyHwnd, 0)
	if deleteDialogHwnd == 0 {
		procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
		enableWindow(historyHwnd, true)
		procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
		return false, false
	}
	showWindowFront(deleteDialogHwnd)
	var m msg
	for !deleteDialogDone {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	enableWindow(historyHwnd, true)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
	procSetForegroundWindow.Call(uintptr(historyHwnd))
	if histListHwnd != 0 {
		procSetFocus.Call(uintptr(histListHwnd))
	}
	return deleteDialogConfirmed, deleteDialogExternal
}
func deleteDialogProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		deleteDialogHwnd = hwnd
		applyWindowIcons(hwnd)
		dpi := windowDPI(hwnd)
		deleteDialogFont = createUIFontDPI(currentSettings().FontSize, FW_NORMAL, dpi)
		deleteTextHwnd = createWindow(0, "STATIC", tr(effectiveLocale(), "deleteConfirmText"), WS_CHILD|WS_VISIBLE|SS_LEFT, 0, 0, 0, 0, hwnd, 0)
		checkText := tr(effectiveLocale(), "deleteExternal")
		if !deleteDialogShowExternal {
			checkText = tr(effectiveLocale(), "deleteExternalUnavailable")
		}
		deleteCheckHwnd = createWindow(0, "BUTTON", checkText, WS_CHILD|WS_VISIBLE|BS_AUTOCHECKBOX, 0, 0, 0, 0, hwnd, ID_D_CHECK)
		deleteYesHwnd = createWindow(0, "BUTTON", tr(effectiveLocale(), "delete"), WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_D_DELETE)
		deleteCancelHwnd = createWindow(0, "BUTTON", tr(effectiveLocale(), "cancel"), WS_CHILD|WS_VISIBLE|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_D_CANCEL)
		for _, h := range []syscall.Handle{deleteTextHwnd, deleteCheckHwnd, deleteYesHwnd, deleteCancelHwnd} {
			applyFont(h, deleteDialogFont)
		}
		if !deleteDialogShowExternal {
			enableWindow(deleteCheckHwnd, false)
		}
		return 0
	case WM_SIZE:
		r := clientRect(hwnd)
		dpi := windowDPI(hwnd)
		m := scale(22, dpi)
		procMoveWindow.Call(uintptr(deleteTextHwnd), uintptr(m), uintptr(m), uintptr(r.Right-2*m), uintptr(scale(42, dpi)), 1)
		procMoveWindow.Call(uintptr(deleteCheckHwnd), uintptr(m), uintptr(scale(78, dpi)), uintptr(r.Right-2*m), uintptr(scale(30, dpi)), 1)
		bw := scale(100, dpi)
		bh := scale(34, dpi)
		procMoveWindow.Call(uintptr(deleteCancelHwnd), uintptr(r.Right-m-bw), uintptr(r.Bottom-m-bh), uintptr(bw), uintptr(bh), 1)
		procMoveWindow.Call(uintptr(deleteYesHwnd), uintptr(r.Right-m-bw*2-scale(10, dpi)), uintptr(r.Bottom-m-bh), uintptr(bw), uintptr(bh), 1)
		return 0
	case WM_COMMAND:
		switch loword(wParam) {
		case ID_D_DELETE:
			deleteDialogConfirmed = true
			if deleteDialogShowExternal {
				v, _, _ := procSendMessageW.Call(uintptr(deleteCheckHwnd), BM_GETCHECK, 0, 0)
				deleteDialogExternal = v == BST_CHECKED
			}
			procDestroyWindow.Call(uintptr(hwnd))
		case ID_D_CANCEL:
			procDestroyWindow.Call(uintptr(hwnd))
		}
		return 0
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		deleteDialogDone = true
		if deleteDialogFont != 0 {
			procDeleteObject.Call(uintptr(deleteDialogFont))
			deleteDialogFont = 0
		}
		deleteDialogHwnd = 0
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func showFullReport(rec historyRecord) {
	viewerTitle = tr(effectiveLocale(), "historyWindowTitle") + " — " + rec.GeneratedAt.Format("2006-01-02 15:04:05")
	viewerText = rec.Report
	if viewerHwnd != 0 {
		showWindowFront(viewerHwnd)
		setText(viewerHwnd, viewerTitle)
		setRichText(viewerEditHwnd, historyDisplayText(viewerText))
		return
	}
	dpi := mainDPI
	viewerHwnd = createWindow(WS_EX_APPWINDOW, "HHVViewerWindow", viewerTitle, WS_OVERLAPPEDWINDOW|WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, scale(900, dpi), scale(680, dpi), 0, 0)
	showWindowFront(viewerHwnd)
}
func viewerProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		viewerHwnd = hwnd
		applyWindowIcons(hwnd)
		viewerEditHwnd = createWindow(WS_EX_CLIENTEDGE, "RICHEDIT50W", historyDisplayText(viewerText), WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|ES_AUTOHSCROLL, 0, 0, 0, 0, hwnd, ID_V_CONTENT)
		viewerFont = createUIFontDPI(currentSettings().FontSize, FW_NORMAL, windowDPI(hwnd))
		applyFont(viewerEditHwnd, viewerFont)
		return 0
	case WM_SIZE:
		r := clientRect(hwnd)
		m := scale(12, windowDPI(hwnd))
		procMoveWindow.Call(uintptr(viewerEditHwnd), uintptr(m), uintptr(m), uintptr(r.Right-2*m), uintptr(r.Bottom-2*m), 1)
		return 0
	case WM_GETMINMAXINFO:
		if lParam != 0 {
			m := (*minMaxInfo)(unsafe.Pointer(lParam))
			m.MinTrackSize.X = 600
			m.MinTrackSize.Y = 420
		}
		return 0
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		if viewerFont != 0 {
			procDeleteObject.Call(uintptr(viewerFont))
			viewerFont = 0
		}
		viewerHwnd = 0
		viewerEditHwnd = 0
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func layoutHistory() {
	if historyHwnd == 0 {
		return
	}
	if !histSplitDragging && histDragOverlayHwnd != 0 {
		procShowWindow.Call(uintptr(histDragOverlayHwnd), SW_HIDE)
		releaseHistoryDragSnapshot()
	}
	m := currentHistoryMetrics()
	paneMoves, _ := historyPaneMoves()
	moves := []windowMove{
		{histTitleHwnd, m.m, m.m, m.titleW, m.titleH},
		{histOpenHwnd, m.buttonStart, m.buttonTop, m.buttonW, m.buttonH},
		{histChangeHwnd, m.buttonStart + m.buttonW + m.buttonGap, m.buttonTop, m.buttonW, m.buttonH},
		{histPathHwnd, m.m, m.pathTop, max32(scale(100, int(m.dpi)), m.w-2*m.m), m.pathH},
	}
	moves = append(moves, paneMoves...)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	applyWindowMoves(moves)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
	redrawWindowClean(historyHwnd, nil)
}

func historyProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		historyHwnd = hwnd
		applyWindowIcons(hwnd)
		histTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS, 0, 0, 0, 0, hwnd, 0)
		histPathHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		histOpenHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_H_OPEN_DIR)
		histChangeHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_H_CHANGE_DIR)
		histRecordsLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		histPreviewLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		histSplitterHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_NOTIFY, 0, 0, 0, 0, hwnd, 0)
		histListHwnd = createWindow(WS_EX_CLIENTEDGE, "LISTBOX", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_NOINTEGRALHEIGHT|LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, ID_H_LIST)
		histPreviewHwnd = createWindow(WS_EX_CLIENTEDGE, "RICHEDIT50W", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|ES_AUTOHSCROLL, 0, 0, 0, 0, hwnd, 0)
		histFullHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP, 0, 0, 0, 0, hwnd, ID_H_FULL)
		histEmptyHwnd = createWindow(0, "STATIC", "", WS_CHILD|SS_LEFT, 0, 0, 0, 0, hwnd, ID_H_EMPTY)
		histDragOverlayHwnd = createWindow(WS_EX_NOACTIVATE, "HHVHistoryDragOverlay", "", WS_CHILD|WS_CLIPSIBLINGS, 0, 0, 0, 0, hwnd, 0)
		histSplitterBrush = createBrush(rgb(213, 219, 228))
		histSplitterActiveBrush = createBrush(rgb(174, 184, 198))
		setWindowTheme(histListHwnd, "Explorer")
		histListCallback = syscall.NewCallback(historyListProc)
		old, _, _ := procSetWindowLongPtrW.Call(uintptr(histListHwnd), ^uintptr(3), histListCallback)
		histListOldProc = old
		histSplitterCallback = syscall.NewCallback(historySplitterProc)
		splitOld, _, _ := procSetWindowLongPtrW.Call(uintptr(histSplitterHwnd), ^uintptr(3), histSplitterCallback)
		histSplitterOldProc = splitOld
		recreateHistoryFonts()
		updateHistoryTexts()
		reloadHistoryRecords()
		return 0
	case WM_SIZE:
		if wParam != SIZE_MINIMIZED {
			layoutHistory()
		}
		return 0
	case WM_DPICHANGED:
		recreateHistoryFonts()
		layoutHistory()
		return 0
	case WM_GETMINMAXINFO:
		if lParam != 0 {
			m := (*minMaxInfo)(unsafe.Pointer(lParam))
			m.MinTrackSize.X = scale(520, windowDPI(hwnd))
			m.MinTrackSize.Y = scale(400, windowDPI(hwnd))
		}
		return 0
	case WM_DRAWITEM:
		dis := (*drawItemStruct)(unsafe.Pointer(lParam))
		if dis != nil && dis.CtlID == ID_H_LIST {
			drawHistoryItem(dis)
			return 1
		}
	case WM_COMMAND:
		id := loword(wParam)
		notify := hiword(wParam)
		switch id {
		case ID_H_OPEN_DIR:
			openHistoryDirectory()
		case ID_H_CHANGE_DIR:
			changeHistoryDirectory()
			updateHistoryTexts()
		case ID_H_FULL:
			if histSelected >= 0 && histSelected < len(histRecords) {
				showFullReport(histRecords[histSelected])
			}
		case ID_H_LIST:
			if notify == LBN_SELCHANGE {
				idx, _, _ := procSendMessageW.Call(uintptr(histListHwnd), LB_GETCURSEL, 0, 0)
				if int(idx) >= 0 && int(idx) < len(histRecords) {
					histSelected = int(idx)
					setRichText(histPreviewHwnd, historyDisplayText(histRecords[histSelected].Report))
				}
			}
		}
		return 0
	case WM_CTLCOLORSTATIC:
		control := syscall.Handle(lParam)
		if control == histSplitterHwnd {
			procSetBkMode.Call(wParam, OPAQUE)
			if histSplitDragging && histSplitterActiveBrush != 0 {
				return uintptr(histSplitterActiveBrush)
			}
			if histSplitterBrush != 0 {
				return uintptr(histSplitterBrush)
			}
		}
		if control == histEmptyHwnd {
			procSetTextColor.Call(wParam, uintptr(rgb(78, 91, 110)))
			procSetBkMode.Call(wParam, TRANSPARENT)
			b, _, _ := procGetSysColorBrush.Call(COLOR_WINDOW)
			return b
		}
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		deleteFonts(histFonts)
		histFonts = nil
		historyHwnd = 0
		histListHwnd = 0
		histSplitterHwnd = 0
		histDragOverlayHwnd = 0
		releaseHistoryDragSnapshot()
		for _, brush := range []syscall.Handle{histSplitterBrush, histSplitterActiveBrush} {
			if brush != 0 {
				procDeleteObject.Call(uintptr(brush))
			}
		}
		histSplitterBrush, histSplitterActiveBrush = 0, 0
		histListOldProc = 0
		histSplitterOldProc = 0
		histSplitDragging = false
		histRecords = nil
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

// ---------- Changelog ----------
func recreateChangeFonts() {
	deleteFonts(changeFonts)
	dpi := windowDPI(changelogHwnd)
	base := currentSettings().FontSize
	displayBase := maxInt(8, base-1)
	changeFonts = []syscall.Handle{
		createUIFontDPI(displayBase+7, FW_SEMIBOLD, dpi),
		createUIFontDPI(displayBase, FW_NORMAL, dpi),
		createUIFontDPI(displayBase+1, FW_SEMIBOLD, dpi),
		createUIFontDPI(displayBase, FW_NORMAL, dpi),
		createUIFontHalfPointDPI(displayBase*2+1, FW_SEMIBOLD, dpi),
	}
	applyFont(changeTitleHwnd, changeFonts[0])
	applyFont(changeSubtitleHwnd, changeFonts[1])
	applyFont(changeVersionsLabelHwnd, changeFonts[2])
	applyFont(changeContentLabelHwnd, changeFonts[2])
	applyFont(changeContentHwnd, changeFonts[3])
	procSendMessageW.Call(uintptr(changeListHwnd), LB_SETITEMHEIGHT, 0, uintptr(scale(int32(32+(displayBase-8)*2), dpi)))
}
func updateChangelogTexts() {
	code := effectiveLocale()
	setText(changelogHwnd, tr(code, "changelogTitle"))
	setText(changeTitleHwnd, tr(code, "changelogTitle"))
	setText(changeSubtitleHwnd, tr(code, "changelogSubtitle"))
	setText(changeVersionsLabelHwnd, tr(code, "versions"))
	setText(changeContentLabelHwnd, tr(code, "changes"))
}
func reloadChangelog() {
	if changeListHwnd == 0 {
		return
	}
	changeEntries = changelogFor(effectiveLocale())
	procSendMessageW.Call(uintptr(changeListHwnd), LB_RESETCONTENT, 0, 0)
	for _, v := range changeEntries {
		procSendMessageW.Call(uintptr(changeListHwnd), LB_ADDSTRING, 0, uintptr(unsafe.Pointer(utf16Ptr(v.Version))))
	}
	if len(changeEntries) > 0 {
		procSendMessageW.Call(uintptr(changeListHwnd), LB_SETCURSEL, 0, 0)
		setRichText(changeContentHwnd, renderChangeVersion(changeEntries[0]))
	}
	procInvalidateRect.Call(uintptr(changeListHwnd), 0, 1)
}
func openChangelog() {
	if changelogHwnd != 0 {
		showWindowFront(changelogHwnd)
		return
	}
	dpi := mainDPI
	changelogHwnd = createWindow(WS_EX_APPWINDOW|WS_EX_CONTROLPARENT, "HHVChangelogWindow", tr(effectiveLocale(), "changelogTitle"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, scale(1060, dpi), scale(680, dpi), 0, 0)
	showWindowFront(changelogHwnd)
}
func drawChangeItem(dis *drawItemStruct) {
	i := int(dis.ItemID)
	if i < 0 || i >= len(changeEntries) {
		return
	}
	r := dis.RcItem
	selected := dis.ItemState&ODS_SELECTED != 0
	bg := rgb(255, 255, 255)
	fg := rgb(35, 45, 60)
	if selected {
		bg = rgb(231, 241, 255)
		fg = rgb(22, 83, 170)
	}
	b := createBrush(bg)
	procFillRect.Call(uintptr(dis.HDC), uintptr(unsafe.Pointer(&r)), uintptr(b))
	procDeleteObject.Call(uintptr(b))
	rr := r
	rr.Left += scale(14, windowDPI(changelogHwnd))
	rr.Right -= scale(10, windowDPI(changelogHwnd))
	drawText(dis.HDC, changeEntries[i].Version, &rr, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, changeFonts[4], fg)
}
func layoutChangelog() {
	if changelogHwnd == 0 {
		return
	}
	r := clientRect(changelogHwnd)
	w, h := r.Right, r.Bottom
	dpi := windowDPI(changelogHwnd)
	m := scale(24, dpi)
	if w < scale(700, dpi) {
		m = scale(14, dpi)
	}
	titleH := scale(46, dpi)
	subH := scale(32, dpi)
	bodyTop := m + titleH + subH + scale(16, dpi)
	bodyH := max32(scale(100, dpi), h-bodyTop-m)
	gap := scale(12, dpi)
	labelH := scale(32, dpi)
	available := max32(0, w-2*m-gap)
	leftW := int32(float64(available) * 0.25)
	leftW = max32(scale(130, dpi), min32(scale(230, dpi), leftW))
	if leftW > available-scale(220, dpi) {
		leftW = max32(scale(120, dpi), available-scale(220, dpi))
	}
	rx := m + leftW + gap
	rw := max32(scale(120, dpi), w-rx-m)
	moves := []windowMove{
		{changeTitleHwnd, m, m, max32(scale(100, dpi), w-2*m), titleH},
		{changeSubtitleHwnd, m, m + titleH, max32(scale(100, dpi), w-2*m), subH},
		{changeVersionsLabelHwnd, m, bodyTop, leftW, labelH},
		{changeListHwnd, m, bodyTop + labelH, leftW, bodyH - labelH},
		{changeContentLabelHwnd, rx, bodyTop, rw, labelH},
		{changeContentHwnd, rx, bodyTop + labelH, rw, bodyH - labelH},
	}
	procSendMessageW.Call(uintptr(changelogHwnd), WM_SETREDRAW, 0, 0)
	applyWindowMoves(moves)
	procSendMessageW.Call(uintptr(changelogHwnd), WM_SETREDRAW, 1, 0)
	redrawWindowClean(changelogHwnd, nil)
}

func changelogProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		changelogHwnd = hwnd
		applyWindowIcons(hwnd)
		changeTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE, 0, 0, 0, 0, hwnd, 0)
		changeSubtitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE, 0, 0, 0, 0, hwnd, 0)
		changeVersionsLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		changeContentLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		changeListHwnd = createWindow(WS_EX_CLIENTEDGE, "LISTBOX", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_NOINTEGRALHEIGHT|LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, ID_C_LIST)
		changeContentHwnd = createWindow(WS_EX_CLIENTEDGE, "RICHEDIT50W", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|ES_AUTOHSCROLL, 0, 0, 0, 0, hwnd, ID_C_CONTENT)
		setWindowTheme(changeListHwnd, "Explorer")
		recreateChangeFonts()
		updateChangelogTexts()
		reloadChangelog()
		return 0
	case WM_SIZE:
		if wParam != SIZE_MINIMIZED {
			layoutChangelog()
		}
		return 0
	case WM_DPICHANGED:
		recreateChangeFonts()
		layoutChangelog()
		return 0
	case WM_GETMINMAXINFO:
		if lParam != 0 {
			m := (*minMaxInfo)(unsafe.Pointer(lParam))
			m.MinTrackSize.X = scale(500, windowDPI(hwnd))
			m.MinTrackSize.Y = scale(380, windowDPI(hwnd))
		}
		return 0
	case WM_DRAWITEM:
		dis := (*drawItemStruct)(unsafe.Pointer(lParam))
		if dis != nil && dis.CtlID == ID_C_LIST {
			drawChangeItem(dis)
			return 1
		}
	case WM_COMMAND:
		if loword(wParam) == ID_C_LIST && hiword(wParam) == LBN_SELCHANGE {
			idx, _, _ := procSendMessageW.Call(uintptr(changeListHwnd), LB_GETCURSEL, 0, 0)
			if int(idx) >= 0 && int(idx) < len(changeEntries) {
				setRichText(changeContentHwnd, renderChangeVersion(changeEntries[int(idx)]))
			}
		}
		return 0
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		deleteFonts(changeFonts)
		changeFonts = nil
		changelogHwnd = 0
		changeListHwnd = 0
		changeEntries = nil
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

// ---------- About ----------
func aboutSummaryText() string   { return tr(effectiveLocale(), "aboutSummary") }
func aboutDeveloperText() string { return tr(effectiveLocale(), "aboutDeveloperText") }
func aboutFeedbackText() string  { return tr(effectiveLocale(), "aboutFeedbackText") }
func aboutCopyrightText() string { return tr(effectiveLocale(), "aboutCopyrightText") }

func normalizedNonEmptyLines(text string) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	var result []string
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			result = append(result, line)
		}
	}
	return result
}

func aboutDeveloperParts() (author, github, coolapk string) {
	for _, line := range normalizedNonEmptyLines(aboutDeveloperText()) {
		lower := strings.ToLower(line)
		switch {
		case strings.HasPrefix(lower, "http://") || strings.HasPrefix(lower, "https://"):
			continue
		case strings.Contains(lower, "github"):
			github = line
		case strings.Contains(lower, "coolapk") || strings.Contains(line, "酷安"):
			coolapk = line
		case author == "":
			author = line
		}
	}
	return
}

func splitContactLine(line string) (label, value string) {
	line = strings.TrimSpace(line)
	if line == "" {
		return "", ""
	}
	if parts := strings.SplitN(line, "\t", 2); len(parts) == 2 {
		return strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
	}
	for _, separator := range []string{"：", ":"} {
		if index := strings.Index(line, separator); index >= 0 {
			return strings.TrimSpace(line[:index+len(separator)]), strings.TrimSpace(line[index+len(separator):])
		}
	}
	return line, ""
}

func aboutFeedbackParts() (intro, qqLabel, qqValue, emailLabel, emailValue string) {
	for _, line := range normalizedNonEmptyLines(aboutFeedbackText()) {
		lower := strings.ToLower(line)
		switch {
		case strings.Contains(lower, "mail") || strings.Contains(line, "邮箱") || strings.Contains(line, "メール") || strings.Contains(line, "이메일"):
			emailLabel, emailValue = splitContactLine(line)
		case strings.Contains(lower, "qq"):
			qqLabel, qqValue = splitContactLine(line)
		case intro == "":
			intro = line
		default:
			intro += " " + line
		}
	}
	return
}

func createAboutLinkFont(points int, dpi int) syscall.Handle {
	height := -int32(points * dpi / 72)
	h, _, _ := procCreateFontW.Call(uintptr(height), 0, 0, 0, uintptr(FW_NORMAL), 0, 1, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, uintptr(unsafe.Pointer(utf16Ptr("Segoe UI"))))
	return syscall.Handle(h)
}

func recreateAboutFonts() {
	deleteFonts(aboutFonts)
	if aboutHwnd == 0 {
		return
	}
	dpi := windowDPI(aboutHwnd)
	base := currentSettings().FontSize
	titleSize := base + 5
	if titleSize < 15 {
		titleSize = 15
	}
	bodySize := base - 1
	if bodySize < 9 {
		bodySize = 9
	}
	aboutFonts = []syscall.Handle{
		createUIFontDPI(titleSize, FW_SEMIBOLD, dpi),
		createUIFontDPI(bodySize, FW_NORMAL, dpi),
		createUIFontDPI(bodySize, FW_SEMIBOLD, dpi),
		createUIFontDPI(base+1, FW_SEMIBOLD, dpi),
		createUIFontDPI(bodySize, FW_NORMAL, dpi),
		createAboutLinkFont(bodySize, dpi),
	}
	applyFont(aboutTitleHwnd, aboutFonts[0])
	applyFont(aboutSummaryHwnd, aboutFonts[1])
	applyFont(aboutVersionHwnd, aboutFonts[2])
	applyFont(aboutDeveloperTitleHwnd, aboutFonts[3])
	applyFont(aboutFeedbackTitleHwnd, aboutFonts[3])
	applyFont(aboutCopyrightTitleHwnd, aboutFonts[3])
	for _, h := range []syscall.Handle{aboutAuthorHwnd, aboutGithubInfoHwnd, aboutCoolapkInfoHwnd, aboutFeedbackIntroHwnd, aboutQQLabelHwnd, aboutQQValueHwnd, aboutEmailLabelHwnd, aboutEmailValueHwnd, aboutCopyrightHwnd} {
		applyFont(h, aboutFonts[4])
	}
	applyFont(aboutGithubLinkHwnd, aboutFonts[5])
	applyFont(aboutCoolapkLinkHwnd, aboutFonts[5])
}

func updateAboutTexts() {
	if aboutHwnd == 0 {
		return
	}
	code := effectiveLocale()
	setText(aboutHwnd, tr(code, "about"))
	setText(aboutTitleHwnd, tr(code, "aboutAppName"))
	setText(aboutSummaryHwnd, aboutSummaryText())
	setText(aboutVersionHwnd, trf(code, "aboutVersion", appVersion))
	setText(aboutDeveloperTitleHwnd, tr(code, "aboutDeveloper"))
	setText(aboutFeedbackTitleHwnd, tr(code, "aboutFeedback"))
	setText(aboutCopyrightTitleHwnd, tr(code, "aboutCopyright"))
	author, github, coolapk := aboutDeveloperParts()
	intro, qqLabel, qqValue, emailLabel, emailValue := aboutFeedbackParts()
	setText(aboutAuthorHwnd, author)
	setText(aboutGithubInfoHwnd, github)
	setText(aboutGithubLinkHwnd, "https://github.com/xincheng1237")
	setText(aboutCoolapkInfoHwnd, coolapk)
	setText(aboutCoolapkLinkHwnd, "https://www.coolapk.com/u/3594167")
	setText(aboutFeedbackIntroHwnd, intro)
	setText(aboutQQLabelHwnd, qqLabel)
	setText(aboutQQValueHwnd, qqValue)
	setText(aboutEmailLabelHwnd, emailLabel)
	setText(aboutEmailValueHwnd, emailValue)
	setText(aboutCopyrightHwnd, aboutCopyrightText())
}

func aboutMaxScroll(clientH int32) int32 {
	if aboutContentHeight <= clientH {
		return 0
	}
	return aboutContentHeight - clientH
}

func updateAboutScrollBar(clientH int32) {
	maxPos := aboutMaxScroll(clientH)
	if aboutScrollPos > maxPos {
		aboutScrollPos = maxPos
	}
	if aboutScrollPos < 0 {
		aboutScrollPos = 0
	}
	si := scrollInfo{CbSize: uint32(unsafe.Sizeof(scrollInfo{})), FMask: SIF_RANGE | SIF_PAGE | SIF_POS, NMin: 0, NMax: max32(0, aboutContentHeight-1), NPage: uint32(max32(1, clientH)), NPos: aboutScrollPos}
	procSetScrollInfo.Call(uintptr(aboutHwnd), SB_VERT, uintptr(unsafe.Pointer(&si)), 1)
}

func setAboutScroll(pos int32) {
	if aboutHwnd == 0 {
		return
	}
	r := clientRect(aboutHwnd)
	maxPos := aboutMaxScroll(r.Bottom)
	if pos < 0 {
		pos = 0
	}
	if pos > maxPos {
		pos = maxPos
	}
	if pos == aboutScrollPos {
		return
	}
	aboutScrollPos = pos
	layoutAbout()
}

func layoutAbout() {
	if aboutHwnd == 0 {
		return
	}
	r := clientRect(aboutHwnd)
	dpi := windowDPI(aboutHwnd)
	m := scale(30, dpi)
	if r.Right < scale(620, dpi) {
		m = scale(20, dpi)
	}
	accentW := scale(4, dpi)
	gap := scale(14, dpi)
	contentX := m + accentW + gap
	contentW := max32(scale(220, dpi), r.Right-contentX-m)
	titleH := scale(42, dpi)
	summaryH := scale(48, dpi)
	feedbackIntroH := scale(48, dpi)
	if r.Right < scale(700, dpi) {
		summaryH = scale(72, dpi)
		feedbackIntroH = scale(72, dpi)
	}
	versionH := scale(24, dpi)
	headerH := titleH + scale(6, dpi) + summaryH + scale(6, dpi) + versionH
	lineH := scale(28, dpi)
	sectionTitleH := scale(30, dpi)
	sectionGap := scale(18, dpi)
	lineGap := scale(5, dpi)

	logicalY := m
	y := logicalY - aboutScrollPos
	moves := []windowMove{
		{aboutAccentHwnd, m, y, accentW, headerH},
		{aboutTitleHwnd, contentX, y, contentW, titleH},
		{aboutSummaryHwnd, contentX, y + titleH + scale(6, dpi), contentW, summaryH},
		{aboutVersionHwnd, contentX, y + titleH + scale(6, dpi) + summaryH + scale(6, dpi), contentW, versionH},
	}
	logicalY += headerH + scale(30, dpi)
	y = logicalY - aboutScrollPos
	moves = append(moves, windowMove{aboutDeveloperTitleHwnd, m, y, r.Right - 2*m, sectionTitleH})
	logicalY += sectionTitleH
	for _, h := range []syscall.Handle{aboutAuthorHwnd, aboutGithubInfoHwnd, aboutGithubLinkHwnd, aboutCoolapkInfoHwnd, aboutCoolapkLinkHwnd} {
		y = logicalY - aboutScrollPos
		moves = append(moves, windowMove{h, m, y, r.Right - 2*m, lineH})
		logicalY += lineH + lineGap
	}
	logicalY += sectionGap
	y = logicalY - aboutScrollPos
	moves = append(moves, windowMove{aboutFeedbackTitleHwnd, m, y, r.Right - 2*m, sectionTitleH})
	logicalY += sectionTitleH
	y = logicalY - aboutScrollPos
	moves = append(moves, windowMove{aboutFeedbackIntroHwnd, m, y, r.Right - 2*m, feedbackIntroH})
	logicalY += feedbackIntroH + lineGap
	contactFont := aboutFonts[4]
	labelWidth := max32(
		measureTextWidth(aboutHwnd, getText(aboutQQLabelHwnd), contactFont),
		measureTextWidth(aboutHwnd, getText(aboutEmailLabelHwnd), contactFont),
	) + scale(14, dpi)
	maxLabelWidth := max32(scale(84, dpi), (r.Right-2*m)/2)
	if labelWidth > maxLabelWidth {
		labelWidth = maxLabelWidth
	}
	valueX := m + labelWidth
	valueWidth := max32(scale(120, dpi), r.Right-m-valueX)
	for _, row := range [][2]syscall.Handle{{aboutQQLabelHwnd, aboutQQValueHwnd}, {aboutEmailLabelHwnd, aboutEmailValueHwnd}} {
		y = logicalY - aboutScrollPos
		moves = append(moves,
			windowMove{row[0], m, y, labelWidth, lineH},
			windowMove{row[1], valueX, y, valueWidth, lineH},
		)
		logicalY += lineH + lineGap
	}
	logicalY += sectionGap
	y = logicalY - aboutScrollPos
	moves = append(moves, windowMove{aboutCopyrightTitleHwnd, m, y, r.Right - 2*m, sectionTitleH})
	logicalY += sectionTitleH
	y = logicalY - aboutScrollPos
	moves = append(moves, windowMove{aboutCopyrightHwnd, m, y, r.Right - 2*m, lineH})
	logicalY += lineH + m
	aboutContentHeight = logicalY
	updateAboutScrollBar(r.Bottom)

	procSendMessageW.Call(uintptr(aboutHwnd), WM_SETREDRAW, 0, 0)
	applyWindowMoves(moves)
	procSendMessageW.Call(uintptr(aboutHwnd), WM_SETREDRAW, 1, 0)
	redrawWindowClean(aboutHwnd, nil)
}

func aboutLinkURL(hwnd syscall.Handle) string {
	switch hwnd {
	case aboutGithubLinkHwnd:
		return "https://github.com/xincheng1237"
	case aboutCoolapkLinkHwnd:
		return "https://www.coolapk.com/u/3594167"
	}
	return ""
}

func aboutLinkProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_SETCURSOR:
		cursor, _, _ := procLoadCursorW.Call(0, IDC_HAND)
		procSetCursor.Call(cursor)
		return 1
	case WM_LBUTTONDOWN:
		procSetFocus.Call(uintptr(hwnd))
		procSendMessageW.Call(uintptr(hwnd), EM_SETSEL, 0, ^uintptr(0))
		return 0
	case WM_LBUTTONDBLCLK:
		procSendMessageW.Call(uintptr(hwnd), EM_SETSEL, 0, ^uintptr(0))
		return 0
	case WM_LBUTTONUP:
		procSendMessageW.Call(uintptr(hwnd), EM_SETSEL, 0, ^uintptr(0))
		now := time.Now()
		if aboutLastLinkHwnd == hwnd && !aboutLastLinkClick.IsZero() && now.Sub(aboutLastLinkClick) <= 550*time.Millisecond {
			aboutLastLinkHwnd = 0
			aboutLastLinkClick = time.Time{}
			if url := aboutLinkURL(hwnd); url != "" {
				_ = openPath(url)
			}
		} else {
			aboutLastLinkHwnd = hwnd
			aboutLastLinkClick = now
		}
		return 0
	case WM_MOUSEWHEEL:
		procSendMessageW.Call(uintptr(aboutHwnd), WM_MOUSEWHEEL, wParam, lParam)
		return 0
	}
	r, _, _ := procCallWindowProcW.Call(aboutLinkOldProc, uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func createAboutTextControl(hwnd syscall.Handle, id uintptr, multiline bool) syscall.Handle {
	style := uint32(WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | ES_READONLY | ES_AUTOHSCROLL)
	if multiline {
		style = WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | ES_MULTILINE | ES_READONLY
	}
	return createWindow(0, "EDIT", "", style, 0, 0, 0, 0, hwnd, id)
}

func openAbout() {
	if aboutHwnd != 0 {
		showWindowFront(aboutHwnd)
		return
	}
	dpi := mainDPI
	aboutHwnd = createWindow(WS_EX_APPWINDOW|WS_EX_CONTROLPARENT, "HHVAboutWindow", tr(effectiveLocale(), "about"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN|WS_VSCROLL, CW_USEDEFAULT, CW_USEDEFAULT, scale(780, dpi), scale(720, dpi), 0, 0)
	showWindowFront(aboutHwnd)
}

func aboutProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		aboutHwnd = hwnd
		aboutScrollPos = 0
		applyWindowIcons(hwnd)
		aboutAccentBrush = createBrush(rgb(46, 111, 218))
		aboutAccentHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS, 0, 0, 0, 0, hwnd, ID_A_ACCENT)
		aboutTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		aboutSummaryHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT, 0, 0, 0, 0, hwnd, ID_A_SUMMARY)
		aboutVersionHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_A_VERSION)
		aboutDeveloperTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_A_DEVELOPER)
		aboutFeedbackTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_A_FEEDBACK)
		aboutCopyrightTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, ID_A_COPYRIGHT)
		aboutAuthorHwnd = createAboutTextControl(hwnd, ID_A_AUTHOR, false)
		aboutGithubInfoHwnd = createAboutTextControl(hwnd, ID_A_GITHUB_INFO, false)
		aboutGithubLinkHwnd = createAboutTextControl(hwnd, ID_A_GITHUB_LINK, false)
		aboutCoolapkInfoHwnd = createAboutTextControl(hwnd, ID_A_COOLAPK_INFO, false)
		aboutCoolapkLinkHwnd = createAboutTextControl(hwnd, ID_A_COOLAPK_LINK, false)
		aboutFeedbackIntroHwnd = createAboutTextControl(hwnd, ID_A_FEEDBACK_INTRO, true)
		aboutQQLabelHwnd = createAboutTextControl(hwnd, ID_A_QQ_LABEL, false)
		aboutQQValueHwnd = createAboutTextControl(hwnd, ID_A_QQ_VALUE, false)
		aboutEmailLabelHwnd = createAboutTextControl(hwnd, ID_A_EMAIL_LABEL, false)
		aboutEmailValueHwnd = createAboutTextControl(hwnd, ID_A_EMAIL_VALUE, false)
		aboutCopyrightHwnd = createAboutTextControl(hwnd, ID_A_COPYRIGHT_TXT, false)
		aboutLinkCallback = syscall.NewCallback(aboutLinkProc)
		old, _, _ := procSetWindowLongPtrW.Call(uintptr(aboutGithubLinkHwnd), ^uintptr(3), aboutLinkCallback)
		aboutLinkOldProc = old
		procSetWindowLongPtrW.Call(uintptr(aboutCoolapkLinkHwnd), ^uintptr(3), aboutLinkCallback)
		recreateAboutFonts()
		updateAboutTexts()
		return 0
	case WM_SIZE:
		if wParam != SIZE_MINIMIZED {
			layoutAbout()
		}
		return 0
	case WM_DPICHANGED:
		recreateAboutFonts()
		layoutAbout()
		return 0
	case WM_GETMINMAXINFO:
		if lParam != 0 {
			m := (*minMaxInfo)(unsafe.Pointer(lParam))
			m.MinTrackSize.X = scale(520, windowDPI(hwnd))
			m.MinTrackSize.Y = scale(420, windowDPI(hwnd))
		}
		return 0
	case WM_VSCROLL:
		si := scrollInfo{CbSize: uint32(unsafe.Sizeof(scrollInfo{})), FMask: SIF_ALL}
		procGetScrollInfo.Call(uintptr(hwnd), SB_VERT, uintptr(unsafe.Pointer(&si)))
		pos := aboutScrollPos
		switch loword(wParam) {
		case SB_LINEUP:
			pos -= scale(32, windowDPI(hwnd))
		case SB_LINEDOWN:
			pos += scale(32, windowDPI(hwnd))
		case SB_PAGEUP:
			pos -= int32(si.NPage)
		case SB_PAGEDOWN:
			pos += int32(si.NPage)
		case SB_THUMBTRACK, SB_THUMBPOSITION:
			pos = si.NTrackPos
		case SB_TOP:
			pos = 0
		case SB_BOTTOM:
			pos = aboutMaxScroll(clientRect(hwnd).Bottom)
		}
		setAboutScroll(pos)
		return 0
	case WM_MOUSEWHEEL:
		delta := int16(hiword(wParam))
		step := scale(64, windowDPI(hwnd))
		if delta > 0 {
			setAboutScroll(aboutScrollPos - step)
		} else if delta < 0 {
			setAboutScroll(aboutScrollPos + step)
		}
		return 0
	case WM_CTLCOLORSTATIC, WM_CTLCOLOREDIT:
		control := syscall.Handle(lParam)
		procSetBkMode.Call(wParam, TRANSPARENT)
		switch control {
		case aboutAccentHwnd:
			if aboutAccentBrush != 0 {
				return uintptr(aboutAccentBrush)
			}
		case aboutSummaryHwnd:
			procSetTextColor.Call(wParam, uintptr(rgb(82, 94, 112)))
		case aboutVersionHwnd, aboutGithubLinkHwnd, aboutCoolapkLinkHwnd:
			procSetTextColor.Call(wParam, uintptr(rgb(43, 104, 196)))
		case aboutDeveloperTitleHwnd, aboutFeedbackTitleHwnd, aboutCopyrightTitleHwnd:
			procSetTextColor.Call(wParam, uintptr(rgb(32, 49, 70)))
		default:
			procSetTextColor.Call(wParam, uintptr(rgb(18, 31, 48)))
		}
		b, _, _ := procGetSysColorBrush.Call(COLOR_WINDOW)
		return b
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		deleteFonts(aboutFonts)
		aboutFonts = nil
		if aboutAccentBrush != 0 {
			procDeleteObject.Call(uintptr(aboutAccentBrush))
			aboutAccentBrush = 0
		}
		aboutHwnd, aboutTitleHwnd, aboutSummaryHwnd, aboutVersionHwnd = 0, 0, 0, 0
		aboutDeveloperTitleHwnd, aboutFeedbackTitleHwnd, aboutCopyrightTitleHwnd = 0, 0, 0
		aboutAccentHwnd, aboutAuthorHwnd, aboutGithubInfoHwnd, aboutGithubLinkHwnd = 0, 0, 0, 0
		aboutCoolapkInfoHwnd, aboutCoolapkLinkHwnd, aboutFeedbackIntroHwnd = 0, 0, 0
		aboutQQLabelHwnd, aboutQQValueHwnd, aboutEmailLabelHwnd, aboutEmailValueHwnd, aboutCopyrightHwnd = 0, 0, 0, 0, 0
		aboutLinkOldProc, aboutLinkCallback = 0, 0
		aboutLastLinkHwnd = 0
		aboutLastLinkClick = time.Time{}
		aboutScrollPos, aboutContentHeight = 0, 0
		return 0
	}
	r, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return r
}

func main() {
	runtime.LockOSThread()
	if procSetProcessDpiAwarenessContext.Find() == nil {
		if r, _, _ := procSetProcessDpiAwarenessContext.Call(^uintptr(3)); r == 0 {
			procSetProcessDPIAware.Call()
		}
	} else {
		procSetProcessDPIAware.Call()
	}
	loadSettings()
	cleanupLegacyTemporaryFiles()
	loadAppIcons()
	if !isAdmin() {
		if relaunchElevated() {
			return
		}
		code := effectiveLocale()
		messageBox(0, tr(code, "needAdminTitle"), tr(code, "needAdminText"), MB_OK|MB_ICONERROR)
		return
	}
	classes := []struct {
		name string
		proc uintptr
	}{{"HHVMainWindow", syscall.NewCallback(mainWindowProc)}, {"HHVHistoryWindow", syscall.NewCallback(historyProc)}, {"HHVHistoryDragOverlay", syscall.NewCallback(historyDragOverlayProc)}, {"HHVChangelogWindow", syscall.NewCallback(changelogProc)}, {"HHVAboutWindow", syscall.NewCallback(aboutProc)}, {"HHVViewerWindow", syscall.NewCallback(viewerProc)}, {"HHVDeleteDialog", syscall.NewCallback(deleteDialogProc)}}
	for _, c := range classes {
		if e := registerWindowClass(c.name, c.proc, COLOR_WINDOW); e != nil {
			messageBox(0, tr(effectiveLocale(), "errorTitle"), e.Error(), MB_OK|MB_ICONERROR)
			return
		}
	}
	startupDPI := windowDPI(0)
	mainHwnd = createWindow(WS_EX_APPWINDOW|WS_EX_CONTROLPARENT, "HHVMainWindow", tr(effectiveLocale(), "reportTitle"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, scale(1180, startupDPI), scale(780, startupDPI), 0, 0)
	if mainHwnd == 0 {
		return
	}
	showWindowFront(mainHwnd)
	var m msg
	for {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
}

// Keep strconv linked for Windows 7 fallback builds that use the shared source set.
var _ = strconv.Itoa
