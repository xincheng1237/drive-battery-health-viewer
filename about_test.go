package main

import (
	"fmt"
	"strings"
	"testing"
)

func TestAboutInformationAvailableInAllLocales(t *testing.T) {
	keys := []string{
		"about", "aboutAppName", "aboutSummary", "aboutVersion",
		"aboutDeveloper", "aboutDeveloperText", "aboutFeedback", "aboutFeedbackText",
		"aboutCopyright", "aboutCopyrightText",
	}
	for _, code := range localeOrder {
		l := locales[code]
		for _, key := range keys {
			if strings.TrimSpace(l.Text[key]) == "" {
				t.Fatalf("locale %s missing %s", code, key)
			}
		}
		text := l.Text["aboutDeveloperText"] + "\n" + l.Text["aboutFeedbackText"] + "\n" + l.Text["aboutCopyrightText"] + "\n" + l.Text["aboutSummary"] + "\n" + fmt.Sprintf(l.Text["aboutVersion"], appVersion)
		for _, required := range []string{"v1.0.4", "xincheng1237", "1040456137", "2680149724@qq.com"} {
			if !strings.Contains(text, required) {
				t.Fatalf("locale %s about text missing %q", code, required)
			}
		}
	}
}

func TestChineseAboutCopyrightPunctuation(t *testing.T) {
	got := locales["zh-CN"].Text["aboutCopyrightText"]
	want := "© 2026 程心，保留所有权利。"
	if got != want {
		t.Fatalf("Chinese copyright text = %q, want %q", got, want)
	}
}
