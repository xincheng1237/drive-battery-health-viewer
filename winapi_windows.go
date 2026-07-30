//go:build windows

package main

import (
	"fmt"
	"syscall"
	"unsafe"
)

const (
	WM_CREATE          = 0x0001
	WM_DESTROY         = 0x0002
	WM_MOVE            = 0x0003
	WM_SIZE            = 0x0005
	WM_SETFOCUS        = 0x0007
	WM_PAINT           = 0x000F
	WM_ERASEBKGND      = 0x0014
	WM_SETCURSOR       = 0x0020
	WM_CLOSE           = 0x0010
	WM_GETMINMAXINFO   = 0x0024
	WM_SETFONT         = 0x0030
	WM_SETICON         = 0x0080
	WM_COMMAND         = 0x0111
	WM_SYSCOMMAND      = 0x0112
	WM_TIMER           = 0x0113
	WM_DRAWITEM        = 0x002B
	WM_MEASUREITEM     = 0x002C
	WM_CTLCOLORSTATIC  = 0x0138
	WM_CTLCOLOREDIT    = 0x0133
	WM_CTLCOLORLISTBOX = 0x0134
	WM_MOUSEMOVE       = 0x0200
	WM_LBUTTONDOWN     = 0x0201
	WM_LBUTTONUP       = 0x0202
	WM_LBUTTONDBLCLK   = 0x0203
	WM_CAPTURECHANGED  = 0x0215
	WM_MOUSELEAVE      = 0x02A3
	WM_MOUSEWHEEL      = 0x020A
	WM_VSCROLL         = 0x0115
	WM_DPICHANGED      = 0x02E0
	WM_SETREDRAW       = 0x000B
	WM_NOTIFY          = 0x004E
	WM_USER            = 0x0400
	WM_APP_SCAN_DONE   = 0x8001

	WS_OVERLAPPED       = 0x00000000
	WS_POPUP            = 0x80000000
	WS_CAPTION          = 0x00C00000
	WS_SYSMENU          = 0x00080000
	WS_THICKFRAME       = 0x00040000
	WS_MINIMIZEBOX      = 0x00020000
	WS_MAXIMIZEBOX      = 0x00010000
	WS_OVERLAPPEDWINDOW = 0x00CF0000
	WS_VISIBLE          = 0x10000000
	WS_CHILD            = 0x40000000
	WS_VSCROLL          = 0x00200000
	WS_HSCROLL          = 0x00100000
	WS_TABSTOP          = 0x00010000
	WS_CLIPCHILDREN     = 0x02000000
	WS_CLIPSIBLINGS     = 0x04000000
	WS_EX_CLIENTEDGE    = 0x00000200
	WS_EX_TOOLWINDOW    = 0x00000080
	WS_EX_NOACTIVATE    = 0x08000000
	WS_EX_APPWINDOW     = 0x00040000
	WS_EX_CONTROLPARENT = 0x00010000
	WS_EX_COMPOSITED    = 0x02000000

	ES_MULTILINE    = 0x0004
	ES_AUTOVSCROLL  = 0x0040
	ES_AUTOHSCROLL  = 0x0080
	ES_READONLY     = 0x0800
	ES_NOHIDESEL    = 0x0100
	BS_AUTOCHECKBOX = 0x00000003
	BST_CHECKED     = 1
	BM_GETCHECK     = 0x00F0
	BM_SETCHECK     = 0x00F1
	SS_LEFT         = 0
	SS_CENTER       = 1
	SS_NOTIFY       = 0x0100
	SS_ETCHEDVERT   = 0x0011
	SS_CENTERIMAGE  = 0x0200

	LBS_NOTIFY           = 0x0001
	LBS_OWNERDRAWFIXED   = 0x0010
	LBS_NOINTEGRALHEIGHT = 0x0100
	LBS_HASSTRINGS       = 0x0040
	LB_ADDSTRING         = 0x0180
	LB_RESETCONTENT      = 0x0184
	LB_GETCURSEL         = 0x0188
	LB_SETCURSEL         = 0x0186
	LB_GETITEMRECT       = 0x0198
	LB_ITEMFROMPOINT     = 0x01A9
	LB_SETITEMHEIGHT     = 0x01A0
	LBN_SELCHANGE        = 1
	LBN_DBLCLK           = 2

	EM_SETSEL        = 0x00B1
	EM_SCROLLCARET   = 0x00B7
	EM_SETREADONLY   = 0x00CF
	EM_SETBKGNDCOLOR = 0x0443
	EM_GETEVENTMASK  = WM_USER + 59
	EM_SETEVENTMASK  = WM_USER + 69
	EM_GETTEXTRANGE  = WM_USER + 75
	EM_AUTOURLDETECT = WM_USER + 91
	ENM_LINK         = 0x04000000
	EN_LINK          = 0x070B

	SW_HIDE              = 0
	SW_SHOWNORMAL        = 1
	SW_SHOW              = 5
	SW_MINIMIZE          = 6
	SW_RESTORE           = 9
	SIZE_MINIMIZED       = 1
	CW_USEDEFAULT  int32 = -2147483648
	IDC_ARROW            = 32512
	IDC_SIZEWE           = 32644
	IDC_HAND             = 32649
	COLOR_WINDOW         = 5
	COLOR_BTNFACE        = 15

	MB_OK              = 0
	MB_OKCANCEL        = 1
	MB_YESNO           = 4
	MB_ICONINFORMATION = 0x40
	MB_ICONERROR       = 0x10
	MB_ICONWARNING     = 0x30
	MB_DEFBUTTON2      = 0x100
	IDOK               = 1
	IDCANCEL           = 2
	IDYES              = 6

	CF_UNICODETEXT      = 13
	GMEM_MOVEABLE       = 2
	OFN_OVERWRITEPROMPT = 2
	OFN_PATHMUSTEXIST   = 0x800
	OFN_EXPLORER        = 0x80000
	OFN_NOCHANGEDIR     = 8

	MF_STRING      = 0
	MF_SEPARATOR   = 0x800
	MF_CHECKED     = 8
	MF_UNCHECKED   = 0
	MF_GRAYED      = 1
	TPM_RIGHTALIGN = 8
	TPM_TOPALIGN   = 0
	TPM_RETURNCMD  = 0x100

	DT_LEFT         = 0
	DT_CENTER       = 1
	DT_RIGHT        = 2
	DT_VCENTER      = 4
	DT_SINGLELINE   = 0x20
	DT_END_ELLIPSIS = 0x8000
	DT_NOPREFIX     = 0x800
	DT_CALCRECT     = 0x0400
	TRANSPARENT     = 1
	OPAQUE          = 2
	ODS_SELECTED    = 1
	ODS_FOCUS       = 0x10
	SRCCOPY         = 0x00CC0020
	PS_SOLID        = 0

	GWLP_WNDPROC = -4
	GWL_STYLE    = -16
	TME_LEAVE    = 2

	SB_HORZ          = 0
	SB_VERT          = 1
	SB_LINEUP        = 0
	SB_LINEDOWN      = 1
	SB_PAGEUP        = 2
	SB_PAGEDOWN      = 3
	SB_THUMBPOSITION = 4
	SB_THUMBTRACK    = 5
	SB_TOP           = 6
	SB_BOTTOM        = 7
	SIF_RANGE        = 0x0001
	SIF_PAGE         = 0x0002
	SIF_POS          = 0x0004
	SIF_TRACKPOS     = 0x0010
	SIF_ALL          = SIF_RANGE | SIF_PAGE | SIF_POS | SIF_TRACKPOS

	LOGPIXELSY          = 90
	FW_NORMAL           = 400
	FW_SEMIBOLD         = 600
	FW_BOLD             = 700
	DEFAULT_CHARSET     = 1
	OUT_DEFAULT_PRECIS  = 0
	CLIP_DEFAULT_PRECIS = 0
	CLEARTYPE_QUALITY   = 5
	DEFAULT_PITCH       = 0

	FILE_SHARE_READ                        = 1
	FILE_SHARE_WRITE                       = 2
	OPEN_EXISTING                          = 3
	GENERIC_READ                           = 0x80000000
	IOCTL_STORAGE_QUERY_PROPERTY           = 0x002D1400
	IOCTL_DISK_GET_LENGTH_INFO             = 0x0007405C
	StorageDeviceProperty                  = 0
	StorageAdapterProtocolSpecificProperty = 49
	StorageDeviceProtocolSpecificProperty  = 50
	PropertyStandardQuery                  = 0
	ProtocolTypeNvme                       = 3
	NVMeDataTypeLogPage                    = 2
	NVMeHealthLogPage                      = 2

	BIF_RETURNONLYFSDIRS = 0x0001
	BIF_NEWDIALOGSTYLE   = 0x0040
	MAX_PATH             = 260
	HWND_TOP             = 0
	SWP_NOSIZE           = 1
	SWP_NOMOVE           = 2
	SWP_NOZORDER         = 4
	SWP_NOACTIVATE       = 0x10
	SWP_SHOWWINDOW       = 0x40
	SWP_NOREDRAW         = 0x0008
	SWP_NOCOPYBITS       = 0x0100

	ICON_SMALL = 0
	ICON_BIG   = 1

	LR_DEFAULTCOLOR = 0x0000

	RDW_INVALIDATE  = 0x0001
	RDW_ERASE       = 0x0004
	RDW_NOERASE     = 0x0020
	RDW_UPDATENOW   = 0x0100
	RDW_ALLCHILDREN = 0x0080
	RDW_FRAME       = 0x0400
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	comdlg32 = syscall.NewLazyDLL("comdlg32.dll")
	ntdll    = syscall.NewLazyDLL("ntdll.dll")
	uxtheme  = syscall.NewLazyDLL("uxtheme.dll")

	procRegisterClassExW              = user32.NewProc("RegisterClassExW")
	procCreateWindowExW               = user32.NewProc("CreateWindowExW")
	procDefWindowProcW                = user32.NewProc("DefWindowProcW")
	procShowWindow                    = user32.NewProc("ShowWindow")
	procUpdateWindow                  = user32.NewProc("UpdateWindow")
	procGetMessageW                   = user32.NewProc("GetMessageW")
	procTranslateMessage              = user32.NewProc("TranslateMessage")
	procDispatchMessageW              = user32.NewProc("DispatchMessageW")
	procPostQuitMessage               = user32.NewProc("PostQuitMessage")
	procDestroyWindow                 = user32.NewProc("DestroyWindow")
	procMoveWindow                    = user32.NewProc("MoveWindow")
	procSetWindowTextW                = user32.NewProc("SetWindowTextW")
	procGetWindowTextLengthW          = user32.NewProc("GetWindowTextLengthW")
	procGetWindowTextW                = user32.NewProc("GetWindowTextW")
	procSendMessageW                  = user32.NewProc("SendMessageW")
	procPostMessageW                  = user32.NewProc("PostMessageW")
	procMessageBoxW                   = user32.NewProc("MessageBoxW")
	procLoadCursorW                   = user32.NewProc("LoadCursorW")
	procSetCursor                     = user32.NewProc("SetCursor")
	procSetCapture                    = user32.NewProc("SetCapture")
	procReleaseCapture                = user32.NewProc("ReleaseCapture")
	procOpenClipboard                 = user32.NewProc("OpenClipboard")
	procEmptyClipboard                = user32.NewProc("EmptyClipboard")
	procSetClipboardData              = user32.NewProc("SetClipboardData")
	procCloseClipboard                = user32.NewProc("CloseClipboard")
	procSetProcessDPIAware            = user32.NewProc("SetProcessDPIAware")
	procSetProcessDpiAwarenessContext = user32.NewProc("SetProcessDpiAwarenessContext")
	procEnableWindow                  = user32.NewProc("EnableWindow")
	procGetDC                         = user32.NewProc("GetDC")
	procReleaseDC                     = user32.NewProc("ReleaseDC")
	procBeginPaint                    = user32.NewProc("BeginPaint")
	procEndPaint                      = user32.NewProc("EndPaint")
	procGetClientRect                 = user32.NewProc("GetClientRect")
	procGetWindowRect                 = user32.NewProc("GetWindowRect")
	procInvalidateRect                = user32.NewProc("InvalidateRect")
	procSetWindowPos                  = user32.NewProc("SetWindowPos")
	procSetForegroundWindow           = user32.NewProc("SetForegroundWindow")
	procSetFocus                      = user32.NewProc("SetFocus")
	procIsIconic                      = user32.NewProc("IsIconic")
	procCreatePopupMenu               = user32.NewProc("CreatePopupMenu")
	procAppendMenuW                   = user32.NewProc("AppendMenuW")
	procTrackPopupMenu                = user32.NewProc("TrackPopupMenu")
	procDestroyMenu                   = user32.NewProc("DestroyMenu")
	procGetCursorPos                  = user32.NewProc("GetCursorPos")
	procClientToScreen                = user32.NewProc("ClientToScreen")
	procSetTimer                      = user32.NewProc("SetTimer")
	procKillTimer                     = user32.NewProc("KillTimer")
	procTrackMouseEvent               = user32.NewProc("TrackMouseEvent")
	procSetWindowLongPtrW             = user32.NewProc("SetWindowLongPtrW")
	procGetWindowLongPtrW             = user32.NewProc("GetWindowLongPtrW")
	procCallWindowProcW               = user32.NewProc("CallWindowProcW")
	procGetDpiForWindow               = user32.NewProc("GetDpiForWindow")
	procDrawTextW                     = user32.NewProc("DrawTextW")
	procGetSysColorBrush              = user32.NewProc("GetSysColorBrush")
	procFillRect                      = user32.NewProc("FillRect")
	procFrameRect                     = user32.NewProc("FrameRect")
	procRedrawWindow                  = user32.NewProc("RedrawWindow")
	procBeginDeferWindowPos           = user32.NewProc("BeginDeferWindowPos")
	procDeferWindowPos                = user32.NewProc("DeferWindowPos")
	procEndDeferWindowPos             = user32.NewProc("EndDeferWindowPos")
	procCreateIconFromResourceEx      = user32.NewProc("CreateIconFromResourceEx")
	procDestroyIcon                   = user32.NewProc("DestroyIcon")
	procSetScrollInfo                 = user32.NewProc("SetScrollInfo")
	procGetScrollInfo                 = user32.NewProc("GetScrollInfo")

	procGetModuleHandleW         = kernel32.NewProc("GetModuleHandleW")
	procCreateFileW              = kernel32.NewProc("CreateFileW")
	procDeviceIoControl          = kernel32.NewProc("DeviceIoControl")
	procCloseHandle              = kernel32.NewProc("CloseHandle")
	procGlobalAlloc              = kernel32.NewProc("GlobalAlloc")
	procGlobalLock               = kernel32.NewProc("GlobalLock")
	procGlobalUnlock             = kernel32.NewProc("GlobalUnlock")
	procGlobalFree               = kernel32.NewProc("GlobalFree")
	procRtlMoveMemory            = kernel32.NewProc("RtlMoveMemory")
	procGetUserDefaultUILanguage = kernel32.NewProc("GetUserDefaultUILanguage")
	procLoadLibraryW             = kernel32.NewProc("LoadLibraryW")

	procShellExecuteW        = shell32.NewProc("ShellExecuteW")
	procIsUserAnAdmin        = shell32.NewProc("IsUserAnAdmin")
	procSHBrowseForFolderW   = shell32.NewProc("SHBrowseForFolderW")
	procSHGetPathFromIDListW = shell32.NewProc("SHGetPathFromIDListW")
	procCoTaskMemFree        = syscall.NewLazyDLL("ole32.dll").NewProc("CoTaskMemFree")

	procCreateFontW            = gdi32.NewProc("CreateFontW")
	procDeleteObject           = gdi32.NewProc("DeleteObject")
	procGetDeviceCaps          = gdi32.NewProc("GetDeviceCaps")
	procCreateSolidBrush       = gdi32.NewProc("CreateSolidBrush")
	procCreatePen              = gdi32.NewProc("CreatePen")
	procSelectObject           = gdi32.NewProc("SelectObject")
	procSetTextColor           = gdi32.NewProc("SetTextColor")
	procSetBkMode              = gdi32.NewProc("SetBkMode")
	procRoundRect              = gdi32.NewProc("RoundRect")
	procCreateCompatibleDC     = gdi32.NewProc("CreateCompatibleDC")
	procDeleteDC               = gdi32.NewProc("DeleteDC")
	procCreateCompatibleBitmap = gdi32.NewProc("CreateCompatibleBitmap")
	procBitBlt                 = gdi32.NewProc("BitBlt")

	procGetSaveFileNameW = comdlg32.NewProc("GetSaveFileNameW")
	procRtlGetVersion    = ntdll.NewProc("RtlGetVersion")
	procSetWindowTheme   = uxtheme.NewProc("SetWindowTheme")
)

type point struct{ X, Y int32 }
type rect struct{ Left, Top, Right, Bottom int32 }
type paintStruct struct {
	Hdc       syscall.Handle
	Erase     int32
	Paint     rect
	Restore   int32
	IncUpdate int32
	Reserved  [32]byte
}
type msg struct {
	Hwnd           syscall.Handle
	Message        uint32
	_pad           uint32
	WParam, LParam uintptr
	Time           uint32
	Pt             point
	LPrivate       uint32
}
type wndClassEx struct {
	CbSize                                   uint32
	Style                                    uint32
	LpfnWndProc                              uintptr
	CbClsExtra, CbWndExtra                   int32
	HInstance, HIcon, HCursor, HbrBackground syscall.Handle
	LpszMenuName, LpszClassName              *uint16
	HIconSm                                  syscall.Handle
}
type minMaxInfo struct{ Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize point }
type openFilename struct {
	LStructSize                    uint32
	HwndOwner, HInstance           syscall.Handle
	LpstrFilter, LpstrCustomFilter *uint16
	NMaxCustFilter, NFilterIndex   uint32
	LpstrFile                      *uint16
	NMaxFile                       uint32
	LpstrFileTitle                 *uint16
	NMaxFileTitle                  uint32
	LpstrInitialDir, LpstrTitle    *uint16
	Flags                          uint32
	NFileOffset, NFileExtension    uint16
	LpstrDefExt                    *uint16
	LCustData, LpfnHook            uintptr
	LpTemplateName                 *uint16
	PvReserved                     uintptr
	DwReserved, FlagsEx            uint32
}

type scrollInfo struct {
	CbSize    uint32
	FMask     uint32
	NMin      int32
	NMax      int32
	NPage     uint32
	NPos      int32
	NTrackPos int32
}
type osVersionInfo struct {
	Size, Major, Minor, Build, Platform uint32
	CSDVersion                          [128]uint16
}
type drawItemStruct struct {
	CtlType, CtlID, ItemID, ItemAction, ItemState uint32
	HwndItem, HDC                                 syscall.Handle
	RcItem                                        rect
	ItemData                                      uintptr
}
type trackMouseEvent struct {
	CbSize, DwFlags uint32
	HwndTrack       syscall.Handle
	DwHoverTime     uint32
}
type browseInfo struct {
	HwndOwner      syscall.Handle
	PidlRoot       uintptr
	PszDisplayName *uint16
	LpszTitle      *uint16
	UlFlags        uint32
	Lpfn           uintptr
	LParam         uintptr
	IImage         int32
}

type charRange struct {
	CpMin int32
	CpMax int32
}

type textRange struct {
	Chrg      charRange
	LpstrText *uint16
}

type nmhdr struct {
	HwndFrom syscall.Handle
	IdFrom   uintptr
	Code     uint32
}

type enlink struct {
	Hdr    nmhdr
	Msg    uint32
	WParam uintptr
	LParam uintptr
	Chrg   charRange
}

func utf16Ptr(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }
func utf16MultiString(parts ...string) []uint16 {
	r := make([]uint16, 0, 128)
	for _, p := range parts {
		u, _ := syscall.UTF16FromString(p)
		r = append(r, u...)
	}
	return append(r, 0)
}
func loword(v uintptr) uint16      { return uint16(v & 0xffff) }
func hiword(v uintptr) uint16      { return uint16(v >> 16) }
func rgb(r, g, b byte) uint32      { return uint32(r) | uint32(g)<<8 | uint32(b)<<16 }
func scale(v int32, dpi int) int32 { return int32(int64(v) * int64(dpi) / 96) }

func messageBox(owner syscall.Handle, title, text string, flags uintptr) int {
	r, _, _ := procMessageBoxW.Call(uintptr(owner), uintptr(unsafe.Pointer(utf16Ptr(text))), uintptr(unsafe.Pointer(utf16Ptr(title))), flags)
	return int(r)
}
func createWindow(ex uint32, class, text string, style uint32, x, y, w, h int32, parent syscall.Handle, id uintptr) syscall.Handle {
	inst, _, _ := procGetModuleHandleW.Call(0)
	r, _, _ := procCreateWindowExW.Call(uintptr(ex), uintptr(unsafe.Pointer(utf16Ptr(class))), uintptr(unsafe.Pointer(utf16Ptr(text))), uintptr(style), uintptr(x), uintptr(y), uintptr(w), uintptr(h), uintptr(parent), id, inst, 0)
	return syscall.Handle(r)
}
func setText(h syscall.Handle, s string) {
	if h != 0 {
		procSetWindowTextW.Call(uintptr(h), uintptr(unsafe.Pointer(utf16Ptr(s))))
	}
}
func getText(h syscall.Handle) string {
	n, _, _ := procGetWindowTextLengthW.Call(uintptr(h))
	if n == 0 {
		return ""
	}
	b := make([]uint16, n+1)
	procGetWindowTextW.Call(uintptr(h), uintptr(unsafe.Pointer(&b[0])), n+1)
	return syscall.UTF16ToString(b)
}
func clientRect(h syscall.Handle) rect {
	var r rect
	procGetClientRect.Call(uintptr(h), uintptr(unsafe.Pointer(&r)))
	return r
}
func windowDPI(h syscall.Handle) int {
	if h != 0 && procGetDpiForWindow.Find() == nil {
		if d, _, _ := procGetDpiForWindow.Call(uintptr(h)); d >= 72 && d <= 480 {
			return int(d)
		}
	}
	dc, _, _ := procGetDC.Call(0)
	if dc == 0 {
		return 96
	}
	defer procReleaseDC.Call(0, dc)
	d, _, _ := procGetDeviceCaps.Call(dc, LOGPIXELSY)
	if d < 72 || d > 480 {
		return 96
	}
	return int(d)
}
func createUIFontDPI(points int, weight int32, dpi int) syscall.Handle {
	height := -int32(points * dpi / 72)
	h, _, _ := procCreateFontW.Call(uintptr(height), 0, 0, 0, uintptr(weight), 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, uintptr(unsafe.Pointer(utf16Ptr("Segoe UI"))))
	return syscall.Handle(h)
}
func createUIFontHalfPointDPI(halfPoints int, weight int32, dpi int) syscall.Handle {
	// halfPoints stores the point size multiplied by two, allowing sizes such as 9.5 pt.
	height := -int32(halfPoints * dpi / 144)
	h, _, _ := procCreateFontW.Call(uintptr(height), 0, 0, 0, uintptr(weight), 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, uintptr(unsafe.Pointer(utf16Ptr("Segoe UI"))))
	return syscall.Handle(h)
}
func applyFont(h, f syscall.Handle) {
	if h != 0 && f != 0 {
		procSendMessageW.Call(uintptr(h), WM_SETFONT, uintptr(f), 1)
	}
}
func enableWindow(h syscall.Handle, b bool) {
	v := uintptr(0)
	if b {
		v = 1
	}
	procEnableWindow.Call(uintptr(h), v)
}
func showWindowFront(h syscall.Handle) {
	if h == 0 {
		return
	}
	if r, _, _ := procIsIconic.Call(uintptr(h)); r != 0 {
		procShowWindow.Call(uintptr(h), SW_RESTORE)
	} else {
		procShowWindow.Call(uintptr(h), SW_SHOW)
	}
	procSetWindowPos.Call(uintptr(h), HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW)
	procSetForegroundWindow.Call(uintptr(h))
}
func centerWindow(h syscall.Handle, w, hgt int32) {
	sw := int32(1200)
	sh := int32(800) // conservative fallback
	x := (sw - w) / 2
	y := (sh - hgt) / 2
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	procSetWindowPos.Call(uintptr(h), 0, uintptr(x), uintptr(y), uintptr(w), uintptr(hgt), SWP_NOZORDER|SWP_SHOWWINDOW)
}
func setRichText(h syscall.Handle, text string) {
	if h == 0 {
		return
	}
	procSendMessageW.Call(uintptr(h), WM_SETREDRAW, 0, 0)
	setText(h, text)
	procSendMessageW.Call(uintptr(h), EM_SETSEL, 0, 0)
	procSendMessageW.Call(uintptr(h), EM_SCROLLCARET, 0, 0)
	procSendMessageW.Call(uintptr(h), WM_SETREDRAW, 1, 0)
	procInvalidateRect.Call(uintptr(h), 0, 1)
	procUpdateWindow.Call(uintptr(h))
}
func setWindowTheme(h syscall.Handle, theme string) {
	if h != 0 {
		procSetWindowTheme.Call(uintptr(h), uintptr(unsafe.Pointer(utf16Ptr(theme))), 0)
	}
}

func richEditRangeText(h syscall.Handle, chrg charRange) (string, bool) {
	if h == 0 || chrg.CpMax <= chrg.CpMin {
		return "", false
	}
	buf := make([]uint16, chrg.CpMax-chrg.CpMin+2)
	tr := textRange{Chrg: chrg, LpstrText: &buf[0]}
	procSendMessageW.Call(uintptr(h), EM_GETTEXTRANGE, 0, uintptr(unsafe.Pointer(&tr)))
	return syscall.UTF16ToString(buf), true
}

func saveFileDialog(owner syscall.Handle, title, defaultName, initialDir, filterLabel, allLabel string) (string, bool, error) {
	buf := make([]uint16, 32768)
	u, _ := syscall.UTF16FromString(defaultName)
	copy(buf, u)
	filter := utf16MultiString(filterLabel, "*.txt", allLabel, "*.*")
	of := openFilename{HwndOwner: owner, LpstrFilter: &filter[0], NFilterIndex: 1, LpstrFile: &buf[0], NMaxFile: uint32(len(buf)), LpstrTitle: utf16Ptr(title), Flags: OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT, LpstrDefExt: utf16Ptr("txt")}
	if initialDir != "" {
		of.LpstrInitialDir = utf16Ptr(initialDir)
	}
	of.LStructSize = uint32(unsafe.Sizeof(of))
	r, _, e := procGetSaveFileNameW.Call(uintptr(unsafe.Pointer(&of)))
	if r == 0 {
		if errno, ok := e.(syscall.Errno); ok && errno != 0 {
			return "", false, errno
		}
		return "", false, nil
	}
	return syscall.UTF16ToString(buf), true, nil
}
func chooseFolder(owner syscall.Handle, title string) (string, bool) {
	display := make([]uint16, MAX_PATH)
	bi := browseInfo{HwndOwner: owner, PszDisplayName: &display[0], LpszTitle: utf16Ptr(title), UlFlags: BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE}
	pidl, _, _ := procSHBrowseForFolderW.Call(uintptr(unsafe.Pointer(&bi)))
	if pidl == 0 {
		return "", false
	}
	defer procCoTaskMemFree.Call(pidl)
	path := make([]uint16, 32768)
	ok, _, _ := procSHGetPathFromIDListW.Call(pidl, uintptr(unsafe.Pointer(&path[0])))
	if ok == 0 {
		return "", false
	}
	return syscall.UTF16ToString(path), true
}
func openPath(path string) error {
	r, _, e := procShellExecuteW.Call(0, uintptr(unsafe.Pointer(utf16Ptr("open"))), uintptr(unsafe.Pointer(utf16Ptr(path))), 0, 0, SW_SHOWNORMAL)
	if r <= 32 {
		return fmt.Errorf("ShellExecuteW: %v", e)
	}
	return nil
}
func windowsMajorVersion() uint32 {
	v := osVersionInfo{Size: uint32(unsafe.Sizeof(osVersionInfo{}))}
	r, _, _ := procRtlGetVersion.Call(uintptr(unsafe.Pointer(&v)))
	if r != 0 {
		return 0
	}
	return v.Major
}
func registerWindowClass(name string, proc uintptr, background uint32) error {
	inst, _, _ := procGetModuleHandleW.Call(0)
	cur, _, _ := procLoadCursorW.Call(0, IDC_ARROW)
	wc := wndClassEx{CbSize: uint32(unsafe.Sizeof(wndClassEx{})), LpfnWndProc: proc, HInstance: syscall.Handle(inst), HIcon: appIconLarge, HCursor: syscall.Handle(cur), HbrBackground: syscall.Handle(background + 1), LpszClassName: utf16Ptr(name), HIconSm: appIconSmall}
	r, _, e := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))
	if r == 0 {
		return fmt.Errorf("RegisterClassExW: %v", e)
	}
	return nil
}

func applyWindowIcons(h syscall.Handle) {
	if h == 0 {
		return
	}
	if appIconLarge != 0 {
		procSendMessageW.Call(uintptr(h), WM_SETICON, ICON_BIG, uintptr(appIconLarge))
	}
	if appIconSmall != 0 {
		procSendMessageW.Call(uintptr(h), WM_SETICON, ICON_SMALL, uintptr(appIconSmall))
	}
}
func createBrush(c uint32) syscall.Handle {
	h, _, _ := procCreateSolidBrush.Call(uintptr(c))
	return syscall.Handle(h)
}
func createPen(c uint32, w int32) syscall.Handle {
	h, _, _ := procCreatePen.Call(PS_SOLID, uintptr(w), uintptr(c))
	return syscall.Handle(h)
}
func drawText(hdc syscall.Handle, text string, r *rect, flags uint32, font syscall.Handle, color uint32) {
	old := uintptr(0)
	if font != 0 {
		old, _, _ = procSelectObject.Call(uintptr(hdc), uintptr(font))
	}
	procSetBkMode.Call(uintptr(hdc), TRANSPARENT)
	procSetTextColor.Call(uintptr(hdc), uintptr(color))
	procDrawTextW.Call(uintptr(hdc), uintptr(unsafe.Pointer(utf16Ptr(text))), ^uintptr(0), uintptr(unsafe.Pointer(r)), uintptr(flags))
	if old != 0 {
		procSelectObject.Call(uintptr(hdc), old)
	}
}

func measureTextWidth(h syscall.Handle, text string, font syscall.Handle) int32 {
	dc, _, _ := procGetDC.Call(uintptr(h))
	if dc == 0 {
		return int32(len([]rune(text)) * 8)
	}
	defer procReleaseDC.Call(uintptr(h), dc)
	old := uintptr(0)
	if font != 0 {
		old, _, _ = procSelectObject.Call(dc, uintptr(font))
	}
	r := rect{0, 0, 4096, 4096}
	procDrawTextW.Call(dc, uintptr(unsafe.Pointer(utf16Ptr(text))), ^uintptr(0), uintptr(unsafe.Pointer(&r)), DT_SINGLELINE|DT_NOPREFIX|DT_CALCRECT)
	if old != 0 {
		procSelectObject.Call(dc, old)
	}
	return r.Right - r.Left
}
