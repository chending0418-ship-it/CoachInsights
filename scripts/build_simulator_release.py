#!/usr/bin/env python3
"""Reproduce an arm64 Universal Release app, optionally install on QA simulators."""
from pathlib import Path
import argparse,json,plistlib,subprocess
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument("--install",action="store_true");args=parser.parse_args()
def run(*cmd,**kwargs):return subprocess.run(cmd,cwd=ROOT,text=True,check=True,**kwargs)
run("python3","scripts/prepare_dependencies.py");run("python3","scripts/generate_project.py")
output=ROOT/"artifacts/release";output.mkdir(parents=True,exist_ok=True)
with (output/"build.log").open("w") as log:
    run("xcodebuild","-project","CoachInsights.xcodeproj","-scheme","CoachInsights","-configuration","Release",
        "-destination","generic/platform=iOS Simulator","-derivedDataPath","build/ReleaseV1","CODE_SIGNING_ALLOWED=NO","build",stdout=log,stderr=subprocess.STDOUT)
app=ROOT/"build/ReleaseV1/Build/Products/Release-iphonesimulator/CoachInsights.app"
with (app/"Info.plist").open("rb") as source:
    bundle_identifier=plistlib.load(source)["CFBundleIdentifier"]
if args.install:
    devices=json.loads(run("xcrun","simctl","list","devices","available","--json",capture_output=True).stdout)
    targets=[d for group in devices["devices"].values() for d in group if d["name"] in ["CoachInsights 1.0 iPhone QA","CoachInsights 1.0 iPad QA"]]
    for target in targets:
        run("xcrun","simctl","bootstatus",target["udid"],"-b")
        subprocess.run(["xcrun","simctl","terminate",target["udid"],bundle_identifier],capture_output=True)
        run("xcrun","simctl","install",target["udid"],str(app));run("xcrun","simctl","launch",target["udid"],bundle_identifier)
        print("Installed Release:",target["name"])
print(app)
