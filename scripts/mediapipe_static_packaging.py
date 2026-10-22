#!/usr/bin/env python3
"""Remove Xcode's empty MediaPipe wrappers after static linking, before signing.

The pinned SDK contains static archives. Xcode copies their resource wrappers,
removes the archives, then injects empty dylibs without dSYMs. These bundles have
no resources or runtime clients. Never remove a real dylib, a resource bundle,
or a wrapper referenced by any Mach-O image in the app.
"""
from pathlib import Path
import argparse
import json
import plistlib
import shutil
import struct

NAMES = (
    "MediaPipeTasksAudio", "MediaPipeTasksCommon", "MediaPipeTasksDecision",
    "MediaPipeTasksRetrieval", "MediaPipeTasksText", "MediaPipeTasksVision",
)
MACH_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}


class PackagingError(RuntimeError):
    pass


def images(data):
    """Inspect 64-bit Mach-O slices, including a universal binary's slices."""
    magic = data[:4]
    if magic in {b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}:
        count = struct.unpack_from(">I", data, 4)[0]
        if not 0 < count <= 16:
            raise PackagingError("Unexpected universal binary slice count")
        stride = 32 if magic == b"\xca\xfe\xba\xbf" else 20
        result = []
        for index in range(count):
            offset = 8 + index * stride
            start, size = struct.unpack_from(">QQ" if stride == 32 else ">II", data, offset + 8)
            if start + size > len(data):
                raise PackagingError("Invalid universal binary slice bounds")
            result.extend(images(data[start:start + size]))
        return result
    if magic not in {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"}:
        raise PackagingError("Expected a 64-bit Mach-O image")
    endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
    _, _, _, filetype, count, commands_size, _, _ = struct.unpack_from(endian + "8I", data)
    end, offset = 32 + commands_size, 32
    if end > len(data):
        raise PackagingError("Invalid Mach-O load command bounds")
    result = {"filetype": filetype, "sections": [], "dependencies": [], "hasExports": False}

    def check_exports(start, size):
        if start + size > len(data):
            raise PackagingError("Invalid Mach-O export trie bounds")
        # Apple's linker emits an eight-byte zero-filled trie for an empty
        # dylib. Any terminal, child edge or symbol makes this nonzero.
        result["hasExports"] |= any(data[start:start + size])
    for _ in range(count):
        cmd, size = struct.unpack_from(endian + "II", data, offset)
        if size < 8 or offset + size > end:
            raise PackagingError("Invalid Mach-O load command")
        if cmd == 0x19:  # LC_SEGMENT_64
            sections = struct.unpack_from(endian + "I", data, offset + 64)[0]
            if size < 72 + sections * 80:
                raise PackagingError("Invalid Mach-O section bounds")
            for index in range(sections):
                section = offset + 72 + index * 80
                name = data[section:section + 16].rstrip(b"\0").decode()
                length = struct.unpack_from(endian + "Q", data, section + 40)[0]
                result["sections"].append((name, length))
        elif cmd in {0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x20, 0x23 | 0x80000000}:
            start = offset + struct.unpack_from(endian + "I", data, offset + 8)[0]
            if not offset + 8 <= start < offset + size:
                raise PackagingError("Invalid Mach-O dependency name")
            result["dependencies"].append(data[start:offset + size].split(b"\0", 1)[0].decode())
        elif cmd in {0x22, 0x22 | 0x80000000}:  # LC_DYLD_INFO[_ONLY]
            check_exports(*struct.unpack_from(endian + "II", data, offset + 40))
        elif cmd == 0x33 | 0x80000000:  # LC_DYLD_EXPORTS_TRIE
            check_exports(*struct.unpack_from(endian + "II", data, offset + 8))
        offset += size
    return [result]


def removal_plan(app, products):
    if not app.is_dir() or app.suffix != ".app":
        raise PackagingError("Expected the built .app directory")
    if not (app / app.stem).is_file():
        raise PackagingError("The main executable must be linked before inspecting runtime dependencies")
    candidates = []
    for name in NAMES:
        wrapper = app / "Frameworks" / f"{name}.framework"
        if not wrapper.exists():
            continue
        if wrapper.is_symlink():
            raise PackagingError(f"Refusing a symlinked wrapper: {name}")
        source = products / f"{name}.framework" / name
        if not source.is_file():
            raise PackagingError(f"{name}: missing linked static archive")
        with source.open("rb") as linked_input:
            is_archive = linked_input.read(8) == b"!<arch>\n"
        if not is_archive:
            raise PackagingError(f"{name}: linked input is not the expected static archive")
        for path in wrapper.rglob("*"):
            if path.is_symlink():
                raise PackagingError(f"{name}: refusing a symlink inside the wrapper")
            if path.is_file() and path.relative_to(wrapper).as_posix() not in {
                name, "Info.plist", "_CodeSignature/CodeResources",
            }:
                raise PackagingError(f"{name}: wrapper contains resources; preserve it")
        with (wrapper / "Info.plist").open("rb") as source_info:
            if plistlib.load(source_info).get("CFBundleExecutable") != name:
                raise PackagingError(f"{name}: unexpected executable name")
        for image in images((wrapper / name).read_bytes()):
            if image["filetype"] != 6 or image["hasExports"] or any(size for _, size in image["sections"]):
                raise PackagingError(f"{name}: wrapper has code/data/exports; preserve it")
        candidates.append(wrapper)
    # Validate the entire app before deleting anything. Also covers Debug dylibs
    # and future app extensions, not just the main executable's direct links.
    for path in app.rglob("*"):
        if not path.is_file() or any(wrapper == path or wrapper in path.parents for wrapper in candidates):
            continue
        with path.open("rb") as stream:
            magic = stream.read(4)
        if magic not in MACH_MAGICS:
            continue
        for image in images(path.read_bytes()):
            for dependency in image["dependencies"]:
                if any(f"/{wrapper.name}/" in dependency for wrapper in candidates):
                    raise PackagingError(f"{path.name}: runtime dependency on {dependency}; preserve wrappers")
    return candidates


def remove_wrappers(app, products):
    candidates = removal_plan(app, products)
    for wrapper in candidates:
        shutil.rmtree(wrapper)
    return [wrapper.name for wrapper in candidates]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--built-products", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    removed = remove_wrappers(args.app, args.built_products)
    args.report.write_text(json.dumps({"removedEmptyStaticWrappers": removed}, indent=2) + "\n")
    print(f"MediaPipe static packaging: removed {len(removed)} empty wrappers; statically linked code and app dSYM retained.")


if __name__ == "__main__":
    main()
