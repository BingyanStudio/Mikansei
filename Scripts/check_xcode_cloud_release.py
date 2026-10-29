#!/usr/bin/env python3
"""Fail a native cloud build when release identity or bundled resources are incomplete."""

import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError

from check_ios_archive_icons import (
    IconCheckError,
    locate_app_bundle,
    validate_app_bundle,
)
from supabase_config import (
    RESOURCE_PATH,
    load_client_configuration,
    validate_client_configuration,
)


class ReleaseCheckError(Exception):
    pass


def read_plist(path):
    if not path.is_file() or path.is_symlink():
        raise ReleaseCheckError("Required property list is missing: {}".format(path.name))
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    if not isinstance(data, dict):
        raise ReleaseCheckError("Property list is not a dictionary: {}".format(path.name))
    return data


def project_metadata(root):
    project = root / "Mikansei.xcodeproj" / "project.pbxproj"
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(project)],
        check=True, capture_output=True, text=True,
    )
    objects = json.loads(result.stdout)["objects"]
    targets = {}
    for target in objects.values():
        if target.get("isa") != "PBXNativeTarget":
            continue
        name = target.get("name")
        if name not in ("Mikansei", "MikanseiWidgets"):
            continue
        configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
        settings = [
            objects[identifier]["buildSettings"] for identifier in configurations
        ]
        if len(settings) != 2:
            raise ReleaseCheckError("{} must have Debug and Release configurations.".format(name))
        fields = ("DEVELOPMENT_TEAM", "PRODUCT_BUNDLE_IDENTIFIER",
                  "MARKETING_VERSION", "CURRENT_PROJECT_VERSION")
        identity = {field: settings[0].get(field) for field in fields}
        for configuration in settings:
            if any(configuration.get(field) != identity[field] for field in fields):
                raise ReleaseCheckError("{} configurations disagree on release identity.".format(name))
            if configuration.get("CODE_SIGN_STYLE") != "Automatic":
                raise ReleaseCheckError("{} must use automatic signing.".format(name))
            if name == "Mikansei" and configuration.get("ASSETCATALOG_COMPILER_APPICON_NAME") != "AppIcon":
                raise ReleaseCheckError("Main target must select the AppIcon asset set.")
        if not re.fullmatch(r"[A-Z0-9]{10}", identity["DEVELOPMENT_TEAM"] or ""):
            raise ReleaseCheckError("{} has no valid signing Team.".format(name))
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", identity["MARKETING_VERSION"] or ""):
            raise ReleaseCheckError("{} has no valid marketing version.".format(name))
        if not re.fullmatch(r"[1-9][0-9]*", identity["CURRENT_PROJECT_VERSION"] or ""):
            raise ReleaseCheckError("{} has no valid build number.".format(name))
        resources = set()
        for phase_id in target.get("buildPhases", []):
            phase = objects[phase_id]
            for build_id in phase.get("files", []):
                reference = objects.get(objects[build_id].get("fileRef"), {})
                path = reference.get("path")
                if phase.get("isa") == "PBXResourcesBuildPhase" and path:
                    resources.add(path)
                if phase.get("isa") in ("PBXResourcesBuildPhase", "PBXSourcesBuildPhase") and path:
                    if not (root / path).exists():
                        raise ReleaseCheckError("Project references a missing source/resource: {}".format(path))
        required = (
            {"App/Assets.xcassets", "App/PrivacyInfo.xcprivacy", str(RESOURCE_PATH)}
            if name == "Mikansei" else {"Widgets/PrivacyInfo.xcprivacy"}
        )
        if not required.issubset(resources):
            raise ReleaseCheckError("{} lacks required resource references.".format(name))
        if name == "MikanseiWidgets" and str(RESOURCE_PATH) in resources:
            raise ReleaseCheckError("Widgets must not include the cloud client configuration.")
        if name == "Mikansei" and any(Path(path).name.startswith("AppIcon") and path.endswith(".png") for path in resources):
            raise ReleaseCheckError("Legacy loose AppIcon PNGs must not be copied with the asset catalog.")
        targets[name] = identity
    if set(targets) != {"Mikansei", "MikanseiWidgets"}:
        raise ReleaseCheckError("The main app and widget targets are both required.")
    app, widget = targets["Mikansei"], targets["MikanseiWidgets"]
    for field in ("DEVELOPMENT_TEAM", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        if app[field] != widget[field]:
            raise ReleaseCheckError("App and widgets disagree on {}.".format(field))
    if widget["PRODUCT_BUNDLE_IDENTIFIER"] != app["PRODUCT_BUNDLE_IDENTIFIER"] + ".widgets":
        raise ReleaseCheckError("The widget bundle ID must match the host app plus .widgets.")
    info = read_plist(root / "App/Info.plist")
    if any(key in info for key in ("CFBundleIcons", "CFBundleIcons~ipad")):
        raise ReleaseCheckError("Primary icon metadata must be generated by the asset compiler.")
    return targets


def check_source(root):
    targets = project_metadata(root)
    expected = load_client_configuration(root)
    generated = validate_client_configuration(read_plist(root / RESOURCE_PATH))
    if expected is None or generated is None or expected != generated:
        raise ReleaseCheckError("The generated public client configuration is missing or invalid.")
    for path in ("App/PrivacyInfo.xcprivacy", "Widgets/PrivacyInfo.xcprivacy"):
        read_plist(root / path)
    return targets, expected


def check_archive(root, archive, targets, expected):
    app = locate_app_bundle(archive)
    validate_app_bundle(app)
    widget = app / "PlugIns" / "MikanseiWidgets.appex"
    app_info = read_plist(app / "Info.plist")
    widget_info = read_plist(widget / "Info.plist")
    for name, info, bundle in (
        ("Mikansei", app_info, app), ("MikanseiWidgets", widget_info, widget)
    ):
        settings = targets[name]
        if info.get("CFBundleIdentifier") != settings["PRODUCT_BUNDLE_IDENTIFIER"]:
            raise ReleaseCheckError("{} archive bundle ID differs from the release source.".format(name))
        if info.get("CFBundleShortVersionString") != settings["MARKETING_VERSION"]:
            raise ReleaseCheckError("{} archive marketing version differs from the release source.".format(name))
        if not re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", str(info.get("CFBundleVersion", ""))):
            raise ReleaseCheckError("{} archive build number is invalid.".format(name))
        team = info.get("DTAppStoreConnectTeamIdentifier")
        if team and team != settings["DEVELOPMENT_TEAM"]:
            raise ReleaseCheckError("{} archive team differs from the release source.".format(name))
        read_plist(bundle / "PrivacyInfo.xcprivacy")
    # Xcode Cloud may manage the build number. Compare the actual app and widget
    # numbers to one another instead of requiring the source's placeholder.
    if app_info["CFBundleVersion"] != widget_info["CFBundleVersion"]:
        raise ReleaseCheckError("The archived app and widget build numbers differ.")
    bundled = validate_client_configuration(read_plist(app / RESOURCE_PATH.name))
    if bundled != expected:
        raise ReleaseCheckError("The archive does not contain the expected public cloud configuration.")
    if (widget / RESOURCE_PATH.name).exists():
        raise ReleaseCheckError("The widget unexpectedly contains the cloud client configuration.")
    return {
        "version": app_info["CFBundleShortVersionString"],
        "build": app_info["CFBundleVersion"],
        "app_bundle_id": app_info["CFBundleIdentifier"],
        "widget_bundle_id": widget_info["CFBundleIdentifier"],
        "icons": "passed",
        "public_client_configuration": "passed; main app only",
        "privacy_manifests": "passed",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--archive", type=Path)
    arguments = parser.parse_args(argv)
    try:
        targets, configuration = check_source(arguments.root)
        if arguments.archive:
            report = check_archive(arguments.root, arguments.archive, targets, configuration)
            print("Xcode Cloud archive check passed: " + json.dumps(report, ensure_ascii=False))
        else:
            app = targets["Mikansei"]
            print("Xcode Cloud source check passed: Team {}, {} {} ({}); icons, privacy and public cloud resource are configured.".format(
                app["DEVELOPMENT_TEAM"], app["PRODUCT_BUNDLE_IDENTIFIER"],
                app["MARKETING_VERSION"], app["CURRENT_PROJECT_VERSION"],
            ))
    except (ReleaseCheckError, IconCheckError) as error:
        print("ERROR: {}".format(error), file=sys.stderr)
        return 1
    except (ValueError, OSError, KeyError, TypeError, ExpatError,
            subprocess.CalledProcessError, plistlib.InvalidFileException):
        # Do not echo exception values: malformed configuration can contain keys.
        print("ERROR: release resources or identity are incomplete. Confirm AppIcon, matching App/Widgets settings, privacy manifests and a valid public Supabase configuration.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
