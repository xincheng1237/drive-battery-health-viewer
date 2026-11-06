#!/usr/bin/env python3
"""Generate a signed macOS feed from the actual exported in-app changelog."""
import argparse
import datetime
import html
import json
from pathlib import Path
import plistlib
import re
import subprocess

ACCOUNT = "com.chengxin.drive-battery-health-viewer.sparkle"
REPOSITORY = "https://github.com/xincheng1237/drive-battery-health-viewer"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--sign-tool", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package = Path(__file__).resolve().parent.parent
    info = plistlib.loads((package / "Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    expected = f"DriveBatteryHealthViewer_v{version}_build{build}_macOS_Universal.zip"
    if args.archive.name != expected or not args.archive.is_file():
        parser.error(f"Expected immutable update archive {expected}")
    notes = json.loads(args.notes.read_text())
    languages = {n["language"] for n in notes}
    if languages != {"en", "zh-Hans", "ru", "fr", "de", "ko", "ja"} or len(notes) != 7:
        parser.error("Expected exactly the seven application languages")
    if any(n["version"] != version or not n["sections"] for n in notes):
        parser.error("Notes do not match the release version")
    signer = str(args.sign_tool.resolve())
    attributes = subprocess.check_output([signer, "--account", ACCOUNT, str(args.archive.resolve())], text=True).strip()
    match = re.fullmatch(r'sparkle:edSignature="([A-Za-z0-9+/=]+)" length="([0-9]+)"', attributes)
    if not match or int(match.group(2)) != args.archive.stat().st_size:
        raise ValueError("Unexpected signing output or archive length")
    descriptions = []
    for note in notes:
        language = note["language"]
        content = "\n\n".join(s["title"] + "\n" + "\n".join("• " + text for text in s["items"]) for s in note["sections"])
        descriptions.append(f'<description xml:lang="{language}" sparkle:format="plain-text">{html.escape(content)}</description>')
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    url = f"{REPOSITORY}/releases/download/v{version}/{expected}"
    feed = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>Drive &amp; Battery Health Viewer for macOS</title>
<item><title>Version {version}</title><pubDate>{date}</pubDate>
<sparkle:version>{build}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>
{chr(10).join(descriptions)}
<enclosure url="{url}" {attributes} type="application/octet-stream"/>
</item></channel></rss>
'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(feed)
    subprocess.run([signer, "--account", ACCOUNT, str(args.output.resolve())], check=True)
    subprocess.run([signer, "--account", ACCOUNT, "--verify", str(args.output.resolve())], check=True)
    print(f"Verified signed feed: {args.output}")


if __name__ == "__main__":
    main()
