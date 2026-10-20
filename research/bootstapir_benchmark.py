"""Official BootsTAPIR weights; desktop offline feasibility, not an iOS port."""
import json
import argparse
import os
from pathlib import Path
import sys
import time

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
import cv2
import numpy as np
import torch

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT / "vendor"))
from tapnet.torch import tapir_model


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--width',type=int,default=448)
    args=parser.parse_args()
    base = ROOT / "results"
    frames = json.loads((base / "frames.json").read_text())
    config = json.loads((base / "tracking_config.json").read_text())
    # Same whole-frame field of view; resizing follows the model's official interface.
    width, height = args.width, 256
    array = np.stack([cv2.cvtColor(cv2.resize(cv2.imread(str(base / "frames" / f["file"])),
        (width, height)), cv2.COLOR_BGR2RGB) for f in frames])
    # First two queries are baseline tip/knob at frame 0. Extra queries simulate explicit user corrections.
    queries = [[0, s["point"][1] / 720 * height, s["point"][0] / 1280 * width]
        for s in config["seeds"]]
    corrections = [(18, [647, 90]), (42, [546, 368])]
    queries += [[n, p[1] / 720 * height, p[0] / 1280 * width] for n, p in corrections]
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    torch.set_num_threads(4)
    model = tapir_model.TAPIR(pyramid_level=1)
    model.load_state_dict(torch.load(ROOT / "models" / "bootstapir_checkpoint_v2.pt", map_location="cpu", weights_only=True))
    model = model.to(device).eval()
    video = torch.from_numpy(array).float().to(device)[None] / 255 * 2 - 1
    query = torch.tensor(queries, dtype=torch.float32, device=device)[None]
    print(f"BootsTAPIR {device}, video {tuple(video.shape)}, queries {len(queries)}", flush=True)
    begin = time.perf_counter()
    with torch.inference_mode():
        output = model(video, query, query_chunk_size=4)
    if device == "mps":
        torch.mps.synchronize()
    elapsed = time.perf_counter() - begin
    tracks = output["tracks"][0].cpu().numpy()
    visibility = ((1 - torch.sigmoid(output["occlusion"][0])) *
        (1 - torch.sigmoid(output["expected_dist"][0]))).cpu().numpy()
    tracks[..., 0] *= 1280 / width
    tracks[..., 1] *= 720 / height
    rows = []
    corrected_rows = []
    for i, frame in enumerate(frames):
        rows.append({"index": i, "seconds": frame["seconds"],
            "points": tracks[:2, i].tolist(), "visibilityScore": visibility[:2, i].tolist(),
            "valid": (visibility[:2, i] > 0.5).tolist()})
        query_index = 0 if i < 18 else 2 if i < 42 else 3
        corrected_rows.append({"index": i, "seconds": frame["seconds"],
            "points": [tracks[query_index, i].tolist(), tracks[1, i].tolist()],
            "visibilityScore": [float(visibility[query_index, i]), float(visibility[1, i])],
            "valid": [bool(visibility[query_index, i] > 0.5), bool(visibility[1, i] > 0.5)],
            "corrected": i in [18, 42]})
    common = {"torchVersion": torch.__version__, "device": device,
        "inputWidth": width, "inputHeight": height, "elapsedSeconds": elapsed,
        "checkpoint": "bootstapir_checkpoint_v2.pt", "semantics": "Offline noncausal inference; uses the whole clip. No iOS performance claim."}
    suffix='' if width==448 else f'_{width}'
    (base / f"bootstapir{suffix}.json").write_text(json.dumps({**common, "frames": rows}, indent=2))
    (base / f"bootstapir_corrected{suffix}.json").write_text(json.dumps({**common,
        "corrections": [{"index": n, "tip": p} for n, p in corrections], "frames": corrected_rows}, indent=2))
    print(f"BootsTAPIR completed in {elapsed:.2f}s", flush=True)


if __name__ == "__main__":
    main()
