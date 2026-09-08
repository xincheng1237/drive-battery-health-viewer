//go:build windows

package main

import "testing"

func TestParseSmartctlNVMeJSON(t *testing.T) {
	data := []byte(`{
  "smartctl":{"exit_status":0},
  "device":{"protocol":"NVMe"},
  "model_name":"Example NVMe",
  "serial_number":"SERIAL-1",
  "firmware_version":"1.06",
  "smart_status":{"passed":true},
  "nvme_smart_health_information_log":{
    "temperature":36,
    "percentage_used":7,
    "data_units_read":2,
    "data_units_written":3,
    "power_cycles":12,
    "power_on_hours":345,
    "unsafe_shutdowns":1,
    "media_errors":0,
    "num_err_log_entries":4
  }
}`)
	info, err := parseSmartctlJSON(data)
	if err != nil {
		t.Fatalf("parseSmartctlJSON: %v", err)
	}
	if info.Model != "Example NVMe" || info.Serial != "SERIAL-1" || info.Protocol != "NVMe" {
		t.Fatalf("unexpected identity: %+v", info)
	}
	if info.BytesRead == nil || *info.BytesRead != 1024000 {
		t.Fatalf("unexpected bytes read: %+v", info.BytesRead)
	}
	if info.BytesWritten == nil || *info.BytesWritten != 1536000 {
		t.Fatalf("unexpected bytes written: %+v", info.BytesWritten)
	}
	if info.PercentageUsed == nil || *info.PercentageUsed != 7 || info.PowerOnHours == nil || *info.PowerOnHours != 345 {
		t.Fatalf("unexpected health counters: %+v", info)
	}
	if info.UnsafeShutdowns == nil || *info.UnsafeShutdowns != 1 || info.ErrorLogEntries == nil || *info.ErrorLogEntries != 4 {
		t.Fatalf("unexpected shutdown/error counters: %+v", info)
	}
}

func TestParseSmartctlATAAttributes(t *testing.T) {
	data := []byte(`{
  "smartctl":{"exit_status":0},
  "model_name":"USB SATA SSD",
  "smart_status":{"passed":false},
  "temperature":{"current":41},
  "ata_smart_attributes":{"table":[
    {"name":"Power_On_Hours","raw":{"value":99}},
    {"name":"Power_Cycle_Count","raw":{"value":8}}
  ]}
}`)
	info, err := parseSmartctlJSON(data)
	if err != nil {
		t.Fatalf("parseSmartctlJSON: %v", err)
	}
	if info.SmartPassed == nil || *info.SmartPassed {
		t.Fatalf("expected failed SMART status: %+v", info.SmartPassed)
	}
	if info.Temperature == nil || *info.Temperature != 41 || info.PowerOnHours == nil || *info.PowerOnHours != 99 || info.PowerCycles == nil || *info.PowerCycles != 8 {
		t.Fatalf("unexpected ATA values: %+v", info)
	}
}

func TestMergeDiskFallbacksRejectsChangedIdentity(t *testing.T) {
	disks := []diskDescriptor{{Number: 2, Model: "Original Disk", Serial: "A", Capacity: 1000}}
	cim := map[int]cimDiskInfo{2: {Index: 2, Model: "Replacement Disk", SerialNumber: "B", FirmwareRevision: "wrong", Size: 2000}}
	reliability := []storageReliability{{DeviceID: "2", FriendlyName: "Replacement Disk", HealthStatus: "Healthy"}}
	smart := map[int]*smartctlDriveInfo{2: {Model: "Replacement Disk", Serial: "B", Firmware: "wrong"}}

	merged := mergeDiskFallbacks(disks, cim, reliability, smart)
	if len(merged) != 1 {
		t.Fatalf("unexpected disk count: %d", len(merged))
	}
	if merged[0].Model != "Original Disk" || merged[0].Serial != "A" || merged[0].Firmware != "" {
		t.Fatalf("changed identity was merged: %+v", merged[0])
	}
	if merged[0].Reliability != nil || merged[0].Smartctl != nil {
		t.Fatalf("health data from a replacement disk was merged: %+v", merged[0])
	}
}

func TestMergeDiskFallbacksAcceptsMatchingIdentity(t *testing.T) {
	disks := []diskDescriptor{{Number: 1, Model: "Example SSD", Capacity: 1000}}
	cim := map[int]cimDiskInfo{1: {Index: 1, Model: "Example SSD", SerialNumber: "SERIAL", FirmwareRevision: "FW", Size: 1000}}
	smart := map[int]*smartctlDriveInfo{1: {Model: "Example SSD", Serial: "SERIAL"}}

	merged := mergeDiskFallbacks(disks, cim, nil, smart)
	if merged[0].Serial != "SERIAL" || merged[0].Firmware != "FW" || merged[0].Smartctl == nil {
		t.Fatalf("matching fallback was not merged: %+v", merged[0])
	}
}
