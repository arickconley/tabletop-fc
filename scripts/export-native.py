#!/usr/bin/env python3
"""Build local macOS/Windows packages and an unsigned iOS Xcode project."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot"
OUTPUT = ROOT / "dist/native"
PLACEHOLDER = "UNSIGNED00"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    (OUTPUT / "ios").mkdir(parents=True, exist_ok=True)
    presets = PROJECT / "export_presets.cfg"
    for platform in ["macOS", "Windows Desktop", "iOS"]:
        original = presets.read_text()
        unsigned_ios = platform == "iOS" and 'application/app_store_team_id=""' in original
        log = OUTPUT / (platform.replace(" ", "-") + "-export.log")
        try:
            if unsigned_ios:
                # Godot requires a team even for project-only exports; never use this for signing.
                presets.write_text(original.replace('application/app_store_team_id=""', f'application/app_store_team_id="{PLACEHOLDER}"'))
            with log.open("w") as stream:
                subprocess.run([args.godot, "--headless", "--path", str(PROJECT), "--export-release", platform],
                               env={**os.environ, "GODOT_MCP_RUNTIME": "0"}, stdout=stream, stderr=subprocess.STDOUT, check=True)
            if "ERROR:" in log.read_text():
                raise RuntimeError(f"{platform} reported an export error; see {log}")
        finally:
            if unsigned_ios:
                presets.write_text(original)
        if unsigned_ios:
            for path in (OUTPUT / "ios").rglob("*"):
                if path.suffix == ".pbxproj" or path.name == "export_options.plist":
                    text = path.read_text().replace(f"= {PLACEHOLDER};", '= "";').replace(PLACEHOLDER, "")
                    path.write_text(text)
        if platform == "iOS":
            info = OUTPUT / "ios/TabletopFC/TabletopFC-Info.plist"
            data = plistlib.loads(info.read_bytes())
            # The game never requests these permissions; omit empty template descriptions.
            for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"]:
                if data.get(key) == "":
                    del data[key]
            info.write_bytes(plistlib.dumps(data, sort_keys=False))
        print(f"Built {platform}: {log}", flush=True)
    for name, source in [("LICENSES.txt", PROJECT / "LICENSES.txt"), ("FONT-LICENSE.txt", PROJECT / "assets/fonts/OFL.txt")]:
        shutil.copyfile(source, OUTPUT / name)
        shutil.copyfile(source, OUTPUT / "ios" / name)
    notice = "Local review builds only. macOS is ad-hoc signed, Windows is unsigned.\nThe iOS export contains an Xcode project; build with Apple Development signing for device installation.\nPublic Apple distribution requires signing and notarization/App Store validation.\n"
    (OUTPUT / "BUILD-NOTES.txt").write_text(notice)
    (OUTPUT / "ios/BUILD-NOTES.txt").write_text(notice)
    with zipfile.ZipFile(OUTPUT / "TabletopFC-macOS.zip", "a", zipfile.ZIP_DEFLATED) as archive:
        for name in ["LICENSES.txt", "FONT-LICENSE.txt", "BUILD-NOTES.txt"]:
            archive.write(OUTPUT / name, name)
    with zipfile.ZipFile(OUTPUT / "TabletopFC-Windows.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for name in ["TabletopFC.exe", "LICENSES.txt", "FONT-LICENSE.txt", "BUILD-NOTES.txt"]:
            archive.write(OUTPUT / name, name)
    shutil.make_archive(str(OUTPUT / "TabletopFC-iOS-project"), "zip", OUTPUT / "ios")


if __name__ == "__main__":
    main()
