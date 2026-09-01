#!/bin/sh
set -eu

identifier="com.chengxin.drivebatteryhealthviewer.chargehelper"
helper_destination="/Library/PrivilegedHelperTools/${identifier}"
plist_destination="/Library/LaunchDaemons/${identifier}.plist"
state_directory="/Library/Application Support/DriveBatteryHealthViewer/ChargeProtection"
status_path="${state_directory}/status.json"
log_directory="/Library/Logs/DriveBatteryHealthViewer"
log_path="${log_directory}/charge-helper.jsonl"

if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must run as root." >&2
    exit 1
fi

restore_charging() {
    fallback_config_path="${1:-}"
    fallback_owner_uid="${2:-}"
    if [ -x "${helper_destination}" ] && [ -f "${plist_destination}" ]; then
        config_path=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "${plist_destination}" 2>/dev/null || true)
        owner_uid=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:8' "${plist_destination}" 2>/dev/null || true)
        [ -n "${config_path}" ] || config_path="${fallback_config_path}"
        [ -n "${owner_uid}" ] || owner_uid="${fallback_owner_uid}"
        if [ -n "${config_path}" ] && [ -n "${owner_uid}" ]; then
            "${helper_destination}" --config "${config_path}" --status "${status_path}" --log "${log_path}" --owner-uid "${owner_uid}" --restore-only
            return 0
        fi
    elif [ -x "${helper_destination}" ] && [ -n "${fallback_config_path}" ] && [ -n "${fallback_owner_uid}" ]; then
        "${helper_destination}" --config "${fallback_config_path}" --status "${status_path}" --log "${log_path}" --owner-uid "${fallback_owner_uid}" --restore-only
        return 0
    elif [ ! -x "${helper_destination}" ] && [ ! -e "${state_directory}/powerui-owner.json" ]; then
        return 0
    fi
    echo "Normal charging could not be verified; installed components were preserved." >&2
    return 1
}

case "${1:-}" in
    install)
        installation_complete=0
        cleanup_install() {
            rm -f "${plist_temporary:-}" "${helper_temporary:-}"
            if [ "${installation_complete}" -ne 1 ]; then
                launchctl bootout system/"${identifier}" >/dev/null 2>&1 || true
                rm -f "${plist_destination}" "${helper_destination}"
            fi
        }
        helper_source="${2:-}"
        owner_uid="${3:-}"
        owner_home="${4:-}"
        config_path="${5:-}"
        application_path="${6:-}"
        case "${owner_uid}" in *[!0-9]*|'') echo "Invalid owner UID." >&2; exit 1;; esac
        [ "${owner_uid}" -ge 500 ] || { echo "Invalid owner UID." >&2; exit 1; }
        [ -d "${owner_home}" ] && [ ! -L "${owner_home}" ] || { echo "Invalid home directory." >&2; exit 1; }
        home_owner=$(stat -f '%u' "${owner_home}")
        [ "${home_owner}" = "${owner_uid}" ] || { echo "Home directory ownership mismatch." >&2; exit 1; }
        case "${config_path}" in "${owner_home}"/*) ;; *) echo "Configuration path is outside the user home." >&2; exit 1;; esac
        case "${application_path}" in /*.app) ;; *) echo "Invalid application path." >&2; exit 1;; esac
        [ -d "${application_path}" ] && [ ! -L "${application_path}" ] || { echo "Application bundle is unavailable." >&2; exit 1; }
        application_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${application_path}/Contents/Info.plist" 2>/dev/null || true)
        [ "${application_identifier}" = "com.chengxin.drive-battery-health-viewer" ] || { echo "Unexpected application identifier." >&2; exit 1; }
        [ -f "${helper_source}" ] && [ ! -L "${helper_source}" ] || { echo "Invalid helper source." >&2; exit 1; }
        [ -f "${config_path}" ] && [ ! -L "${config_path}" ] || { echo "Invalid configuration file." >&2; exit 1; }
        config_owner=$(stat -f '%u' "${config_path}")
        config_mode=$(stat -f '%Lp' "${config_path}")
        [ "${config_owner}" = "${owner_uid}" ] && [ "${config_mode}" = "600" ] || { echo "Unsafe configuration permissions." >&2; exit 1; }

        # A drag replacement of the main application cannot replace this
        # root-owned component. Before installing a newer bundled helper,
        # explicitly put the old helper into its safe charging state, stop its
        # LaunchDaemon, and remove both old launch metadata and executable.
        # This prevents an old mapped process and a new process from controlling
        # the SMC at the same time during an upgrade.
        restore_charging
        launchctl bootout system/"${identifier}" >/dev/null 2>&1 || true
        rm -f "${plist_destination}" "${helper_destination}"

        mkdir -p "/Library/PrivilegedHelperTools" "${state_directory}" "${log_directory}"
        chown root:wheel "${state_directory}" "${log_directory}"
        chmod 755 "${state_directory}" "${log_directory}"
        helper_temporary=$(mktemp "/Library/PrivilegedHelperTools/.${identifier}.XXXXXX")
        trap cleanup_install EXIT
        trap 'exit 1' HUP INT TERM
        install -o root -g wheel -m 0500 "${helper_source}" "${helper_temporary}"
        /usr/bin/codesign --verify --strict "${helper_temporary}"
        helper_identifier=$(/usr/bin/codesign -dv "${helper_temporary}" 2>&1 | /usr/bin/awk -F= '$1 == "Identifier" { print $2; exit }')
        [ "${helper_identifier}" = "${identifier}" ] || { echo "Unexpected helper code-signing identifier." >&2; exit 1; }
        chmod 0555 "${helper_temporary}"
        mv -f "${helper_temporary}" "${helper_destination}"
        cmp -s "${helper_source}" "${helper_destination}" || {
            echo "Installed helper does not exactly match the bundled helper." >&2
            exit 1
        }
        /usr/bin/codesign --verify --strict "${helper_destination}"

        plist_temporary=$(mktemp "/tmp/${identifier}.XXXXXX")
        # mktemp creates a zero-byte file. PlistBuddy cannot clear or edit that
        # file until it contains a valid property-list root dictionary.
        /usr/bin/plutil -create xml1 "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :Label string ${identifier}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string ${helper_destination}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:1 string --config' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string ${config_path}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:3 string --status' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:4 string ${status_path}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:5 string --log' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:6 string ${log_path}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:7 string --owner-uid' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:8 string ${owner_uid}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:9 string --application' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c "Add :ProgramArguments:10 string ${application_path}" "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :KeepAlive dict' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :KeepAlive:SuccessfulExit bool false' "${plist_temporary}"
        /usr/libexec/PlistBuddy -c 'Add :ProcessType string Background' "${plist_temporary}"
        plutil -lint "${plist_temporary}" >/dev/null

        install -o root -g wheel -m 0644 "${plist_temporary}" "${plist_destination}"
        launchctl bootstrap system "${plist_destination}"
        launchctl print system/"${identifier}" >/dev/null
        # RunAtLoad starts the helper as part of a successful bootstrap.  Do
        # not immediately issue enable/kickstart as a second registration
        # operation: on some macOS releases launchd briefly reports the newly
        # bootstrapped label as unavailable even though the job is already
        # running, which made a successful upgrade look like a failure.
        installation_complete=1
        ;;
    uninstall)
        fallback_config_path="${2:-}"
        fallback_owner_uid="${3:-}"
        launchctl bootout system/"${identifier}" >/dev/null 2>&1 || true
        restore_charging "${fallback_config_path}" "${fallback_owner_uid}"
        rm -f \
            "${plist_destination}" \
            "${helper_destination}" \
            "${status_path}" \
            "${state_directory}/powerui-owner.json" \
            "${log_path}"
        if launchctl print system/"${identifier}" >/dev/null 2>&1; then
            echo "The charge helper launchd job is still registered." >&2
            exit 1
        fi
        [ ! -e "${plist_destination}" ] && [ ! -e "${helper_destination}" ] || {
            echo "The charge helper could not be removed completely." >&2
            exit 1
        }
        rmdir "${state_directory}" >/dev/null 2>&1 || true
        rmdir "${log_directory}" >/dev/null 2>&1 || true
        rmdir "/Library/Application Support/DriveBatteryHealthViewer" >/dev/null 2>&1 || true
        ;;
    *)
        echo "Usage: $0 install HELPER UID HOME CONFIG APPLICATION | uninstall" >&2
        exit 2
        ;;
esac
