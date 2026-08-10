#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
dist_dir="${project_dir}/dist"
version="1.0.6"
app_name="Drive & Battery Health Viewer"
artifact_name="DriveBatteryHealthViewer_v${version}_macOS_Universal"
volume_name="Drive & Battery Health Viewer ${version}"
archive="${dist_dir}/${artifact_name}.zip"
output="${dist_dir}/${artifact_name}.dmg"
bundle_build="7"
bundle_identifier="com.chengxin.drive-battery-health-viewer"
minimum_system="13.0"
smartctl_source_sha256="690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e"
smartctl_copying_sha256="8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643"
workspace="$(mktemp -d)"
staging_dir="${workspace}/staging"
verify_mount="${workspace}/verify"
is_mounted=0

cleanup() {
    if (( is_mounted )); then
        hdiutil detach "${verify_mount}" >/dev/null 2>&1 || true
    fi
    rm -rf "${workspace}"
}
trap cleanup EXIT

verify_minimum_system() {
    local binary="$1"
    local architecture="$2"
    local expected="$3"
    local actual
    actual="$(xcrun vtool -arch "${architecture}" -show-build "${binary}" | awk '$1 == "minos" { print $2; exit }')"
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 "Unexpected minimum macOS version for ${architecture}: ${actual:-missing} (${binary})"
        exit 1
    fi
}

if [[ "${DBHV_USE_EXISTING_ARCHIVE:-0}" != "1" ]]; then
    "${script_dir}/build-universal.sh"
fi

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
mkdir -p "${verify_mount}"
hdiutil attach -readonly -nobrowse -mountpoint "${verify_mount}" "${output}" >/dev/null
is_mounted=1

verified_app="${verify_mount}/${app_name}.app"
codesign --verify --deep --strict "${verified_app}"
verified_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${verified_app}/Contents/Info.plist")"
if [[ "${verified_version}" != "${version}" ]]; then
    print -u2 "DMG contains version ${verified_version}; expected ${version}."
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${verified_app}/Contents/Info.plist")" != "${bundle_build}" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${verified_app}/Contents/Info.plist")" != "${bundle_identifier}" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${verified_app}/Contents/Info.plist")" != "${minimum_system}" ]]; then
    print -u2 "DMG bundle metadata does not match the release manifest."
    exit 1
fi
for binary in \
    "${verified_app}/Contents/MacOS/DriveBatteryHealthViewer" \
    "${verified_app}/Contents/Helpers/smartctl"; do
    architectures="$(lipo -archs "${binary}")"
    if [[ " ${architectures} " != *" arm64 "* || " ${architectures} " != *" x86_64 "* ]]; then
        print -u2 "DMG contains a non-Universal binary: ${architectures} (${binary})"
        exit 1
    fi
done
verify_minimum_system "${verified_app}/Contents/MacOS/DriveBatteryHealthViewer" arm64 "${minimum_system}"
verify_minimum_system "${verified_app}/Contents/MacOS/DriveBatteryHealthViewer" x86_64 "${minimum_system}"
test -f "${verified_app}/Contents/Resources/ThirdParty/smartmontools/COPYING"
test -f "${verified_app}/Contents/Resources/ThirdParty/smartmontools/smartmontools-7.5.tar.gz"
test -s "${verified_app}/Contents/Resources/ThirdParty/smartmontools/NOTICE.md"
gzip -t "${verified_app}/Contents/Resources/ThirdParty/smartmontools/smartmontools-7.5.tar.gz"
if [[ "$(/usr/bin/shasum -a 256 "${verified_app}/Contents/Resources/ThirdParty/smartmontools/smartmontools-7.5.tar.gz" | awk '{print $1}')" != "${smartctl_source_sha256}" ||
      "$(/usr/bin/shasum -a 256 "${verified_app}/Contents/Resources/ThirdParty/smartmontools/COPYING" | awk '{print $1}')" != "${smartctl_copying_sha256}" ]]; then
    print -u2 "DMG contains an unexpected smartmontools source or license payload."
    exit 1
fi
verified_smartctl_version="$("${verified_app}/Contents/Helpers/smartctl" --version | head -1)"
if [[ "${verified_smartctl_version}" != *"smartctl 7.5"* || "${verified_smartctl_version}" != *"r5714"* ]]; then
    print -u2 "DMG contains an unexpected smartctl helper: ${verified_smartctl_version}"
    exit 1
fi
hdiutil detach "${verify_mount}" >/dev/null
is_mounted=0

(
    cd "${dist_dir}"
    /usr/bin/shasum -a 256 "${output:t}" > "${output:t}.sha256"
)
print "Built ${output}"
