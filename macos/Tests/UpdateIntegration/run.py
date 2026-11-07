#!/usr/bin/env python3
"""Sparkle 2.10.1 loopback test; use the pinned SwiftPM artifact and a new output directory."""
import concurrent.futures
import http.server
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import threading
import time
import uuid

artifact, sandbox, output = map(lambda v: pathlib.Path(v).resolve(), sys.argv[1:])
output.mkdir(parents=True)
here = pathlib.Path(__file__).resolve().parent
framework = next(artifact.glob("Sparkle.xcframework/*/Sparkle.framework"))
sign_update = artifact / "bin/sign_update"
base = output / "base"
base.mkdir()
subprocess.run(["/usr/bin/swiftc", "-parse-as-library", "-F", str(framework.parent), "-framework", "Sparkle",
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                str(here / "Fixture.swift"), str(here.parent.parent / "Sources/DriveBatteryHealthViewer/InAppUpdater.swift"),
                "-o", str(base / "Fixture")], check=True)
shutil.copytree(framework, base / "Sparkle.framework", symlinks=True)
# The key helper uses only CryptoKit and this disposable path. No Keychain.
env = dict(os.environ, DYLD_FRAMEWORK_PATH=str(base))
subprocess.run([str(base / "Fixture"), "install-handoff-mock"], env=env, check=True)
key = output / "temporary-test-key"
os.umask(0o077)
public = subprocess.check_output([str(base / "Fixture"), "key", str(key)], env=env, text=True).strip()
served = output / "www"
served.mkdir()
served.joinpath("test.zip").write_bytes(b"Download must be canceled; this is not an installable package.")
attrs = subprocess.check_output([str(sign_update), "-f", str(key), str(served / "test.zip")], text=True).strip()
requests = []
class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=served, **kwargs)
    def do_GET(self):
        requests.append((self.path, time.monotonic()))
        if self.path == "/offline.xml" or (self.path == "/recover.xml" and not (output / "network-restored").exists()):
            self.close_connection = True
            return
        if self.path == "/upgrade-queued.xml" and not (output / "queue-started").exists():
            (output / "queue-started").touch()
            deadline = time.monotonic() + 12
            while not (output / "queue-release").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            if not (output / "queue-release").exists():
                self.send_error(408)
                return
            (output / "queue-responded").touch()
        elif self.path == "/upgrade-queued.xml" and not (output / "queue-responded").exists():
            (output / "queue-overlapped").touch()
        return super().do_GET()
    def log_message(self, *_):
        pass
with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    endpoint = f"http://127.0.0.1:{server.server_port}"
    for label, build in (("new", 38), ("running", 38), ("download", 38),
                         ("disabled", 38), ("restart", 38), ("none", 37), ("tampered", 38), ("higher", 38), ("recover", 38), ("upgrade-legacy", 39), ("upgrade-queued", 39),
                         ("quiet-standard", 40)):
        feed = served / f"{label}.xml"
        version = {"higher": "1.2.2", "upgrade-legacy": "1.3", "upgrade-queued": "1.3",
                   "quiet-standard": "1.3.1"}.get(label, "1.2.1")
        feed.write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><title>DBHV isolated fixture</title><item><title>Fixture</title>
<sparkle:version>{build}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString>
<enclosure url="{endpoint}/test.zip" type="application/octet-stream" {attrs}/>
</item></channel></rss>""")
        subprocess.run([str(sign_update), "-f", str(key), str(feed)], check=True)
        subprocess.run([str(sign_update), "-f", str(key), "--verify", str(feed)], check=True)
        if label == "tampered":
            feed.write_text(feed.read_text().replace("isolated fixture", "tampered fixture"))
    subprocess.run([str(sign_update), "-f", str(key), "--verify", str(served / "test.zip"), attrs.split('"')[1]], check=True)
    key.unlink()
    served.joinpath("malformed.xml").write_text("this is not XML")
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def run(label):
        bundle = output / (label + ".app") / "Contents"
        binary = bundle / "MacOS/Fixture"
        binary.parent.mkdir(parents=True)
        shutil.copy2(base / "Fixture", binary)
        (bundle / "Frameworks").mkdir()
        shutil.copytree(base / "Sparkle.framework", bundle / "Frameworks/Sparkle.framework", symlinks=True)
        prefs = output / (label + "-home")
        prefs.mkdir()
        identity = "com.dbhv.update-fixture." + uuid.uuid4().hex
        old_host = label in ("upgrade-legacy", "upgrade-queued")
        host_build, host_version = ("35", "1.2") if old_host else ("39", "1.3") if label == "quiet-standard" else ("37", "1.2.1")
        (bundle / "Info.plist").write_bytes(plistlib.dumps(dict(
            CFBundleIdentifier=identity, CFBundleName="DBHV Test Fixture", CFBundleExecutable="Fixture",
            CFBundlePackageType="APPL", CFBundleVersion=host_build, CFBundleShortVersionString=host_version,
            SUPublicEDKey=public, SUFeedURL=f"{endpoint}/{label}.xml", SURequireSignedFeed=True,
            SUVerifyUpdateBeforeExtraction=True, SUSignedFeedFailureExpirationInterval=0,
            SUEnableAutomaticChecks=label != "upgrade-legacy", SUAllowsAutomaticUpdates=False,
            SUAutomaticallyUpdate=False, SUScheduledCheckInterval=604800,
            LSUIElement=True, NSAppTransportSecurity=dict(NSAllowsArbitraryLoads=True),
        )))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(bundle.parent)], check=True)
        fixture_env = dict(os.environ, CFFIXED_USER_HOME=str(prefs), no_proxy="127.0.0.1")
        with open(output / (label + ".log"), "w") as log:
            result = subprocess.run(["/usr/bin/sandbox-exec", "-f", str(sandbox), str(binary), label, str(output / "network-restored")],
                                    env=fixture_env, stdout=log, stderr=subprocess.STDOUT, timeout=50)
        count = sum(path == f"/{label}.xml" for path, _ in requests)
        print(label, "exit", result.returncode, "requests", count, flush=True)
        if label in ("disabled", "restart", "none", "upgrade-legacy", "quiet-standard"):
            assert count == 1, (label, count)
        if label == "upgrade-queued":
            assert count == 2 and not (output / "queue-overlapped").exists(), (label, count)
        return result.returncode

    with concurrent.futures.ThreadPoolExecutor(max_workers=9) as pool:
        results = list(pool.map(run, ["new", "running", "download", "disabled", "restart", "none", "offline", "malformed", "tampered", "higher", "recover", "upgrade-legacy", "upgrade-queued", "quiet-standard"]))
    (output / "http-requests.txt").write_text("".join(f"{stamp:.3f} {path}\n" for path, stamp in requests))
    sys.exit(0 if all(result == 0 for result in results) else 1)
