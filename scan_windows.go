//go:build windows

package main

import (
	"bytes"
	"encoding/binary"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

func openPhysicalDrive(number int) (syscall.Handle, error) {
	path := fmt.Sprintf(`\\.\PhysicalDrive%d`, number)
	p := utf16Ptr(path)
	h, _, e := procCreateFileW.Call(
		uintptr(unsafe.Pointer(p)), 0, FILE_SHARE_READ|FILE_SHARE_WRITE,
		0, OPEN_EXISTING, 0, 0,
	)
	if h == ^uintptr(0) {
		h, _, e = procCreateFileW.Call(
			uintptr(unsafe.Pointer(p)), GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_WRITE,
			0, OPEN_EXISTING, 0, 0,
		)
	}
	if h == ^uintptr(0) {
		return 0, e
	}
	return syscall.Handle(h), nil
}

func deviceIoControl(handle syscall.Handle, code uint32, inBuffer, outBuffer []byte) (uint32, error) {
	var returned uint32
	var inPtr, outPtr uintptr
	if len(inBuffer) > 0 {
		inPtr = uintptr(unsafe.Pointer(&inBuffer[0]))
	}
	if len(outBuffer) > 0 {
		outPtr = uintptr(unsafe.Pointer(&outBuffer[0]))
	}
	r, _, e := procDeviceIoControl.Call(
		uintptr(handle), uintptr(code), inPtr, uintptr(len(inBuffer)), outPtr, uintptr(len(outBuffer)),
		uintptr(unsafe.Pointer(&returned)), 0,
	)
	if r == 0 {
		return returned, e
	}
	return returned, nil
}

func queryDeviceDescriptor(handle syscall.Handle) (model, serial, firmware, bus string, err error) {
	query := makeStoragePropertyQuery(StorageDeviceProperty)
	header := make([]byte, 8)
	returned, err := deviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, query, header)
	if err != nil {
		return "", "", "", "", fmt.Errorf("device descriptor header: %w", err)
	}
	if returned < 8 {
		return "", "", "", "", fmt.Errorf("device descriptor header is too short: %d bytes", returned)
	}
	size := binary.LittleEndian.Uint32(header[4:8])
	if size < 36 || size > 1024*1024 {
		return "", "", "", "", fmt.Errorf("device descriptor reported invalid size: %d bytes", size)
	}
	buf := make([]byte, size)
	returned, err = deviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, query, buf)
	if err != nil {
		return "", "", "", "", fmt.Errorf("device descriptor body: %w", err)
	}
	if returned < 36 {
		return "", "", "", "", fmt.Errorf("storage descriptor is too short: %d bytes", returned)
	}
	if int(returned) < len(buf) {
		buf = buf[:returned]
	}
	return parseStorageDeviceDescriptor(buf)
}

func queryCapacity(handle syscall.Handle) (uint64, error) {
	out := make([]byte, 8)
	returned, err := deviceIoControl(handle, IOCTL_DISK_GET_LENGTH_INFO, nil, out)
	if err != nil {
		return 0, err
	}
	if returned < 8 {
		return 0, fmt.Errorf("disk length response is too short: %d bytes", returned)
	}
	return binary.LittleEndian.Uint64(out), nil
}

func queryNVMeHealthWithProperty(handle syscall.Handle, propertyID uint32) (*NVMeHealth, error) {
	const queryHeader = 8
	const protocolSpecific = 40
	const healthLog = 512
	buf := make([]byte, queryHeader+protocolSpecific+healthLog)
	binary.LittleEndian.PutUint32(buf[0:4], propertyID)
	binary.LittleEndian.PutUint32(buf[4:8], PropertyStandardQuery)
	p := queryHeader
	binary.LittleEndian.PutUint32(buf[p+0:p+4], ProtocolTypeNvme)
	binary.LittleEndian.PutUint32(buf[p+4:p+8], NVMeDataTypeLogPage)
	binary.LittleEndian.PutUint32(buf[p+8:p+12], NVMeHealthLogPage)
	binary.LittleEndian.PutUint32(buf[p+12:p+16], 0)
	binary.LittleEndian.PutUint32(buf[p+16:p+20], protocolSpecific)
	binary.LittleEndian.PutUint32(buf[p+20:p+24], healthLog)
	returned, err := deviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, buf, buf)
	if err != nil {
		return nil, err
	}
	if returned < queryHeader+protocolSpecific {
		return nil, fmt.Errorf("NVMe protocol response is too short: %d bytes", returned)
	}
	dataOffset := int(binary.LittleEndian.Uint32(buf[queryHeader+16 : queryHeader+20]))
	dataLength := int(binary.LittleEndian.Uint32(buf[queryHeader+20 : queryHeader+24]))
	start := queryHeader + dataOffset
	limit := len(buf)
	if int(returned) < limit {
		limit = int(returned)
	}
	if dataOffset < protocolSpecific || dataLength < healthLog || start < 0 || start+healthLog > limit {
		return nil, fmt.Errorf("NVMe SMART response has invalid offset or length (offset=%d length=%d returned=%d)", dataOffset, dataLength, returned)
	}
	h, err := parseNVMeHealth(buf[start : start+healthLog])
	if err != nil {
		return nil, err
	}
	return &h, nil
}

func queryNVMeHealth(handle syscall.Handle) (*NVMeHealth, error) {
	major := windowsMajorVersion()
	if major > 0 && major < 10 {
		return nil, fmt.Errorf("the standard NVMe protocol query requires Windows 10 or later")
	}
	h, deviceErr := queryNVMeHealthWithProperty(handle, StorageDeviceProtocolSpecificProperty)
	if deviceErr == nil {
		return h, nil
	}
	h, adapterErr := queryNVMeHealthWithProperty(handle, StorageAdapterProtocolSpecificProperty)
	if adapterErr == nil {
		return h, nil
	}
	return nil, fmt.Errorf("device query: %v; adapter query: %v", deviceErr, adapterErr)
}

type cimDiskInfo struct {
	Index            int    `json:"Index"`
	Model            string `json:"Model"`
	SerialNumber     string `json:"SerialNumber"`
	FirmwareRevision string `json:"FirmwareRevision"`
	InterfaceType    string `json:"InterfaceType"`
	Size             uint64 `json:"Size"`
}

func runHidden(name string, args ...string) ([]byte, error) {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd.Output()
}

func queryCimDisks() map[int]cimDiskInfo {
	result := make(map[int]cimDiskInfo)
	scripts := []string{
		`[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $d=@(Get-CimInstance Win32_DiskDrive | Select-Object Index,Model,SerialNumber,FirmwareRevision,InterfaceType,Size); ConvertTo-Json -InputObject $d -Compress`,
		`[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $d=@(Get-WmiObject Win32_DiskDrive | Select-Object Index,Model,SerialNumber,FirmwareRevision,InterfaceType,Size); ConvertTo-Json -InputObject $d -Compress`,
	}
	for _, script := range scripts {
		out, err := runHidden("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
		if err != nil {
			continue
		}
		out = bytes.TrimPrefix(out, []byte{0xEF, 0xBB, 0xBF})
		var disks []cimDiskInfo
		if json.Unmarshal(out, &disks) == nil {
			for _, d := range disks {
				result[d.Index] = d
			}
			if len(result) > 0 {
				return result
			}
		}
	}
	return queryWmicDisks()
}

func decodeWindowsCommandText(data []byte) string {
	if len(data) >= 2 && data[0] == 0xFF && data[1] == 0xFE {
		u := make([]uint16, 0, len(data)/2)
		for i := 2; i+1 < len(data); i += 2 {
			u = append(u, binary.LittleEndian.Uint16(data[i:i+2]))
		}
		return string(utf16.Decode(u))
	}
	// cmd /u and WMIC sometimes emit UTF-16LE without a BOM.
	zeros := 0
	for i := 1; i < len(data) && i < 200; i += 2 {
		if data[i] == 0 {
			zeros++
		}
	}
	if len(data) > 8 && zeros > 10 {
		u := make([]uint16, 0, len(data)/2)
		for i := 0; i+1 < len(data); i += 2 {
			u = append(u, binary.LittleEndian.Uint16(data[i:i+2]))
		}
		return string(utf16.Decode(u))
	}
	return strings.TrimPrefix(string(data), "\uFEFF")
}

func queryWmicDisks() map[int]cimDiskInfo {
	result := make(map[int]cimDiskInfo)
	out, err := runHidden("wmic.exe", "diskdrive", "get", "Index,Model,SerialNumber,FirmwareRevision,InterfaceType,Size", "/format:csv")
	if err != nil {
		return result
	}
	r := csv.NewReader(strings.NewReader(strings.TrimSpace(decodeWindowsCommandText(out))))
	r.FieldsPerRecord = -1
	records, err := r.ReadAll()
	if err != nil || len(records) < 2 {
		return result
	}
	headers := make(map[string]int)
	for i, h := range records[0] {
		headers[strings.TrimSpace(h)] = i
	}
	get := func(row []string, name string) string {
		i, ok := headers[name]
		if !ok || i >= len(row) {
			return ""
		}
		return strings.TrimSpace(row[i])
	}
	for _, row := range records[1:] {
		idx, err := strconv.Atoi(get(row, "Index"))
		if err != nil {
			continue
		}
		size, _ := strconv.ParseUint(get(row, "Size"), 10, 64)
		result[idx] = cimDiskInfo{Index: idx, Model: get(row, "Model"), SerialNumber: get(row, "SerialNumber"), FirmwareRevision: get(row, "FirmwareRevision"), InterfaceType: get(row, "InterfaceType"), Size: size}
	}
	return result
}

func queryStorageReliability() []storageReliability {
	script := `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $x=@(Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object { $p=$_; $r=$null; try {$r=$p | Get-StorageReliabilityCounter -ErrorAction Stop} catch {}; [pscustomobject]@{DeviceId=[string]$p.DeviceId;FriendlyName=[string]$p.FriendlyName;HealthStatus=[string]$p.HealthStatus;Temperature=$(if($r){$r.Temperature}else{$null});Wear=$(if($r){$r.Wear}else{$null});PowerOnHours=$(if($r){$r.PowerOnHours}else{$null});ReadErrorsUncorrected=$(if($r){$r.ReadErrorsUncorrected}else{$null});WriteErrorsUncorrected=$(if($r){$r.WriteErrorsUncorrected}else{$null})}}); ConvertTo-Json -InputObject $x -Compress`
	out, err := runHidden("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
	if err != nil {
		return nil
	}
	out = bytes.TrimPrefix(out, []byte{0xEF, 0xBB, 0xBF})
	var values []storageReliability
	if json.Unmarshal(out, &values) != nil {
		return nil
	}
	return values
}

func findReliability(number int, model string, values []storageReliability) *storageReliability {
	numberText := strconv.Itoa(number)
	for i := range values {
		if strings.TrimSpace(values[i].DeviceID) == numberText {
			return &values[i]
		}
	}
	model = strings.TrimSpace(model)
	if model != "" {
		for i := range values {
			friendly := strings.TrimSpace(values[i].FriendlyName)
			if friendly != "" && (strings.EqualFold(friendly, model) || strings.Contains(strings.ToLower(model), strings.ToLower(friendly))) {
				return &values[i]
			}
		}
	}
	return nil
}

func enumerateDisksNative() []diskDescriptor {
	result := make([]diskDescriptor, 0, 4)
	missesAfterFound := 0
	foundAny := false
	for i := 0; i < 32; i++ {
		h, err := openPhysicalDrive(i)
		if err != nil {
			if foundAny {
				missesAfterFound++
				if missesAfterFound >= 8 {
					break
				}
			}
			continue
		}
		foundAny = true
		missesAfterFound = 0
		d := diskDescriptor{Number: i}
		d.Model, d.Serial, d.Firmware, d.Bus, err = queryDeviceDescriptor(h)
		if err != nil {
			d.ErrorParts = append(d.ErrorParts, diskErrorPart{Kind: "nativeModelFailed", Detail: err.Error()})
		}
		if capacity, capErr := queryCapacity(h); capErr == nil {
			d.Capacity = capacity
		} else {
			d.ErrorParts = append(d.ErrorParts, diskErrorPart{Kind: "nativeCapacityFailed", Detail: capErr.Error()})
		}
		busLower := strings.ToLower(strings.TrimSpace(d.Bus))
		tryNVMe := busLower == "" || busLower == "unknown" || strings.Contains(busLower, "nvme") || strings.Contains(busLower, "raid") || strings.Contains(busLower, "scsi")
		if tryNVMe {
			d.Health, err = queryNVMeHealth(h)
			if err != nil && (strings.Contains(busLower, "nvme") || strings.Contains(busLower, "raid") || busLower == "") {
				d.ErrorParts = append(d.ErrorParts, diskErrorPart{Kind: "nvmeNotPassed", Detail: err.Error()})
			}
			if d.Health != nil && (d.Bus == "" || strings.EqualFold(d.Bus, "Unknown")) {
				d.Bus = "NVMe"
			}
		}
		procCloseHandle.Call(uintptr(h))
		result = append(result, d)
	}
	return result
}

func mergeDiskFallbacks(disks []diskDescriptor, cim map[int]cimDiskInfo, reliability []storageReliability) []diskDescriptor {
	for i := range disks {
		d := &disks[i]
		if c, ok := cim[d.Number]; ok {
			if strings.TrimSpace(d.Model) == "" {
				d.Model = strings.TrimSpace(c.Model)
			}
			if strings.TrimSpace(d.Serial) == "" {
				d.Serial = strings.TrimSpace(c.SerialNumber)
			}
			if strings.TrimSpace(d.Firmware) == "" {
				d.Firmware = strings.TrimSpace(c.FirmwareRevision)
			}
			if strings.TrimSpace(d.Bus) == "" || strings.EqualFold(d.Bus, "Unknown") {
				d.Bus = strings.TrimSpace(c.InterfaceType)
			}
			if d.Capacity == 0 {
				d.Capacity = c.Size
			}
		}
		d.Reliability = findReliability(d.Number, d.Model, reliability)
		// Do not show a low-level error once a fallback has supplied the same field.
		filtered := d.ErrorParts[:0]
		for _, part := range d.ErrorParts {
			resolved := (part.Kind == "nativeModelFailed" && strings.TrimSpace(d.Model) != "") ||
				(part.Kind == "nativeCapacityFailed" && d.Capacity > 0) ||
				(part.Kind == "nvmeNotPassed" && d.Health != nil)
			if !resolved {
				filtered = append(filtered, part)
			}
		}
		d.ErrorParts = filtered
	}
	// A controller may reject CreateFile while WMI still enumerates a disk.
	seen := make(map[int]bool)
	for _, d := range disks {
		seen[d.Number] = true
	}
	for number, c := range cim {
		if seen[number] {
			continue
		}
		disks = append(disks, diskDescriptor{Number: number, Model: strings.TrimSpace(c.Model), Serial: strings.TrimSpace(c.SerialNumber), Firmware: strings.TrimSpace(c.FirmwareRevision), Bus: strings.TrimSpace(c.InterfaceType), Capacity: c.Size, Reliability: findReliability(number, c.Model, reliability)})
	}
	sort.Slice(disks, func(i, j int) bool { return disks[i].Number < disks[j].Number })
	return disks
}

func runBatteryReport() ([]BatteryInfo, error) {
	f, err := os.CreateTemp("", "hardware_health_battery_*.xml")
	if err == nil {
		path := f.Name()
		f.Close()
		os.Remove(path)
		defer os.Remove(path)
		cmd := exec.Command("powercfg.exe", "/batteryreport", "/output", path, "/xml")
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		if output, runErr := cmd.CombinedOutput(); runErr == nil {
			if data, readErr := os.ReadFile(path); readErr == nil {
				return parseBatteryReportXML(data)
			}
		} else {
			_ = output
		}
	}
	return runBatteryWmicFallback()
}

func parseWmicList(text string) []map[string]string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	blocks := strings.Split(text, "\n\n")
	result := make([]map[string]string, 0)
	for _, block := range blocks {
		m := make(map[string]string)
		for _, line := range strings.Split(block, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			parts := strings.SplitN(line, "=", 2)
			if len(parts) != 2 {
				continue
			}
			m[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
		if len(m) > 0 {
			result = append(result, m)
		}
	}
	return result
}

func runWmicList(args ...string) []map[string]string {
	out, err := runHidden("wmic.exe", args...)
	if err != nil {
		return nil
	}
	return parseWmicList(decodeWindowsCommandText(out))
}

func runBatteryWmicFallback() ([]BatteryInfo, error) {
	static := runWmicList("/namespace:\\\\root\\wmi", "path", "BatteryStaticData", "get", "InstanceName,DeviceName,ManufactureName,SerialNumber,DesignedCapacity", "/format:list")
	full := runWmicList("/namespace:\\\\root\\wmi", "path", "BatteryFullChargedCapacity", "get", "InstanceName,FullChargedCapacity", "/format:list")
	cycles := runWmicList("/namespace:\\\\root\\wmi", "path", "BatteryCycleCount", "get", "InstanceName,CycleCount", "/format:list")
	find := func(list []map[string]string, instance string) map[string]string {
		for _, m := range list {
			if strings.EqualFold(m["InstanceName"], instance) {
				return m
			}
		}
		if len(list) > 0 {
			return list[0]
		}
		return nil
	}
	result := make([]BatteryInfo, 0, len(static))
	for _, s := range static {
		instance := s["InstanceName"]
		f := find(full, instance)
		c := find(cycles, instance)
		design, _ := strconv.ParseInt(s["DesignedCapacity"], 10, 64)
		fullCap := int64(0)
		if f != nil {
			fullCap, _ = strconv.ParseInt(f["FullChargedCapacity"], 10, 64)
		}
		health := 0.0
		if design > 0 && fullCap > 0 {
			health = float64(fullCap) * 100 / float64(design)
		}
		cycle := ""
		if c != nil {
			cycle = c["CycleCount"]
		}
		result = append(result, BatteryInfo{Name: s["DeviceName"], Manufacturer: s["ManufactureName"], SerialNumber: s["SerialNumber"], DesignCapacityMWh: design, FullChargeMWh: fullCap, CycleCount: cycle, HealthPercent: health})
	}
	if len(result) > 0 {
		return result, nil
	}

	// Last-resort Win32_Battery query, available on Windows 7 and later.
	basic := runWmicList("path", "Win32_Battery", "get", "Name,DeviceID,DesignCapacity,FullChargeCapacity", "/format:list")
	for _, b := range basic {
		design, _ := strconv.ParseInt(b["DesignCapacity"], 10, 64)
		fullCap, _ := strconv.ParseInt(b["FullChargeCapacity"], 10, 64)
		health := 0.0
		if design > 0 && fullCap > 0 {
			health = float64(fullCap) * 100 / float64(design)
		}
		result = append(result, BatteryInfo{Name: b["Name"], SerialNumber: b["DeviceID"], DesignCapacityMWh: design, FullChargeMWh: fullCap, HealthPercent: health})
	}
	if len(result) == 0 {
		return nil, fmt.Errorf("powercfg and WMI did not return battery data")
	}
	return result, nil
}

func scanHardware() scanResult {
	result := scanResult{GeneratedAt: time.Now(), Computer: os.Getenv("COMPUTERNAME")}
	var native []diskDescriptor
	var cim map[int]cimDiskInfo
	var reliability []storageReliability
	var batteries []BatteryInfo
	var batteryErr error
	var wg sync.WaitGroup
	wg.Add(4)
	go func() { defer wg.Done(); native = enumerateDisksNative() }()
	go func() { defer wg.Done(); cim = queryCimDisks() }()
	go func() { defer wg.Done(); reliability = queryStorageReliability() }()
	go func() { defer wg.Done(); batteries, batteryErr = runBatteryReport() }()
	wg.Wait()
	result.Disks = mergeDiskFallbacks(native, cim, reliability)
	result.Batteries = batteries
	if batteryErr != nil {
		result.BatteryErr = batteryErr.Error()
	}
	return result
}
