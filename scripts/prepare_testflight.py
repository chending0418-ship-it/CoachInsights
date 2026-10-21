#!/usr/bin/env python3
"""Build and inspect an unsigned iOS archive locally. Never signs or uploads."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/testflight"
ARCHIVE = ROOT / "build/TestFlightPreflight/CoachInsights-unsigned.xcarchive"
MODEL_SHA256 = "5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1"


def run(*cmd, **kwargs):
    return subprocess.run(cmd, cwd=ROOT, text=True, check=True, **kwargs)


def plist(path):
    with path.open("rb") as source:
        return plistlib.load(source)


def uuids(binary):
    output = run("xcrun", "dwarfdump", "--uuid", str(binary), capture_output=True).stdout
    return set(re.findall(r"UUID: ([A-Fa-f0-9-]+)", output))


def inspect(archive):
    app = archive / "Products/Applications/CoachInsights.app"
    info = plist(app / "Info.plist")
    archive_info = plist(archive / "Info.plist")
    checks = {}

    def check(name, passed):
        checks[name] = bool(passed)

    check("application_archive", archive_info.get("ApplicationProperties", {}).get("ApplicationPath") == "Applications/CoachInsights.app")
    check("ios_device_build", info.get("DTPlatformName") == "iphoneos")
    check("sdk_at_least_26", int(info.get("DTSDKName", "iphoneos0").removeprefix("iphoneos").split(".")[0]) >= 26)
    check("iphone_and_ipad", set(info.get("UIDeviceFamily", [])) == {1, 2})
    check("minimum_ios_17", info.get("MinimumOSVersion") == "17.0")
    check("version_present", bool(info.get("CFBundleShortVersionString")) and bool(info.get("CFBundleVersion")))
    check("display_name", info.get("CFBundleDisplayName") == "Coach Insights")
    check("usage_descriptions", all(info.get(key) for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"]))
    check("encryption_declaration", info.get("ITSAppUsesNonExemptEncryption") is False)
    check("compiled_icons", (app / "Assets.car").is_file() and bool(info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon")))
    model = app / "pose_landmarker_full.task"
    check("offline_model_checksum", model.is_file() and hashlib.sha256(model.read_bytes()).hexdigest() == MODEL_SHA256)
    check("mediapipe_license", (app / "MediaPipe-LICENSE.txt").is_file())
    privacy = plist(app / "PrivacyInfo.xcprivacy")
    check("local_privacy_declaration", privacy.get("NSPrivacyTracking") is False and privacy.get("NSPrivacyCollectedDataTypes") == [])
    for name in ["Abseil_Privacy", "Protobuf_Privacy"]:
        path = app / f"{name}.bundle/PrivacyInfo.xcprivacy"
        check(name, path.is_file() and plist(path).get("NSPrivacyTracking") is False)
    files = [path for path in app.rglob("*") if path.is_file()]
    forbidden = [str(path.relative_to(app)) for path in files if
                 path.suffix.lower() in {".mov", ".mp4", ".m4v", ".xctest"} or
                 any(term in str(path.relative_to(app)).lower() for term in ["localfixtures", "pose_landmarker_heavy", "xctest.framework", ".debug.dylib"])]
    check("no_test_media_or_debug_libraries", not forbidden)
    check("app_symbols_match", bool(uuids(app / "CoachInsights")) and uuids(app / "CoachInsights") == uuids(archive / "dSYMs/CoachInsights.app.dSYM"))
    framework_symbols = []
    for framework in sorted((app / "Frameworks").glob("*.framework")):
        binary = framework / framework.stem
        archs = run("xcrun", "lipo", "-archs", str(binary), capture_output=True).stdout.split()
        check(f"{framework.stem}_arm64", archs == ["arm64"])
        dsym = archive / f"dSYMs/{framework.name}.dSYM"
        if not dsym.exists():
            framework_symbols.append(framework.name)
    app_archs = run("xcrun", "lipo", "-archs", str(app / "CoachInsights"), capture_output=True).stdout.split()
    check("app_arm64", app_archs == ["arm64"])
    return {
        "localChecksPassed": all(checks.values()),
        "uploadReady": False,
        "signed": False,
        "notice": "Unsigned local preflight only. Select a paid Developer team, archive again in Xcode, and validate/upload manually.",
        "archive": str(archive),
        "bundleIdentifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "sdk": info["DTSDKName"],
        "appSizeMiB": round(sum(path.stat().st_size for path in files) / 1024 ** 2, 2),
        "checks": checks,
        "unexpectedFiles": forbidden,
        "vendorFrameworksWithoutDSYM": framework_symbols,
        "limitations": [
            "Apple account membership, bundle ID ownership, signing and server-side validation require your Apple account.",
            "The pinned vendor frameworks do not supply dSYMs; Xcode may report missing vendor symbols during upload. The app dSYM is checked separately.",
            "Local manifest checks do not replace Organizer validation or Apple's SDK privacy/signature checks."
        ]
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-only", action="store_true", help="Inspect the existing unsigned preflight archive without rebuilding")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Avoid leaving a stale success report when a new build fails.
    report_path = OUTPUT / "preflight.json"
    report_path.unlink(missing_ok=True)
    if not args.inspect_only:
        run(sys.executable, "scripts/prepare_dependencies.py")
        run(sys.executable, "scripts/generate_project.py")
        ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
        print("Building unsigned iOS archive; log:", OUTPUT / "archive.log", flush=True)
        with (OUTPUT / "archive.log").open("w") as log:
            run("xcodebuild", "-project", "CoachInsights.xcodeproj", "-scheme", "CoachInsights",
                "-configuration", "Release", "-destination", "generic/platform=iOS",
                "-derivedDataPath", "build/DeviceBuild", "-archivePath", str(ARCHIVE),
                "CODE_SIGNING_ALLOWED=NO", "archive", stdout=log, stderr=subprocess.STDOUT)
    report = inspect(ARCHIVE)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report["localChecksPassed"]:
        raise SystemExit("Preflight failed; inspect artifacts/testflight/preflight.json")


if __name__ == "__main__":
    main()
