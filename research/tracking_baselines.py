"""Identical human initial points; no automatic detections or resets."""
import json
from pathlib import Path
import time

import cv2
import numpy as np

BASE = Path(__file__).parent / "results"


def run_lk(frames, seeds, corrections=None):
    previous = None
    points = np.array([s["point"] for s in seeds], np.float32).reshape(-1, 1, 2)
    rows = []
    for frame in frames:
        image = cv2.imread(str(BASE / "frames" / frame["file"]))
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        start = time.perf_counter()
        flags = [True] * len(seeds)
        fb_errors = [0.0] * len(seeds)
        if previous is not None:
            nxt, status, error = cv2.calcOpticalFlowPyrLK(previous, gray, points, None,
                winSize=(31, 31), maxLevel=4,
                criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 40, 0.01))
            back, back_status, _ = cv2.calcOpticalFlowPyrLK(gray, previous, nxt, None,
                winSize=(31, 31), maxLevel=4,
                criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 40, 0.01))
            fb = np.linalg.norm(back - points, axis=2).reshape(-1)
            fb_errors = fb.astype(float).tolist()
            flags = [(bool(a) and bool(b) and float(c) < 2.0 and float(e) < 30.0)
                for a,b,c,e in zip(status.reshape(-1), back_status.reshape(-1), fb, error.reshape(-1))]
            points = nxt  # Preserve raw outputs for diagnosing drift; flags are not correctness labels.
        corrected = False
        if corrections and str(frame["index"]) in corrections:
            points[0, 0] = corrections[str(frame["index"])]["tip"]
            flags[0] = True
            corrected = True
        rows.append({"index": frame["index"], "seconds": frame["seconds"],
            "points": points.reshape(-1, 2).astype(float).tolist(),
            "valid": flags, "forwardBackwardError": fb_errors,
            "corrected": corrected, "trackMS": (time.perf_counter() - start) * 1000})
        previous = gray
    return rows


def run_csrt(frames, seeds):
    rows = []
    trackers = [cv2.TrackerCSRT_create() for _ in seeds]
    for frame in frames:
        image = cv2.imread(str(BASE / "frames" / frame["file"]))
        begin = time.perf_counter()
        points = []
        valid = []
        for tracker, seed in zip(trackers, seeds):
            if frame["index"] == 0:
                x, y, w, h = seed["rect"]
                rect = tuple(round(x) for x in (x * 1280, y * 720, w * 1280, h * 720))
                tracker.init(image, rect)
                success = True
            else:
                success, rect = tracker.update(image)
            x, y, w, h = rect
            points.append([float(x + w/2), float(y + h/2)])
            valid.append(bool(success))
        rows.append({"index": frame["index"], "seconds": frame["seconds"], "points": points,
            "valid": valid, "trackMS": (time.perf_counter() - begin) * 1000})
    return rows


if __name__ == "__main__":
    frames = json.loads((BASE / "frames.json").read_text())
    seeds = json.loads((BASE / "tracking_config.json").read_text())["seeds"]
    corrections = {"18": {"tip": [647, 90]}, "42": {"tip": [546, 368]}}
    for name, rows in [("opencv_lk", run_lk(frames, seeds)),
                       ("opencv_lk_corrected", run_lk(frames, seeds, corrections)),
                       ("opencv_csrt", run_csrt(frames, seeds))]:
        (BASE / f"{name}.json").write_text(json.dumps(rows, indent=2))
        print(name, "saved", flush=True)
