package main

import (
	"strings"
	"testing"
)

func TestChangelogContinuity(t *testing.T) {
	for _, code := range localeOrder {
		got := changelogFor(code)
		if len(got) != len(versionOrder) {
			t.Fatalf("%s: got %d versions, want %d", code, len(got), len(versionOrder))
		}
		for i, version := range got {
			if version.Version != versionOrder[i] {
				t.Fatalf("%s index %d: got %s, want %s", code, i, version.Version, versionOrder[i])
			}
			if strings.TrimSpace(version.Title) == "" || len(version.Sections) == 0 {
				t.Fatalf("%s %s incomplete", code, version.Version)
			}
			for _, section := range version.Sections {
				if strings.TrimSpace(section.Heading) == "" || len(section.Bullets) == 0 {
					t.Fatalf("%s %s has empty section", code, version.Version)
				}
			}
		}
	}
}

func TestCurrentVersionIs104(t *testing.T) {
	if appVersion != "1.0.4" {
		t.Fatalf("appVersion=%s", appVersion)
	}
}

func TestPatchVersionsAreConsolidated(t *testing.T) {
	removed := map[string]bool{
		"v1.0.3.1": true, "v1.0.3.2": true, "v1.0.3.3": true, "v1.0.3.4": true,
		"v1.0.3.5": true, "v1.0.3.6": true, "v1.0.3.7": true, "v1.0.3.8": true,
	}
	for _, code := range localeOrder {
		versions := changelogFor(code)
		if versions[0].Version != "v1.0.4" {
			t.Fatalf("%s first version=%s", code, versions[0].Version)
		}
		for _, version := range versions {
			if removed[version.Version] {
				t.Fatalf("%s still exposes consolidated patch %s", code, version.Version)
			}
		}
	}
}

func TestV104HasCompleteUserFacingSummary(t *testing.T) {
	for _, code := range localeOrder {
		versions := changelogFor(code)
		current := versions[0]
		bullets := 0
		for _, section := range current.Sections {
			bullets += len(section.Bullets)
		}
		if bullets < 6 {
			t.Fatalf("%s v1.0.4 has only %d bullets", code, bullets)
		}
	}
}

func TestChineseChangelogUsesUserFacingWording(t *testing.T) {
	forbidden := []string{
		"验证", "测试", "构建检查", "更新日志不再", "更新日志内容", "优化更新日志",
		"重构", "重做", "继续保留", "重新调整", "再次缩小", "Rich Edit",
	}
	for _, version := range changelogZH() {
		text := renderChangeVersion(version)
		for _, phrase := range forbidden {
			if strings.Contains(text, phrase) {
				t.Fatalf("%s contains forbidden wording %q", version.Version, phrase)
			}
		}
		for _, section := range version.Sections {
			heading := strings.TrimSpace(section.Heading)
			if heading == "更新日志" || heading == "验证" {
				t.Fatalf("%s contains internal section %q", version.Version, heading)
			}
		}
	}
}

func TestV101DoesNotMentionArchitectureReduction(t *testing.T) {
	for _, code := range localeOrder {
		for _, version := range changelogFor(code) {
			if version.Version != "v1.0.1" {
				continue
			}
			text := strings.ToLower(renderChangeVersion(version))
			for _, phrase := range []string{"64 位", "64-bit", "64 bit", "64-раз", "64 bits", "64비트", "64 ビット"} {
				if strings.Contains(text, strings.ToLower(phrase)) {
					t.Fatalf("%s v1.0.1 still mentions architecture reduction: %q", code, phrase)
				}
			}
		}
	}
}

func TestLanguageSettingPreservesExplicitChoice(t *testing.T) {
	old := currentSettings()
	defer func() { settingsMu.Lock(); settings = old; settingsMu.Unlock() }()
	settingsMu.Lock()
	settings.Language = "ja"
	settingsMu.Unlock()
	if effectiveLocale() != "ja" {
		t.Fatal(effectiveLocale())
	}
	settingsMu.Lock()
	settings.Language = languageSystem
	settingsMu.Unlock()
	if effectiveLocale() == "" {
		t.Fatal("system locale empty")
	}
}
