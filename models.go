package main

import "time"

const appVersion = "1.0.4"

type diskDescriptor struct {
	Number      int
	Model       string
	Serial      string
	Firmware    string
	Bus         string
	Capacity    uint64
	Health      *NVMeHealth
	Reliability *storageReliability
	ErrorParts  []diskErrorPart
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
