package main

import (
	"encoding/binary"
	"math"
	"testing"
	"unicode/utf16"
)

func putLE128Low64(dst []byte, v uint64) {
	binary.LittleEndian.PutUint64(dst[:8], v)
	for i := 8; i < 16; i++ {
		dst[i] = 0
	}
}

func TestParseNVMeHealth(t *testing.T) {
	log := make([]byte, 512)
	binary.LittleEndian.PutUint16(log[1:3], 300)
	log[3] = 100
	log[4] = 10
	log[5] = 4
	putLE128Low64(log[32:48], 1_000_000)
	putLE128Low64(log[48:64], 2_000_000)
	putLE128Low64(log[112:128], 321)
	putLE128Low64(log[128:144], 1234)
	putLE128Low64(log[144:160], 7)
	putLE128Low64(log[160:176], 0)

	h, err := parseNVMeHealth(log)
	if err != nil {
		t.Fatal(err)
	}
	if h.TemperatureC != 27 || h.PercentageUsed != 4 || h.PowerOnHours != "1234" {
		t.Fatalf("unexpected parsed values: %+v", h)
	}
	if math.Abs(h.DataWrittenTB-1.024) > 0.000001 {
		t.Fatalf("unexpected written TB: %f", h.DataWrittenTB)
	}
}

func TestParseBatteryReportUTF8(t *testing.T) {
	data := []byte(`<?xml version="1.0" encoding="utf-8"?>
<BatteryReport><Batteries><Battery><Id>TESTBAT</Id><Manufacturer>OEM</Manufacturer><SerialNumber>123</SerialNumber><Chemistry>LION</Chemistry><DesignCapacity>80000</DesignCapacity><FullChargeCapacity>76000</FullChargeCapacity><CycleCount>42</CycleCount></Battery></Batteries></BatteryReport>`)
	got, err := parseBatteryReportXML(data)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].DesignCapacityMWh != 80000 || got[0].CycleCount != "42" {
		t.Fatalf("unexpected battery parse: %+v", got)
	}
	if math.Abs(got[0].HealthPercent-95.0) > 0.0001 {
		t.Fatalf("unexpected health: %f", got[0].HealthPercent)
	}
}

func TestParseBatteryReportUTF16LE(t *testing.T) {
	s := `<?xml version="1.0" encoding="utf-16"?><BatteryReport><Batteries><Battery><Id>BAT</Id><DesignCapacity>60,000</DesignCapacity><FullChargeCapacity>54,000</FullChargeCapacity></Battery></Batteries></BatteryReport>`
	words := utf16.Encode([]rune(s))
	data := []byte{0xFF, 0xFE}
	for _, w := range words {
		var b [2]byte
		binary.LittleEndian.PutUint16(b[:], w)
		data = append(data, b[:]...)
	}
	got, err := parseBatteryReportXML(data)
	if err != nil {
		t.Fatal(err)
	}
	if got[0].DesignCapacityMWh != 60000 || got[0].FullChargeMWh != 54000 {
		t.Fatalf("unexpected UTF16 parse: %+v", got[0])
	}
}
