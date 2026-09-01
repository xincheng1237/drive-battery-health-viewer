#!/bin/sh
set -eu

identifier="com.chengxin.drivebatteryhealthviewer.chargelimitagent"
uid="$(id -u)"
user_domain="gui/${uid}"
installation_directory="${HOME}/Library/Application Support/DriveBatteryHealthViewer/ChargeLimitAgent"
agent_app="${installation_directory}/DriveBatteryChargeLimitAgent.app"
destination="${agent_app}/Contents/MacOS/DriveBatteryChargeLimitAgent"
legacy_destination="${installation_directory}/DriveBatteryChargeLimitAgent"
launch_agents_directory="${HOME}/Library/LaunchAgents"
plist="${launch_agents_directory}/${identifier}.plist"
lock_path="${installation_directory}/instance.lock"
source_fingerprint_path="${agent_app}/Contents/Resources/source.sha256"

if [ "${uid}" -eq 0 ]; then
    echo "The menu-bar agent installer must not run as root." >&2
    exit 1
fi

unload() {
    /bin/launchctl bootout "${user_domain}/${identifier}" >/dev/null 2>&1 || true
    /bin/launchctl bootout "${user_domain}" "${plist}" >/dev/null 2>&1 || true
    # Also remove an older copy started directly through LaunchServices. Such a
    # process is not owned by this LaunchAgent job and otherwise survives a
    # bootout, producing a second status item after an upgrade. Match full
    # executable paths because macOS process names may be truncated and cannot
    # reliably match this long executable name with pgrep/pkill -x.
    /usr/bin/pkill -TERM -f -u "${uid}" "${destination}$" >/dev/null 2>&1 || true
    /usr/bin/pkill -TERM -f -u "${uid}" "${legacy_destination}$" >/dev/null 2>&1 || true
    remaining=0
    while /usr/bin/pgrep -f -u "${uid}" "${destination}$" >/dev/null 2>&1 ||
          /usr/bin/pgrep -f -u "${uid}" "${legacy_destination}$" >/dev/null 2>&1; do
        remaining=$((remaining + 1))
        [ "${remaining}" -lt 10 ] || break
        /bin/sleep 0.05
    done
    /usr/bin/pkill -KILL -f -u "${uid}" "${destination}$" >/dev/null 2>&1 || true
    /usr/bin/pkill -KILL -f -u "${uid}" "${legacy_destination}$" >/dev/null 2>&1 || true
}

case "${1:-}" in
    install)
        source="${2:-}"
        [ -f "${source}" ] && [ ! -L "${source}" ] || {
            echo "Invalid menu-bar agent source." >&2
            exit 1
        }
        /usr/bin/codesign --verify --strict "${source}"
        source_identifier=$(/usr/bin/codesign -dv "${source}" 2>&1 | /usr/bin/awk -F= '$1 == "Identifier" { print $2; exit }')
        [ "${source_identifier}" = "${identifier}" ] || {
            echo "Unexpected menu-bar agent code-signing identifier." >&2
            exit 1
        }
        source_fingerprint=$(/usr/bin/shasum -a 256 "${source}" | /usr/bin/awk '{ print $1 }')

        # Reinstalling an identical, already running agent would briefly remove
        # its status item and lose the user's menu-bar placement. Leave a healthy
        # current installation untouched on ordinary app launches.
        running_count=$(/usr/bin/pgrep -f -u "${uid}" "${destination}$" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        legacy_running_count=$(/usr/bin/pgrep -f -u "${uid}" "${legacy_destination}$" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        if [ "${running_count}" = "1" ] && [ "${legacy_running_count}" = "0" ] &&
           [ -f "${destination}" ] && [ ! -L "${destination}" ] &&
           [ -f "${plist}" ] && [ ! -L "${plist}" ] &&
           [ -f "${source_fingerprint_path}" ] && [ ! -L "${source_fingerprint_path}" ] &&
           [ "$(/bin/cat "${source_fingerprint_path}")" = "${source_fingerprint}" ] &&
           /usr/bin/plutil -lint "${plist}" >/dev/null 2>&1 &&
           /bin/launchctl print "${user_domain}/${identifier}" >/dev/null 2>&1; then
            exit 0
        fi

        /bin/mkdir -p "${installation_directory}" "${launch_agents_directory}"
        /bin/chmod 0700 "${installation_directory}"
        temporary_app=$(/usr/bin/mktemp -d "${installation_directory}/.agent-app.XXXXXX")
        temporary_plist=$(/usr/bin/mktemp "${launch_agents_directory}/.${identifier}.XXXXXX")
        cleanup() { /bin/rm -rf "${temporary_app:-}"; /bin/rm -f "${temporary_plist:-}"; }
        trap cleanup EXIT HUP INT TERM
        /bin/mkdir -p "${temporary_app}/Contents/MacOS" "${temporary_app}/Contents/Resources"
        /usr/bin/install -m 0755 "${source}" "${temporary_app}/Contents/MacOS/DriveBatteryChargeLimitAgent"
        /usr/bin/printf '%s' "${source_fingerprint}" > "${temporary_app}/Contents/Resources/source.sha256"
        /bin/chmod 0600 "${temporary_app}/Contents/Resources/source.sha256"
        /usr/bin/plutil -create xml1 "${temporary_app}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${identifier}" "${temporary_app}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Add :CFBundleName string DriveBatteryChargeLimitAgent' "${temporary_app}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string DriveBatteryChargeLimitAgent' "${temporary_app}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "${temporary_app}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "${temporary_app}/Contents/Info.plist"
        /usr/bin/codesign --force --sign - --identifier "${identifier}" "${temporary_app}"

        /usr/bin/plutil -create xml1 "${temporary_plist}"
        /usr/libexec/PlistBuddy -c "Add :Label string ${identifier}" "${temporary_plist}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "${temporary_plist}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${destination}" "${temporary_plist}"
        /usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "${temporary_plist}"
        /usr/libexec/PlistBuddy -c 'Add :KeepAlive bool true' "${temporary_plist}"
        /usr/libexec/PlistBuddy -c 'Add :ProcessType string Interactive' "${temporary_plist}"
        /usr/bin/plutil -lint "${temporary_plist}" >/dev/null
        /bin/chmod 0600 "${temporary_plist}"

        unload
        # Only after the old process has stopped do we destroy its bundle and
        # launch metadata. The new generation is then moved into place as one
        # complete signed bundle, so two agent versions can never coexist.
        /bin/rm -rf "${agent_app}"
        /bin/rm -f "${legacy_destination}" "${plist}"
        /bin/mv "${temporary_app}" "${agent_app}"
        /bin/mv -f "${temporary_plist}" "${plist}"
        /usr/bin/codesign --verify --deep --strict "${agent_app}"
        [ "$(/bin/cat "${source_fingerprint_path}")" = "${source_fingerprint}" ] || {
            echo "Installed menu-bar agent fingerprint does not match the bundled agent." >&2
            exit 1
        }
        /bin/launchctl enable "${user_domain}/${identifier}"
        /bin/launchctl bootstrap "${user_domain}" "${plist}"
        # RunAtLoad and KeepAlive start the freshly bootstrapped job. Forcing an
        # immediate `kickstart -k` kills that first process during AppKit /
        # LaunchServices registration; on macOS 15.8 its replacement can remain
        # alive without ever receiving a usable status-item launch callback.
        # Let bootstrap own the one clean initial launch.
        started=0
        attempts=0
        while [ "${attempts}" -lt 20 ]; do
            running_count=$(/usr/bin/pgrep -f -u "${uid}" "${destination}$" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
            if [ "${running_count}" = "1" ] &&
               /bin/launchctl print "${user_domain}/${identifier}" >/dev/null 2>&1; then
                started=1
                break
            fi
            attempts=$((attempts + 1))
            /bin/sleep 0.1
        done
        [ "${started}" = "1" ] || {
            echo "The menu-bar agent did not start cleanly." >&2
            exit 1
        }
        ;;
    uninstall)
        unload
        /bin/rm -f "${plist}" "${legacy_destination}" "${lock_path}"
        /bin/rm -rf "${agent_app}"
        # This directory is dedicated to this app's Agent. Removing it as one
        # exact path also clears interrupted-install staging directories from
        # older builds without touching the sibling user configuration.
        /bin/rm -rf "${installation_directory}"
        if /usr/bin/pgrep -f -u "${uid}" "${destination}$" >/dev/null 2>&1 ||
           /usr/bin/pgrep -f -u "${uid}" "${legacy_destination}$" >/dev/null 2>&1 ||
           /bin/launchctl print "${user_domain}/${identifier}" >/dev/null 2>&1 ||
           [ -e "${plist}" ] || [ -e "${installation_directory}" ]; then
            echo "The menu-bar charge Agent could not be removed completely." >&2
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 install AGENT | uninstall" >&2
        exit 2
        ;;
esac
