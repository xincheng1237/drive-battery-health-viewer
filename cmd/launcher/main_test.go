//go:build windows

package main

import "testing"

func TestSupportsModernVersionBoundary(t *testing.T) {
	tests := []struct {
		name        string
		major, build uint32
		want        bool
	}{
		{"Windows 7", 6, 7601, false},
		{"Windows 8.1", 6, 9600, false},
		{"Windows 10 1803", 10, 17134, false},
		{"Windows 10 1809 boundary", 10, 17763, true},
		{"Windows 11 reported as 10", 10, 26100, true},
		{"future major version", 11, 0, true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := supportsModernVersion(test.major, test.build); got != test.want {
				t.Fatalf("supportsModernVersion(%d, %d) = %v, want %v", test.major, test.build, got, test.want)
			}
		})
	}
}

func TestWantsModernIsOptIn(t *testing.T) {
	tests := []struct {
		name       string
		envModern  string
		envLegacy  string
		args       []string
		wantModern bool
		wantArgs   []string
	}{
		{name: "default compatibility shell", args: []string{"--example"}, wantArgs: []string{"--example"}},
		{name: "environment opt in", envModern: "1", args: []string{"--example"}, wantModern: true, wantArgs: []string{"--example"}},
		{name: "explicit opt in", args: []string{"--modern", "--example"}, wantModern: true, wantArgs: []string{"--example"}},
		{name: "legacy overrides modern", envModern: "1", args: []string{"--modern", "--legacy", "--example"}, wantArgs: []string{"--example"}},
		{name: "legacy flag is consumed", args: []string{"--legacy"}, wantArgs: []string{}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("DBHV_USE_MODERN", test.envModern)
			t.Setenv("DBHV_FORCE_LEGACY", test.envLegacy)
			gotModern, gotArgs := wantsModern(test.args)
			if gotModern != test.wantModern {
				t.Fatalf("wantsModern(%v) = %v, want %v", test.args, gotModern, test.wantModern)
			}
			if len(gotArgs) != len(test.wantArgs) {
				t.Fatalf("wantsModern(%v) args = %v, want %v", test.args, gotArgs, test.wantArgs)
			}
			for i := range gotArgs {
				if gotArgs[i] != test.wantArgs[i] {
					t.Fatalf("wantsModern(%v) args = %v, want %v", test.args, gotArgs, test.wantArgs)
				}
			}
		})
	}
}
