//go:build windows

package main

import (
	_ "embed"
	"encoding/binary"
	"syscall"
	"unsafe"
)

//go:embed app.ico
var embeddedAppIcon []byte

var appIconLarge, appIconSmall syscall.Handle

type icoEntry struct {
	width, height int
	size, offset  uint32
}

func icoEntries(data []byte) []icoEntry {
	if len(data) < 6 || binary.LittleEndian.Uint16(data[0:2]) != 0 || binary.LittleEndian.Uint16(data[2:4]) != 1 {
		return nil
	}
	count := int(binary.LittleEndian.Uint16(data[4:6]))
	if count <= 0 || len(data) < 6+count*16 {
		return nil
	}
	result := make([]icoEntry, 0, count)
	for i := 0; i < count; i++ {
		o := 6 + i*16
		w := int(data[o])
		h := int(data[o+1])
		if w == 0 {
			w = 256
		}
		if h == 0 {
			h = 256
		}
		size := binary.LittleEndian.Uint32(data[o+8 : o+12])
		offset := binary.LittleEndian.Uint32(data[o+12 : o+16])
		if size == 0 || int(offset)+int(size) > len(data) {
			continue
		}
		result = append(result, icoEntry{width: w, height: h, size: size, offset: offset})
	}
	return result
}

func embeddedIconForSize(size int) syscall.Handle {
	entries := icoEntries(embeddedAppIcon)
	if len(entries) == 0 {
		return 0
	}
	best := entries[0]
	bestDistance := 1 << 30
	for _, entry := range entries {
		distance := entry.width - size
		if distance < 0 {
			distance = -distance + 4 // prefer an equal or larger source when distances tie
		}
		if distance < bestDistance {
			best = entry
			bestDistance = distance
		}
	}
	bits := embeddedAppIcon[best.offset : best.offset+best.size]
	if len(bits) == 0 {
		return 0
	}
	r, _, _ := procCreateIconFromResourceEx.Call(
		uintptr(unsafe.Pointer(&bits[0])), uintptr(len(bits)), 1, 0x00030000,
		uintptr(size), uintptr(size), LR_DEFAULTCOLOR,
	)
	return syscall.Handle(r)
}

func loadAppIcons() {
	if appIconLarge == 0 {
		appIconLarge = embeddedIconForSize(64)
	}
	if appIconSmall == 0 {
		appIconSmall = embeddedIconForSize(24)
	}
}

func releaseAppIcons() {
	if appIconLarge != 0 {
		procDestroyIcon.Call(uintptr(appIconLarge))
		appIconLarge = 0
	}
	if appIconSmall != 0 {
		procDestroyIcon.Call(uintptr(appIconSmall))
		appIconSmall = 0
	}
}
