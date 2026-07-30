package main

import (
	"fmt"
	"strconv"
	"strings"
)

func valueOrUnknownLocalized(code, s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return tr(code, "notReported")
	}
	return s
}

func formatBatteryCapacity(mwh int64) string {
	if mwh <= 0 {
		return ""
	}
	return fmt.Sprintf("%d mWh / %.3f Wh", mwh, float64(mwh)/1000.0)
}

func hoursWithDaysLocalized(code, s string) string {
	hours, err := strconv.ParseUint(strings.TrimSpace(s), 10, 64)
	if err != nil {
		return s
	}
	return trf(code, "hoursDays", s, float64(hours)/24.0)
}

func localizedHealthStatus(code, raw string) string {
	s := strings.ToLower(strings.TrimSpace(raw))
	switch s {
	case "healthy", "good", "ok", "良好":
		return tr(code, "good")
	case "warning", "unhealthy", "caution", "警告":
		return tr(code, "warning")
	case "":
		return tr(code, "notReported")
	default:
		return raw
	}
}

func renderReport(result scanResult, code string) string {
	return renderReportWithOptions(result, code, false)
}

func serialDisplayValue(code, raw string, hide bool) string {
	if hide && strings.TrimSpace(raw) != "" {
		return "********"
	}
	return valueOrUnknownLocalized(code, raw)
}

func renderReportWithOptions(result scanResult, code string, hideSerial bool) string {
	var b strings.Builder
	b.WriteString(tr(code, "reportTitle") + "\r\n")
	b.WriteString(tr(code, "generatedAt") + ": " + result.GeneratedAt.Format("2006-01-02 15:04:05") + "\r\n")
	b.WriteString(tr(code, "computerName") + ": " + valueOrUnknownLocalized(code, result.Computer) + "\r\n")

	b.WriteString("\r\n==================== " + tr(code, "diskSection") + " ====================\r\n")
	if len(result.Disks) == 0 {
		b.WriteString(tr(code, "noDisks") + "\r\n")
	}
	for _, d := range result.Disks {
		b.WriteString("\r\n[" + trf(code, "physicalDisk", d.Number) + "]\r\n")
		b.WriteString(tr(code, "model") + ": " + valueOrUnknownLocalized(code, d.Model) + "\r\n")
		if d.Capacity > 0 {
			b.WriteString(tr(code, "capacity") + ": " + formatCapacityBytes(d.Capacity) + "\r\n")
		} else {
			b.WriteString(tr(code, "capacity") + ": " + tr(code, "notReported") + "\r\n")
		}
		b.WriteString(tr(code, "bus") + ": " + valueOrUnknownLocalized(code, d.Bus) + "\r\n")
		b.WriteString(tr(code, "firmware") + ": " + valueOrUnknownLocalized(code, d.Firmware) + "\r\n")
		b.WriteString(tr(code, "serial") + ": " + serialDisplayValue(code, d.Serial, hideSerial) + "\r\n")

		if d.Health != nil {
			h := d.Health
			remaining := 100 - h.PercentageUsed
			if remaining < 0 {
				remaining = 0
			}
			healthText := tr(code, "good")
			if h.CriticalWarning != 0 || h.PercentageUsed >= 100 || h.MediaErrors != "0" {
				healthText = tr(code, "warning")
			}
			b.WriteString(tr(code, "healthStatus") + ": " + healthText + "\r\n")
			b.WriteString(trf(code, "remainingNvme", remaining, h.PercentageUsed) + "\r\n")
			b.WriteString(fmt.Sprintf("%s: %d ℃\r\n", tr(code, "temperature"), h.TemperatureC))
			b.WriteString(tr(code, "powerOnTime") + ": " + hoursWithDaysLocalized(code, h.PowerOnHours) + "\r\n")
			b.WriteString(tr(code, "powerCycles") + ": " + trf(code, "times", h.PowerCycles) + "\r\n")
			b.WriteString(tr(code, "totalWritten") + ": " + formatDecimalTB(h.DataWrittenTB) + "\r\n")
			b.WriteString(tr(code, "totalRead") + ": " + formatDecimalTB(h.DataReadTB) + "\r\n")
			b.WriteString(tr(code, "unsafeShutdowns") + ": " + trf(code, "times", h.UnsafeShutdowns) + "\r\n")
			b.WriteString(tr(code, "mediaErrors") + ": " + trf(code, "times", h.MediaErrors) + "\r\n")
			b.WriteString(tr(code, "errorLogEntries") + ": " + trf(code, "entries", h.ErrorLogEntries) + "\r\n")
			b.WriteString(trf(code, "availableSpare", h.AvailableSpare, h.SpareThreshold) + "\r\n")
		} else if d.Reliability != nil {
			r := d.Reliability
			b.WriteString(tr(code, "healthStatus") + ": " + localizedHealthStatus(code, r.HealthStatus) + " (" + tr(code, "reliabilitySuffix") + ")\r\n")
			if r.Wear != nil {
				remaining := 100 - int(*r.Wear)
				if remaining < 0 {
					remaining = 0
				}
				b.WriteString(trf(code, "remainingWindows", remaining, *r.Wear) + "\r\n")
			}
			if r.Temperature != nil {
				b.WriteString(fmt.Sprintf("%s: %d ℃\r\n", tr(code, "temperature"), *r.Temperature))
			}
			if r.PowerOnHours != nil {
				b.WriteString(tr(code, "powerOnTime") + ": " + trf(code, "hoursDays", fmt.Sprintf("%d", *r.PowerOnHours), float64(*r.PowerOnHours)/24.0) + "\r\n")
			}
			if r.ReadErrorsUncorrected != nil {
				b.WriteString(fmt.Sprintf("%s: %d\r\n", tr(code, "readUncorrected"), *r.ReadErrorsUncorrected))
			}
			if r.WriteErrorsUncorrected != nil {
				b.WriteString(fmt.Sprintf("%s: %d\r\n", tr(code, "writeUncorrected"), *r.WriteErrorsUncorrected))
			}
			b.WriteString(tr(code, "totalRwUnavailable") + "\r\n")
		} else {
			b.WriteString(tr(code, "smartUnavailable") + "\r\n")
		}
		for _, part := range d.ErrorParts {
			prefix := part.Kind
			switch part.Kind {
			case "nativeModelFailed":
				prefix = tr(code, "nativeModelFailed")
			case "nativeCapacityFailed":
				prefix = tr(code, "nativeCapacityFailed")
			case "nvmeNotPassed":
				prefix = tr(code, "nvmeNotPassed")
			}
			b.WriteString(tr(code, "note") + ": " + prefix + ": " + part.Detail + "\r\n")
		}
	}

	b.WriteString("\r\n==================== " + tr(code, "batterySection") + " ====================\r\n")
	if result.BatteryErr != "" {
		b.WriteString(trf(code, "batteryReadFailed", result.BatteryErr) + "\r\n")
	} else if len(result.Batteries) == 0 {
		b.WriteString(tr(code, "noBattery") + "\r\n")
	} else {
		for i, bat := range result.Batteries {
			b.WriteString("\r\n[" + trf(code, "battery", i+1) + "]\r\n")
			name := strings.TrimSpace(bat.Name)
			if name == "" {
				name = tr(code, "internalBattery")
			}
			b.WriteString(tr(code, "name") + ": " + name + "\r\n")
			b.WriteString(tr(code, "manufacturer") + ": " + valueOrUnknownLocalized(code, bat.Manufacturer) + "\r\n")
			b.WriteString(tr(code, "chemistry") + ": " + valueOrUnknownLocalized(code, bat.Chemistry) + "\r\n")
			if bat.DesignCapacityMWh > 0 {
				b.WriteString(tr(code, "designCapacity") + ": " + formatBatteryCapacity(bat.DesignCapacityMWh) + "\r\n")
			} else {
				b.WriteString(tr(code, "designCapacity") + ": " + tr(code, "notReported") + "\r\n")
			}
			if bat.FullChargeMWh > 0 {
				b.WriteString(tr(code, "fullChargeCapacity") + ": " + formatBatteryCapacity(bat.FullChargeMWh) + "\r\n")
			} else {
				b.WriteString(tr(code, "fullChargeCapacity") + ": " + tr(code, "notReported") + "\r\n")
			}
			if bat.HealthPercent > 0 {
				b.WriteString(fmt.Sprintf("%s: %.1f%%\r\n", tr(code, "batteryHealth"), bat.HealthPercent))
			} else {
				b.WriteString(tr(code, "batteryHealth") + ": " + tr(code, "unableCalculate") + "\r\n")
			}
			cycle := strings.TrimSpace(bat.CycleCount)
			if cycle == "" {
				cycle = tr(code, "deviceNotReported")
			}
			b.WriteString(tr(code, "cycleCount") + ": " + cycle + "\r\n")
			b.WriteString(tr(code, "serial") + ": " + serialDisplayValue(code, bat.SerialNumber, hideSerial) + "\r\n")
		}
	}

	b.WriteString("\r\n==================== " + tr(code, "explanationSection") + " ====================\r\n")
	if hideSerial {
		b.WriteString(tr(code, "explainSerialHidden") + "\r\n")
	} else {
		b.WriteString(tr(code, "explainSerial") + "\r\n")
	}
	b.WriteString(tr(code, "explainReadonly") + "\r\n")
	b.WriteString(tr(code, "explainUnits") + "\r\n")
	b.WriteString(tr(code, "explainPassthrough") + "\r\n")
	b.WriteString(tr(code, "explainHealth") + "\r\n")
	return b.String()
}

// maskSerialLines hides drive and battery serial numbers in reports that were
// created by older versions or in a different interface language. It only
// rewrites lines whose label exactly matches one of the supported localized
// serial-number labels, so unrelated values are left untouched.
func maskSerialLines(text string) string {
	labels := make(map[string]struct{}, len(locales))
	for _, def := range locales {
		label := strings.TrimSpace(def.Text["serial"])
		if label != "" {
			labels[label] = struct{}{}
		}
	}
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		separator := strings.IndexAny(trimmed, ":：")
		if separator <= 0 {
			continue
		}
		label := strings.TrimSpace(trimmed[:separator])
		if _, ok := labels[label]; !ok {
			continue
		}
		leading := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
		sepRune := trimmed[separator : separator+1]
		if trimmed[separator] >= 0x80 {
			sepRune = "："
		}
		lines[i] = leading + label + sepRune + " ********"
	}
	return strings.Join(lines, "\r\n")
}
