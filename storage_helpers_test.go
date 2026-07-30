package main

import (
	"encoding/binary"
	"testing"
)

func putCString(buf []byte, offset int, s string) {
	copy(buf[offset:], []byte(s))
	buf[offset+len(s)] = 0
}

func TestStoragePropertyQueryUsesFullStructureLength(t *testing.T) {
	q := makeStoragePropertyQuery(0)
	if len(q) != 12 {
		t.Fatalf("STORAGE_PROPERTY_QUERY length = %d, want 12", len(q))
	}
	if binary.LittleEndian.Uint32(q[0:4]) != 0 || binary.LittleEndian.Uint32(q[4:8]) != 0 {
		t.Fatalf("unexpected query header: %v", q[:8])
	}
}

func TestParseStorageDeviceDescriptor(t *testing.T) {
	buf := make([]byte, 160)
	binary.LittleEndian.PutUint32(buf[0:4], 36)
	binary.LittleEndian.PutUint32(buf[4:8], uint32(len(buf)))
	binary.LittleEndian.PutUint32(buf[12:16], 64)
	binary.LittleEndian.PutUint32(buf[16:20], 80)
	binary.LittleEndian.PutUint32(buf[20:24], 112)
	binary.LittleEndian.PutUint32(buf[24:28], 128)
	binary.LittleEndian.PutUint32(buf[28:32], 17)
	putCString(buf, 64, "SanDisk")
	putCString(buf, 80, "PC SN7100S 1TB")
	putCString(buf, 112, "73110000")
	putCString(buf, 128, "ABC123")

	model, serial, firmware, bus, err := parseStorageDeviceDescriptor(buf)
	if err != nil {
		t.Fatal(err)
	}
	if model != "SanDisk PC SN7100S 1TB" || serial != "ABC123" || firmware != "73110000" || bus != "NVMe" {
		t.Fatalf("unexpected descriptor: model=%q serial=%q firmware=%q bus=%q", model, serial, firmware, bus)
	}
}

func TestParseStorageDeviceDescriptorRejectsShortData(t *testing.T) {
	if _, _, _, _, err := parseStorageDeviceDescriptor(make([]byte, 35)); err == nil {
		t.Fatal("expected short descriptor error")
	}
}
