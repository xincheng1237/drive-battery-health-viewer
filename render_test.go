package main

import (
	"strings"
	"testing"
	"time"
)

func TestBatteryCapacityIncludesWh(t *testing.T) {
	got := formatBatteryCapacity(92041)
	if got != "92041 mWh / 92.041 Wh" {
		t.Fatalf("unexpected capacity: %q", got)
	}
}

func TestAllLocalesHaveEnglishKeys(t *testing.T) {
	base := locales["en"].Text
	for _, code := range localeOrder {
		l := locales[code]
		for key := range base {
			if _, ok := l.Text[key]; !ok {
				t.Errorf("locale %s is missing key %s", code, key)
			}
		}
	}
}

func TestRenderReportOrderAndNoInlineChangelog(t *testing.T) {
	r := scanResult{
		GeneratedAt: time.Date(2026, 7, 28, 18, 0, 0, 0, time.Local),
		Computer:    "TEST-PC",
		Batteries:   []BatteryInfo{{Name: "BAT", DesignCapacityMWh: 92041, FullChargeMWh: 90000, CycleCount: "23", HealthPercent: 97.78}},
	}
	got := renderReport(r, "zh-CN")
	serial := strings.Index(got, "报告包含硬盘和电池序列号")
	readonly := strings.Index(got, "本程序只读取信息")
	if serial < 0 || readonly < 0 || serial > readonly {
		t.Fatalf("serial warning must be first: %s", got)
	}
	if strings.Contains(got, "v0.1") || strings.Contains(got, "修复并完善硬盘") {
		t.Fatalf("full changelog should not be in report")
	}
	if !strings.Contains(got, "92041 mWh / 92.041 Wh") {
		t.Fatalf("Wh display missing: %s", got)
	}
}

func TestRenderAllLocalesNoFormattingErrors(t *testing.T) {
	r := scanResult{
		GeneratedAt: time.Date(2026, 7, 28, 18, 0, 0, 0, time.Local),
		Computer:    "TEST-PC",
		Disks: []diskDescriptor{{
			Number: 0, Model: "TEST NVME", Serial: "SERIAL", Firmware: "1.0", Bus: "NVMe", Capacity: 1_000_000_000_000,
			Health: &NVMeHealth{TemperatureC: 40, AvailableSpare: 100, SpareThreshold: 10, PercentageUsed: 1, DataWrittenTB: 12.3, DataReadTB: 15.4, PowerCycles: "50", PowerOnHours: "1000", UnsafeShutdowns: "2", MediaErrors: "0", ErrorLogEntries: "0"},
		}},
		Batteries: []BatteryInfo{{Name: "BAT", Manufacturer: "OEM", Chemistry: "LION", DesignCapacityMWh: 92041, FullChargeMWh: 90000, CycleCount: "23", HealthPercent: 97.78, SerialNumber: "BAT-SERIAL"}},
	}
	for _, code := range localeOrder {
		got := renderReport(r, code)
		if strings.Contains(got, "%!") {
			t.Fatalf("locale %s has formatting error: %s", code, got)
		}
		if !strings.Contains(got, "92.041 Wh") {
			t.Fatalf("locale %s lacks Wh capacity: %s", code, got)
		}
	}
}

func TestSerialMaskingCoversStructuredAndLegacyReports(t *testing.T) {
	r := scanResult{
		GeneratedAt: time.Date(2026, 7, 29, 18, 0, 0, 0, time.Local),
		Computer:    "TEST-PC",
		Disks:       []diskDescriptor{{Number: 0, Model: "SSD", Serial: "DRIVE-SECRET"}},
		Batteries:   []BatteryInfo{{Name: "BAT", SerialNumber: "BATTERY-SECRET"}},
	}
	masked := renderReportWithOptions(r, "zh-CN", true)
	if strings.Contains(masked, "DRIVE-SECRET") || strings.Contains(masked, "BATTERY-SECRET") {
		t.Fatalf("structured serial leaked: %s", masked)
	}
	if strings.Count(masked, "********") < 2 || !strings.Contains(masked, "当前已隐藏") {
		t.Fatalf("masked indicators missing: %s", masked)
	}
	legacy := "序列号： ABC123\r\nSerial number: XYZ987\r\nModel: keep"
	got := maskSerialLines(legacy)
	if strings.Contains(got, "ABC123") || strings.Contains(got, "XYZ987") || !strings.Contains(got, "Model: keep") {
		t.Fatalf("legacy masking failed: %q", got)
	}
}
