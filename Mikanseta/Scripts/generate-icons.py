#!/usr/bin/env python3
"""Export every Mikanseta platform icon from Artwork/AppIcon.png."""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "Artwork" / "AppIcon.png"
WINDOWS_SIZES = (16, 24, 32, 48, 64, 128, 256)


def image_properties(path: Path) -> tuple[int, int, bool]:
    output = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        text=True,
    )
    values: dict[str, str] = {}
    for line in output.splitlines():
        if ":" in line:
            key, value = line.split(":", maxsplit=1)
            values[key.strip()] = value.strip()
    return int(values["pixelWidth"]), int(values["pixelHeight"]), values["hasAlpha"] == "yes"


def resize(source: Path, target: Path, size: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(source), "--out", str(target)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def export_asset_catalog(source: Path, platform: str) -> None:
    folder = ROOT / platform / "Runner/Assets.xcassets/AppIcon.appiconset"
    contents_path = folder / "Contents.json"
    contents = json.loads(contents_path.read_text())
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        logical_size = float(image["size"].split("x", maxsplit=1)[0])
        scale = float(image.get("scale", "1x").removesuffix("x"))
        pixel_size = round(logical_size * scale)
        resize(source, folder / filename, pixel_size)


def export_android(source: Path) -> None:
    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, pixel_size in sizes.items():
        target = ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        resize(source, target, pixel_size)


def export_windows(source: Path) -> None:
    target = ROOT / "windows/runner/resources/app_icon.ico"
    target.parent.mkdir(parents=True, exist_ok=True)
    frames: list[bytes] = []
    entries: list[bytes] = []
    data_offset = 6 + len(WINDOWS_SIZES) * 16

    with tempfile.TemporaryDirectory(prefix="mikanseta-icon-") as temporary_directory:
        temporary = Path(temporary_directory)
        for pixel_size in WINDOWS_SIZES:
            frame_path = temporary / f"{pixel_size}.png"
            resize(source, frame_path, pixel_size)
            frame = frame_path.read_bytes()
            if not frame.startswith(b"\x89PNG\r\n\x1a\n"):
                raise RuntimeError(f"sips did not produce a PNG frame: {frame_path}")

            dimension_byte = 0 if pixel_size == 256 else pixel_size
            entries.append(
                struct.pack(
                    "<BBBBHHII",
                    dimension_byte,
                    dimension_byte,
                    0,
                    0,
                    1,
                    32,
                    len(frame),
                    data_offset,
                )
            )
            frames.append(frame)
            data_offset += len(frame)

    header = struct.pack("<HHH", 0, 1, len(WINDOWS_SIZES))
    target.write_bytes(header + b"".join(entries) + b"".join(frames))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export iOS, macOS, Android, and Windows icons from one 1024px PNG."
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help=f"opaque 1024x1024 PNG source (default: {DEFAULT_SOURCE})",
    )
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    if not source.is_file():
        parser.error(f"icon source does not exist: {source}")
    width, height, has_alpha = image_properties(source)
    if (width, height) != (1024, 1024):
        parser.error(f"icon source must be exactly 1024x1024, got {width}x{height}")
    if has_alpha:
        parser.error("icon source must be opaque; sips reports an alpha channel")

    export_asset_catalog(source, "ios")
    export_asset_catalog(source, "macos")
    export_android(source)
    export_windows(source)
    print(f"Exported platform icons from {source}")


if __name__ == "__main__":
    main()
