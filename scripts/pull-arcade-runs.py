#!/usr/bin/env python3
"""Pull only Bigger Fish debug run files and print compact summaries."""
import argparse
import collections
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

BUNDLE_ID = "com.kraigstrong.biggerfish"


def connected_device():
    with tempfile.TemporaryDirectory() as folder:
        output = Path(folder) / "devices.json"
        subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", str(output)],
                       check=True, stdout=subprocess.DEVNULL)
        devices = json.loads(output.read_text())["result"]["devices"]
    connected = [d for d in devices if d.get("connectionProperties", {}).get("tunnelState") == "connected"]
    if len(connected) != 1:
        raise RuntimeError("Connect one iPhone, or choose it with --device (name or identifier).")
    return connected[0]["identifier"]


def summarize(folder):
    files = sorted(folder.rglob("run-*.jsonl"))
    if not files:
        print("No run recordings found. Install the new Debug build and play a run first.")
    for path in files:
        records = []
        for line in path.read_text().splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue  # A recording pulled during play can end with a partial line.
        start = next((r for r in records if r.get("type") == "start"), {})
        end = next((r for r in reversed(records) if r.get("type") == "end"), {})
        counts = collections.Counter(r.get("type") for r in records)
        meals = [r for r in records if r.get("type") == "eat"]
        duration = end.get("time", records[-1].get("time", 0) if records else 0)
        print(f"{path.name}: {start.get('world', '?')} level {start.get('level', '?')} · "
              f"{end.get('outcome', 'unfinished')} {duration:.1f}s · "
              f"{sum(r.get('predatorID') == 0 for r in meals)} player meals / "
              f"{sum(r.get('predatorID') != 0 for r in meals)} AI meals · "
              f"{sum(r.get('type') == 'bounce' and r.get('fishID') == 0 for r in records)} bounces · "
              f"{counts['snapshot']} snapshots" + (f" · {end['reason']}" if end.get("reason") else ""))
    print(f"Recordings: {folder.resolve()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Connected iPhone name or CoreDevice identifier")
    parser.add_argument("--simulator", help="Simulator identifier or 'booted' (for verification)")
    parser.add_argument("--summarize-only", action="store_true", help="Read already downloaded logs")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "build/arcade-runs")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if not args.summarize_only:
        if args.simulator:
            container = subprocess.check_output(["xcrun", "simctl", "get_app_container", args.simulator, BUNDLE_ID, "data"], text=True).strip()
            shutil.copytree(Path(container) / "Documents/ArcadeRuns", args.output, dirs_exist_ok=True)
        else:
            device = args.device or connected_device()
            subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", device,
                            "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID,
                            "--source", "Documents/ArcadeRuns", "--destination", str(args.output.resolve())], check=True)
    summarize(args.output)
    subprocess.run(["python3", str(Path(__file__).with_name("analyze-arcade-runs.py")),
                    "--input", str(args.output), "--output", str(args.output / "analysis")], check=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, FileNotFoundError) as error:
        raise SystemExit(f"Could not pull recordings: {error}\nInstall the Debug build, play a run, pause or finish, and keep the phone unlocked and connected.")
