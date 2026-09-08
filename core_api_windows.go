//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

// The JSON boundary is intentionally versioned.  Both Windows front ends use
// this contract, while all probing, health calculation, privacy and history
// behaviour remain in the Go 1.20-compatible engine.
type coreEnvelope struct {
	Schema      int               `json:"schema"`
	Version     string            `json:"version"`
	GeneratedAt time.Time         `json:"generatedAt"`
	Computer    string            `json:"computer"`
	Locale      string            `json:"locale"`
	HistoryDir  string            `json:"historyDir"`
	Settings    coreSettings      `json:"settings"`
	Disks       []coreDisk        `json:"disks"`
	Batteries   []coreBattery     `json:"batteries"`
	History     []coreHistoryItem `json:"history,omitempty"`
	Report      string            `json:"report"`
	Error       string            `json:"error,omitempty"`
}

type coreSettings struct {
	Language    string `json:"language"`
	FontSize    int    `json:"fontSize"`
	HistoryMode string `json:"historyMode"`
	HideSerial  bool   `json:"hideSerial"`
}

type coreSettingsPatch struct {
	Language    *string `json:"language"`
	FontSize    *int    `json:"fontSize"`
	HistoryMode *string `json:"historyMode"`
	HistoryDir  *string `json:"historyDir"`
	HideSerial  *bool   `json:"hideSerial"`
}

type coreDeleteRequest struct {
	IDs            []string `json:"ids"`
	DeleteExternal bool     `json:"deleteExternal"`
}

type coreDisk struct {
	Number          int      `json:"number"`
	Model           string   `json:"model"`
	Device          string   `json:"device"`
	Serial          string   `json:"serial"`
	Firmware        string   `json:"firmware"`
	Interface       string   `json:"interface"`
	Capacity        string   `json:"capacity"`
	HealthPercent   *float64 `json:"healthPercent"`
	Status          string   `json:"status"`
	StatusGood      bool     `json:"statusGood"`
	Temperature     string   `json:"temperature"`
	PowerOnTime     string   `json:"powerOnTime"`
	PowerCycles     string   `json:"powerCycles"`
	TotalRead       string   `json:"totalRead"`
	TotalWritten    string   `json:"totalWritten"`
	UnsafeShutdowns string   `json:"unsafeShutdowns"`
	ErrorLogEntries string   `json:"errorLogEntries"`
}

type coreBattery struct {
	Name           string   `json:"name"`
	Manufacturer   string   `json:"manufacturer"`
	Serial         string   `json:"serial"`
	Chemistry      string   `json:"chemistry"`
	DesignCapacity string   `json:"designCapacity"`
	FullCapacity   string   `json:"fullCapacity"`
	CycleCount     string   `json:"cycleCount"`
	HealthPercent  *float64 `json:"healthPercent"`
	Status         string   `json:"status"`
	StatusGood     bool     `json:"statusGood"`
}

type coreHistoryItem struct {
	ID          string    `json:"id"`
	GeneratedAt time.Time `json:"generatedAt"`
	Computer    string    `json:"computer"`
	Source      string    `json:"source"`
	Report      string    `json:"report"`
}

func coreMaskedSerial(serial string, hide bool) string {
	if hide && strings.TrimSpace(serial) != "" {
		return "********"
	}
	return strings.TrimSpace(serial)
}

func makeCoreEnvelope(result scanResult, includeHistory bool) coreEnvelope {
	s := currentSettings()
	code := effectiveLocale()
	out := coreEnvelope{
		Schema: 1, Version: appVersion, GeneratedAt: result.GeneratedAt,
		Computer: result.Computer, Locale: code, HistoryDir: historyDirectory(),
		Settings: coreSettings{Language: s.Language, FontSize: s.FontSize, HistoryMode: s.HistoryMode, HideSerial: s.HideSerial},
		Report:   renderReportWithOptions(result, code, s.HideSerial),
	}
	for _, d := range result.Disks {
		percent, known := diskHealthPercent(d)
		status, good := diskStatusText(d, known)
		read, written := diskReadWrite(d)
		var hp *float64
		if known {
			v := percent
			hp = &v
		}
		capacity := tr(code, "notReported")
		if d.Capacity > 0 {
			capacity = formatCapacityBytes(d.Capacity)
		}
		out.Disks = append(out.Disks, coreDisk{
			Number: d.Number, Model: strings.TrimSpace(d.Model), Device: fmt.Sprintf("PhysicalDrive%d", d.Number),
			Serial: coreMaskedSerial(d.Serial, s.HideSerial), Firmware: strings.TrimSpace(d.Firmware),
			Interface: strings.TrimSpace(d.Bus), Capacity: capacity, HealthPercent: hp, Status: status, StatusGood: good,
			Temperature: diskTemperature(d), PowerOnTime: diskPowerHours(d), PowerCycles: diskPowerCycles(d),
			TotalRead: read, TotalWritten: written, UnsafeShutdowns: diskUnsafeShutdowns(d), ErrorLogEntries: diskErrorLogEntries(d),
		})
	}
	for _, b := range result.Batteries {
		var hp *float64
		status, good := shellText(code, "unknown"), false
		if b.HealthPercent > 0 {
			v := b.HealthPercent
			hp = &v
			good = v >= 60
			if good {
				status = shellText(code, "healthy")
			} else {
				status = tr(code, "warning")
			}
		}
		design, full := tr(code, "notReported"), tr(code, "notReported")
		if b.DesignCapacityMWh > 0 {
			design = formatBatteryCapacityWithVoltage(b.DesignCapacityMWh, b.DesignVoltageMillivolts)
		}
		if b.FullChargeMWh > 0 {
			full = formatBatteryCapacityWithVoltage(b.FullChargeMWh, b.DesignVoltageMillivolts)
		}
		out.Batteries = append(out.Batteries, coreBattery{
			Name: b.Name, Manufacturer: b.Manufacturer, Serial: coreMaskedSerial(b.SerialNumber, s.HideSerial),
			Chemistry: b.Chemistry, DesignCapacity: design, FullCapacity: full, CycleCount: b.CycleCount,
			HealthPercent: hp, Status: status, StatusGood: good,
		})
	}
	if includeHistory {
		if records, err := loadHistoryRecords(); err == nil {
			for _, rec := range records {
				out.History = append(out.History, coreHistoryItem{ID: rec.ID, GeneratedAt: rec.GeneratedAt, Computer: rec.Computer, Source: rec.Source, Report: rec.Report})
			}
		}
	}
	return out
}

func runCoreCommand() bool {
	if len(os.Args) < 2 || !strings.HasPrefix(os.Args[1], "--core-") {
		return false
	}
	loadSettings()
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	switch os.Args[1] {
	case "--core-scan-json":
		result := scanHardware()
		if currentSettings().HistoryMode == historyOnRefresh {
			code := effectiveLocale()
			rec := historyRecord{Version: appVersion, GeneratedAt: result.GeneratedAt, Computer: result.Computer, Locale: code, Source: historyOnRefresh, Report: renderReportWithOptions(result, code, currentSettings().HideSerial)}
			_ = saveHistoryRecord(&rec)
		}
		_ = enc.Encode(makeCoreEnvelope(result, true))
	case "--core-state-json":
		_ = enc.Encode(makeCoreEnvelope(scanResult{GeneratedAt: time.Now(), Computer: os.Getenv("COMPUTERNAME")}, true))
	case "--core-update-settings-json":
		var patch coreSettingsPatch
		if err := json.NewDecoder(os.Stdin).Decode(&patch); err != nil {
			_ = enc.Encode(coreEnvelope{Schema: 1, Version: appVersion, Error: err.Error()})
			break
		}
		updateSettings(func(s *appSettings) {
			if patch.Language != nil {
				_, supportedLanguage := locales[*patch.Language]
				if *patch.Language == languageSystem || supportedLanguage {
					s.Language = *patch.Language
				}
			}
			if patch.FontSize != nil && *patch.FontSize >= 8 && *patch.FontSize <= 24 {
				s.FontSize = *patch.FontSize
			}
			if patch.HistoryMode != nil {
				if *patch.HistoryMode == historyOnExport {
					s.HistoryMode = historyOnExport
				} else {
					s.HistoryMode = historyOnRefresh
				}
			}
			if patch.HistoryDir != nil && strings.TrimSpace(*patch.HistoryDir) != "" {
				s.HistoryDir = strings.TrimSpace(*patch.HistoryDir)
			}
			if patch.HideSerial != nil {
				s.HideSerial = *patch.HideSerial
			}
		})
		_ = enc.Encode(makeCoreEnvelope(scanResult{GeneratedAt: time.Now(), Computer: os.Getenv("COMPUTERNAME")}, true))
	case "--core-delete-history-json":
		var req coreDeleteRequest
		if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
			_ = enc.Encode(coreEnvelope{Schema: 1, Version: appVersion, Error: err.Error()})
			break
		}
		records, _ := loadHistoryRecords()
		wanted := make(map[string]bool, len(req.IDs))
		for _, id := range req.IDs {
			wanted[id] = true
		}
		for _, rec := range records {
			if wanted[rec.ID] {
				_ = deleteHistoryRecord(rec, req.DeleteExternal)
			}
		}
		_ = enc.Encode(makeCoreEnvelope(scanResult{GeneratedAt: time.Now(), Computer: os.Getenv("COMPUTERNAME")}, true))
	default:
		_ = enc.Encode(coreEnvelope{Schema: 1, Version: appVersion, Error: "unknown core command"})
	}
	return true
}
