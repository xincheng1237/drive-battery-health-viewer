package main

import (
	"bytes"
	"encoding/binary"
	"encoding/xml"
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"strings"
	"unicode/utf16"
)

type NVMeHealth struct {
	CriticalWarning    byte
	TemperatureC       int
	AvailableSpare     int
	SpareThreshold     int
	PercentageUsed     int
	DataReadTB         float64
	DataWrittenTB      float64
	HostReadCommands   string
	HostWriteCommands  string
	ControllerBusyMins string
	PowerCycles        string
	PowerOnHours       string
	UnsafeShutdowns    string
	MediaErrors        string
	ErrorLogEntries    string
}

func readLE128(b []byte) (*big.Int, error) {
	if len(b) < 16 {
		return nil, errors.New("uint128 data is shorter than 16 bytes")
	}
	reversed := make([]byte, 16)
	for i := 0; i < 16; i++ {
		reversed[15-i] = b[i]
	}
	return new(big.Int).SetBytes(reversed), nil
}

func readLE128String(b []byte) (string, error) {
	n, err := readLE128(b)
	if err != nil {
		return "", err
	}
	return n.String(), nil
}

func readLE128Float64(b []byte) (float64, error) {
	n, err := readLE128(b)
	if err != nil {
		return 0, err
	}
	f, _ := new(big.Float).SetInt(n).Float64()
	return f, nil
}

func parseNVMeHealth(log []byte) (NVMeHealth, error) {
	if len(log) < 512 {
		return NVMeHealth{}, fmt.Errorf("NVMe SMART log length is %d, expected at least 512", len(log))
	}

	dataReadUnits, err := readLE128Float64(log[32:48])
	if err != nil {
		return NVMeHealth{}, err
	}
	dataWrittenUnits, err := readLE128Float64(log[48:64])
	if err != nil {
		return NVMeHealth{}, err
	}

	values := make([]string, 7)
	offsets := []int{64, 80, 96, 112, 128, 144, 160}
	for i, off := range offsets {
		values[i], err = readLE128String(log[off : off+16])
		if err != nil {
			return NVMeHealth{}, err
		}
	}
	errorLog, err := readLE128String(log[176:192])
	if err != nil {
		return NVMeHealth{}, err
	}

	kelvin := int(binary.LittleEndian.Uint16(log[1:3]))
	tempC := 0
	if kelvin > 0 {
		tempC = kelvin - 273
	}

	return NVMeHealth{
		CriticalWarning:    log[0],
		TemperatureC:       tempC,
		AvailableSpare:     int(log[3]),
		SpareThreshold:     int(log[4]),
		PercentageUsed:     int(log[5]),
		DataReadTB:         dataReadUnits * 512000.0 / 1_000_000_000_000.0,
		DataWrittenTB:      dataWrittenUnits * 512000.0 / 1_000_000_000_000.0,
		HostReadCommands:   values[0],
		HostWriteCommands:  values[1],
		ControllerBusyMins: values[2],
		PowerCycles:        values[3],
		PowerOnHours:       values[4],
		UnsafeShutdowns:    values[5],
		MediaErrors:        values[6],
		ErrorLogEntries:    errorLog,
	}, nil
}

type BatteryInfo struct {
	Name              string
	Manufacturer      string
	SerialNumber      string
	Chemistry         string
	DesignCapacityMWh int64
	FullChargeMWh     int64
	CycleCount        string
	HealthPercent     float64
}

type batteryReportXML struct {
	Batteries struct {
		Battery []struct {
			ID                 string `xml:"Id"`
			Manufacturer       string `xml:"Manufacturer"`
			SerialNumber       string `xml:"SerialNumber"`
			Chemistry          string `xml:"Chemistry"`
			DesignCapacity     string `xml:"DesignCapacity"`
			FullChargeCapacity string `xml:"FullChargeCapacity"`
			CycleCount         string `xml:"CycleCount"`
		} `xml:"Battery"`
	} `xml:"Batteries"`
}

func decodePossiblyUTF16(data []byte) ([]byte, error) {
	if len(data) >= 2 && data[0] == 0xFF && data[1] == 0xFE {
		u16 := make([]uint16, 0, (len(data)-2)/2)
		for i := 2; i+1 < len(data); i += 2 {
			u16 = append(u16, binary.LittleEndian.Uint16(data[i:i+2]))
		}
		decoded := []byte(string(utf16.Decode(u16)))
		decoded = bytes.Replace(decoded, []byte(`encoding="utf-16"`), []byte(`encoding="utf-8"`), 1)
		decoded = bytes.Replace(decoded, []byte(`encoding="UTF-16"`), []byte(`encoding="utf-8"`), 1)
		return decoded, nil
	}
	if len(data) >= 2 && data[0] == 0xFE && data[1] == 0xFF {
		u16 := make([]uint16, 0, (len(data)-2)/2)
		for i := 2; i+1 < len(data); i += 2 {
			u16 = append(u16, binary.BigEndian.Uint16(data[i:i+2]))
		}
		decoded := []byte(string(utf16.Decode(u16)))
		decoded = bytes.Replace(decoded, []byte(`encoding="utf-16"`), []byte(`encoding="utf-8"`), 1)
		decoded = bytes.Replace(decoded, []byte(`encoding="UTF-16"`), []byte(`encoding="utf-8"`), 1)
		return decoded, nil
	}
	return bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF}), nil
}

func digitsOnlyInt64(s string) int64 {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return 0
	}
	n, _ := strconv.ParseInt(b.String(), 10, 64)
	return n
}

func parseBatteryReportXML(data []byte) ([]BatteryInfo, error) {
	normalized, err := decodePossiblyUTF16(data)
	if err != nil {
		return nil, err
	}
	var report batteryReportXML
	if err := xml.Unmarshal(normalized, &report); err != nil {
		return nil, err
	}
	result := make([]BatteryInfo, 0, len(report.Batteries.Battery))
	for _, b := range report.Batteries.Battery {
		design := digitsOnlyInt64(b.DesignCapacity)
		full := digitsOnlyInt64(b.FullChargeCapacity)
		health := 0.0
		if design > 0 && full > 0 {
			health = float64(full) * 100.0 / float64(design)
		}
		cycle := strings.TrimSpace(b.CycleCount)
		name := strings.TrimSpace(b.ID)
		result = append(result, BatteryInfo{
			Name:              name,
			Manufacturer:      strings.TrimSpace(b.Manufacturer),
			SerialNumber:      strings.TrimSpace(b.SerialNumber),
			Chemistry:         strings.TrimSpace(b.Chemistry),
			DesignCapacityMWh: design,
			FullChargeMWh:     full,
			CycleCount:        cycle,
			HealthPercent:     health,
		})
	}
	if len(result) == 0 {
		return nil, errors.New("battery report contains no battery entries")
	}
	return result, nil
}

func formatDecimalTB(v float64) string {
	if v < 1 {
		return fmt.Sprintf("%.3f TB", v)
	}
	return fmt.Sprintf("%.2f TB", v)
}

func formatCapacityBytes(v uint64) string {
	const gib = 1024 * 1024 * 1024
	const tib = gib * 1024
	if v >= tib {
		return fmt.Sprintf("%.2f TB", float64(v)/float64(tib))
	}
	return fmt.Sprintf("%.1f GB", float64(v)/float64(gib))
}
