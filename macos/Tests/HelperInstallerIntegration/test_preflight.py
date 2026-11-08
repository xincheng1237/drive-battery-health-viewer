#!/usr/bin/env python3
"""Exercise the helper installer in a disposable filesystem with fake privileged commands."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

INSTALLER = (Path(__file__).resolve().parents[2] / "Resources/ChargeProtection/install-charge-helper.sh")
IDENTIFIER = "com.chengxin.drivebatteryhealthviewer.chargehelper"

MOCK = r"""#!/bin/sh
case "${0##*/}" in
    id) echo 0 ;;
    stat) case "$2" in '%u') echo 501;; '%Lp') echo 600;; esac ;;
    chown) ;;
    install)
        while [ "$#" -gt 2 ]; do shift; done
        cp "$1" "$2"
        ;;
    codesign)
        case "$1" in
            --verify) [ "$SCENARIO" != invalid_signature ] ;;
            -dv) echo "Identifier=$TEST_LABEL" >&2 ;;
            *) exit 97 ;;
        esac
        ;;
    plutil)
        case "$1" in
            -create) printf 'new plist' > "$3" ;;
            -lint) [ "$SCENARIO" != invalid_plist ] ;;
            *) exit 97 ;;
        esac
        ;;
    PlistBuddy)
        case "$2" in
            'Print :CFBundleIdentifier') echo com.chengxin.drive-battery-health-viewer ;;
            'Print :ProgramArguments:2') echo "$TEST_CONFIG" ;;
            'Print :ProgramArguments:8') echo 501 ;;
        esac
        ;;
    launchctl)
        echo "$1" >> "$TEST_TRACE"
        case "$1" in
            print) [ -f "$TEST_JOB" ] ;;
            bootout) [ "$SCENARIO" != cannot_stop ] && rm -f "$TEST_JOB" ;;
            bootstrap) [ "$SCENARIO" != cannot_start ] && touch "$TEST_JOB" ;;
            *) exit 97 ;;
        esac
        ;;
esac
"""

def run(source, scenario):
    with tempfile.TemporaryDirectory(prefix="dbhv-installer-") as tmp:
        root = Path(tmp)
        for path in ("bin", "tmp", "Library/PrivilegedHelperTools", "Library/LaunchDaemons", "home/Test.app/Contents"):
            (root / path).mkdir(parents=True)
        for name in ("id", "stat", "chown", "install", "codesign", "plutil", "PlistBuddy", "launchctl"):
            mock = root / "bin" / name
            mock.write_text(MOCK)
            mock.chmod(0o700)
        helper = root / "Library/PrivilegedHelperTools" / IDENTIFIER
        plist = root / "Library/LaunchDaemons" / (IDENTIFIER + ".plist")
        config = root / "home/charge.json"
        new = root / "replacement"
        job = root / "job"
        trace = root / "trace"
        old = '#!/bin/sh\necho restore >> "$TEST_TRACE"\n[ "$SCENARIO" != cannot_restore ]\n'
        helper.write_text(old)
        helper.chmod(0o700)
        plist.write_text("old plist")
        config.write_text("{}")
        new.write_text("new helper")
        job.touch()
        trace.touch()
        # Keep the production control flow and sandbox every system path and privileged command.
        substitutions = {
            "/Library/": str(root / "Library") + "/",
            "/tmp/": str(root / "tmp") + "/",
            "/usr/bin/codesign": str(root / "bin/codesign"),
            "/usr/bin/plutil": str(root / "bin/plutil"),
            "/usr/libexec/PlistBuddy": str(root / "bin/PlistBuddy"),
        }
        pattern = "|".join(re.escape(key) for key in substitutions)
        script = root / "installer.sh"
        script.write_text(re.sub(pattern, lambda match: substitutions[match[0]], source))
        env = dict(os.environ, PATH=f"{root}/bin:/usr/bin:/bin", SCENARIO=scenario,
                   TEST_LABEL=IDENTIFIER, TEST_CONFIG=str(config), TEST_TRACE=str(trace), TEST_JOB=str(job))
        result = subprocess.run(["/bin/sh", str(script), "install", str(new), "501", str(root / "home"),
                                 str(config), str(root / "home/Test.app")], env=env, capture_output=True, text=True)
        calls = trace.read_text().splitlines()
        if scenario == "success":
            assert result.returncode == 0, result.stderr
            assert helper.read_text() == "new helper" and plist.read_text() == "new plist" and job.exists()
            assert calls == ["restore", "bootout", "print", "bootstrap", "print"], calls
        else:
            assert result.returncode != 0, scenario
            if scenario == "cannot_start":
                assert not helper.exists() and not plist.exists() and not job.exists(), calls
                assert "restore" in calls and "bootstrap" in calls, calls
            else:
                assert helper.exists() and helper.read_text() == old, (scenario, "old helper removed", calls)
                assert plist.read_text() == "old plist" and job.exists(), scenario
                if scenario in ("invalid_signature", "invalid_plist"):
                    assert calls == [], (scenario, calls)
                elif scenario == "cannot_restore":
                    assert calls == ["restore"], calls
                elif scenario == "cannot_stop":
                    assert calls == ["restore", "bootout", "print"], calls
        print("PASS", scenario)

if __name__ == "__main__":
    source = (Path(sys.argv[1]) if len(sys.argv) > 1 else INSTALLER).read_text()
    for scenario in ("invalid_signature", "invalid_plist", "cannot_restore", "cannot_stop", "cannot_start", "success"):
        run(source, scenario)
