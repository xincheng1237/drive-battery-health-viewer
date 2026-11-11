#!/bin/sh
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077

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

restore_charging() (
    fallback_config_path="${1:-}"
    fallback_owner_uid="${2:-}"
    if [ -x "${helper_destination}" ] && [ -f "${plist_destination}" ]; then
        config_path=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "${plist_destination}" 2>/dev/null || true)
        owner_uid=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:8' "${plist_destination}" 2>/dev/null || true)
        [ -n "${config_path}" ] || config_path="${fallback_config_path}"
        [ -n "${owner_uid}" ] || owner_uid="${fallback_owner_uid}"
        if [ -n "${config_path}" ] && [ -n "${owner_uid}" ]; then
            "${helper_destination}" --config "${config_path}" --status "${status_path}" --log "${log_path}" --owner-uid "${owner_uid}" --restore-only
            return $?
        fi
    elif [ -x "${helper_destination}" ] && [ -n "${fallback_config_path}" ] && [ -n "${fallback_owner_uid}" ]; then
        "${helper_destination}" --config "${fallback_config_path}" --status "${status_path}" --log "${log_path}" --owner-uid "${fallback_owner_uid}" --restore-only
        return $?
    elif [ ! -x "${helper_destination}" ] && [ ! -e "${state_directory}/powerui-owner.json" ]; then
        return 0
    fi
    echo "Normal charging could not be verified; installed components were preserved." >&2
    return 1
)

trusted_directory() {
    [ -d "$1" ] && [ ! -L "$1" ] && [ "$(stat -f '%u' "$1")" = 0 ] || return 1
    case "$(stat -f '%Lp' "$1")" in
        700|711|750|751|755) return 0 ;;
        *) return 1 ;;
    esac
}

create_trusted_directory() {
    if [ ! -e "$1" ] && [ ! -L "$1" ]; then
        mkdir -m 0755 "$1" || return 1
    fi
    trusted_directory "$1" || { echo "Unsafe installation directory: $1" >&2; return 1; }
}

job="system/${identifier}"
stop_job() (
    if details=$(launchctl print "${job}" 2>/dev/null); then
        previous_pid=$(printf '%s\n' "${details}" | awk '$1 == "pid" && $2 == "=" && $3 ~ /^[1-9][0-9]*$/ {print $3; exit}')
        launchctl bootout "${job}" >/dev/null 2>&1 || return 1
        attempt=0
        while launchctl print "${job}" >/dev/null 2>&1 ||
              { [ -n "${previous_pid}" ] && kill -0 "${previous_pid}" 2>/dev/null; }; do
            [ "${attempt}" -lt 100 ] || return 1
            attempt=$((attempt + 1))
            sleep 0.1
        done
    fi
)

case "${1:-}" in
    install)
        installation_complete=0
        stop_requested=0
        old_registered=0
        replacement_started=0
        transaction="${state_directory}/.helper-upgrade"
        cleanup_install() {
            result=$?
            trap - EXIT
            trap '' HUP INT TERM
            if [ "${installation_complete}" -ne 1 ]; then
                [ "${result}" -ne 0 ] || result=1
                if [ "${replacement_started}" -eq 1 ]; then
                    if ! stop_job; then
                        echo "Could not stop the replacement Helper. Backups retained at ${transaction}." >&2
                        exit 1
                    fi
                    if [ -f "${transaction}/helper" ]; then
                        if ! install -o root -g wheel -m 0555 "${transaction}/helper" "${helper_destination}"; then
                            echo "Could not restore the prior Helper. Backups retained at ${transaction}." >&2
                            exit 1
                        fi
                    else
                        rm -f "${helper_destination}" || exit 1
                    fi
                    if [ -f "${transaction}/daemon.plist" ]; then
                        if ! install -o root -g wheel -m 0644 "${transaction}/daemon.plist" "${plist_destination}"; then
                            echo "Could not restore the prior launch configuration. Backups retained at ${transaction}." >&2
                            exit 1
                        fi
                    else
                        rm -f "${plist_destination}" || exit 1
                    fi
                fi
                if [ "${stop_requested}" -eq 1 ] && [ "${old_registered}" -eq 1 ] &&
                   ! launchctl print "${job}" >/dev/null 2>&1; then
                    if [ "${old_stopped}" -ne 1 ] ||
                       ! launchctl bootstrap system "${plist_destination}" ||
                       ! launchctl print "${job}" >/dev/null 2>&1; then
                        echo "Could not safely restart the prior Helper. Backups retained at ${transaction}." >&2
                        exit 1
                    fi
                fi
            fi
            rm -f "${helper_temporary:-}" "${plist_temporary:-}"
            rm -rf "${transaction}"
            exit "${result}"
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

        trusted_directory "/Library" && trusted_directory "/Library/Application Support" &&
            trusted_directory "/Library/LaunchDaemons" && trusted_directory "/Library/Logs" || exit 1
        create_trusted_directory "/Library/PrivilegedHelperTools"
        create_trusted_directory "/Library/Application Support/DriveBatteryHealthViewer"
        create_trusted_directory "${state_directory}"
        create_trusted_directory "${log_directory}"
        for component in "${helper_destination}" "${plist_destination}"; do
            if [ -e "${component}" ] || [ -L "${component}" ]; then
                [ -f "${component}" ] && [ ! -L "${component}" ] &&
                    [ "$(stat -f '%u' "${component}")" = 0 ] || {
                    echo "Unsafe installed component: ${component}" >&2
                    exit 1
                }
            fi
        done
        mkdir -m 0700 "${transaction}" || {
            echo "A Helper upgrade transaction already exists. Inspect ${transaction} before retrying." >&2
            exit 1
        }
        old_stopped=0
        trap cleanup_install EXIT
        trap 'exit 1' HUP INT TERM
        chown root:wheel "${transaction}"
        helper_temporary=$(mktemp "/Library/PrivilegedHelperTools/.${identifier}.XXXXXX")
        install -o root -g wheel -m 0500 "${helper_source}" "${helper_temporary}"
        /usr/bin/codesign --verify --strict "${helper_temporary}"
        helper_identifier=$(/usr/bin/codesign -dv "${helper_temporary}" 2>&1 | /usr/bin/awk -F= '$1 == "Identifier" { print $2; exit }')
        [ "${helper_identifier}" = "${identifier}" ] || { echo "Unexpected helper code-signing identifier." >&2; exit 1; }
        chmod 0555 "${helper_temporary}"
        plist_temporary="${transaction}/new.plist"
        : > "${plist_temporary}"
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

        if [ -f "${helper_destination}" ]; then
            install -o root -g wheel -m 0500 "${helper_destination}" "${transaction}/helper"
        fi
        if [ -f "${plist_destination}" ]; then
            install -o root -g wheel -m 0600 "${plist_destination}" "${transaction}/daemon.plist"
        fi
        "${helper_temporary}" --prepare-upgrade-ownership
        if launchctl print "${job}" >/dev/null 2>&1; then
            [ -f "${transaction}/helper" ] && [ -f "${transaction}/daemon.plist" ] || {
                echo "The registered Helper cannot be backed up. Installation stopped." >&2
                exit 1
            }
            old_registered=1
        fi
        stop_requested=1
        stop_job || { echo "The existing charge helper could not be stopped." >&2; exit 1; }
        old_stopped=1
        restore_charging "${config_path}" "${owner_uid}"
        "${helper_temporary}" --reconcile-upgrade-ownership

        replacement_started=1
        rm -f "${status_path}"
        mv -f "${helper_temporary}" "${helper_destination}"
        cmp -s "${helper_source}" "${helper_destination}" || {
            echo "Installed helper does not exactly match the bundled helper." >&2
            exit 1
        }
        /usr/bin/codesign --verify --strict "${helper_destination}"

        install -o root -g wheel -m 0644 "${plist_temporary}" "${plist_destination}"
        launchctl bootstrap system "${plist_destination}"
        # A registered job alone does not prove that the Helper is running.
        # Readiness requires its first report and a live launchd process.
        attempt=0
        while :; do
            if details=$(launchctl print "${job}" 2>/dev/null) &&
               printf '%s\n' "${details}" | awk '$1 == "pid" && $2 == "=" && $3 ~ /^[1-9][0-9]*$/ { found=1 } END { exit !found }' &&
               [ "$(plutil -extract helperVersion raw -o - "${status_path}" 2>/dev/null)" = "1.1.2.4" ]; then
                break
            fi
            [ "${attempt}" -lt 60 ] || { echo "The replacement Helper did not report readiness." >&2; exit 1; }
            attempt=$((attempt + 1))
            sleep 0.5
        done
        installation_complete=1
        ;;
    uninstall)
        fallback_config_path="${2:-}"
        fallback_owner_uid="${3:-}"
        [ ! -e "${state_directory}/.helper-upgrade" ] || exit 1
        stop_job
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
