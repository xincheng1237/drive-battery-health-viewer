package main

import (
	"os"
	"strings"
	"testing"
)

func TestInstallerUsesSevenLanguagesAndApplicationIcon(t *testing.T) {
	data, err := os.ReadFile("installer.iss")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, language := range []string{"ChineseSimplified.isl", "Default.isl", "Russian.isl", "French.isl", "German.isl", "Korean.isl", "Japanese.isl"} {
		if !strings.Contains(script, language) {
			t.Errorf("installer language missing: %s", language)
		}
	}
	for _, iconRule := range []string{
		`Source: "app.ico"; DestDir: "{app}"`,
		`IconFilename: "{app}\app.ico"`,
		`UninstallDisplayIcon={app}\app.ico`,
	} {
		if !strings.Contains(script, iconRule) {
			t.Errorf("installer icon rule missing: %s", iconRule)
		}
	}
	if strings.Contains(script, "LicenseFile=") {
		t.Error("installer should not show a license agreement page")
	}
	for _, fastFlowRule := range []string{
		"DisableWelcomePage=yes",
		"DisableDirPage=no",
		"DisableReadyPage=yes",
		"ShowLanguageDialog=auto",
		"CurPageID = wpSelectDir",
		"SetupMessage(msgButtonInstall)",
	} {
		if !strings.Contains(script, fastFlowRule) {
			t.Errorf("streamlined installer rule missing: %s", fastFlowRule)
		}
	}
	if strings.Contains(script, "[Tasks]") {
		t.Error("installer should not show a separate tasks page")
	}
}

func TestInstallerShipsOneEntryAndTwoSystemSelectedInterfaces(t *testing.T) {
	data, err := os.ReadFile("installer.iss")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, rule := range []string{
		`Source: "dist\{#MyAppExeName}"; DestDir: "{app}"`,
		`Source: "dist\DriveBatteryHealthViewer.Legacy.exe"; DestDir: "{app}"`,
		`Source: "dist\modern\*"; DestDir: "{app}\modern"`,
		`Check: IsModernWindows`,
		`Filename: "{app}\{#MyAppExeName}"`,
		`MinVersion=6.1`,
		`GetWindowsVersionEx(Version)` ,
		`Version.Build >= 17763`,
	} {
		if !strings.Contains(script, rule) {
			t.Errorf("dual-interface installer rule missing: %s", rule)
		}
	}
}
