package main

import "time"

const (
	appVersion = "1.0.6"
	// appBuildID is intentionally not shown in the UI. It lets a revised build
	// of the same public version show its one-time, non-modal changelog hint.
	appBuildID = "1.0.6-20260820b"
)

type diskDescriptor struct {
	Number      int
	Model       string
	Serial      string
	Firmware    string
	Bus         string
	Capacity    uint64
	Health      *NVMeHealth
	Smartctl    *smartctlDriveInfo
	Reliability *storageReliability
	ErrorParts  []diskErrorPart
}

// smartctlDriveInfo contains the read-only health information returned by the
// bundled smartctl helper. Pointer fields distinguish an actual zero from a
// value the bridge or drive did not report.
type smartctlDriveInfo struct {
	Model           string
	Serial          string
	Firmware        string
	Protocol        string
	SmartPassed     *bool
	Temperature     *int64
	PercentageUsed  *uint64
	PowerOnHours    *uint64
	PowerCycles     *uint64
	BytesRead       *uint64
	BytesWritten    *uint64
	UnsafeShutdowns *uint64
	MediaErrors     *uint64
	ErrorLogEntries *uint64
}

type diskErrorPart struct {
	Kind   string
	Detail string
}

type scanResult struct {
	GeneratedAt time.Time
	Computer    string
	Disks       []diskDescriptor
	Batteries   []BatteryInfo
	BatteryErr  string
}

type storageReliability struct {
	DeviceID               string  `json:"DeviceId"`
	FriendlyName           string  `json:"FriendlyName"`
	HealthStatus           string  `json:"HealthStatus"`
	Temperature            *int64  `json:"Temperature"`
	Wear                   *uint64 `json:"Wear"`
	PowerOnHours           *uint64 `json:"PowerOnHours"`
	ReadErrorsUncorrected  *uint64 `json:"ReadErrorsUncorrected"`
	WriteErrorsUncorrected *uint64 `json:"WriteErrorsUncorrected"`
}
