package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestHistorySortAndDelete(t *testing.T) {
	old := currentSettings()
	dir := t.TempDir()
	settingsMu.Lock()
	settings.HistoryDir = dir
	settingsMu.Unlock()
	defer func() { settingsMu.Lock(); settings = old; settingsMu.Unlock() }()
	a := historyRecord{GeneratedAt: time.Date(2026, 1, 1, 1, 0, 0, 0, time.Local), Computer: "A", Report: "a"}
	b := historyRecord{GeneratedAt: time.Date(2026, 1, 2, 1, 0, 0, 0, time.Local), Computer: "B", Report: "b"}
	if err := saveHistoryRecord(&a); err != nil {
		t.Fatal(err)
	}
	if err := saveHistoryRecord(&b); err != nil {
		t.Fatal(err)
	}
	rows, err := loadHistoryRecords()
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 || rows[0].Computer != "B" {
		t.Fatalf("bad sort: %#v", rows)
	}
	ext := filepath.Join(dir, "external.txt")
	os.WriteFile(ext, []byte("x"), 0644)
	rows[0].ExportPath = ext
	if err := deleteHistoryRecord(rows[0], false); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(ext); err != nil {
		t.Fatal("external should remain")
	}
}

func TestFirstInstallDefaults(t *testing.T) {
	s := appSettings{Language: languageSystem, FontSize: 9, HistoryMode: historyOnRefresh}
	if s.Language != "system" || s.FontSize != 9 || s.HistoryMode != "refresh" || s.HideSerial {
		t.Fatal(s)
	}
}

func TestLinkedExternalReportAvailability(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "export.txt")
	rec := historyRecord{ExportPath: path}
	if _, ok := linkedExternalReport(rec); ok {
		t.Fatal("missing export reported as available")
	}
	if err := os.WriteFile(path, []byte("report"), 0644); err != nil {
		t.Fatal(err)
	}
	got, ok := linkedExternalReport(rec)
	if !ok || got != path {
		t.Fatalf("got %q, %v", got, ok)
	}
	if _, ok := linkedExternalReport(historyRecord{}); ok {
		t.Fatal("record without export reported as available")
	}
}
