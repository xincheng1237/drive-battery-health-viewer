//go:build windows

package main

import "testing"

func TestCompareVersions(t *testing.T) {
	tests := []struct {
		left, right string
		want        int
	}{
		{"1.0.6-beta", "v1.0.6", 0},
		{"1.0.5", "1.0.6", -1},
		{"1.10", "1.9.9", 1},
		{"1.0.0", "1", 0},
	}
	for _, test := range tests {
		got, ok := compareVersions(test.left, test.right)
		if !ok || got != test.want {
			t.Fatalf("compareVersions(%q, %q)=(%d,%v), want (%d,true)", test.left, test.right, got, ok, test.want)
		}
	}
}

func TestWindowsInstallerURL(t *testing.T) {
	assets := []releaseAsset{
		{Name: "DriveBatteryHealthViewer_v1.0.7_macOS_Universal.dmg", BrowserDownloadURL: "https://example.invalid/mac"},
		{Name: "DriveBatteryHealthViewer_v1.0.7_Windows_x64_Setup.exe", BrowserDownloadURL: "https://example.invalid/setup"},
	}
	if got := windowsInstallerURL(assets); got != "https://example.invalid/setup" {
		t.Fatalf("windowsInstallerURL=%q", got)
	}
}
