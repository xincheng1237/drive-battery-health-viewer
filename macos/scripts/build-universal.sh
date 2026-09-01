#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
repo_dir="${project_dir:h}"
dist_dir="${project_dir}/dist"
staging_dir="$(mktemp -d)"
version="1.1.0"
app_name="Drive & Battery Health Viewer"
artifact_name="DriveBatteryHealthViewer_v${version}_macOS_Universal"
executable_name="DriveBatteryHealthViewer"
bundle_build="9"
charge_helper_name="DriveBatteryChargeHelper"
charge_limit_agent_name="DriveBatteryChargeLimitAgent"
bundle_identifier="com.chengxin.drive-battery-health-viewer"
minimum_system="13.0"
smartctl_sha256="5d8a03980cba1799a94f7f9740827a6d058062aa78805c8c29c22918b34257a8"
smartctl_source_sha256="690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e"
smartctl_copying_sha256="8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643"

cleanup() {
    rm -rf "${staging_dir}"
}
trap cleanup EXIT

build_architecture() {
    local architecture="$1"
    local triple="${architecture}-apple-macosx13.0"
    local scratch_dir="${project_dir}/.build-${architecture}"
    mkdir -p "${scratch_dir}/module-cache" "${scratch_dir}/cache" "${scratch_dir}/config" "${scratch_dir}/security"
    CLANG_MODULE_CACHE_PATH="${scratch_dir}/module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="${scratch_dir}/module-cache" \
    swift build \
        --package-path "${project_dir}" \
        --product "${executable_name}" \
        -c release \
        --triple "${triple}" \
        --disable-sandbox \
        --cache-path "${scratch_dir}/cache" \
        --config-path "${scratch_dir}/config" \
        --security-path "${scratch_dir}/security" \
        --scratch-path "${scratch_dir}"
}

build_charge_helper() {
    local scratch_dir="${project_dir}/.build-charge-helper"
    mkdir -p "${scratch_dir}/module-cache" "${scratch_dir}/cache" "${scratch_dir}/config" "${scratch_dir}/security"
    CLANG_MODULE_CACHE_PATH="${scratch_dir}/module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="${scratch_dir}/module-cache" \
    swift build \
        --package-path "${project_dir}" \
        --product "${charge_helper_name}" \
        -c release \
        --triple "arm64-apple-macosx13.0" \
        --disable-sandbox \
        --cache-path "${scratch_dir}/cache" \
        --config-path "${scratch_dir}/config" \
        --security-path "${scratch_dir}/security" \
        --scratch-path "${scratch_dir}"
}

build_charge_limit_agent() {
    local scratch_dir="${project_dir}/.build-charge-limit-agent"
    mkdir -p "${scratch_dir}/module-cache" "${scratch_dir}/cache" "${scratch_dir}/config" "${scratch_dir}/security"
    CLANG_MODULE_CACHE_PATH="${scratch_dir}/module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="${scratch_dir}/module-cache" \
    swift build \
        --package-path "${project_dir}" \
        --product "${charge_limit_agent_name}" \
        -c release \
        --triple "arm64-apple-macosx13.0" \
        --disable-sandbox \
        --cache-path "${scratch_dir}/cache" \
        --config-path "${scratch_dir}/config" \
        --security-path "${scratch_dir}/security" \
        --scratch-path "${scratch_dir}"
}

binary_path() {
    local architecture="$1"
    find "${project_dir}/.build-${architecture}" -type f -path "*/release/${executable_name}" -perm -111 -print -quit
}

make_icon() {
    local iconset_dir="${staging_dir}/AppIcon.iconset"
    local source_file="${project_dir}/Resources/AppIcon.png"
    local padded_source="${staging_dir}/AppIcon-padded.png"
    local tool_cache="${project_dir}/.build-tools/module-cache"
    mkdir -p "${iconset_dir}" "${tool_cache}"
    CLANG_MODULE_CACHE_PATH="${tool_cache}" SWIFT_MODULECACHE_PATH="${tool_cache}" \
        swift "${script_dir}/PrepareAppIcon.swift" "${source_file}" "${padded_source}"
    sips -z 16 16 "${padded_source}" --out "${iconset_dir}/icon_16x16.png" >/dev/null
    sips -z 32 32 "${padded_source}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "${padded_source}" --out "${iconset_dir}/icon_32x32.png" >/dev/null
    sips -z 64 64 "${padded_source}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "${padded_source}" --out "${iconset_dir}/icon_128x128.png" >/dev/null
    sips -z 256 256 "${padded_source}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "${padded_source}" --out "${iconset_dir}/icon_256x256.png" >/dev/null
    sips -z 512 512 "${padded_source}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "${padded_source}" --out "${iconset_dir}/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "${padded_source}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null
    CLANG_MODULE_CACHE_PATH="${tool_cache}" SWIFT_MODULECACHE_PATH="${tool_cache}" \
        swift "${script_dir}/CreateICNS.swift" "${iconset_dir}" "${staging_dir}/AppIcon.icns"
}

make_app_bundle() {
    local bundle_path="$1"
    local binary_file="$2"
    mkdir -p \
        "${bundle_path}/Contents/MacOS" \
        "${bundle_path}/Contents/Helpers" \
        "${bundle_path}/Contents/Resources/ThirdParty" \
        "${bundle_path}/Contents/Resources/ChargeProtection"
    cp "${project_dir}/Info.plist" "${bundle_path}/Contents/Info.plist"
    cp "${binary_file}" "${bundle_path}/Contents/MacOS/${executable_name}"
    cp "${project_dir}/Resources/Tools/smartctl" "${bundle_path}/Contents/Helpers/smartctl"
    cp "${charge_helper_binary}" "${bundle_path}/Contents/Helpers/${charge_helper_name}"
    cp "${charge_limit_agent_binary}" "${bundle_path}/Contents/Helpers/${charge_limit_agent_name}"
    cp -R "${project_dir}/Resources/ThirdParty/smartmontools" "${bundle_path}/Contents/Resources/ThirdParty/"
    cp -R "${project_dir}/Resources/ThirdParty/ChargeWatch" "${bundle_path}/Contents/Resources/ThirdParty/"
    cp "${project_dir}/Resources/ChargeProtection/install-charge-helper.sh" "${bundle_path}/Contents/Resources/ChargeProtection/"
    cp "${project_dir}/Resources/ChargeProtection/install-charge-limit-agent.sh" "${bundle_path}/Contents/Resources/ChargeProtection/"
    cp "${staging_dir}/AppIcon.icns" "${bundle_path}/Contents/Resources/AppIcon.icns"
    local localization_dir
    for localization_dir in "${project_dir}"/Resources/*.lproj; do
        cp -R "${localization_dir}" "${bundle_path}/Contents/Resources/"
    done
    chmod 755 \
        "${bundle_path}/Contents/MacOS/${executable_name}" \
        "${bundle_path}/Contents/Helpers/smartctl" \
        "${bundle_path}/Contents/Helpers/${charge_helper_name}" \
        "${bundle_path}/Contents/Helpers/${charge_limit_agent_name}" \
        "${bundle_path}/Contents/Resources/ChargeProtection/install-charge-helper.sh" \
        "${bundle_path}/Contents/Resources/ChargeProtection/install-charge-limit-agent.sh"
    xattr -cr "${bundle_path}"
    xattr -d com.apple.FinderInfo "${bundle_path}" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "${bundle_path}" 2>/dev/null || true
    codesign --force --sign - "${bundle_path}/Contents/Helpers/smartctl"
    codesign --force --sign - --identifier com.chengxin.drivebatteryhealthviewer.chargehelper "${bundle_path}/Contents/Helpers/${charge_helper_name}"
    codesign --force --sign - --identifier com.chengxin.drivebatteryhealthviewer.chargelimitagent "${bundle_path}/Contents/Helpers/${charge_limit_agent_name}"
    codesign --force --sign - "${bundle_path}"
}

verify_sha256() {
    local expected="$1"
    local file="$2"
    local actual
    actual="$(/usr/bin/shasum -a 256 "${file}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 "SHA-256 mismatch for ${file}: ${actual}"
        exit 1
    fi
}

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

mkdir -p "${dist_dir}"
verify_sha256 "${smartctl_sha256}" "${project_dir}/Resources/Tools/smartctl"
verify_sha256 "${smartctl_source_sha256}" "${project_dir}/Resources/ThirdParty/smartmontools/smartmontools-7.5.tar.gz"
verify_sha256 "${smartctl_copying_sha256}" "${project_dir}/Resources/ThirdParty/smartmontools/COPYING"
smartctl_version="$("${project_dir}/Resources/Tools/smartctl" --version | head -1)"
if [[ "${smartctl_version}" != *"smartctl 7.5"* || "${smartctl_version}" != *"r5714"* ]]; then
    print -u2 "Unexpected bundled smartctl version: ${smartctl_version}"
    exit 1
fi
build_architecture arm64
build_architecture x86_64
build_charge_helper
build_charge_limit_agent
make_icon

arm_binary="$(binary_path arm64)"
intel_binary="$(binary_path x86_64)"
charge_helper_binary="$(find "${project_dir}/.build-charge-helper" -type f -path "*/release/${charge_helper_name}" -perm -111 -print -quit)"
charge_limit_agent_binary="$(find "${project_dir}/.build-charge-limit-agent" -type f -path "*/release/${charge_limit_agent_name}" -perm -111 -print -quit)"
if [[ -z "${arm_binary}" || -z "${intel_binary}" || -z "${charge_helper_binary}" || -z "${charge_limit_agent_binary}" ]]; then
    print -u2 "Could not locate one or both release binaries."
    exit 1
fi

universal_app="${staging_dir}/${app_name}.app"

universal_binary="${staging_dir}/${executable_name}-universal"
lipo -create "${arm_binary}" "${intel_binary}" -output "${universal_binary}"
make_app_bundle "${universal_app}" "${universal_binary}"

codesign --verify --deep --strict "${universal_app}"
for binary in \
    "${universal_app}/Contents/MacOS/${executable_name}" \
    "${universal_app}/Contents/Helpers/smartctl"; do
    architectures="$(lipo -archs "${binary}")"
    if [[ " ${architectures} " != *" arm64 "* || " ${architectures} " != *" x86_64 "* ]]; then
        print -u2 "Expected a Universal 2 binary, found: ${architectures} (${binary})"
        exit 1
    fi
done
if [[ "$(lipo -archs "${universal_app}/Contents/Helpers/${charge_helper_name}")" != "arm64" ]]; then
    print -u2 "Charge helper must be arm64-only."
    exit 1
fi
if [[ "$(lipo -archs "${universal_app}/Contents/Helpers/${charge_limit_agent_name}")" != "arm64" ]]; then
    print -u2 "Charge-limit menu-bar agent must be arm64-only."
    exit 1
fi
helper_identifier=$(/usr/bin/codesign -dv "${universal_app}/Contents/Helpers/${charge_helper_name}" 2>&1 | awk -F= '$1 == "Identifier" { print $2; exit }')
if [[ "${helper_identifier}" != "com.chengxin.drivebatteryhealthviewer.chargehelper" ]]; then
    print -u2 "Charge helper has an unexpected code-signing identifier."
    exit 1
fi
agent_identifier=$(/usr/bin/codesign -dv "${universal_app}/Contents/Helpers/${charge_limit_agent_name}" 2>&1 | awk -F= '$1 == "Identifier" { print $2; exit }')
if [[ "${agent_identifier}" != "com.chengxin.drivebatteryhealthviewer.chargelimitagent" ]]; then
    print -u2 "Charge-limit menu-bar agent has an unexpected code-signing identifier."
    exit 1
fi
verify_minimum_system "${universal_app}/Contents/MacOS/${executable_name}" arm64 "${minimum_system}"
verify_minimum_system "${universal_app}/Contents/MacOS/${executable_name}" x86_64 "${minimum_system}"

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${universal_app}/Contents/Info.plist")"
if [[ "${bundle_version}" != "${version}" ]]; then
    print -u2 "Bundle version ${bundle_version} does not match release version ${version}."
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${universal_app}/Contents/Info.plist")" != "${bundle_build}" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${universal_app}/Contents/Info.plist")" != "${bundle_identifier}" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${universal_app}/Contents/Info.plist")" != "${minimum_system}" ]]; then
    print -u2 "Bundle metadata does not match the 1.1.0 release manifest."
    exit 1
fi

archive="${dist_dir}/${artifact_name}.zip"
temporary_archive="${staging_dir}/${artifact_name}.zip"
find "${universal_app}" -name '._*' -delete
archive_staging="${staging_dir}/archive"
mkdir -p "${archive_staging}"
COPYFILE_DISABLE=1 cp -R -X "${universal_app}" "${archive_staging}/"
find "${archive_staging}" -name '._*' -delete
(
    cd "${archive_staging}"
    /usr/bin/zip -q -r -y "${temporary_archive}" "${app_name}.app"
)
mv -f "${temporary_archive}" "${archive}"
(
    cd "${dist_dir}"
    /usr/bin/shasum -a 256 "${archive:t}" > "${archive:t}.sha256"
)

lipo -info "${universal_app}/Contents/MacOS/${executable_name}"
plutil -lint "${universal_app}/Contents/Info.plist"
test -f "${universal_app}/Contents/Resources/ThirdParty/ChargeWatch/LICENSE"
test -f "${universal_app}/Contents/Resources/ThirdParty/ChargeWatch/NOTICE.md"
test -x "${universal_app}/Contents/Resources/ChargeProtection/install-charge-helper.sh"
test -x "${universal_app}/Contents/Resources/ChargeProtection/install-charge-limit-agent.sh"
print "Built macOS release artifacts in ${dist_dir}"
