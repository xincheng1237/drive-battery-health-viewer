package main

import (
	"encoding/binary"
	"fmt"
	"strings"
)

func makeStoragePropertyQuery(propertyID uint32) []byte {
	// STORAGE_PROPERTY_QUERY is two DWORDs plus AdditionalParameters[1].
	// C structure alignment rounds this to 12 bytes.
	query := make([]byte, 12)
	binary.LittleEndian.PutUint32(query[0:4], propertyID)
	binary.LittleEndian.PutUint32(query[4:8], 0) // PropertyStandardQuery
	return query
}

func cStringAt(buf []byte, offset uint32) string {
	if offset == 0 || int(offset) >= len(buf) {
		return ""
	}
	end := int(offset)
	for end < len(buf) && buf[end] != 0 {
		end++
	}
	return strings.TrimSpace(string(buf[int(offset):end]))
}

func busTypeName(v uint32) string {
	names := map[uint32]string{
		0: "Unknown", 1: "SCSI", 2: "ATAPI", 3: "ATA", 4: "IEEE 1394", 5: "SSA", 6: "Fibre", 7: "USB", 8: "RAID", 9: "iSCSI", 10: "SAS", 11: "SATA", 12: "SD", 13: "MMC", 14: "Virtual", 15: "File-backed virtual", 16: "Storage Spaces", 17: "NVMe", 18: "SCM", 19: "UFS",
	}
	if s, ok := names[v]; ok {
		return s
	}
	return fmt.Sprintf("BusType %d", v)
}

func parseStorageDeviceDescriptor(buf []byte) (model, serial, firmware, bus string, err error) {
	if len(buf) < 36 {
		return "", "", "", "", fmt.Errorf("storage descriptor is too short: %d bytes", len(buf))
	}
	vendor := cStringAt(buf, binary.LittleEndian.Uint32(buf[12:16]))
	product := cStringAt(buf, binary.LittleEndian.Uint32(buf[16:20]))
	firmware = cStringAt(buf, binary.LittleEndian.Uint32(buf[20:24]))
	serial = cStringAt(buf, binary.LittleEndian.Uint32(buf[24:28]))
	bus = busTypeName(binary.LittleEndian.Uint32(buf[28:32]))
	model = strings.TrimSpace(strings.TrimSpace(vendor) + " " + strings.TrimSpace(product))
	return model, serial, firmware, bus, nil
}
