#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
repo_dir="${project_dir:h}"
dist_dir="${project_dir}/dist"
staging_dir="$(mktemp -d)"
version="1.0.5"
app_name="Drive & Battery Health Viewer"
executable_name="DriveBatteryHealthViewer"

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
        -c release \
        --triple "${triple}" \
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
    mkdir -p "${bundle_path}/Contents/MacOS" "${bundle_path}/Contents/Resources"
    cp "${project_dir}/Info.plist" "${bundle_path}/Contents/Info.plist"
    cp "${binary_file}" "${bundle_path}/Contents/MacOS/${executable_name}"
    cp "${staging_dir}/AppIcon.icns" "${bundle_path}/Contents/Resources/AppIcon.icns"
    chmod 755 "${bundle_path}/Contents/MacOS/${executable_name}"
    xattr -cr "${bundle_path}"
    xattr -d com.apple.FinderInfo "${bundle_path}" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "${bundle_path}" 2>/dev/null || true
    codesign --force --deep --sign - "${bundle_path}"
}

mkdir -p "${dist_dir}"
build_architecture arm64
build_architecture x86_64
make_icon

arm_binary="$(binary_path arm64)"
intel_binary="$(binary_path x86_64)"
if [[ -z "${arm_binary}" || -z "${intel_binary}" ]]; then
    print -u2 "Could not locate one or both release binaries."
    exit 1
fi

universal_app="${staging_dir}/${app_name}.app"

universal_binary="${staging_dir}/${executable_name}-universal"
lipo -create "${arm_binary}" "${intel_binary}" -output "${universal_binary}"
make_app_bundle "${universal_app}" "${universal_binary}"

codesign --verify --deep --strict "${universal_app}"
archive="${dist_dir}/${app_name}-${version}-macOS-Universal.zip"
ditto -c -k --sequesterRsrc --keepParent "${universal_app}" "${archive}"

lipo -info "${universal_app}/Contents/MacOS/${executable_name}"
plutil -lint "${universal_app}/Contents/Info.plist"
print "Built macOS release artifacts in ${dist_dir}"
