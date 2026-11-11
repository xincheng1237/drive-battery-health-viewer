#!/usr/bin/env python3
"""Run the entire production installer with relocated paths and fake privileged commands."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

MACOS = Path(__file__).resolve().parents[2]
INSTALLER = MACOS / "Resources/ChargeProtection/install-charge-helper.sh"
IDENTIFIER = "com.chengxin.drivebatteryhealthviewer.chargehelper"

MOCK = r"""#!/bin/sh
set -eu
case "${0##*/}" in
    id) echo 0 ;;
    stat)
        case "$2" in
            '%u') case "$3" in "$TEST_HOME"|"$TEST_CONFIG") echo 501 ;; *) echo 0 ;; esac ;;
            '%Lp') /usr/bin/stat "$@" ;;
        esac ;;
    chown) ;;
    install)
        while [ "$#" -gt 2 ]; do
            case "$1" in -m) mode=$2 ;; esac
            shift 2
        done
        /usr/bin/install -m "$mode" "$1" "$2"
        ;;
    codesign)
        case "$1" in
            --verify) [ "$SCENARIO" != invalid_signature ] ;;
            -dv) echo "Identifier=$TEST_LABEL" >&2 ;;
            *) exit 97 ;;
        esac ;;
    plutil)
        case "$1" in
            -create) printf 'new plist' > "$3" ;;
            -lint) [ "$SCENARIO" != invalid_plist ] ;;
            -extract)
                [ "$SCENARIO" != no_readiness ] && [ -f "$6" ] && echo 1.1.2.4
                ;;
            *) exit 97 ;;
        esac ;;
    PlistBuddy)
        case "$2" in
            'Print :CFBundleIdentifier') echo com.chengxin.drive-battery-health-viewer ;;
            'Print :ProgramArguments:2') echo "$TEST_CONFIG" ;;
            'Print :ProgramArguments:8') echo 501 ;;
        esac ;;
    launchctl)
        case "$1" in
            print) [ -f "$TEST_JOB" ] && echo 'pid = 999999' ;;
            bootout)
                echo bootout >> "$TEST_TRACE"
                case "$SCENARIO" in
                    cannot_stop|stop_pending) touch "$TEST_STOP_REQUESTED" ;;
                    *) rm -f "$TEST_JOB" ;;
                esac ;;
            bootstrap)
                if grep -q '^old plist' "$3"; then
                    echo bootstrap_old >> "$TEST_TRACE"
                else
                    echo bootstrap_new >> "$TEST_TRACE"
                    [ "$SCENARIO" != cannot_start ] || exit 1
                    if [ "$SCENARIO" = interrupted ]; then
                        # Only the isolated installer shell receives the signal.
                        kill -TERM "$PPID"
                    fi
                fi
                touch "$TEST_JOB"
                touch "$TEST_STATE/status.json"
                ;;
            *) exit 97 ;;
        esac ;;
    sleep)
        if [ "$SCENARIO" = stop_pending ] && [ -f "$TEST_STOP_REQUESTED" ]; then rm -f "$TEST_JOB"; fi
        ;;
esac
"""

OLD = r"""#!/bin/sh
set -eu
echo "restore-$OLD_BUILD" >> "$TEST_TRACE"
[ "$SCENARIO" != cannot_restore ] || exit 1
rm -f "$TEST_STATE/powerui-owner.json"
"""

NEW = r"""#!/bin/sh
set -eu
echo "$1" >> "$TEST_TRACE"
"$TEST_FIXTURE" "$1" "$TEST_STATE" "$TEST_BASELINE"
"""

def run(source, scenario, fixture, old_build=49):
    with tempfile.TemporaryDirectory(prefix="dbhv-installer-") as tmp:
        root = Path(tmp)
        for path in (
            "bin", "tmp", "Library/PrivilegedHelperTools", "Library/LaunchDaemons",
            "Library/Logs", "Library/Application Support/DriveBatteryHealthViewer/ChargeProtection",
            "home/Test.app/Contents",
        ):
            (root / path).mkdir(parents=True, mode=0o755)
        for name in ("id", "stat", "chown", "install", "codesign", "plutil", "PlistBuddy", "launchctl", "sleep"):
            mock = root / "bin" / name
            mock.write_text(MOCK)
            mock.chmod(0o700)
        state = root / "Library/Application Support/DriveBatteryHealthViewer/ChargeProtection"
        marker = state / "powerui-owner.json"
        helper = root / "Library/PrivilegedHelperTools" / IDENTIFIER
        plist = root / "Library/LaunchDaemons" / (IDENTIFIER + ".plist")
        config = root / "home/charge.json"
        replacement = root / "replacement"
        job = root / "job"
        trace = root / "trace"
        helper.write_text(OLD)
        helper.chmod(0o700)
        plist.write_text("old plist")
        config.write_text("{}")
        config.chmod(0o600)
        replacement.write_text(NEW)
        job.touch()
        trace.touch()
        if scenario in {"corrupt", "insecure", "clean", "topOff", "system", "unknown", "provisional"}:
            record = dict(helperIdentifier=IDENTIFIER, targetPercentage=80, schema=1)
            if old_build != 47:
                record["leaseState"] = "preEngaging" if scenario == "provisional" else "activeEighty"
            marker.write_text("bad JSON" if scenario == "corrupt" else json.dumps(record))
            marker.chmod(0o644 if scenario == "insecure" else 0o600)

        substitutions = {
            '"/Library"': f'"{root}/Library"',
            "/Library/": str(root / "Library") + "/",
            "/tmp/": str(root / "tmp") + "/",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin": f"PATH={root}/bin:/usr/bin:/bin",
            "/usr/bin/codesign": str(root / "bin/codesign"),
            "/usr/bin/plutil": str(root / "bin/plutil"),
            "/usr/libexec/PlistBuddy": str(root / "bin/PlistBuddy"),
        }
        pattern = "|".join(re.escape(key) for key in substitutions)
        script = root / "installer.sh"
        script.write_text(re.sub(pattern, lambda match: substitutions[match[0]], source))
        env = dict(os.environ, PATH=f"{root}/bin:/usr/bin:/bin", SCENARIO=scenario,
                   TEST_LABEL=IDENTIFIER, TEST_HOME=str(root / "home"), TEST_CONFIG=str(config),
                   TEST_TRACE=str(trace), TEST_JOB=str(job), TEST_STATE=str(state), OLD_BUILD=str(old_build),
                   TEST_FIXTURE=str(fixture), TEST_STOP_REQUESTED=str(root / "stop_requested"),
                   TEST_BASELINE="topOff" if scenario == "provisional" else scenario)
        result = subprocess.run(
            ["/bin/sh", str(script), "install", str(replacement), "501", str(root / "home"),
             str(config), str(root / "home/Test.app")], env=env, capture_output=True, text=True, timeout=60
        )
        calls = trace.read_text().splitlines()
        expected_success = scenario in {"success", "stop_pending", "clean", "topOff", "system", "provisional"}
        print(f"{scenario} old-build={old_build} installer-exit={result.returncode} events={calls}", flush=True)
        if result.stderr:
            print(result.stderr.strip(), flush=True)
        assert (result.returncode == 0) == expected_success, scenario
        if expected_success:
            assert helper.read_text() == NEW and plist.read_text() == "new plist" and job.exists()
            if scenario == "topOff":
                assert json.loads(marker.read_text())["leaseState"] == "restoredTopOff"
                assert marker.stat().st_mode & 0o777 == 0o600
            else:
                assert not marker.exists(), "the installer fabricated ownership"
            assert calls.index("bootout") < calls.index(f"restore-{old_build}") < calls.index("bootstrap_new")
        else:
            assert helper.read_text() == OLD and plist.read_text() == "old plist" and job.exists()
            if scenario in {"invalid_signature", "invalid_plist", "corrupt", "insecure"}:
                assert "bootout" not in calls
            if scenario in {"cannot_start", "no_readiness", "interrupted", "unknown"}:
                assert calls[-1] == "bootstrap_old"
        assert not (state / ".helper-upgrade").exists()


if __name__ == "__main__":
    source = (Path(sys.argv[1]) if len(sys.argv) > 1 else INSTALLER).read_text()
    scenarios = sys.argv[2:] or [
        "corrupt", "insecure", "clean", "topOff", "system", "unknown", "provisional",
        "invalid_signature", "invalid_plist", "cannot_restore", "cannot_stop", "stop_pending",
        "cannot_start", "no_readiness", "interrupted", "success",
    ]
    with tempfile.TemporaryDirectory(prefix="dbhv-test-ownership-") as tmp:
        fixture = Path(tmp) / "ownership-fixture"
        subprocess.run(
            ["swiftc", "-module-cache-path", str(Path(tmp) / "modules"), "-o", str(fixture),
             *(str(path) for path in (MACOS / "Sources/ChargeProtectionCore").glob("*.swift")),
             str(Path(__file__).with_name("OwnershipFixture.swift"))],
            check=True,
        )
        failed = False
        for scenario in scenarios:
            for build in (47, 48, 49) if scenario == "topOff" else (49,):
                try:
                    run(source, scenario, fixture, build)
                except AssertionError as error:
                    print(f"FAIL {scenario}: {error}", file=sys.stderr)
                    failed = True
        sys.exit(int(failed))
