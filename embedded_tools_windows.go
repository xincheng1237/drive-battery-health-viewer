//go:build windows

package main

import (
	"crypto/sha256"
	"embed"
	"os"
	"path/filepath"
	"sync"
)

// smartmontools is GPL-2.0-or-later software. Its license text is embedded
// with the helper and extracted beside it on first use.
//
//go:embed assets/windows/smartctl.exe assets/windows/drivedb.h assets/windows/SMARTMONTOOLS_COPYING.txt
var embeddedWindowsTools embed.FS

var (
	embeddedToolOnce sync.Once
	embeddedToolPath string
)

func writeEmbeddedToolFile(path string, data []byte) error {
	if existing, err := os.ReadFile(path); err == nil && sha256.Sum256(existing) == sha256.Sum256(data) {
		return nil
	}
	temporary := path + ".new"
	if err := os.WriteFile(temporary, data, 0o600); err != nil {
		return err
	}
	// Windows cannot atomically rename over an existing file. Remove only this
	// exact, versioned cache target after the replacement has been written.
	_ = os.Remove(path)
	if err := os.Rename(temporary, path); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	return nil
}

func unpackEmbeddedWindowsTools() string {
	embeddedToolOnce.Do(func() {
		root, err := os.UserCacheDir()
		if err != nil || root == "" {
			return
		}
		directory := filepath.Join(root, "DriveBatteryHealthViewer", "Tools", "smartmontools-7.5")
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return
		}
		files := []struct{ source, name string }{
			{"assets/windows/smartctl.exe", "smartctl.exe"},
			{"assets/windows/drivedb.h", "drivedb.h"},
			{"assets/windows/SMARTMONTOOLS_COPYING.txt", "COPYING.txt"},
		}
		for _, file := range files {
			data, readErr := embeddedWindowsTools.ReadFile(file.source)
			if readErr != nil || len(data) == 0 {
				return
			}
			if writeErr := writeEmbeddedToolFile(filepath.Join(directory, file.name), data); writeErr != nil {
				return
			}
		}
		candidate := filepath.Join(directory, "smartctl.exe")
		if info, statErr := os.Stat(candidate); statErr == nil && info.Size() > 0 {
			embeddedToolPath = candidate
		}
	})
	return embeddedToolPath
}
