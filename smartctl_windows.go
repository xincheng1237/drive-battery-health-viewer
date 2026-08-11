//go:build windows

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

func smartctlExecutable() string {
	candidates := make([]string, 0, 4)
	if configured := strings.TrimSpace(os.Getenv("DBHV_SMARTCTL_PATH")); configured != "" {
		candidates = append(candidates, configured)
	}
	if embedded := unpackEmbeddedWindowsTools(); embedded != "" {
		candidates = append(candidates, embedded)
	}
	if executable, err := os.Executable(); err == nil {
		dir := filepath.Dir(executable)
		candidates = append(candidates, filepath.Join(dir, "smartctl.exe"), filepath.Join(dir, "tools", "smartctl.exe"))
	}
	for _, candidate := range candidates {
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			return candidate
		}
	}
	if path, err := exec.LookPath("smartctl.exe"); err == nil {
		return path
	}
	return ""
}

func smartValue(root map[string]interface{}, path ...string) interface{} {
	var current interface{} = root
	for _, part := range path {
		object, ok := current.(map[string]interface{})
		if !ok {
			return nil
		}
		current = object[part]
	}
	return current
}

func smartString(value interface{}) string {
	switch v := value.(type) {
	case string:
		return strings.TrimSpace(v)
	case json.Number:
		return v.String()
	case map[string]interface{}:
		for _, key := range []string{"string", "value"} {
			if text := smartString(v[key]); text != "" {
				return text
			}
		}
	}
	return ""
}

func smartUint(value interface{}) (*uint64, bool) {
	if object, ok := value.(map[string]interface{}); ok {
		for _, key := range []string{"value", "raw", "blocks"} {
			if result, found := smartUint(object[key]); found {
				return result, true
			}
		}
		return nil, false
	}
	text := strings.TrimSpace(smartString(value))
	if text == "" {
		return nil, false
	}
	if fields := strings.Fields(text); len(fields) > 0 {
		text = strings.Trim(fields[0], ",")
	}
	parsed, err := strconv.ParseUint(text, 10, 64)
	if err != nil {
		return nil, false
	}
	return &parsed, true
}

func smartInt(value interface{}) (*int64, bool) {
	if object, ok := value.(map[string]interface{}); ok {
		for _, key := range []string{"current", "value", "raw"} {
			if result, found := smartInt(object[key]); found {
				return result, true
			}
		}
		return nil, false
	}
	text := strings.TrimSpace(smartString(value))
	if text == "" {
		return nil, false
	}
	if fields := strings.Fields(text); len(fields) > 0 {
		text = strings.Trim(fields[0], ",")
	}
	parsed, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		return nil, false
	}
	return &parsed, true
}

func checkedMultiply(value, multiplier uint64) *uint64 {
	if multiplier != 0 && value > ^uint64(0)/multiplier {
		return nil
	}
	result := value * multiplier
	return &result
}

func parseSmartctlJSON(data []byte) (*smartctlDriveInfo, error) {
	decoder := json.NewDecoder(bytes.NewReader(bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF})))
	decoder.UseNumber()
	var root map[string]interface{}
	if err := decoder.Decode(&root); err != nil {
		return nil, fmt.Errorf("invalid smartctl JSON: %w", err)
	}
	if messages, ok := root["smartctl"].(map[string]interface{}); ok {
		if exitStatus, found := smartUint(messages["exit_status"]); found && *exitStatus&3 != 0 {
			return nil, fmt.Errorf("smartctl could not open or identify the device (exit status %d)", *exitStatus)
		}
	}
	result := &smartctlDriveInfo{
		Model:    smartString(root["model_name"]),
		Serial:   smartString(root["serial_number"]),
		Firmware: smartString(root["firmware_version"]),
		Protocol: smartString(smartValue(root, "device", "protocol")),
	}
	if result.Model == "" {
		result.Model = smartString(root["product"])
	}
	if status, ok := smartValue(root, "smart_status", "passed").(bool); ok {
		result.SmartPassed = &status
	}
	result.Temperature, _ = smartInt(smartValue(root, "temperature", "current"))
	result.PowerOnHours, _ = smartUint(smartValue(root, "power_on_time", "hours"))
	result.PowerCycles, _ = smartUint(root["power_cycle_count"])

	if nvme, ok := root["nvme_smart_health_information_log"].(map[string]interface{}); ok {
		if value, found := smartInt(nvme["temperature"]); found {
			result.Temperature = value
		}
		result.PercentageUsed, _ = smartUint(nvme["percentage_used"])
		result.PowerOnHours, _ = smartUint(nvme["power_on_hours"])
		result.PowerCycles, _ = smartUint(nvme["power_cycles"])
		result.UnsafeShutdowns, _ = smartUint(nvme["unsafe_shutdowns"])
		result.MediaErrors, _ = smartUint(nvme["media_errors"])
		if units, found := smartUint(nvme["data_units_read"]); found {
			result.BytesRead = checkedMultiply(*units, 512000)
		}
		if units, found := smartUint(nvme["data_units_written"]); found {
			result.BytesWritten = checkedMultiply(*units, 512000)
		}
	}

	if attributes, ok := smartValue(root, "ata_smart_attributes", "table").([]interface{}); ok {
		for _, item := range attributes {
			attribute, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			name := strings.ToLower(smartString(attribute["name"]))
			value, found := smartUint(smartValue(attribute, "raw", "value"))
			if !found {
				continue
			}
			switch {
			case strings.Contains(name, "power_on") && strings.Contains(name, "hour"):
				result.PowerOnHours = value
			case strings.Contains(name, "power_cycle"):
				result.PowerCycles = value
			}
		}
	}
	return result, nil
}

func smartctlDeviceModes(bus string) []string {
	modes := []string{""}
	lower := strings.ToLower(bus)
	if strings.Contains(lower, "usb") || strings.Contains(lower, "sata") || strings.Contains(lower, "ata") {
		modes = append(modes, "sat")
	}
	if strings.Contains(lower, "scsi") || strings.Contains(lower, "sas") {
		modes = append(modes, "scsi", "sat")
	}
	if strings.Contains(lower, "nvme") {
		modes = append(modes, "nvme")
	}
	return modes
}

func querySmartctlDrive(ctx context.Context, executable string, disk diskDescriptor) (*smartctlDriveInfo, error) {
	device := fmt.Sprintf("/dev/pd%d", disk.Number)
	var lastErr error
	for _, mode := range smartctlDeviceModes(disk.Bus) {
		args := []string{"-j", "-a"}
		if mode != "" {
			args = append(args, "-d", mode)
		}
		args = append(args, device)
		out, err := runHiddenContext(ctx, 7*time.Second, executable, args...)
		if info, parseErr := parseSmartctlJSON(out); parseErr == nil {
			return info, nil
		} else if err != nil {
			lastErr = fmt.Errorf("%v; %v", err, parseErr)
		} else {
			lastErr = parseErr
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
	}
	return nil, lastErr
}

func querySmartctlDrives(ctx context.Context, disks []diskDescriptor) map[int]*smartctlDriveInfo {
	executable := smartctlExecutable()
	if executable == "" || len(disks) == 0 {
		return nil
	}
	type answer struct {
		number int
		info   *smartctlDriveInfo
	}
	results := make(chan answer, len(disks))
	semaphore := make(chan struct{}, 4)
	var workers sync.WaitGroup
	for _, disk := range disks {
		disk := disk
		workers.Add(1)
		go func() {
			defer workers.Done()
			select {
			case semaphore <- struct{}{}:
				defer func() { <-semaphore }()
			case <-ctx.Done():
				return
			}
			info, _ := querySmartctlDrive(ctx, executable, disk)
			if info != nil {
				results <- answer{number: disk.Number, info: info}
			}
		}()
	}
	go func() { workers.Wait(); close(results) }()
	values := make(map[int]*smartctlDriveInfo)
	for {
		select {
		case result, ok := <-results:
			if !ok {
				return values
			}
			values[result.number] = result.info
		case <-ctx.Done():
			return values
		}
	}
}
