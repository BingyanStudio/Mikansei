#!/usr/bin/env python3
"""Validate the primary iPhone and iPad icons in an iOS app or archive."""

import argparse
import plistlib
import struct
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
REQUIRED_ICONS = (
    ("iPhone", "CFBundleIcons", (120, 120)),
    ("iPad", "CFBundleIcons~ipad", (152, 152)),
)


class IconCheckError(Exception):
    """An expected archive validation failure with a safe user-facing message."""


def locate_app_bundle(path):
    if path.is_symlink():
        raise IconCheckError("Input path must not be a symbolic link.")
    if not path.is_dir():
        raise IconCheckError("Input path must be an existing .xcarchive or .app directory.")

    if path.suffix == ".app":
        return path
    if path.suffix != ".xcarchive":
        raise IconCheckError("Input path must end in .xcarchive or .app.")

    applications = path / "Products" / "Applications"
    preferred = applications / "Mikansei.app"
    if preferred.is_dir() and not preferred.is_symlink():
        return preferred

    candidates = []
    if applications.is_dir() and not applications.is_symlink():
        candidates = sorted(
            item
            for item in applications.iterdir()
            if item.suffix == ".app" and item.is_dir() and not item.is_symlink()
        )
    if len(candidates) == 1:
        return candidates[0]
    raise IconCheckError("Archive does not contain a unique application bundle.")


def read_png_dimensions(path):
    try:
        with path.open("rb") as image:
            file_size = path.stat().st_size
            if image.read(len(PNG_SIGNATURE)) != PNG_SIGNATURE:
                raise IconCheckError("A referenced icon file is not a PNG.")

            while image.tell() + 8 <= file_size:
                chunk_header = image.read(8)
                if len(chunk_header) != 8:
                    break
                chunk_length, chunk_type = struct.unpack(">I4s", chunk_header)
                chunk_data_offset = image.tell()
                chunk_end = chunk_data_offset + chunk_length + 4
                if chunk_end > file_size:
                    raise IconCheckError("A referenced PNG has a truncated chunk.")

                if chunk_type == b"IHDR":
                    if chunk_length != 13:
                        raise IconCheckError("A referenced PNG has an invalid IHDR chunk.")
                    image_header = image.read(13)
                    if len(image_header) != 13:
                        raise IconCheckError("A referenced PNG has a truncated IHDR chunk.")
                    width, height = struct.unpack(">II", image_header[:8])
                    if width < 1 or height < 1:
                        raise IconCheckError("A referenced PNG has invalid dimensions.")
                    return width, height

                # AppleCgBI is a valid leading chunk in optimized iOS PNGs.
                # Skip unknown chunks until the standard IHDR supplies dimensions.
                image.seek(chunk_end)
    except IconCheckError:
        raise
    except (OSError, struct.error):
        raise IconCheckError("A referenced PNG could not be read.")

    raise IconCheckError("A referenced PNG does not contain an IHDR chunk.")


def png_candidates(app_bundle, reference):
    if not isinstance(reference, str) or not reference:
        raise IconCheckError("Primary icon metadata contains an invalid PNG reference.")
    if (
        Path(reference).name != reference
        or "/" in reference
        or "\\" in reference
        or "\x00" in reference
    ):
        raise IconCheckError("Primary icon metadata contains an invalid PNG reference.")

    if reference.lower().endswith(".png"):
        names = (reference,)
    else:
        names = [reference + ".png"]
        for scale in ("@1x", "@2x", "@3x"):
            names.append(reference + scale + ".png")
            for idiom in ("~iphone", "~ipad"):
                names.append(reference + scale + idiom + ".png")
        names.extend(
            reference + idiom + ".png" for idiom in ("~iphone", "~ipad")
        )

    result = []
    for name in names:
        candidate = app_bundle / name
        if candidate.is_file() and not candidate.is_symlink():
            result.append(candidate)
    return result


def verify_primary_icon(app_bundle, info, platform, plist_key, required_size):
    platform_icons = info.get(plist_key)
    if not isinstance(platform_icons, dict):
        raise IconCheckError("{} primary icon metadata is missing.".format(platform))

    primary_icon = platform_icons.get("CFBundlePrimaryIcon")
    if not isinstance(primary_icon, dict):
        raise IconCheckError("{} primary icon metadata is missing.".format(platform))
    if primary_icon.get("CFBundleIconName") != "AppIcon":
        raise IconCheckError(
            "{} primary CFBundleIconName must be AppIcon.".format(platform)
        )

    references = primary_icon.get("CFBundleIconFiles")
    if not isinstance(references, list) or not references:
        raise IconCheckError(
            "{} primary icon does not reference any PNG files.".format(platform)
        )

    found_size = False
    for reference in references:
        for candidate in png_candidates(app_bundle, reference):
            if read_png_dimensions(candidate) == required_size:
                found_size = True
    if not found_size:
        dimensions = "{}x{}".format(*required_size)
        raise IconCheckError(
            "{} primary icon does not reference a {} PNG.".format(
                platform, dimensions
            )
        )


def validate_app_bundle(app_bundle):
    info_path = app_bundle / "Info.plist"
    if not info_path.is_file() or info_path.is_symlink():
        raise IconCheckError("Application Info.plist is missing.")

    try:
        with info_path.open("rb") as info_file:
            info = plistlib.load(info_file)
    except (
        OSError,
        plistlib.InvalidFileException,
        ExpatError,
        ValueError,
        TypeError,
    ):
        raise IconCheckError("Application Info.plist could not be read.")
    if not isinstance(info, dict):
        raise IconCheckError("Application Info.plist has an invalid format.")

    assets_catalog = app_bundle / "Assets.car"
    if not assets_catalog.is_file() or assets_catalog.is_symlink():
        raise IconCheckError("Application Assets.car is missing.")
    try:
        if assets_catalog.stat().st_size == 0:
            raise IconCheckError("Application Assets.car is empty.")
    except OSError:
        raise IconCheckError("Application Assets.car could not be read.")

    for platform, plist_key, dimensions in REQUIRED_ICONS:
        verify_primary_icon(app_bundle, info, platform, plist_key, dimensions)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "Check iPhone and iPad primary icon metadata and PNG dimensions "
            "in an iOS .xcarchive or .app."
        )
    )
    parser.add_argument("path", help="Path to an iOS .xcarchive or .app directory.")
    arguments = parser.parse_args(argv)

    try:
        app_bundle = locate_app_bundle(Path(arguments.path).expanduser())
        validate_app_bundle(app_bundle)
    except IconCheckError as error:
        print("ERROR: iOS archive icon check failed: {}".format(error), file=sys.stderr)
        return 1
    except OSError:
        print(
            "ERROR: iOS archive icon check failed: archive or app bundle could not be read.",
            file=sys.stderr,
        )
        return 1

    print(
        "iOS app icon check passed: iPhone and iPad use AppIcon; "
        "120x120 and 152x152 PNGs and Assets.car are present."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
