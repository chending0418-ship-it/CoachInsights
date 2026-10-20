"""Prepare versioned numerical fixtures and generated coordinate-test images."""
import argparse
from pathlib import Path
import random
import shutil

from PIL import Image, ImageDraw


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=root / "results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ["tracking_config.json", "reference_points.json"]:
        target = args.output / name
        if not target.exists():
            shutil.copyfile(root / "fixtures" / "img_9673" / name, target)

    rng = random.Random(7)
    image = Image.new("RGB", (320, 240), (30, 30, 30))
    draw = ImageDraw.Draw(image)
    for _ in range(300):
        x, y = rng.randrange(320), rng.randrange(240)
        color = tuple(rng.randrange(256) for _ in range(3))
        draw.rectangle((x, y, x + rng.randrange(3, 20), y + rng.randrange(3, 20)), fill=color)
    image.save(args.output / "sanity_a.png")
    translated = Image.new("RGB", image.size)
    translated.paste(image, (10, 5))
    translated.save(args.output / "sanity_b.png")
    print(f"Prepared study inputs in {args.output}")


if __name__ == "__main__":
    main()
