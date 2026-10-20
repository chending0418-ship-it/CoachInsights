"""Download public wheels via a mirror, verify against official PyPI SHA256."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import sys
import urllib.request

from packaging.tags import sys_tags
from packaging.utils import parse_wheel_filename

package = sys.argv[1]
meta = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/{package}/json", timeout=30))
supported = {tag: index for index, tag in enumerate(sys_tags())}
candidates = []
for entry in meta["urls"]:
    if not entry["filename"].endswith(".whl"):
        continue
    tags = parse_wheel_filename(entry["filename"])[3]
    ranks = [supported[t] for t in tags if t in supported]
    if ranks:
        candidates.append((min(ranks), entry))
entry = min(candidates, key=lambda x: x[0])[1]
out = Path(__file__).parent / "downloads" / entry["filename"]
out.parent.mkdir(exist_ok=True)
expected = entry["digests"]["sha256"]
if out.exists() and out.stat().st_size == entry["size"]:
    assert hashlib.file_digest(out.open("rb"), "sha256").hexdigest() == expected
    print("Already verified", out.name, flush=True)
    sys.exit()
offset = out.stat().st_size if out.exists() else 0
prefix = out.with_suffix(".prefix")
if offset:
    shutil.copyfile(out, prefix)
remaining = entry["size"] - offset
chunk_size = (remaining + 3) // 4
url = "https://mirrors.aliyun.com/pypi/packages/" + entry["url"].split("/packages/")[1]


def part(index):
    start = offset + index * chunk_size
    end = min(entry["size"] - 1, start + chunk_size - 1)
    target = out.with_suffix(f".part{index}")
    request = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(request, timeout=40) as response, target.open("wb") as dest:
        if response.status != 206:
            raise RuntimeError("Mirror must support exact HTTP byte ranges")
        while block := response.read(1024 * 1024):
            dest.write(block)
    assert target.stat().st_size == end - start + 1
    print("Downloaded part", index, flush=True)
    return target


print("Fetching", out.name, "remaining MB", round(remaining / 1e6, 1), flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    parts = list(executor.map(part, range(4)))
complete = out.with_suffix(".complete")
with complete.open("wb") as dest:
    if offset:
        with prefix.open("rb") as source:
            shutil.copyfileobj(source, dest)
    for target in parts:
        with target.open("rb") as source:
            shutil.copyfileobj(source, dest)
assert complete.stat().st_size == entry["size"]
assert hashlib.file_digest(complete.open("rb"), "sha256").hexdigest() == expected
complete.replace(out)
for target in [prefix, *parts]:
    target.unlink(missing_ok=True)
print("SHA256 verified against official PyPI:", out.name, flush=True)
