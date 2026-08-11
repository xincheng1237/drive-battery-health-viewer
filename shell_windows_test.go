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
