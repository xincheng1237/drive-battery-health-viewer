#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
dist_dir="${project_dir}/dist"
resources_dir="${project_dir}/Resources/DMG"
version="1.0.4"
app_name="Drive & Battery Health Viewer"
volume_name="Drive & Battery Health Viewer"
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

if [[ ! -f "${resources_dir}/FinderLayout.dsstore" ]]; then
    print -u2 "Missing Finder layout template: ${resources_dir}/FinderLayout.dsstore"
    exit 3
fi

mkdir -p "${staging_dir}/.background"
ditto -x -k "${archive}" "${staging_dir}"
ln -s /Applications "${staging_dir}/Applications"

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
    -out "${staging_dir}/.background/dbhv-dmg-background.tiff" >/dev/null

cp "${resources_dir}/FinderLayout.dsstore" "${staging_dir}/.DS_Store"
cp "${staging_dir}/${app_name}.app/Contents/Resources/AppIcon.icns" "${staging_dir}/.VolumeIcon.icns"
SetFile -a V "${staging_dir}/.background" "${staging_dir}/.VolumeIcon.icns"
SetFile -a C "${staging_dir}"
xattr -cr "${staging_dir}/${app_name}.app"

rm -f "${output}"
hdiutil create \
    -ov \
    -volname "${volume_name}" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -srcfolder "${staging_dir}" \
    "${output}" >/dev/null

hdiutil verify "${output}" >/dev/null
print "Built ${output}"
