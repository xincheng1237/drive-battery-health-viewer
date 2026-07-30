package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	languageSystem   = "system"
	historyOnRefresh = "refresh"
	historyOnExport  = "export"
)

type appSettings struct {
	Language    string
	FontSize    int
	HistoryDir  string
	HistoryMode string
	HideSerial  bool
}

var (
	settingsMu sync.RWMutex
	settings   = appSettings{Language: languageSystem, FontSize: 9, HistoryMode: historyOnRefresh}
)

func appDataDirectory() string {
	base, err := os.UserConfigDir()
	if err != nil || strings.TrimSpace(base) == "" {
		base = os.Getenv("APPDATA")
	}
	if strings.TrimSpace(base) == "" {
		base = "."
	}
	return filepath.Join(base, "HardwareHealthViewer")
}

func defaultHistoryDirectory() string { return filepath.Join(appDataDirectory(), "History") }
func settingsPath() string            { return filepath.Join(appDataDirectory(), "settings.ini") }
func hiddenHistoryPath() string       { return filepath.Join(appDataDirectory(), "hidden_history.json") }

func currentSettings() appSettings {
	settingsMu.RLock()
	defer settingsMu.RUnlock()
	return settings
}

func updateSettings(fn func(*appSettings)) {
	settingsMu.Lock()
	fn(&settings)
	s := settings
	settingsMu.Unlock()
	_ = saveSettingsValue(s)
}

func loadSettings() {
	s := appSettings{Language: languageSystem, FontSize: 9, HistoryMode: historyOnRefresh}
	f, err := os.Open(settingsPath())
	if err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			line := strings.TrimSpace(sc.Text())
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			parts := strings.SplitN(line, "=", 2)
			if len(parts) != 2 {
				continue
			}
			key, value := strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
			switch key {
			case "language":
				if value == languageSystem {
					s.Language = value
				} else if _, ok := locales[value]; ok {
					s.Language = value
				}
			case "font":
				if n, e := strconv.Atoi(value); e == nil && n >= 8 && n <= 24 {
					s.FontSize = n
				}
			case "history_dir":
				s.HistoryDir = value
			case "history_mode":
				if value == historyOnExport {
					s.HistoryMode = value
				} else {
					s.HistoryMode = historyOnRefresh
				}
			case "hide_serial":
				s.HideSerial = value == "1" || strings.EqualFold(value, "true") || strings.EqualFold(value, "yes")
			}
		}
	}
	if strings.TrimSpace(s.HistoryDir) == "" {
		s.HistoryDir = defaultHistoryDirectory()
	}
	settingsMu.Lock()
	settings = s
	settingsMu.Unlock()
	_ = saveSettingsValue(s)
}

func saveSettingsValue(s appSettings) error {
	if err := os.MkdirAll(appDataDirectory(), 0755); err != nil {
		return err
	}
	hideSerial := 0
	if s.HideSerial {
		hideSerial = 1
	}
	text := fmt.Sprintf("version=%s\r\nlanguage=%s\r\nfont=%d\r\nhistory_mode=%s\r\nhistory_dir=%s\r\nhide_serial=%d\r\n", appVersion, s.Language, s.FontSize, s.HistoryMode, s.HistoryDir, hideSerial)
	return atomicWriteFile(settingsPath(), []byte(text), 0644)
}

func effectiveLocale() string {
	s := currentSettings()
	if s.Language == languageSystem || s.Language == "" {
		return detectLocale()
	}
	if _, ok := locales[s.Language]; ok {
		return s.Language
	}
	return detectLocale()
}

func historyDirectory() string {
	s := currentSettings()
	if strings.TrimSpace(s.HistoryDir) == "" {
		return defaultHistoryDirectory()
	}
	return s.HistoryDir
}

func atomicWriteFile(path string, data []byte, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".hhv-write-*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err = f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	_ = os.Chmod(tmp, perm)
	if err = os.Rename(tmp, path); err != nil {
		_ = os.Remove(path)
		err = os.Rename(tmp, path)
	}
	return err
}

type historyRecord struct {
	ID          string    `json:"id"`
	Version     string    `json:"version"`
	GeneratedAt time.Time `json:"generated_at"`
	Computer    string    `json:"computer"`
	Locale      string    `json:"locale"`
	Source      string    `json:"source"`
	Report      string    `json:"report"`
	ExportPath  string    `json:"export_path,omitempty"`
	MetaPath    string    `json:"-"`
	LegacyPath  string    `json:"-"`
}

func sanitizeFileName(s string) string {
	s = strings.TrimSpace(s)
	r := strings.NewReplacer("\\", "_", "/", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	return r.Replace(s)
}

func historyRecordName(t time.Time, computer string) string {
	c := sanitizeFileName(computer)
	if c == "" {
		c = "PC"
	}
	return fmt.Sprintf("HHV_%s_%s_%03d.hhv.json", c, t.Format("20060102_150405"), t.Nanosecond()/1e6)
}

func saveHistoryRecord(rec *historyRecord) error {
	if rec == nil {
		return errors.New("nil history record")
	}
	if rec.ID == "" {
		rec.ID = fmt.Sprintf("%d-%s", rec.GeneratedAt.UnixNano(), sanitizeFileName(rec.Computer))
	}
	if rec.Version == "" {
		rec.Version = appVersion
	}
	if rec.GeneratedAt.IsZero() {
		rec.GeneratedAt = time.Now()
	}
	dir := historyDirectory()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	if rec.MetaPath == "" {
		rec.MetaPath = filepath.Join(dir, historyRecordName(rec.GeneratedAt, rec.Computer))
	}
	data, err := json.MarshalIndent(rec, "", "  ")
	if err != nil {
		return err
	}
	return atomicWriteFile(rec.MetaPath, data, 0644)
}

func readHistoryRecord(path string) (historyRecord, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return historyRecord{}, err
	}
	var rec historyRecord
	if err := json.Unmarshal(data, &rec); err != nil {
		return historyRecord{}, err
	}
	rec.MetaPath = path
	return rec, nil
}

func loadHiddenHistory() map[string]bool {
	data, err := os.ReadFile(hiddenHistoryPath())
	if err != nil {
		return map[string]bool{}
	}
	var paths []string
	if json.Unmarshal(data, &paths) != nil {
		return map[string]bool{}
	}
	m := make(map[string]bool, len(paths))
	for _, p := range paths {
		m[strings.ToLower(filepath.Clean(p))] = true
	}
	return m
}

func saveHiddenHistory(m map[string]bool) error {
	paths := make([]string, 0, len(m))
	for p := range m {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	data, _ := json.MarshalIndent(paths, "", "  ")
	return atomicWriteFile(hiddenHistoryPath(), data, 0644)
}

func parseLegacyHistory(path string) (historyRecord, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return historyRecord{}, err
	}
	text := strings.TrimPrefix(string(data), "\uFEFF")
	info, _ := os.Stat(path)
	t := time.Now()
	if info != nil {
		t = info.ModTime()
	}
	// Best effort timestamp from old file names.
	base := filepath.Base(path)
	for _, layout := range []string{"20060102_150405", "2006-01-02_15-04-05"} {
		for i := 0; i+len(layout) <= len(base); i++ {
			if tt, e := time.ParseInLocation(layout, base[i:i+len(layout)], time.Local); e == nil {
				t = tt
				break
			}
		}
	}
	return historyRecord{ID: "legacy:" + strings.ToLower(filepath.Clean(path)), Version: "legacy", GeneratedAt: t, Computer: extractComputerFromReport(text), Locale: "", Source: "legacy", Report: text, LegacyPath: path, ExportPath: path}, nil
}

func extractComputerFromReport(text string) string {
	for _, line := range strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n") {
		l := strings.TrimSpace(line)
		for _, prefix := range []string{"电脑名:", "电脑名：", "Computer name:", "Computer:", "コンピューター名:", "컴퓨터 이름:"} {
			if strings.HasPrefix(l, prefix) {
				return strings.TrimSpace(strings.TrimPrefix(l, prefix))
			}
		}
	}
	return ""
}

func loadHistoryRecords() ([]historyRecord, error) {
	dir := historyDirectory()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	hidden := loadHiddenHistory()
	result := make([]historyRecord, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		low := strings.ToLower(entry.Name())
		var rec historyRecord
		var e error
		switch {
		case strings.HasSuffix(low, ".hhv.json"):
			rec, e = readHistoryRecord(path)
		case strings.HasSuffix(low, ".txt"):
			if hidden[strings.ToLower(filepath.Clean(path))] {
				continue
			}
			rec, e = parseLegacyHistory(path)
		default:
			continue
		}
		if e == nil && strings.TrimSpace(rec.Report) != "" {
			result = append(result, rec)
		}
	}
	sort.SliceStable(result, func(i, j int) bool { return result[i].GeneratedAt.After(result[j].GeneratedAt) })
	return result, nil
}

// linkedExternalReport returns the separate user-facing report file associated
// with a history record. The internal .hhv.json metadata file is intentionally
// excluded because it is always removed when the history item itself is deleted.
func linkedExternalReport(rec historyRecord) (string, bool) {
	path := strings.TrimSpace(rec.ExportPath)
	if path == "" {
		path = strings.TrimSpace(rec.LegacyPath)
	}
	if path == "" {
		return "", false
	}
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return path, false
	}
	return path, true
}

func deleteHistoryRecord(rec historyRecord, deleteExternal bool) error {
	var errs []string
	if rec.MetaPath != "" {
		if err := os.Remove(rec.MetaPath); err != nil && !os.IsNotExist(err) {
			errs = append(errs, err.Error())
		}
	}
	if rec.LegacyPath != "" {
		if deleteExternal {
			if err := os.Remove(rec.LegacyPath); err != nil && !os.IsNotExist(err) {
				errs = append(errs, err.Error())
			}
		} else {
			hidden := loadHiddenHistory()
			hidden[strings.ToLower(filepath.Clean(rec.LegacyPath))] = true
			if err := saveHiddenHistory(hidden); err != nil {
				errs = append(errs, err.Error())
			}
		}
	} else if deleteExternal && strings.TrimSpace(rec.ExportPath) != "" {
		if err := os.Remove(rec.ExportPath); err != nil && !os.IsNotExist(err) {
			errs = append(errs, err.Error())
		}
	}
	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
}

func writeUTF8BOM(path, text string) error {
	return atomicWriteFile(path, append([]byte{0xEF, 0xBB, 0xBF}, []byte(text)...), 0644)
}
