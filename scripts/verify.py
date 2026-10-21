#!/usr/bin/env python3
"""Build and verify on isolated iPhone/iPad simulators; no physical devices or third-party tools."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, text=True, **kwargs)
def sim_json(*args):
    return json.loads(run("xcrun", "simctl", *args, "--json", capture_output=True).stdout)
parser = argparse.ArgumentParser()
parser.add_argument("--device", choices=["iphone", "ipad", "both"], default="both")
parser.add_argument("--regression", type=Path, help="Optional private IMG_9673.mov; copied only to ignored test fixtures")
parser.add_argument("--unit-only", action="store_true")
args = parser.parse_args()
if args.regression:
    fixture = ROOT / "CoachInsightsTests/LocalFixtures/Regression.mov"
    fixture.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.regression.expanduser().resolve(), fixture)
run("python3", "scripts/prepare_dependencies.py")
run("python3", "scripts/generate_project.py")
runtimes = [r for r in sim_json("list", "runtimes")["runtimes"]
            if r["isAvailable"] and r["name"].startswith("iOS ")]
runtime = sorted(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))[-1]
devices = sim_json("list", "devices", "available")["devices"].get(runtime["identifier"], [])
types = sim_json("list", "devicetypes")["devicetypes"]
for kind in (["iphone", "ipad"] if args.device == "both" else [args.device]):
    label = "CoachInsights 1.0 " + ("iPhone" if kind == "iphone" else "iPad") + " QA"
    existing = next((d for d in devices if d["name"] == label), None)
    if existing:
        udid = existing["udid"]
    else:
        prefix = "iPhone" if kind == "iphone" else "iPad"
        preferred = "iPhone 16e" if kind == "iphone" else "iPad mini (A17 Pro)"
        device_type = next((d for d in types if d["name"] == preferred), None)
        if not device_type:
            device_type = [d for d in types if d["name"].startswith(prefix)][-1]
        udid = run("xcrun", "simctl", "create", label, device_type["identifier"],
                   runtime["identifier"], capture_output=True).stdout.strip()
    output = ROOT / "artifacts" / kind
    output.mkdir(parents=True, exist_ok=True)
    result = output / ("Units.xcresult" if args.unit_only else "V1.xcresult")
    if result.exists():
        shutil.rmtree(result)
    command = ["xcodebuild", "-project", "CoachInsights.xcodeproj", "-scheme", "CoachInsights",
               "-destination", f"platform=iOS Simulator,id={udid}",
               "-derivedDataPath", "build/DerivedData", "-resultBundlePath", str(result),
               "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO", "test"]
    if args.unit_only:
        command.insert(-1, "-only-testing:CoachInsightsTests")
    with (output / ("units.log" if args.unit_only else "test.log")).open("w") as log:
        run(*command, stdout=log, stderr=subprocess.STDOUT)
    print(f"{kind}: PASS; {result}", flush=True)
    container = run("xcrun", "simctl", "get_app_container", udid, "com.coachinsights.CoachInsights",
                    "data", capture_output=True).stdout.strip()
    for pattern in ["probe-report*.json", "pose-*.json"]:
        for report in (Path(container) / "Documents").glob(pattern):
            shutil.copy2(report, output / report.name)
print("Simulator verification complete. Private media and artifacts remain ignored.")
