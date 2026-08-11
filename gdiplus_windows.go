//go:build windows

package main

import (
	"math"
	"sync"
	"syscall"
	"unsafe"
)

var (
	gdiplus                       = syscall.NewLazyDLL("gdiplus.dll")
	procGdiplusStartup            = gdiplus.NewProc("GdiplusStartup")
	procGdipCreateFromHDC         = gdiplus.NewProc("GdipCreateFromHDC")
	procGdipDeleteGraphics        = gdiplus.NewProc("GdipDeleteGraphics")
	procGdipSetSmoothingMode      = gdiplus.NewProc("GdipSetSmoothingMode")
	procGdipSetPixelOffsetMode    = gdiplus.NewProc("GdipSetPixelOffsetMode")
	procGdipSetCompositingQuality = gdiplus.NewProc("GdipSetCompositingQuality")
	procGdipCreatePen1            = gdiplus.NewProc("GdipCreatePen1")
	procGdipDeletePen             = gdiplus.NewProc("GdipDeletePen")
	procGdipSetPenStartCap        = gdiplus.NewProc("GdipSetPenStartCap")
	procGdipSetPenEndCap          = gdiplus.NewProc("GdipSetPenEndCap")
	procGdipDrawEllipseI          = gdiplus.NewProc("GdipDrawEllipseI")
	procGdipDrawArcI              = gdiplus.NewProc("GdipDrawArcI")
	procGdipDrawRectangleI        = gdiplus.NewProc("GdipDrawRectangleI")
	procGdipDrawLineI             = gdiplus.NewProc("GdipDrawLineI")
	procGdipCreateSolidFill       = gdiplus.NewProc("GdipCreateSolidFill")
	procGdipDeleteBrush           = gdiplus.NewProc("GdipDeleteBrush")
	procGdipFillRectangleI        = gdiplus.NewProc("GdipFillRectangleI")
	gdiplusOnce                   sync.Once
	gdiplusToken                  uintptr
	gdiplusAvailable              bool
)

type gdiplusStartupInput struct {
	Version                  uint32
	DebugEventCallback       uintptr
	SuppressBackgroundThread int32
	SuppressExternalCodecs   int32
}

func ensureGDIPlus() bool {
	gdiplusOnce.Do(func() {
		input := gdiplusStartupInput{Version: 1}
		status, _, _ := procGdiplusStartup.Call(uintptr(unsafe.Pointer(&gdiplusToken)), uintptr(unsafe.Pointer(&input)), 0)
		gdiplusAvailable = status == 0 && gdiplusToken != 0
	})
	return gdiplusAvailable
}

func argb(a, r, g, b byte) uint32 {
	return uint32(a)<<24 | uint32(r)<<16 | uint32(g)<<8 | uint32(b)
}

func gdipFloat(value float32) uintptr { return uintptr(math.Float32bits(value)) }

func withGDIPlus(hdc syscall.Handle, fn func(graphics uintptr)) bool {
	if !ensureGDIPlus() {
		return false
	}
	var graphics uintptr
	status, _, _ := procGdipCreateFromHDC.Call(uintptr(hdc), uintptr(unsafe.Pointer(&graphics)))
	if status != 0 || graphics == 0 {
		return false
	}
	defer procGdipDeleteGraphics.Call(graphics)
	// SmoothingModeAntiAlias8x8 is enum value 6. Value 7 is invalid and caused
	// GDI+ to silently keep the jagged default rendering mode.
	procGdipSetSmoothingMode.Call(graphics, 6)
	procGdipSetPixelOffsetMode.Call(graphics, 4)
	procGdipSetCompositingQuality.Call(graphics, 2)
	fn(graphics)
	return true
}

func createGDIPlusPen(color uint32, width float32, rounded bool) uintptr {
	var pen uintptr
	status, _, _ := procGdipCreatePen1.Call(uintptr(color), gdipFloat(width), 2, uintptr(unsafe.Pointer(&pen)))
	if status != 0 {
		return 0
	}
	if rounded {
		procGdipSetPenStartCap.Call(pen, 2)
		procGdipSetPenEndCap.Call(pen, 2)
	}
	return pen
}
