#!/usr/bin/env python3
"""Run a focused native pose test on the optimized iPhone/iPad simulator host."""
from pathlib import Path
from datetime import datetime, timezone
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/testflight"


def run(*cmd, **kwargs):
    return subprocess.run(cmd, cwd=ROOT, text=True, check=True, **kwargs)


def main():
    if not (ROOT / "CoachInsightsTests/LocalFixtures/Regression.mov").is_file():
        raise SystemExit("Prepare the local 78-frame Regression.mov fixture with scripts/verify.py --regression first")
    run("python3", "scripts/prepare_dependencies.py")
    run("python3", "scripts/generate_project.py")
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture_output=True).stdout)
    available = [device for group in devices["devices"].values() for device in group]
    # Existing core cases use Debug-only media factories. Keep this Release
    # bundle limited to its independent real-footage case, without compiling
    # DEBUG into the optimized app or shipping synthetic media tools.
    excluded = sorted(path.name for path in (ROOT / "CoachInsightsTests").rglob("*.swift")
                      if path.name != "ReleasePoseTests.swift")
    if any(path.name in excluded for path in (ROOT / "CoachInsights").rglob("*.swift")):
        raise SystemExit("A test filename overlaps app source; scope the exclusions before running")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report_path = OUTPUT / "release-pose-summary.json"
    report_path.unlink(missing_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    results = []
    for kind, title in [("iphone", "iPhone"), ("ipad", "iPad")]:
        name = f"CoachInsights 1.0 {title} QA"
        device = next((d for d in available if d["name"] == name), None)
        if device is None:
            raise SystemExit(f"Run scripts/verify.py first to prepare {name}")
        result = OUTPUT / f"{kind}-release-pose-{stamp}.xcresult"
        log_path = OUTPUT / f"{kind}-release-pose-{stamp}.log"
        print(f"Release pose: {name}; log: {log_path}", flush=True)
        with log_path.open("w") as log:
            run("xcodebuild", "-project", "CoachInsights.xcodeproj", "-scheme", "CoachInsights",
                "-configuration", "Release", "-destination", f"platform=iOS Simulator,id={device['udid']}",
                "-derivedDataPath", "build/ReleasePoseValidation", "-clonedSourcePackagesDirPath", "build/DeviceBuild/SourcePackages",
                "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                "CODE_SIGNING_ALLOWED=NO", "ENABLE_TESTABILITY=YES",
                "EXCLUDED_SOURCE_FILE_NAMES=" + " ".join(excluded),
                "-only-testing:CoachInsightsTests/ReleasePoseTests", "test", stdout=log, stderr=subprocess.STDOUT)
        results.append({"device": kind, "passed": True, "result": str(result), "log": str(log_path)})
        print(f"Release native pose PASS: {kind}", flush=True)
    report_path.write_text(json.dumps({"configuration": "Release", "debugToolsInApp": False,
                                      "testHostEnablesTestability": True, "results": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
