//go:build windows

// The launcher deliberately uses only the Go standard library and APIs that
// exist on Windows 7.  It must be able to select the compatibility UI before
// any .NET or Windows App SDK code is loaded.
package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const windows10Build1809 = 17763

type rtlOSVersionInfoEx struct {
	Size             uint32
	Major            uint32
	Minor            uint32
	Build            uint32
	Platform         uint32
	ServicePack      [128]uint16
	ServicePackMajor uint16
	ServicePackMinor uint16
	SuiteMask        uint16
	ProductType      byte
	Reserved         byte
}

func supportsModernUI() bool {
	var info rtlOSVersionInfoEx
	info.Size = uint32(unsafe.Sizeof(info))
	proc := syscall.NewLazyDLL("ntdll.dll").NewProc("RtlGetVersion")
	if proc.Find() != nil {
		return false
	}
	r, _, _ := proc.Call(uintptr(unsafe.Pointer(&info)))
	return int32(r) >= 0 && supportsModernVersion(info.Major, info.Build)
}

func supportsModernVersion(major, build uint32) bool {
	return major > 10 || (major == 10 && build >= windows10Build1809)
}

// The compatibility shell is the stable release surface.  The modern shell
// remains bundled for validation and can be explicitly selected with
// --modern or DBHV_USE_MODERN=1.  Keeping the default deterministic avoids a
// runtime-dependent visual change on otherwise identical Windows machines.
func wantsModern(args []string) (bool, []string) {
	forceLegacy := strings.EqualFold(os.Getenv("DBHV_FORCE_LEGACY"), "1")
	useModern := strings.EqualFold(os.Getenv("DBHV_USE_MODERN"), "1")
	clean := make([]string, 0, len(args))
	for _, arg := range args {
		switch strings.ToLower(strings.TrimSpace(arg)) {
		case "--legacy":
			forceLegacy = true
		case "--modern":
			useModern = true
		default:
			clean = append(clean, arg)
		}
	}
	return useModern && !forceLegacy, clean
}

func launch(path string, args []string) (*exec.Cmd, error) {
	cmd := exec.Command(path, args...)
	cmd.Dir = filepath.Dir(path)
	return cmd, cmd.Start()
}

func main() {
	exe, err := os.Executable()
	if err != nil {
		return
	}
	root := filepath.Dir(exe)
	legacy := filepath.Join(root, "DriveBatteryHealthViewer.Legacy.exe")
	modern := filepath.Join(root, "modern", "DriveBatteryHealthViewer.Modern.exe")
	useModern, args := wantsModern(os.Args[1:])
	if useModern && supportsModernUI() {
		if _, statErr := os.Stat(modern); statErr == nil {
			cmd, startErr := launch(modern, args)
			if startErr == nil {
				done := make(chan error, 1)
				go func() { done <- cmd.Wait() }()
				select {
				case waitErr := <-done:
					// A healthy UI remains running. An immediate non-zero exit is
					// treated as a missing/broken modern runtime and falls back.
					if waitErr == nil {
						return
					}
				case <-time.After(1500 * time.Millisecond):
					return
				}
			}
		}
	}
	_, _ = launch(legacy, args)
}
