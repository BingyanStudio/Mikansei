#!/usr/bin/env python3
"""Check a Mikanseta archive's release identity, extension and public config input."""

import argparse
import base64
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path


class CheckError(Exception):
    pass


def check_ios_icons(root, app):
    sys.path.insert(0, str(root / "Scripts"))
    try:
        from check_ios_archive_icons import IconCheckError, validate_app_bundle
        validate_app_bundle(app)
    except ImportError:
        raise CheckError("The shared iOS AppIcon validation helper is unavailable.")
    except IconCheckError as error:
        raise CheckError("The archived Mikanseta iPhone/iPad AppIcon check failed: {}".format(error))


def read_plist(path):
    if not path.is_file() or path.is_symlink():
        raise CheckError("A required archive property list or privacy manifest is missing.")
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError):
        raise CheckError("A required archive property list or privacy manifest is invalid.")
    if not isinstance(value, dict):
        raise CheckError("A required archive property list has an invalid format.")
    return value


def release_targets(root):
    project = root / "Mikanseta/ios/Mikanseta.xcodeproj/project.pbxproj"
    try:
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(project)],
            check=True, capture_output=True, text=True,
        )
        objects = json.loads(result.stdout)["objects"]
        targets = {}
        for target in objects.values():
            name = target.get("name")
            if target.get("isa") != "PBXNativeTarget" or name not in ("Mikanseta", "MikansetaWidgets"):
                continue
            config_list = objects[target["buildConfigurationList"]]
            release = next(
                objects[item] for item in config_list["buildConfigurations"]
                if objects[item].get("name") == "Release"
            )
            targets[name] = release["buildSettings"]
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, KeyError, StopIteration, TypeError):
        raise CheckError("The Mikanseta iOS project release settings could not be read.")
    if set(targets) != {"Mikanseta", "MikansetaWidgets"}:
        raise CheckError("The Mikanseta App and Widget release targets are both required.")
    return targets


def expected_public_defines(root):
    sys.path.insert(0, str(root / "Scripts"))
    try:
        from supabase_config import CLIENT_KEY, PUBLIC_RESOURCE_PATH, URL_KEY, validate_client_configuration
        with (root / PUBLIC_RESOURCE_PATH).open("rb") as handle:
            client = validate_client_configuration(plistlib.load(handle))
        if client is None:
            raise ValueError
        return {
            "SUPABASE_URL=" + client[URL_KEY],
            "SUPABASE_ANON_KEY=" + client[CLIENT_KEY],
        }
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException):
        raise CheckError("The tracked public Supabase client configuration is missing or invalid.")


def check_generated_configuration(root, expected):
    generated = root / "Mikanseta/ios/Flutter/Generated.xcconfig"
    try:
        lines = generated.read_text(encoding="utf-8").splitlines()
        encoded = next(line.partition("=")[2] for line in lines if line.startswith("DART_DEFINES="))
        decoded = {
            base64.b64decode(item, validate=True).decode("utf-8")
            for item in encoded.split(",") if item
        }
    except (OSError, StopIteration, ValueError, UnicodeError):
        raise CheckError("Generated Flutter iOS configuration has no valid Dart defines.")
    if not expected.issubset(decoded):
        raise CheckError("Generated Flutter iOS configuration does not include the validated public client defines.")


def check_archive(root, archive):
    if archive.suffix != ".xcarchive" or archive.is_symlink() or not archive.is_dir():
        raise CheckError("Xcode Cloud did not provide a readable Mikanseta .xcarchive.")
    app = archive / "Products/Applications/Mikanseta.app"
    widget = app / "PlugIns/MikansetaWidgets.appex"
    check_ios_icons(root, app)
    app_info = read_plist(app / "Info.plist")
    widget_info = read_plist(widget / "Info.plist")
    targets = release_targets(root)
    app_settings = targets["Mikanseta"]
    widget_settings = targets["MikansetaWidgets"]

    try:
        version_line = next(
            line for line in (root / "Mikanseta/pubspec.yaml").read_text(encoding="utf-8").splitlines()
            if line.startswith("version:")
        )
        expected_version = version_line.partition(":")[2].strip().split("+", 1)[0]
    except (OSError, StopIteration):
        raise CheckError("Mikanseta's source version could not be read.")

    if widget_settings.get("MARKETING_VERSION") != expected_version:
        raise CheckError("The Widget target marketing version differs from pubspec.yaml.")
    if app_info.get("CFBundleIdentifier") != app_settings.get("PRODUCT_BUNDLE_IDENTIFIER"):
        raise CheckError("The archived App bundle identifier differs from the Mikanseta Release target.")
    if widget_info.get("CFBundleIdentifier") != widget_settings.get("PRODUCT_BUNDLE_IDENTIFIER"):
        raise CheckError("The archived Widget bundle identifier differs from the Mikanseta Release target.")
    if app_info.get("CFBundleShortVersionString") != expected_version or widget_info.get("CFBundleShortVersionString") != expected_version:
        raise CheckError("The archived App and Widget versions do not match pubspec.yaml.")
    app_build = str(app_info.get("CFBundleVersion", ""))
    widget_build = str(widget_info.get("CFBundleVersion", ""))
    if not re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", app_build) or app_build != widget_build:
        raise CheckError("The archived App and Widget build numbers are invalid or differ.")

    for bundle in (app, widget):
        manifest = read_plist(bundle / "PrivacyInfo.xcprivacy")
        if (
            not isinstance(manifest.get("NSPrivacyTracking"), bool)
            or not isinstance(manifest.get("NSPrivacyCollectedDataTypes"), list)
            or not isinstance(manifest.get("NSPrivacyAccessedAPITypes"), list)
        ):
            raise CheckError("The archived App or Widget privacy manifest is incomplete.")
    if app_info.get("NSSupportsLiveActivities") is not True:
        raise CheckError("The archived App does not enable Live Activities.")
    check_generated_configuration(root, expected_public_defines(root))
    return expected_version, app_build


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        version, build = check_archive(args.root, args.archive)
    except CheckError as error:
        print("ERROR: Mikanseta TestFlight archive check failed: {}".format(error), file=sys.stderr)
        return 1
    except OSError:
        print("ERROR: Mikanseta TestFlight archive check failed; the archive could not be read.", file=sys.stderr)
        return 1
    print("Mikanseta Xcode Cloud archive check passed: App and Widget identity, version {} ({}), asset catalog, privacy manifests and public client defines are present.".format(version, build))
    return 0


if __name__ == "__main__":
    sys.exit(main())
