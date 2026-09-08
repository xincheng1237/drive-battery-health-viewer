//go:build windows

package main

import "testing"

func TestShellPageConstantsAreZeroBasedAndContiguous(t *testing.T) {
	pages := []int{shellPageOverview, shellPageHistory, shellPageSettings, shellPageAbout}
	for want, got := range pages {
		if got != want {
			t.Fatalf("page constant %d = %d, want %d", want, got, want)
		}
	}
}

func TestShellNavigationCommandMapping(t *testing.T) {
	tests := []struct {
		id   uint16
		page int
	}{{ID_NAV_OVERVIEW, shellPageOverview}, {ID_NAV_HISTORY, shellPageHistory}, {ID_NAV_SETTINGS, shellPageSettings}, {ID_NAV_ABOUT, shellPageAbout}}
	for _, tt := range tests {
		page, ok := shellPageForCommand(tt.id)
		if !ok || page != tt.page {
			t.Fatalf("command %d mapped to page %d, ok=%v; want %d", tt.id, page, ok, tt.page)
		}
	}
}

func TestWindows10_1809FeatureBoundary(t *testing.T) {
	if supportsWindows10_1809Features(10, 17762) {
		t.Fatal("Windows 10 build 17762 must use the compatibility rendering path")
	}
	if !supportsWindows10_1809Features(10, 17763) {
		t.Fatal("Windows 10 build 17763 must enable the 1809 rendering path")
	}
	if !supportsWindows10_1809Features(11, 0) {
		t.Fatal("newer Windows major versions must enable the modern rendering path")
	}
}

func TestBatteryDashboardUsesEvenGrid(t *testing.T) {
	fields := batteryDashboardFields(BatteryInfo{})
	if len(fields) != 6 {
		t.Fatalf("battery dashboard field count = %d, want 6", len(fields))
	}
	if len(fields)%2 != 0 {
		t.Fatalf("battery dashboard field count must be even: %d", len(fields))
	}
}

func TestSettingsContentGeometryUsesOneCenteredColumn(t *testing.T) {
	for _, tc := range []struct {
		name       string
		width, dpi int32
		wantX      int32
		wantW      int32
	}{
		{name: "wide", width: 1200, dpi: 96, wantX: 220, wantW: 760},
		{name: "fallback", width: 400, dpi: 96, wantX: 16, wantW: 368},
		{name: "high dpi fallback", width: 600, dpi: 144, wantX: 24, wantW: 552},
		{name: "tiny", width: 20, dpi: 96, wantX: 10, wantW: 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			x, width := settingsContentGeometry(tc.width, int(tc.dpi))
			if x != tc.wantX || width != tc.wantW {
				t.Fatalf("geometry = x:%d width:%d, want x:%d width:%d", x, width, tc.wantX, tc.wantW)
			}
			if x < 0 || width < 0 || x+width > tc.width {
				t.Fatalf("geometry escapes page: x:%d width:%d page:%d", x, width, tc.width)
			}
		})
	}
}

func TestSettingsHeadingUsesOnePixelOpticalInset(t *testing.T) {
	for _, x := range []int32{0, 16, 220, 809} {
		if got := settingsHeadingTextX(x); got != x+1 {
			t.Fatalf("heading x = %d, want %d", got, x+1)
		}
	}
}

func TestHistoryItemTextBandsStayInsideItemAtHighDPI(t *testing.T) {
	for _, dpi := range []int{96, 120, 144, 168, 192, 240} {
		itemHeight := scale(56, dpi)
		title, subtitle := historyItemTextRects(scale(14, dpi), scale(240, dpi), itemHeight, dpi)
		if title.Top < 0 || title.Bottom > itemHeight || title.Bottom <= title.Top {
			t.Fatalf("dpi %d invalid title band: %+v, item height %d", dpi, title, itemHeight)
		}
		if subtitle.Top < 0 || subtitle.Bottom > itemHeight || subtitle.Bottom <= subtitle.Top {
			t.Fatalf("dpi %d invalid subtitle band: %+v, item height %d", dpi, subtitle, itemHeight)
		}
		if subtitle.Bottom-subtitle.Top < scale(16, dpi) {
			t.Fatalf("dpi %d subtitle band too short: %+v", dpi, subtitle)
		}
		gap := subtitle.Top - title.Bottom
		if gap < scale(2, dpi) || gap > scale(4, dpi) {
			t.Fatalf("dpi %d text-band gap = %d, want about 3 DIP: title=%+v subtitle=%+v", dpi, gap, title, subtitle)
		}
	}
}

func TestLocalizedUIFontFacesKeepLatinAndCJKInOneFamily(t *testing.T) {
	tests := []struct {
		code  string
		major uint32
		want  string
	}{
		{"zh-CN", 10, "Microsoft YaHei UI"},
		{"zh-CN", 6, "Microsoft YaHei"},
		{"zh-TW", 10, "Microsoft JhengHei UI"},
		{"zh-TW", 6, "Microsoft JhengHei"},
		{"ja", 10, "Yu Gothic UI"},
		{"ja", 6, "Meiryo UI"},
		{"ko", 10, "Malgun Gothic"},
		{"en", 10, "Segoe UI"},
		{"de", 6, "Segoe UI"},
	}
	for _, tt := range tests {
		if got := uiFontFaceForLocaleVersion(tt.code, tt.major); got != tt.want {
			t.Fatalf("face for %s on Windows %d = %q, want %q", tt.code, tt.major, got, tt.want)
		}
	}
}
