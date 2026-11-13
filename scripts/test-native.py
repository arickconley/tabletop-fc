#!/usr/bin/env python3
"""Run native checks with a fixed viewport and fail even when a Godot assert leaves its loop running."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ["rules", "computer", "strategy", "scene", "computer_scene", "layout", "menu_layout", "lobby", "groundskeeper", "ui", "celebration", "polish", "orbit"]


def run_check(engine, check, rendered=False, captures=None):
    with tempfile.TemporaryDirectory(prefix="tabletop-native-") as temporary:
        log = Path(temporary) / "godot.log"
        command = [engine, "--path", str(ROOT / "godot"), "--resolution", "1280x800", "--log-file", str(log), "--script", f"tests/{check}_check.gd"]
        if not rendered:
            command.insert(1, "--headless")
        if captures and check in ["ui", "celebration", "orbit"]:
            command += ["--", str(Path(captures).resolve() / check)]
        env = {**os.environ, "GODOT_MCP_RUNTIME": "0"}
        with (Path(temporary) / "console.log").open("w+") as console:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=console, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 120
            try:
                while process.poll() is None:
                    text = log.read_text(errors="replace") if log.exists() else ""
                    if "SCRIPT ERROR:" in text or time.monotonic() > deadline:
                        process.terminate()
                        break
                    time.sleep(.1)
                process.wait(timeout=5)
            except BaseException:
                process.kill()
                process.wait()
                raise
            console.seek(0)
            output = console.read()
        if process.returncode != 0 or "PASS:" not in output or "SCRIPT ERROR:" in output:
            raise RuntimeError(f"{check} failed:\n{output}")
        print("\n".join(line for line in output.splitlines() if line.startswith(("PASS:", "PROFILE", "Match "))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checks", nargs="*", default=DEFAULT)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--rendered", action="store_true")
    parser.add_argument("--captures")
    args = parser.parse_args()
    subprocess.run(["node", "godot/tests/reference.mjs"], cwd=ROOT, check=True)
    for check in args.checks:
        if not (ROOT / "godot" / "tests" / f"{check}_check.gd").is_file():
            parser.error(f"Unknown check: {check}")
        run_check(args.godot, check, args.rendered, args.captures)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
