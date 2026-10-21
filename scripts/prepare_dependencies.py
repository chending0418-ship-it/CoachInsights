#!/usr/bin/env python3
"""Fetch the pinned Apache-2.0 pose model for offline bundling. No runtime downloads."""
from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/1/pose_landmarker_full.task"
SHA256 = "5134a3aad27a58b93da0088d431f366da362b44e3ccfbe3462b3827a839011b1"
target = ROOT / "CoachInsights/Resources/pose_landmarker_full.task"
target.parent.mkdir(parents=True, exist_ok=True)
if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != SHA256:
    temporary = target.with_suffix(".partial")
    try:
        subprocess.run(["curl", "-fL", "--retry", "3", URL, "-o", str(temporary)], check=True)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != SHA256:
            raise RuntimeError("Pose model SHA-256 mismatch; refusing to bundle")
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
print("Offline pose model verified:", SHA256)
