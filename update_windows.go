//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const latestReleaseAPI = "https://api.github.com/repos/xincheng1237/drive-battery-health-viewer/releases/latest"

type releaseInfo struct {
	Version     string
	URL         string
	DownloadURL string
}

type releaseAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

func windowsInstallerURL(assets []releaseAsset) string {
	for _, asset := range assets {
		name := strings.ToLower(strings.TrimSpace(asset.Name))
		if strings.HasSuffix(name, ".exe") && strings.Contains(name, "windows") && strings.Contains(name, "setup") {
			return strings.TrimSpace(asset.BrowserDownloadURL)
		}
	}
	return ""
}

func normalizedVersion(value string) string {
	value = strings.TrimSpace(value)
	value = strings.TrimPrefix(strings.TrimPrefix(value, "v"), "V")
	if index := strings.IndexAny(value, "-+"); index >= 0 {
		value = value[:index]
	}
	return strings.TrimSpace(value)
}

func versionParts(value string) ([]int, bool) {
	value = normalizedVersion(value)
	if value == "" {
		return nil, false
	}
	items := strings.Split(value, ".")
	parts := make([]int, len(items))
	for i, item := range items {
		if item == "" {
			return nil, false
		}
		number, err := strconv.Atoi(item)
		if err != nil || number < 0 {
			return nil, false
		}
		parts[i] = number
	}
	for len(parts) > 1 && parts[len(parts)-1] == 0 {
		parts = parts[:len(parts)-1]
	}
	return parts, true
}

func compareVersions(left, right string) (int, bool) {
	l, ok := versionParts(left)
	if !ok {
		return 0, false
	}
	r, ok := versionParts(right)
	if !ok {
		return 0, false
	}
	count := len(l)
	if len(r) > count {
		count = len(r)
	}
	for i := 0; i < count; i++ {
		lv, rv := 0, 0
		if i < len(l) {
			lv = l[i]
		}
		if i < len(r) {
			rv = r[i]
		}
		if lv < rv {
			return -1, true
		}
		if lv > rv {
			return 1, true
		}
	}
	return 0, true
}

func queryLatestRelease() (releaseInfo, error) {
	request, err := http.NewRequest(http.MethodGet, latestReleaseAPI, nil)
	if err != nil {
		return releaseInfo{}, err
	}
	request.Header.Set("Accept", "application/vnd.github+json")
	request.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	request.Header.Set("User-Agent", "DriveBatteryHealthViewer/"+appVersion)
	client := &http.Client{Timeout: 10 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return releaseInfo{}, err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return releaseInfo{}, fmt.Errorf("GitHub returned HTTP %d", response.StatusCode)
	}
	var payload struct {
		TagName    string         `json:"tag_name"`
		HTMLURL    string         `json:"html_url"`
		Draft      bool           `json:"draft"`
		Prerelease bool           `json:"prerelease"`
		Assets     []releaseAsset `json:"assets"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		return releaseInfo{}, err
	}
	version := normalizedVersion(payload.TagName)
	if payload.Draft || payload.Prerelease || version == "" || strings.TrimSpace(payload.HTMLURL) == "" {
		return releaseInfo{}, fmt.Errorf("latest release response is not a stable public release")
	}
	if _, ok := versionParts(version); !ok {
		return releaseInfo{}, fmt.Errorf("invalid release version %q", payload.TagName)
	}
	return releaseInfo{Version: version, URL: payload.HTMLURL, DownloadURL: windowsInstallerURL(payload.Assets)}, nil
}

func updateText(code, key string) string {
	texts := map[string]map[string]string{
		"en":    {"check": "Check for Updates...", "checking": "Checking for updates...", "failed": "Unable to check for updates. Check your internet connection and try again.", "latest": "This is the latest version (v%s).", "available": "A new version v%s is available.\r\n\r\nCurrent version: v%s\r\n\r\nDownload the Windows installer now?", "release": "A new version v%s is available.\r\n\r\nCurrent version: v%s\r\n\r\nOpen the release page?", "title": "Software Update"},
		"zh-CN": {"check": "检查更新…", "checking": "正在检查更新…", "failed": "无法检查更新，请检查网络连接后重试。", "latest": "当前已是最新版本（v%s）。", "available": "发现新版本 v%s。\r\n\r\n当前版本：v%s\r\n\r\n是否立即下载 Windows 安装包？", "release": "发现新版本 v%s。\r\n\r\n当前版本：v%s\r\n\r\n是否打开版本发布页面？", "title": "软件更新"},
		"ru":    {"check": "Проверить обновления…", "checking": "Проверка обновлений…", "failed": "Не удалось проверить обновления. Проверьте подключение к интернету и повторите попытку.", "latest": "Установлена последняя версия (v%s).", "available": "Доступна новая версия v%s.\r\n\r\nТекущая версия: v%s\r\n\r\nОткрыть страницу выпуска?", "title": "Обновление"},
		"fr":    {"check": "Rechercher les mises à jour…", "checking": "Recherche des mises à jour…", "failed": "Impossible de rechercher les mises à jour. Vérifiez votre connexion internet et réessayez.", "latest": "Vous utilisez la dernière version (v%s).", "available": "Une nouvelle version v%s est disponible.\r\n\r\nVersion actuelle : v%s\r\n\r\nOuvrir la page de publication ?", "title": "Mise à jour"},
		"de":    {"check": "Nach Updates suchen…", "checking": "Updates werden gesucht…", "failed": "Die Suche nach Updates ist fehlgeschlagen. Prüfen Sie die Internetverbindung und versuchen Sie es erneut.", "latest": "Dies ist die neueste Version (v%s).", "available": "Eine neue Version v%s ist verfügbar.\r\n\r\nAktuelle Version: v%s\r\n\r\nVersionsseite öffnen?", "title": "Softwareupdate"},
		"ko":    {"check": "업데이트 확인…", "checking": "업데이트 확인 중…", "failed": "업데이트를 확인할 수 없습니다. 인터넷 연결을 확인한 후 다시 시도하십시오.", "latest": "최신 버전입니다(v%s).", "available": "새 버전 v%s을 사용할 수 있습니다.\r\n\r\n현재 버전: v%s\r\n\r\n릴리스 페이지를 열까요?", "title": "소프트웨어 업데이트"},
		"ja":    {"check": "アップデートを確認…", "checking": "アップデートを確認中…", "failed": "アップデートを確認できません。インターネット接続を確認して、もう一度お試しください。", "latest": "最新バージョンです（v%s）。", "available": "新しいバージョン v%s が見つかりました。\r\n\r\n現在のバージョン：v%s\r\n\r\nリリースページを開きますか？", "title": "ソフトウェアアップデート"},
	}
	if values, ok := texts[code]; ok {
		if value := values[key]; value != "" {
			return value
		}
	}
	return texts["en"][key]
}

func updateNoticeText(code, key string) string {
	texts := map[string]map[string]string{
		"en":    {"message": "Updated to v1.0.6. Would you like to see what changed?", "view": "View changes", "dismiss": "Not now"},
		"zh-CN": {"message": "已更新到 v1.0.6，要看看本次改进吗？", "view": "查看更新日志", "dismiss": "暂不"},
		"ru":    {"message": "Приложение обновлено до v1.0.6. Посмотреть изменения?", "view": "Изменения", "dismiss": "Не сейчас"},
		"fr":    {"message": "Mise à jour vers v1.0.6. Voir les changements ?", "view": "Voir les nouveautés", "dismiss": "Plus tard"},
		"de":    {"message": "Auf v1.0.6 aktualisiert. Änderungen anzeigen?", "view": "Änderungen", "dismiss": "Später"},
		"ko":    {"message": "v1.0.6으로 업데이트되었습니다. 변경 사항을 볼까요?", "view": "변경 사항 보기", "dismiss": "나중에"},
		"ja":    {"message": "v1.0.6 に更新されました。変更内容を確認しますか？", "view": "更新内容を見る", "dismiss": "後で"},
	}
	if values, ok := texts[code]; ok {
		return values[key]
	}
	return texts["en"][key]
}
