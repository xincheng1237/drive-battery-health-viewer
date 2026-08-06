#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
dist_dir="${project_dir}/dist"
version="1.0.5"
app_name="Drive & Battery Health Viewer"
volume_name="Drive & Battery Health Viewer ${version}"
archive="${dist_dir}/${app_name}-${version}-macOS-Universal.zip"
output="${dist_dir}/${app_name}-${version}-macOS-Universal.dmg"
workspace="$(mktemp -d)"
staging_dir="${workspace}/staging"

cleanup() {
    rm -rf "${workspace}"
}
trap cleanup EXIT

if [[ ! -f "${archive}" ]]; then
    print -u2 "Missing Universal archive: ${archive}"
    print -u2 "Run macos/scripts/build-universal.sh first."
    exit 2
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    print -u2 "Missing create-dmg. Install it with: brew install create-dmg"
    exit 3
fi

mkdir -p "${staging_dir}"
ditto -x -k "${archive}" "${staging_dir}"

tool_cache="${project_dir}/.build-tools/module-cache"
mkdir -p "${tool_cache}"
CLANG_MODULE_CACHE_PATH="${tool_cache}" SWIFT_MODULECACHE_PATH="${tool_cache}" \
    swift "${script_dir}/RenderDMGBackground.swift" \
        "${workspace}/background.png" \
        "${workspace}/background@2x.png" \
        "${version}"
tiffutil -cathidpicheck \
    "${workspace}/background.png" \
    "${workspace}/background@2x.png" \
    -out "${workspace}/background.tiff" >/dev/null
xattr -cr "${staging_dir}/${app_name}.app"

create-dmg \
    --volname "${volume_name}" \
    --volicon "${staging_dir}/${app_name}.app/Contents/Resources/AppIcon.icns" \
    --background "${workspace}/background.tiff" \
    --window-pos 200 200 \
    --window-size 720 450 \
    --text-size 12 \
    --icon-size 128 \
    --icon "${app_name}.app" 190 212 \
    --hide-extension "${app_name}.app" \
    --app-drop-link 530 212 \
    --format UDZO \
    --filesystem HFS+ \
    --no-internet-enable \
    --overwrite \
    "${output}" \
    "${staging_dir}"

hdiutil verify "${output}" >/dev/null
print "Built ${output}"
