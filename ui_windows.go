//go:build windows

package main

import (
	"context"
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
	ID_H_BATCH      = 2006
	ID_H_SELECT_ALL = 2007
	ID_H_EXPORT     = 2008
	ID_H_DELETE     = 2009
	ID_H_DONE       = 2010
	ID_H_PATH       = 2011
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
	ID_A_CHANGELOG      = 7018
	ID_A_UPDATE         = 7019

	MENU_LANG_BASE          = 6000
	MENU_MORE_OPEN          = 6101
	MENU_MORE_CHANGE        = 6102
	MENU_MORE_REFRESH       = 6103
	MENU_MORE_EXPORT        = 6104
	MENU_MORE_CHANGELOG     = 6105
	MENU_MORE_ABOUT         = 6106
	MENU_MORE_UPDATE        = 6107
	MENU_HISTORY_SELECT_ALL = 6201
	MENU_HISTORY_CLEAR      = 6202
	MENU_HISTORY_EXPORT     = 6203
	MENU_HISTORY_DELETE     = 6204
)

var (
	mainHwnd                                                                                              syscall.Handle
	refreshHwnd, exportHwnd, copyHwnd, historyButtonHwnd, languageHwnd, zoomOutHwnd, zoomInHwnd, moreHwnd syscall.Handle
	reportHwnd, statusHwnd, pathLabelHwnd, pathHwnd, fontStatusHwnd, hideSerialHwnd                       syscall.Handle
	mainUIFont, mainReportFont, mainStatusFont                                                            syscall.Handle
	mainDPI                                                                                               = 96

	scanMu                sync.RWMutex
	currentScan           *scanResult
	pendingScan           *scanResult
	pendingScanGeneration uint64
	scanInFlight          bool
	scanGeneration        uint64
	scanCancel            context.CancelFunc
	currentHistory        *historyRecord
	updateChecking        bool
	pendingUpdate         releaseInfo
	pendingUpdateErr      error

	historyHwnd                                                                                                                                                                      syscall.Handle
	histTitleHwnd, histPathHwnd, histOpenHwnd, histChangeHwnd, histRecordsLabelHwnd, histPreviewLabelHwnd, histListHwnd, histPreviewHwnd, histFullHwnd, histEmptyHwnd, histBatchHwnd syscall.Handle
	histSelectAllHwnd, histExportSelectedHwnd, histDeleteSelectedHwnd, histDoneHwnd                                                                                                  syscall.Handle
	histSplitterHwnd, histDragOverlayHwnd                                                                                                                                            syscall.Handle
	histFonts                                                                                                                                                                        []syscall.Handle
	histSplitterBrush, histSplitterActiveBrush                                                                                                                                       syscall.Handle
	histDragSnapshot                                                                                                                                                                 syscall.Handle
	histDragSnapshotW, histDragSnapshotH                                                                                                                                             int32
	histDragSourceLeftW, histDragSourceSplitW, histDragTargetLeftW, histDragLabelH                                                                                                   int32
	histRecords                                                                                                                                                                      []historyRecord
	histSelected                                                                                                                                                                     = -1
	histSelectionMode                                                                                                                                                                bool
	histHover                                                                                                                                                                        = -1
	histHoverAlpha                                                                                                                                                                   = 0
	histListOldProc, histSplitterOldProc                                                                                                                                             uintptr
	histListCallback, histSplitterCallback                                                                                                                                           uintptr
	histSplitRatio                                                                                                                                                                   = 0.28
	histSplitDragging                                                                                                                                                                bool
	histSplitStartScreenX, histSplitStartLeftW                                                                                                                                       int32
	histSplitPendingRatio                                                                                                                                                            = 0.28
	histSplitLastRender                                                                                                                                                              time.Time

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
	aboutChangelogHwnd, aboutUpdateHwnd                                      syscall.Handle
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
	deleteDialogFont, deleteDialogTitleFont                                            syscall.Handle
	deleteDialogCount                                                                  int
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
	mainDPI = windowDPI(mainHwnd)
	mainUIFont = createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, mainDPI)
	mainReportFont = createUIFontDPI(currentSettings().FontSize, FW_NORMAL, mainDPI)
	mainStatusFont = createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_NORMAL, mainDPI)
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
	if shellBrandHwnd != 0 {
		recreateShellFonts()
	}
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
	if shellBrandHwnd != 0 {
		updateShellTexts()
	}
}

func refreshSecondaryFonts() {
	if changelogHwnd != 0 && shellBrandHwnd == 0 {
		recreateChangeFonts()
	}
	if aboutHwnd != 0 && shellBrandHwnd == 0 {
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
	scanGeneration++
	generation := scanGeneration
	ctx, cancel := context.WithTimeout(context.Background(), 35*time.Second)
	scanCancel = cancel
	scanMu.Unlock()
	enableWindow(refreshHwnd, false)
	code := effectiveLocale()
	setText(statusHwnd, tr(code, "scanning"))
	setRichText(reportHwnd, tr(code, "scanning"))
	refreshDashboard()
	go func() {
		defer cancel()
		r := scanHardwareContext(ctx)
		scanMu.Lock()
		if generation == scanGeneration && ctx.Err() != context.Canceled {
			pendingScan = &r
			pendingScanGeneration = generation
		}
		scanMu.Unlock()
		procPostMessageW.Call(uintptr(mainHwnd), WM_APP_SCAN_DONE, uintptr(generation), 0)
	}()
}

func finishScan(generation uint64) {
	scanMu.Lock()
	if generation != pendingScanGeneration || generation != scanGeneration {
		scanMu.Unlock()
		return
	}
	r := pendingScan
	pendingScan = nil
	pendingScanGeneration = 0
	scanInFlight = false
	scanCancel = nil
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
	refreshDashboard()
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
		// The preferred UI face changes with the selected writing system.
		recreateMainFonts()
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
	updateFlags := uintptr(MF_STRING)
	scanMu.RLock()
	checking := updateChecking
	scanMu.RUnlock()
	if checking {
		updateFlags |= MF_GRAYED
	}
	procAppendMenuW.Call(m, updateFlags, MENU_MORE_UPDATE, uintptr(unsafe.Pointer(utf16Ptr(updateText(code, "check")))))
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
	case MENU_MORE_UPDATE:
		checkForUpdates()
	case MENU_MORE_ABOUT:
		openAbout()
	}
}

func checkForUpdates() {
	scanMu.Lock()
	if updateChecking {
		scanMu.Unlock()
		return
	}
	updateChecking = true
	pendingUpdate = releaseInfo{}
	pendingUpdateErr = nil
	scanMu.Unlock()
	setText(statusHwnd, updateText(effectiveLocale(), "checking"))
	go func() {
		release, err := queryLatestRelease()
		scanMu.Lock()
		pendingUpdate = release
		pendingUpdateErr = err
		updateChecking = false
		scanMu.Unlock()
		procPostMessageW.Call(uintptr(mainHwnd), WM_APP_UPDATE_DONE, 0, 0)
	}()
}

func restoreOverviewStatus() {
	r := getCurrentScan()
	if r == nil {
		setText(statusHwnd, tr(effectiveLocale(), "ready"))
		return
	}
	key := "scanCompleteNoSave"
	if currentSettings().HistoryMode == historyOnRefresh {
		key = "scanCompleteRefresh"
	}
	setText(statusHwnd, trf(effectiveLocale(), key, len(r.Disks), len(r.Batteries)))
}

func finishUpdateCheck() {
	scanMu.Lock()
	release, err := pendingUpdate, pendingUpdateErr
	pendingUpdate, pendingUpdateErr = releaseInfo{}, nil
	scanMu.Unlock()
	code := effectiveLocale()
	title := updateText(code, "title")
	if err != nil {
		messageBox(mainHwnd, title, updateText(code, "failed")+"\r\n\r\n"+err.Error(), MB_OK|MB_ICONWARNING)
		restoreOverviewStatus()
		return
	}
	comparison, valid := compareVersions(appVersion, release.Version)
	if !valid {
		messageBox(mainHwnd, title, updateText(code, "failed"), MB_OK|MB_ICONWARNING)
		return
	}
	if comparison >= 0 {
		text := fmt.Sprintf(updateText(code, "latest"), normalizedVersion(appVersion))
		messageBox(mainHwnd, title, text, MB_OK|MB_ICONINFORMATION)
		restoreOverviewStatus()
		return
	}
	key := "available"
	target := release.DownloadURL
	if strings.TrimSpace(target) == "" {
		key = "release"
		target = release.URL
	}
	text := fmt.Sprintf(updateText(code, key), release.Version, normalizedVersion(appVersion))
	if messageBox(mainHwnd, title, text, MB_YESNO|MB_ICONINFORMATION) == IDYES {
		if err := openPath(target); err != nil {
			messageBox(mainHwnd, tr(code, "errorTitle"), err.Error(), MB_OK|MB_ICONERROR)
		}
	}
	restoreOverviewStatus()
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
	if mainReportFont != 0 {
		procDeleteObject.Call(uintptr(mainReportFont))
	}
	mainReportFont = createUIFontDPI(n, FW_NORMAL, mainDPI)
	applyFont(reportHwnd, mainReportFont)
	if r := getCurrentScan(); r != nil {
		setRichText(reportHwnd, renderReportWithOptions(*r, effectiveLocale(), currentSettings().HideSerial))
	}
	if viewerHwnd != 0 {
		if viewerFont != 0 {
			procDeleteObject.Call(uintptr(viewerFont))
		}
		viewerFont = createUIFontDPI(n, FW_NORMAL, windowDPI(viewerHwnd))
		applyFont(viewerEditHwnd, viewerFont)
	}
	updateSettingsPageTexts()
	enforceShellPageVisibility()
	if shellPage == shellPageHistory {
		recreateHistoryFonts()
		layoutHistory()
	}
	active := []syscall.Handle{dashboardHwnd, historyHwnd, settingsPageHwnd, aboutHwnd}[shellPage]
	procRedrawWindow.Call(uintptr(active), 0, 0, RDW_INVALIDATE|RDW_ERASE|RDW_UPDATENOW|RDW_ALLCHILDREN)
}

func layoutMain() {
	if shellBrandHwnd != 0 {
		layoutModernShell()
		return
	}
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
		createModernShell(hwnd)
		recreateMainFonts()
		updateMainTexts()
		setText(statusHwnd, tr(effectiveLocale(), "initializing"))
		// Defer the first page activation and scan until after WM_CREATE returns.
		// Synchronously repainting the complete child hierarchy while the main
		// window is still being created can leave the process without a window.
		procPostMessageW.Call(uintptr(hwnd), WM_APP_SCAN_DONE-1, 0, 0)
		return 0
	case WM_SIZE:
		if wParam != SIZE_MINIMIZED {
			layoutMain()
			enforceShellPageVisibility()
			invalidateShellNavigation()
			procRedrawWindow.Call(uintptr(hwnd), 0, 0, RDW_INVALIDATE|RDW_ERASE|RDW_ALLCHILDREN)
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
			m.MinTrackSize.X = scale(900, windowDPI(hwnd))
			m.MinTrackSize.Y = scale(600, windowDPI(hwnd))
		}
		return 0
	case WM_PAINT:
		paintModernShell(hwnd)
		return 0
	case WM_ERASEBKGND:
		return 1
	case WM_DRAWITEM:
		if drawShellOwnerItem((*drawItemStruct)(unsafe.Pointer(lParam))) {
			return 1
		}
	case WM_COMMAND:
		id := loword(wParam)
		if shellMainCommand(id) {
			return 0
		}
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
			hide := !currentSettings().HideSerial
			if syscall.Handle(lParam) == hideSerialHwnd {
				v, _, _ := procSendMessageW.Call(uintptr(hideSerialHwnd), BM_GETCHECK, 0, 0)
				hide = v == BST_CHECKED
			}
			updateSettings(func(s *appSettings) { s.HideSerial = hide })
			check := uintptr(0)
			if hide {
				check = BST_CHECKED
			}
			procSendMessageW.Call(uintptr(hideSerialHwnd), BM_SETCHECK, check, 0)
			invalidateShellPrivacyButton()
			if r := getCurrentScan(); r != nil {
				setRichText(reportHwnd, renderReportWithOptions(*r, effectiveLocale(), hide))
			}
			refreshDashboard()
			if histSelected >= 0 && histSelected < len(histRecords) {
				setRichText(histPreviewHwnd, historyDisplayText(histRecords[histSelected].Report))
			}
			if viewerHwnd != 0 {
				setRichText(viewerEditHwnd, historyDisplayText(viewerText))
			}
		case ID_UPDATE_NOTICE_VIEW:
			dismissUpdateNotice(true)
		case ID_UPDATE_NOTICE_DISMISS:
			dismissUpdateNotice(false)
		}
		return 0
	case WM_APP_SCAN_DONE - 1:
		switchShellPage(shellPageOverview)
		startScan()
		return 0
	case WM_APP_SCAN_DONE:
		finishScan(uint64(wParam))
		return 0
	case WM_APP_UPDATE_DONE:
		finishUpdateCheck()
		return 0
	case WM_CTLCOLORSTATIC:
		if shellBrandHwnd != 0 {
			procSetBkMode.Call(wParam, TRANSPARENT)
			if syscall.Handle(lParam) == shellUpdateNoticeHwnd && shellNoticeBrush != 0 {
				return uintptr(shellNoticeBrush)
			}
			if (syscall.Handle(lParam) == shellBrandHwnd || syscall.Handle(lParam) == shellBrandVersionHwnd) && shellSidebarBrush != 0 {
				return uintptr(shellSidebarBrush)
			}
			if shellCanvasBrush != 0 {
				return uintptr(shellCanvasBrush)
			}
		}
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
		scanMu.Lock()
		if scanCancel != nil {
			scanCancel()
			scanCancel = nil
		}
		scanGeneration++
		scanInFlight = false
		scanMu.Unlock()
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
		deleteFonts([]syscall.Handle{mainUIFont, mainReportFont, mainStatusFont, shellTitleFont, shellBrandFont, shellNavFont, shellSmallFont, shellIconFont, dashboardTitleFont, dashboardCardTitleFont, dashboardBodyFont, dashboardSmallFont, dashboardPercentFont})
		for _, brush := range []syscall.Handle{shellSidebarBrush, shellCanvasBrush, shellCardBrush, shellNoticeBrush} {
			if brush != 0 {
				procDeleteObject.Call(uintptr(brush))
			}
		}
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
	histFonts = []syscall.Handle{
		createUIFontHalfPointDPI(uiPageTitleHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiBodyHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, dpi),
		createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_NORMAL, dpi),
		createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontDPI(currentSettings().FontSize, FW_NORMAL, dpi),
	}
	applyFont(histTitleHwnd, histFonts[0])
	for _, h := range []syscall.Handle{histOpenHwnd, histChangeHwnd, histFullHwnd, histBatchHwnd, histSelectAllHwnd, histExportSelectedHwnd, histDeleteSelectedHwnd, histDoneHwnd} {
		applyFont(h, histFonts[2])
	}
	for _, h := range []syscall.Handle{histPathHwnd, histRecordsLabelHwnd, histPreviewLabelHwnd, histEmptyHwnd} {
		applyFont(h, histFonts[2])
	}
	applyFont(histPreviewHwnd, histFonts[5])
	itemH := scale(56, dpi)
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
	setText(histBatchHwnd, historyBatchText(code, "batch"))
	setText(histExportSelectedHwnd, historyBatchText(code, "export"))
	setText(histDeleteSelectedHwnd, historyBatchText(code, "delete"))
	setText(histDoneHwnd, historyDoneText(code))
	updateHistorySelectionActions()
}

func historyDoneText(code string) string {
	if code == "zh-CN" || code == "zh-TW" {
		return "\u5b8c\u6210"
	}
	return "Done"
}

func updateHistorySelectionActions() {
	if histSelectAllHwnd == 0 {
		return
	}
	selected := len(selectedHistoryIndices())
	all := len(histRecords) > 0 && selected == len(histRecords)
	prefix := "\u2610  "
	if all {
		prefix = "\u2713  "
	}
	setText(histSelectAllHwnd, prefix+historyBatchText(effectiveLocale(), "selectAll"))
	enableWindow(histExportSelectedHwnd, selected > 0)
	enableWindow(histDeleteSelectedHwnd, selected > 0)
	procInvalidateRect.Call(uintptr(histSelectAllHwnd), 0, 0)
}

func setHistorySelectionMode(enabled bool) {
	if histSelectionMode == enabled || histListHwnd == 0 {
		return
	}
	histSelectionMode = enabled
	procSendMessageW.Call(uintptr(histListHwnd), LB_SETSEL, 0, ^uintptr(0))
	if !enabled && len(histRecords) > 0 {
		if histSelected < 0 || histSelected >= len(histRecords) {
			histSelected = 0
		}
		procSendMessageW.Call(uintptr(histListHwnd), LB_SETSEL, 1, uintptr(histSelected))
		setRichText(histPreviewHwnd, historyDisplayText(histRecords[histSelected].Report))
	}
	for _, h := range []syscall.Handle{histPathHwnd, histChangeHwnd, histBatchHwnd} {
		if enabled {
			procShowWindow.Call(uintptr(h), SW_HIDE)
		} else {
			procShowWindow.Call(uintptr(h), SW_SHOW)
		}
	}
	for _, h := range []syscall.Handle{histSelectAllHwnd, histExportSelectedHwnd, histDeleteSelectedHwnd, histDoneHwnd} {
		if enabled {
			procShowWindow.Call(uintptr(h), SW_SHOW)
		} else {
			procShowWindow.Call(uintptr(h), SW_HIDE)
		}
	}
	updateHistorySelectionActions()
	layoutHistory()
	procSetFocus.Call(uintptr(histListHwnd))
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
		if !histSelectionMode {
			procSendMessageW.Call(uintptr(histListHwnd), LB_SETSEL, 1, uintptr(histSelected))
		}
		setRichText(histPreviewHwnd, historyDisplayText(records[histSelected].Report))
	}
	procSendMessageW.Call(uintptr(histListHwnd), WM_SETREDRAW, 1, 0)
	procRedrawWindow.Call(uintptr(histListHwnd), 0, 0, RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN)
	updateHistorySelectionActions()
}
func openHistory() {
	if shellBrandHwnd != 0 {
		switchShellPage(shellPageHistory)
		return
	}
	if historyHwnd != 0 {
		showWindowFront(historyHwnd)
		reloadHistoryRecords()
		return
	}
	dpi := mainDPI
	historyHwnd = createWindow(secondaryWindowExStyle(), "HHVHistoryWindow", tr(effectiveLocale(), "historyWindowTitle"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, scale(1080, dpi), scale(700, dpi), 0, 0)
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
	buttonW := scale(150, int(dpi))
	buttonStart := w - m - buttonW
	titleW := min32(scale(260, int(dpi)), max32(scale(150, int(dpi)), w/3))
	headerBottom := m + titleH
	if !wide {
		buttonTop = m + titleH + scale(8, int(dpi))
		buttonW = max32(scale(90, int(dpi)), (w-2*m-buttonGap)/3)
		buttonStart = m
		titleW = max32(scale(120, int(dpi)), w-2*m)
		headerBottom = buttonTop + buttonH
	}
	pathTop := buttonTop
	pathH := buttonH
	bodyTop := headerBottom + scale(18, int(dpi))
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
		if histSelectionMode {
			if histHover >= 0 {
				old := histHover
				histHover = -1
				invalidateListItem(hwnd, old)
			}
			break
		}
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
		if !histSelectionMode && histHover >= 0 && histHover < len(histRecords) {
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
		if histSelectionMode {
			break
		}
		idx, _, _ := procSendMessageW.Call(uintptr(hwnd), LB_GETCARETINDEX, 0, 0)
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

// historyItemTextRects gives each line its own generous vertical band.  The
// list uses fixed 10 pt and 8 pt fonts, so its baselines must not be moved by
// the independently configurable report font size.  Keeping the bands tied
// only to the DPI-scaled item height prevents the subtitle from being pushed
// into (and clipped by) the separator at larger report-font settings.
func historyItemTextRects(left, right, itemHeight int32, dpi int) (title, subtitle rect) {
	title = rect{left, scale(6, dpi), right, min32(itemHeight, scale(27, dpi))}
	subtitleTop := min32(itemHeight, scale(30, dpi))
	subtitleBottom := max32(subtitleTop, itemHeight-scale(6, dpi))
	subtitle = rect{left, subtitleTop, right, subtitleBottom}
	return
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
	if histSelectionMode {
		box := scale(18, dpi)
		boxTop := (h - box) / 2
		boxRect := rect{pad, boxTop, pad + box, boxTop + box}
		fill := rgb(255, 255, 255)
		border := rgb(174, 184, 198)
		if selected {
			fill = rgb(37, 99, 180)
			border = fill
		}
		drawRoundedSurface(syscall.Handle(mem), boxRect, fill, border, scale(4, dpi))
		if selected {
			drawText(syscall.Handle(mem), "\u2713", &boxRect, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, histFonts[2], rgb(255, 255, 255))
		}
		pad += box + scale(12, dpi)
	}
	dr := historyDeleteRect(local, dpi)
	textRight := local.Right - pad
	if hover && !histSelectionMode {
		textRight = dr.Left - scale(10, dpi)
	}
	dateR, subR := historyItemTextRects(pad, textRight, local.Bottom, dpi)
	rec := histRecords[i]
	drawText(syscall.Handle(mem), rec.GeneratedAt.Format("2006-01-02 15:04:05"), &dateR, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, histFonts[1], rgb(22, 35, 55))
	computer := strings.TrimSpace(rec.Computer)
	if computer == "" {
		computer = tr(effectiveLocale(), "unknownComputer")
	}
	subtitle := computer + "  ·  " + sourceText(effectiveLocale(), rec.Source)
	drawText(syscall.Handle(mem), subtitle, &subR, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, histFonts[3], rgb(83, 105, 140))
	if hover && !histSelectionMode {
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
	deleteDialogCount = 1
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

func drawDeleteDialogButton(dis *drawItemStruct) bool {
	if dis == nil || (dis.CtlID != ID_D_DELETE && dis.CtlID != ID_D_CANCEL) {
		return false
	}
	dpi := windowDPI(deleteDialogHwnd)
	background := rgb(255, 255, 255)
	border := rgb(215, 220, 228)
	foreground := rgb(42, 53, 70)
	if dis.CtlID == ID_D_DELETE {
		background = rgb(201, 45, 55)
		border = rgb(201, 45, 55)
		foreground = rgb(255, 255, 255)
	}
	if dis.ItemState&ODS_SELECTED != 0 {
		if dis.CtlID == ID_D_DELETE {
			background = rgb(174, 35, 45)
			border = background
		} else {
			background = rgb(232, 238, 247)
			border = rgb(180, 196, 218)
		}
	}
	drawRoundedSurface(dis.HDC, dis.RcItem, background, border, scale(8, dpi))
	r := dis.RcItem
	drawText(dis.HDC, getText(syscall.Handle(dis.HwndItem)), &r, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, deleteDialogFont, foreground)
	return true
}

func historyBatchText(code, key string) string {
	texts := map[string]map[string]string{
		"en":    {"batch": "Select...", "selectAll": "Select All", "clear": "Clear Selection", "export": "Export Selected...", "delete": "Delete Selected", "none": "Select one or more history records first.", "confirm": "Delete the selected history records? Exported report files will be kept.", "exported": "Selected reports were exported to:\r\n%s"},
		"zh-CN": {"batch": "选择…", "selectAll": "全选", "clear": "取消全选", "export": "导出所选记录…", "delete": "删除所选记录", "none": "请先选择一条或多条历史记录。", "confirm": "是否删除所选历史记录？已经导出的报告文件会保留。", "exported": "所选报告已导出到：\r\n%s"},
		"ru":    {"batch": "Выбрать…", "selectAll": "Выбрать все", "clear": "Снять выбор", "export": "Экспортировать выбранные…", "delete": "Удалить выбранные", "none": "Сначала выберите одну или несколько записей.", "confirm": "Удалить выбранные записи? Экспортированные файлы будут сохранены.", "exported": "Выбранные отчеты экспортированы в:\r\n%s"},
		"fr":    {"batch": "Sélection…", "selectAll": "Tout sélectionner", "clear": "Tout désélectionner", "export": "Exporter la sélection…", "delete": "Supprimer la sélection", "none": "Sélectionnez d’abord un ou plusieurs rapports.", "confirm": "Supprimer les rapports sélectionnés ? Les fichiers exportés seront conservés.", "exported": "Rapports sélectionnés exportés vers :\r\n%s"},
		"de":    {"batch": "Auswahl…", "selectAll": "Alle auswählen", "clear": "Auswahl aufheben", "export": "Auswahl exportieren…", "delete": "Auswahl löschen", "none": "Wählen Sie zuerst mindestens einen Verlaufseintrag aus.", "confirm": "Ausgewählte Einträge löschen? Exportierte Dateien bleiben erhalten.", "exported": "Ausgewählte Berichte wurden exportiert nach:\r\n%s"},
		"ko":    {"batch": "선택…", "selectAll": "모두 선택", "clear": "모두 선택 해제", "export": "선택 항목 내보내기…", "delete": "선택 항목 삭제", "none": "먼저 하나 이상의 기록을 선택하십시오.", "confirm": "선택한 기록을 삭제할까요? 내보낸 보고서 파일은 유지됩니다.", "exported": "선택한 보고서를 다음 위치로 내보냈습니다:\r\n%s"},
		"ja":    {"batch": "選択…", "selectAll": "すべて選択", "clear": "選択を解除", "export": "選択項目を書き出す…", "delete": "選択項目を削除", "none": "先に1件以上の履歴を選択してください。", "confirm": "選択した履歴を削除しますか？書き出したファイルは保持されます。", "exported": "選択したレポートを書き出しました：\r\n%s"},
	}
	if values, ok := texts[code]; ok {
		return values[key]
	}
	return texts["en"][key]
}

func selectedHistoryIndices() []int {
	if histListHwnd == 0 || len(histRecords) == 0 {
		return nil
	}
	count, _, _ := procSendMessageW.Call(uintptr(histListHwnd), LB_GETSELCOUNT, 0, 0)
	if count == 0 || count > uintptr(len(histRecords)) {
		return nil
	}
	buffer := make([]int32, int(count))
	actual, _, _ := procSendMessageW.Call(uintptr(histListHwnd), LB_GETSELITEMS, count, uintptr(unsafe.Pointer(&buffer[0])))
	if actual == ^uintptr(0) {
		return nil
	}
	if actual > count {
		actual = count
	}
	result := make([]int, 0, int(actual))
	for _, index := range buffer[:int(actual)] {
		if index >= 0 && int(index) < len(histRecords) {
			result = append(result, int(index))
		}
	}
	return result
}

func showHistoryBatchMenu() {
	code := effectiveLocale()
	menu, _, _ := procCreatePopupMenu.Call()
	defer procDestroyMenu.Call(menu)
	procAppendMenuW.Call(menu, MF_STRING, MENU_HISTORY_SELECT_ALL, uintptr(unsafe.Pointer(utf16Ptr(historyBatchText(code, "selectAll")))))
	procAppendMenuW.Call(menu, MF_STRING, MENU_HISTORY_CLEAR, uintptr(unsafe.Pointer(utf16Ptr(historyBatchText(code, "clear")))))
	procAppendMenuW.Call(menu, MF_SEPARATOR, 0, 0)
	actionFlags := uintptr(MF_STRING)
	if len(selectedHistoryIndices()) == 0 {
		actionFlags |= MF_GRAYED
	}
	procAppendMenuW.Call(menu, actionFlags, MENU_HISTORY_EXPORT, uintptr(unsafe.Pointer(utf16Ptr(historyBatchText(code, "export")))))
	procAppendMenuW.Call(menu, actionFlags, MENU_HISTORY_DELETE, uintptr(unsafe.Pointer(utf16Ptr(historyBatchText(code, "delete")))))
	var position point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&position)))
	command, _, _ := procTrackPopupMenu.Call(menu, TPM_RETURNCMD|TPM_RIGHTALIGN|TPM_TOPALIGN, uintptr(position.X), uintptr(position.Y), 0, uintptr(historyHwnd), 0)
	switch command {
	case MENU_HISTORY_SELECT_ALL:
		procSendMessageW.Call(uintptr(histListHwnd), LB_SETSEL, 1, ^uintptr(0))
		procInvalidateRect.Call(uintptr(histListHwnd), 0, 0)
	case MENU_HISTORY_CLEAR:
		procSendMessageW.Call(uintptr(histListHwnd), LB_SETSEL, 0, ^uintptr(0))
		procInvalidateRect.Call(uintptr(histListHwnd), 0, 0)
	case MENU_HISTORY_EXPORT:
		exportSelectedHistory()
	case MENU_HISTORY_DELETE:
		deleteSelectedHistory()
	}
}

func exportSelectedHistory() {
	indices := selectedHistoryIndices()
	code := effectiveLocale()
	if len(indices) == 0 {
		messageBox(historyHwnd, tr(code, "historyWindowTitle"), historyBatchText(code, "none"), MB_OK|MB_ICONINFORMATION)
		return
	}
	destination, ok := chooseFolder(historyHwnd, historyBatchText(code, "export"))
	if !ok {
		return
	}
	folder := filepath.Join(destination, "DriveBatteryHealthViewer-Reports-"+time.Now().Format("20060102-150405"))
	if err := os.MkdirAll(folder, 0755); err != nil {
		messageBox(historyHwnd, tr(code, "errorTitle"), err.Error(), MB_OK|MB_ICONERROR)
		return
	}
	for sequence, index := range indices {
		record := histRecords[index]
		id := sanitizeFileName(record.ID)
		if id == "" {
			id = fmt.Sprintf("%03d", sequence+1)
		}
		name := fmt.Sprintf("HHV_%s_%s.txt", record.GeneratedAt.Format("20060102_150405_000"), id)
		if err := writeUTF8BOM(filepath.Join(folder, name), historyDisplayText(record.Report)); err != nil {
			messageBox(historyHwnd, tr(code, "errorTitle"), err.Error(), MB_OK|MB_ICONERROR)
			return
		}
	}
	messageBox(historyHwnd, tr(code, "historyWindowTitle"), fmt.Sprintf(historyBatchText(code, "exported"), folder), MB_OK|MB_ICONINFORMATION)
}

func deleteSelectedHistory() {
	indices := selectedHistoryIndices()
	code := effectiveLocale()
	if len(indices) == 0 {
		messageBox(historyHwnd, tr(code, "historyWindowTitle"), historyBatchText(code, "none"), MB_OK|MB_ICONINFORMATION)
		return
	}
	externalAvailable := false
	for _, index := range indices {
		if _, ok := linkedExternalReport(histRecords[index]); ok {
			externalAvailable = true
			break
		}
	}
	deleteDialogCount = len(indices)
	confirmed, deleteExternal := showDeleteDialog(externalAvailable)
	if !confirmed {
		return
	}
	for _, index := range indices {
		if err := deleteHistoryRecord(histRecords[index], deleteExternal); err != nil {
			messageBox(historyHwnd, tr(code, "errorTitle"), trf(code, "deleteFailed", err.Error()), MB_OK|MB_ICONERROR)
			return
		}
	}
	histSelected = -1
	reloadHistoryRecords()
	if len(histRecords) == 0 {
		setHistorySelectionMode(false)
	} else {
		updateHistorySelectionActions()
	}
}

func showDeleteDialog(showExternal bool) (bool, bool) {
	deleteDialogDone = false
	deleteDialogConfirmed = false
	deleteDialogExternal = false
	deleteDialogShowExternal = showExternal
	if deleteDialogCount <= 0 {
		deleteDialogCount = 1
	}
	// Suppress redraw while the owner changes enabled state. This keeps the
	// history window visually stable instead of flashing when the confirmation
	// window is opened or closed.
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	enableWindow(historyHwnd, false)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
	dpi := windowDPI(historyHwnd)
	deleteDialogHwnd = createWindow(0, "HHVDeleteDialog", tr(effectiveLocale(), "deleteConfirmTitle"), WS_CAPTION|WS_SYSMENU|WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, scale(540, dpi), scale(260, dpi), historyHwnd, 0)
	if deleteDialogHwnd == 0 {
		procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
		enableWindow(historyHwnd, true)
		procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
		return false, false
	}
	showWindowFront(deleteDialogHwnd)
	centerWindow(deleteDialogHwnd, scale(540, dpi), scale(260, dpi))
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

func deleteDialogPrompt(code string, count int) string {
	if count <= 1 {
		return tr(code, "deleteConfirmText")
	}
	if code == "zh-CN" || code == "zh-TW" {
		return fmt.Sprintf("\u786e\u5b9a\u4ece\u5386\u53f2\u8bb0\u5f55\u4e2d\u5220\u9664\u9009\u4e2d\u7684 %d \u6761\u62a5\u544a\u5417\uff1f", count)
	}
	return fmt.Sprintf("Delete the %d selected reports from history?", count)
}
func deleteDialogProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		deleteDialogHwnd = hwnd
		applyWindowIcons(hwnd)
		dpi := windowDPI(hwnd)
		deleteDialogFont = createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, dpi)
		deleteDialogTitleFont = createUIFontHalfPointDPI(30, FW_SEMIBOLD, dpi)
		deleteTextHwnd = createWindow(0, "STATIC", deleteDialogPrompt(effectiveLocale(), deleteDialogCount), WS_CHILD|WS_VISIBLE|SS_LEFT, 0, 0, 0, 0, hwnd, 0)
		checkText := tr(effectiveLocale(), "deleteExternal")
		if !deleteDialogShowExternal {
			checkText = tr(effectiveLocale(), "deleteExternalUnavailable")
		}
		deleteCheckHwnd = createWindow(0, "BUTTON", checkText, WS_CHILD|WS_VISIBLE|BS_AUTOCHECKBOX, 0, 0, 0, 0, hwnd, ID_D_CHECK)
		deleteYesHwnd = createWindow(0, "BUTTON", tr(effectiveLocale(), "delete"), WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_D_DELETE)
		deleteCancelHwnd = createWindow(0, "BUTTON", tr(effectiveLocale(), "cancel"), WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_D_CANCEL)
		for _, h := range []syscall.Handle{deleteCheckHwnd, deleteYesHwnd, deleteCancelHwnd} {
			applyFont(h, deleteDialogFont)
		}
		applyFont(deleteTextHwnd, deleteDialogTitleFont)
		if !deleteDialogShowExternal {
			enableWindow(deleteCheckHwnd, false)
			procSendMessageW.Call(uintptr(deleteCheckHwnd), BM_SETCHECK, BST_UNCHECKED, 0)
		} else {
			procSendMessageW.Call(uintptr(deleteCheckHwnd), BM_SETCHECK, BST_CHECKED, 0)
		}
		procSetFocus.Call(uintptr(deleteCancelHwnd))
		return 0
	case WM_SIZE:
		r := clientRect(hwnd)
		dpi := windowDPI(hwnd)
		m := scale(24, dpi)
		procMoveWindow.Call(uintptr(deleteTextHwnd), uintptr(m), uintptr(m), uintptr(r.Right-2*m), uintptr(scale(54, dpi)), 1)
		procMoveWindow.Call(uintptr(deleteCheckHwnd), uintptr(m), uintptr(scale(88, dpi)), uintptr(r.Right-2*m), uintptr(scale(34, dpi)), 1)
		bw := scale(100, dpi)
		bh := scale(34, dpi)
		procMoveWindow.Call(uintptr(deleteCancelHwnd), uintptr(r.Right-m-bw), uintptr(r.Bottom-m-bh), uintptr(bw), uintptr(bh), 1)
		procMoveWindow.Call(uintptr(deleteYesHwnd), uintptr(r.Right-m-bw*2-scale(10, dpi)), uintptr(r.Bottom-m-bh), uintptr(bw), uintptr(bh), 1)
		return 0
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			r := clientRect(hwnd)
			dpi := windowDPI(hwnd)
			fillDC(syscall.Handle(hdc), rect{0, 0, r.Right, r.Bottom}, rgb(248, 249, 251))
			m := scale(16, dpi)
			drawRoundedSurface(syscall.Handle(hdc), rect{m, m, r.Right - m, r.Bottom - scale(66, dpi)}, rgb(255, 255, 255), rgb(226, 229, 234), scale(10, dpi))
		}
		procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		return 0
	case WM_DRAWITEM:
		if drawDeleteDialogButton((*drawItemStruct)(unsafe.Pointer(lParam))) {
			return 1
		}
	case WM_CTLCOLORSTATIC:
		procSetBkMode.Call(wParam, TRANSPARENT)
		procSetTextColor.Call(wParam, uintptr(rgb(32, 41, 55)))
		if shellCardBrush != 0 {
			return uintptr(shellCardBrush)
		}
	case WM_CTLCOLORBTN:
		procSetBkMode.Call(wParam, TRANSPARENT)
		if shellCardBrush != 0 {
			return uintptr(shellCardBrush)
		}
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
		if deleteDialogTitleFont != 0 {
			procDeleteObject.Call(uintptr(deleteDialogTitleFont))
			deleteDialogTitleFont = 0
		}
		deleteDialogCount = 0
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
	titleW := min32(scale(190, int(m.dpi)), max32(scale(140, int(m.dpi)), m.w/4))
	moves := []windowMove{{histTitleHwnd, m.m, m.m, titleW, m.titleH}}
	availableX := m.m + titleW + m.buttonGap
	availableW := m.w - m.m - availableX
	if !m.wideHeader {
		availableX = m.m
		availableW = m.w - 2*m.m
	}
	if histSelectionMode {
		gap := scale(8, int(m.dpi))
		buttonW := max32(scale(72, int(m.dpi)), (availableW-3*gap)/4)
		x := availableX
		moves = append(moves,
			windowMove{histSelectAllHwnd, x, m.buttonTop, buttonW, m.buttonH},
			windowMove{histExportSelectedHwnd, x + buttonW + gap, m.buttonTop, buttonW, m.buttonH},
			windowMove{histDeleteSelectedHwnd, x + 2*(buttonW+gap), m.buttonTop, buttonW, m.buttonH},
			windowMove{histDoneHwnd, x + 3*(buttonW+gap), m.buttonTop, availableW - 3*(buttonW+gap), m.buttonH},
		)
	} else {
		gap := scale(8, int(m.dpi))
		selectW := scale(92, int(m.dpi))
		changeW := scale(174, int(m.dpi))
		if m.wideHeader {
			selectX := m.m + titleW + gap
			changeX := m.w - m.m - changeW
			pathRight := changeX - gap
			pathLeft := max32(selectX+selectW+gap, pathRight-scale(520, int(m.dpi)))
			moves = append(moves,
				windowMove{histBatchHwnd, selectX, m.buttonTop, selectW, m.buttonH},
				windowMove{histPathHwnd, pathLeft, m.pathTop, max32(scale(80, int(m.dpi)), pathRight-pathLeft), m.pathH},
				windowMove{histChangeHwnd, changeX, m.buttonTop, changeW, m.buttonH},
			)
		} else {
			changeW = min32(changeW, max32(scale(132, int(m.dpi)), availableW/3))
			selectW = min32(selectW, max32(scale(76, int(m.dpi)), availableW/5))
			pathW := max32(scale(80, int(m.dpi)), availableW-selectW-changeW-2*gap)
			moves = append(moves,
				windowMove{histBatchHwnd, availableX, m.buttonTop, selectW, m.buttonH},
				windowMove{histPathHwnd, availableX + selectW + gap, m.pathTop, pathW, m.pathH},
				windowMove{histChangeHwnd, availableX + selectW + gap + pathW + gap, m.buttonTop, changeW, m.buttonH},
			)
		}
	}
	moves = append(moves, paneMoves...)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 0, 0)
	applyWindowMoves(moves)
	procSendMessageW.Call(uintptr(historyHwnd), WM_SETREDRAW, 1, 0)
	redrawWindowClean(historyHwnd, nil)
}

func drawHistoryCommandButton(dis *drawItemStruct) bool {
	if dis == nil {
		return false
	}
	switch dis.CtlID {
	case ID_H_OPEN_DIR, ID_H_CHANGE_DIR, ID_H_FULL, ID_H_BATCH, ID_H_SELECT_ALL, ID_H_EXPORT, ID_H_DELETE, ID_H_DONE:
	default:
		return false
	}
	dpi := windowDPI(historyHwnd)
	background := rgb(255, 255, 255)
	border := rgb(224, 228, 234)
	foreground := rgb(42, 53, 70)
	if dis.CtlID == ID_H_DELETE {
		foreground = rgb(184, 40, 51)
		border = rgb(237, 203, 207)
		background = rgb(255, 250, 250)
	}
	if dis.ItemState&ODS_DISABLED != 0 {
		foreground = rgb(151, 158, 168)
		background = rgb(247, 248, 250)
		border = rgb(231, 234, 239)
	}
	if dis.ItemState&ODS_SELECTED != 0 {
		background = rgb(226, 237, 252)
		border = rgb(169, 194, 228)
		foreground = rgb(20, 91, 173)
	}
	drawRoundedSurface(dis.HDC, dis.RcItem, background, border, scale(8, dpi))
	textRect := dis.RcItem
	textRect.Left += scale(10, dpi)
	textRect.Right -= scale(10, dpi)
	drawText(dis.HDC, getText(syscall.Handle(dis.HwndItem)), &textRect, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, histFonts[2], foreground)
	if dis.ItemState&ODS_FOCUS != 0 {
		focusBrush := createBrush(rgb(37, 99, 180))
		focus := rect{dis.RcItem.Left + scale(3, dpi), dis.RcItem.Top + scale(3, dpi), dis.RcItem.Right - scale(3, dpi), dis.RcItem.Bottom - scale(3, dpi)}
		procFrameRect.Call(uintptr(dis.HDC), uintptr(unsafe.Pointer(&focus)), uintptr(focusBrush))
		procDeleteObject.Call(uintptr(focusBrush))
	}
	return true
}

func historyProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_CREATE:
		historyHwnd = hwnd
		applyWindowIcons(hwnd)
		histTitleHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS, 0, 0, 0, 0, hwnd, 0)
		histPathHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_RIGHT|SS_CENTERIMAGE|SS_NOTIFY, 0, 0, 0, 0, hwnd, ID_H_PATH)
		histOpenHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_OPEN_DIR)
		histChangeHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_CHANGE_DIR)
		histRecordsLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		histPreviewLabelHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_LEFT|SS_CENTERIMAGE, 0, 0, 0, 0, hwnd, 0)
		histSplitterHwnd = createWindow(0, "STATIC", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|SS_NOTIFY, 0, 0, 0, 0, hwnd, 0)
		histListHwnd = createWindow(0, "LISTBOX", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_NOINTEGRALHEIGHT|LBS_HASSTRINGS|LBS_EXTENDEDSEL, 0, 0, 0, 0, hwnd, ID_H_LIST)
		histPreviewHwnd = createWindow(0, "RICHEDIT50W", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|ES_AUTOHSCROLL, 0, 0, 0, 0, hwnd, 0)
		procSendMessageW.Call(uintptr(histPreviewHwnd), EM_SETBKGNDCOLOR, 0, uintptr(rgb(255, 255, 255)))
		histFullHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_FULL)
		histEmptyHwnd = createWindow(0, "STATIC", "", WS_CHILD|SS_LEFT, 0, 0, 0, 0, hwnd, ID_H_EMPTY)
		histBatchHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_BATCH)
		histSelectAllHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_SELECT_ALL)
		histExportSelectedHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_EXPORT)
		histDeleteSelectedHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_DELETE)
		histDoneHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_H_DONE)
		histDragOverlayHwnd = createWindow(WS_EX_NOACTIVATE, "HHVHistoryDragOverlay", "", WS_CHILD|WS_CLIPSIBLINGS, 0, 0, 0, 0, hwnd, 0)
		histSplitterBrush = createBrush(rgb(213, 219, 228))
		histSplitterActiveBrush = createBrush(rgb(174, 184, 198))
		setWindowTheme(histListHwnd, "Explorer")
		for _, button := range []syscall.Handle{histOpenHwnd, histChangeHwnd, histFullHwnd, histBatchHwnd, histSelectAllHwnd, histExportSelectedHwnd, histDeleteSelectedHwnd, histDoneHwnd} {
			setWindowTheme(button, "Explorer")
		}
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
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			m := currentHistoryMetrics()
			canvas := rect{0, 0, m.w, m.h}
			fillDC(syscall.Handle(hdc), canvas, rgb(248, 249, 251))
			leftW, rightW, _ := splitPaneWidths(m.total, m.minLeft, m.minRight, histSplitRatio)
			rx := m.m + leftW + m.splitW
			drawRoundedSurface(syscall.Handle(hdc), rect{m.m, m.bodyTop, m.m + leftW, m.bodyTop + m.bodyH}, rgb(255, 255, 255), rgb(226, 229, 234), scale(10, int(m.dpi)))
			drawRoundedSurface(syscall.Handle(hdc), rect{rx, m.bodyTop, rx + rightW, m.bodyTop + m.bodyH}, rgb(255, 255, 255), rgb(226, 229, 234), scale(10, int(m.dpi)))
		}
		procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
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
		if drawHistoryCommandButton(dis) {
			return 1
		}
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
		case ID_H_BATCH:
			setHistorySelectionMode(true)
		case ID_H_SELECT_ALL:
			selectAll := len(selectedHistoryIndices()) != len(histRecords)
			value := uintptr(0)
			if selectAll {
				value = 1
			}
			procSendMessageW.Call(uintptr(histListHwnd), LB_SETSEL, value, ^uintptr(0))
			procInvalidateRect.Call(uintptr(histListHwnd), 0, 0)
			updateHistorySelectionActions()
		case ID_H_EXPORT:
			exportSelectedHistory()
		case ID_H_DELETE:
			deleteSelectedHistory()
		case ID_H_DONE:
			setHistorySelectionMode(false)
		case ID_H_PATH:
			openHistoryDirectory()
		case ID_H_LIST:
			if notify == LBN_SELCHANGE {
				idx, _, _ := procSendMessageW.Call(uintptr(histListHwnd), LB_GETCARETINDEX, 0, 0)
				if int(idx) >= 0 && int(idx) < len(histRecords) {
					histSelected = int(idx)
					setRichText(histPreviewHwnd, historyDisplayText(histRecords[histSelected].Report))
				}
				updateHistorySelectionActions()
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
			if shellCardBrush != 0 {
				return uintptr(shellCardBrush)
			}
		}
		procSetBkMode.Call(wParam, TRANSPARENT)
		if control == histPathHwnd {
			procSetTextColor.Call(wParam, uintptr(rgb(37, 99, 180)))
		}
		if control == histTitleHwnd || control == histPathHwnd {
			if shellCanvasBrush != 0 {
				return uintptr(shellCanvasBrush)
			}
		} else if shellCardBrush != 0 {
			return uintptr(shellCardBrush)
		}
		b, _, _ := procGetSysColorBrush.Call(COLOR_WINDOW)
		return b
	case WM_CLOSE:
		procDestroyWindow.Call(uintptr(hwnd))
		return 0
	case WM_DESTROY:
		deleteFonts(histFonts)
		histFonts = nil
		historyHwnd = 0
		histListHwnd = 0
		histSplitterHwnd = 0
		histBatchHwnd = 0
		histSelectAllHwnd, histExportSelectedHwnd, histDeleteSelectedHwnd, histDoneHwnd = 0, 0, 0, 0
		histSelectionMode = false
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
	changeFonts = []syscall.Handle{
		createUIFontHalfPointDPI(uiPageTitleHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_NORMAL, dpi),
		createUIFontHalfPointDPI(uiSectionHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, dpi),
		createUIFontHalfPointDPI(21, FW_SEMIBOLD, dpi),
	}
	applyFont(changeTitleHwnd, changeFonts[0])
	applyFont(changeSubtitleHwnd, changeFonts[1])
	applyFont(changeVersionsLabelHwnd, changeFonts[2])
	applyFont(changeContentLabelHwnd, changeFonts[2])
	applyFont(changeContentHwnd, changeFonts[3])
	procSendMessageW.Call(uintptr(changeListHwnd), LB_SETITEMHEIGHT, 0, uintptr(scale(34, dpi)))
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
	changelogHwnd = createWindow(secondaryWindowExStyle(), "HHVChangelogWindow", tr(effectiveLocale(), "changelogTitle"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, scale(1060, dpi), scale(680, dpi), 0, 0)
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
		changeListHwnd = createWindow(0, "LISTBOX", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_NOINTEGRALHEIGHT|LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, ID_C_LIST)
		changeContentHwnd = createWindow(0, "RICHEDIT50W", "", WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|ES_AUTOHSCROLL, 0, 0, 0, 0, hwnd, ID_C_CONTENT)
		procSendMessageW.Call(uintptr(changeContentHwnd), EM_SETBKGNDCOLOR, 0, uintptr(rgb(255, 255, 255)))
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
	case WM_ERASEBKGND:
		return 1
	case WM_PAINT:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			r := clientRect(hwnd)
			fillDC(syscall.Handle(hdc), rect{0, 0, r.Right, r.Bottom}, rgb(248, 249, 251))
		}
		procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		return 0
	case WM_CTLCOLORSTATIC:
		procSetBkMode.Call(wParam, TRANSPARENT)
		if shellCanvasBrush != 0 {
			return uintptr(shellCanvasBrush)
		}
		b, _, _ := procGetSysColorBrush.Call(COLOR_WINDOW)
		return b
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

func createAboutLinkFont(halfPoints int, dpi int) syscall.Handle {
	height := -int32(halfPoints * dpi / 144)
	face := uiFontFaceForLocale(effectiveLocale())
	h, _, _ := procCreateFontW.Call(uintptr(height), 0, 0, 0, uintptr(FW_NORMAL), 0, 1, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, uintptr(unsafe.Pointer(utf16Ptr(face))))
	return syscall.Handle(h)
}

func recreateAboutFonts() {
	deleteFonts(aboutFonts)
	if aboutHwnd == 0 {
		return
	}
	dpi := windowDPI(aboutHwnd)
	aboutFonts = []syscall.Handle{
		createUIFontHalfPointDPI(40, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, dpi),
		createUIFontHalfPointDPI(uiCaptionHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiSectionHalfPoints, FW_SEMIBOLD, dpi),
		createUIFontHalfPointDPI(uiBodyHalfPoints, FW_NORMAL, dpi),
		createAboutLinkFont(uiBodyHalfPoints, dpi),
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
	applyFont(aboutChangelogHwnd, aboutFonts[4])
	applyFont(aboutUpdateHwnd, aboutFonts[4])
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
	setText(aboutChangelogHwnd, tr(code, "changelogTitle"))
	setText(aboutUpdateHwnd, updateText(code, "check"))
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
	menuRowH := scale(44, dpi)
	for _, h := range []syscall.Handle{aboutChangelogHwnd, aboutUpdateHwnd} {
		y = logicalY - aboutScrollPos
		moves = append(moves, windowMove{h, m, y, r.Right - 2*m, menuRowH})
		logicalY += menuRowH + scale(7, dpi)
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

func drawAboutMenuButton(dis *drawItemStruct) bool {
	if dis == nil || (dis.CtlID != ID_A_CHANGELOG && dis.CtlID != ID_A_UPDATE) {
		return false
	}
	dpi := windowDPI(aboutHwnd)
	background, border, foreground := rgb(255, 255, 255), rgb(224, 228, 234), rgb(31, 43, 60)
	if dis.ItemState&ODS_SELECTED != 0 {
		background, border, foreground = rgb(230, 239, 252), rgb(174, 199, 231), rgb(20, 91, 173)
	}
	if dis.ItemState&ODS_DISABLED != 0 {
		background, border, foreground = rgb(247, 248, 250), rgb(232, 235, 239), rgb(151, 158, 168)
	}
	drawRoundedSurface(dis.HDC, dis.RcItem, background, border, scale(8, dpi))
	glyph := "\uE823"
	if dis.CtlID == ID_A_UPDATE {
		glyph = "\uE895"
	}
	iconRect := dis.RcItem
	iconRect.Left += scale(12, dpi)
	iconRect.Right = iconRect.Left + scale(24, dpi)
	drawText(dis.HDC, glyph, &iconRect, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, shellIconFont, rgb(31, 106, 204))
	textRect := dis.RcItem
	textRect.Left += scale(46, dpi)
	textRect.Right -= scale(42, dpi)
	drawText(dis.HDC, getText(syscall.Handle(dis.HwndItem)), &textRect, DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX, aboutFonts[4], foreground)
	chevronRect := dis.RcItem
	chevronRect.Left = chevronRect.Right - scale(36, dpi)
	chevronRect.Right -= scale(10, dpi)
	drawText(dis.HDC, "\uE76C", &chevronRect, DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX, shellIconFont, rgb(133, 143, 157))
	return true
}

func openAbout() {
	if shellBrandHwnd != 0 {
		switchShellPage(shellPageAbout)
		return
	}
	if aboutHwnd != 0 {
		showWindowFront(aboutHwnd)
		return
	}
	dpi := mainDPI
	aboutHwnd = createWindow(secondaryWindowExStyle(), "HHVAboutWindow", tr(effectiveLocale(), "about"), WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_CLIPCHILDREN|WS_VSCROLL, CW_USEDEFAULT, CW_USEDEFAULT, scale(780, dpi), scale(720, dpi), 0, 0)
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
		aboutChangelogHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_A_CHANGELOG)
		aboutUpdateHwnd = createWindow(0, "BUTTON", "", WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS|WS_TABSTOP|BS_OWNERDRAW, 0, 0, 0, 0, hwnd, ID_A_UPDATE)
		setWindowTheme(aboutChangelogHwnd, "Explorer")
		setWindowTheme(aboutUpdateHwnd, "Explorer")
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
	case WM_ERASEBKGND:
		return 1
	case WM_DRAWITEM:
		if drawAboutMenuButton((*drawItemStruct)(unsafe.Pointer(lParam))) {
			return 1
		}
	case WM_COMMAND:
		switch loword(wParam) {
		case ID_A_CHANGELOG:
			openChangelog()
			return 0
		case ID_A_UPDATE:
			checkForUpdates()
			return 0
		}
	case WM_PAINT:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			r := clientRect(hwnd)
			fillDC(syscall.Handle(hdc), rect{0, 0, r.Right, r.Bottom}, rgb(248, 249, 251))
		}
		procEndPaint.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&ps)))
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
		if shellCanvasBrush != 0 {
			return uintptr(shellCanvasBrush)
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
		aboutChangelogHwnd, aboutUpdateHwnd = 0, 0
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
	if runCoreCommand() {
		return
	}
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
	// The application must always be able to open under the current account.
	// Windows exposes the overview and battery data without elevation; only a
	// subset of controller-specific SMART fields may be unavailable. Users who
	// need those fields can explicitly choose "Run as administrator" themselves.
	classes := []struct {
		name string
		proc uintptr
	}{{"HHVMainWindow", syscall.NewCallback(mainWindowProc)}, {"HHVDashboard", syscall.NewCallback(dashboardProc)}, {"HHVSettingsPage", syscall.NewCallback(settingsPageProc)}, {"HHVHistoryWindow", syscall.NewCallback(historyProc)}, {"HHVHistoryDragOverlay", syscall.NewCallback(historyDragOverlayProc)}, {"HHVChangelogWindow", syscall.NewCallback(changelogProc)}, {"HHVAboutWindow", syscall.NewCallback(aboutProc)}, {"HHVViewerWindow", syscall.NewCallback(viewerProc)}, {"HHVDeleteDialog", syscall.NewCallback(deleteDialogProc)}}
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
