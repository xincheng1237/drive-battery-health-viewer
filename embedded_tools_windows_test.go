//go:build windows

package main

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestUnpackEmbeddedWindowsTools(t *testing.T) {
	t.Setenv("LocalAppData", t.TempDir())
	embeddedToolOnce = sync.Once{}
	embeddedToolPath = ""
	path := unpackEmbeddedWindowsTools()
	if path == "" {
		t.Fatal("embedded smartctl path is empty")
	}
	for _, name := range []string{"smartctl.exe", "drivedb.h", "COPYING.txt"} {
		info, err := os.Stat(filepath.Join(filepath.Dir(path), name))
		if err != nil {
			t.Fatalf("missing extracted %s: %v", name, err)
		}
		if info.Size() == 0 {
			t.Fatalf("extracted %s is empty", name)
		}
	}
}
