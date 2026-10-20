"""Local-only pose comparison. Input JPEGs/PTS are shared with Apple's Vision."""
import argparse
import importlib.metadata
import json
from pathlib import Path
import time
import urllib.request

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=["lite", "full"], required=True)
    args = parser.parse_args()
    base = Path(__file__).parent
    out = base / "results"
    model = base / "models" / f"pose_landmarker_{args.variant}.task"
    model.parent.mkdir(exist_ok=True)
    if not model.exists():
        url = f"https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_{args.variant}/float16/1/pose_landmarker_{args.variant}.task"
        print(f"Downloading public model: {url}", flush=True)
        urllib.request.urlretrieve(url, model)
    options = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=str(model)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    frames = json.loads((out / "frames.json").read_text())
    rows = []
    with vision.PoseLandmarker.create_from_options(options) as model_runner:
        for frame in frames:
            bgr = cv2.imread(str(out / "frames" / frame["file"]))
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            begin = time.perf_counter()
            result = model_runner.detect_for_video(image, round(frame["seconds"] * 1000))
            elapsed = (time.perf_counter() - begin) * 1000
            people = [
                [{"x": p.x, "y": p.y, "z": p.z, "visibility": p.visibility, "presence": p.presence} for p in person]
                for person in result.pose_landmarks
            ]
            rows.append({"index": frame["index"], "seconds": frame["seconds"], "poseMS": elapsed, "people": people})
            if frame["index"] % 15 == 0:
                print(f"MediaPipe {args.variant} {frame['index']}/{len(frames)}, {elapsed:.1f}ms", flush=True)
    (out / f"mediapipe_{args.variant}.json").write_text(json.dumps({
        "packageVersion": importlib.metadata.version("mediapipe"),
        "variant": args.variant, "backend": "CPU/default Python task delegate, macOS; not iOS latency", "frames": rows,
    }, indent=2))


if __name__ == "__main__":
    main()
