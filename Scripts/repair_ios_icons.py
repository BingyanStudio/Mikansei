#!/usr/bin/env python3
"""Repair the Mikansei iOS app icon resources in an existing Xcode project.

This script uses only Python's standard library and macOS ``plutil``. It
preserves existing target, signing, bundle, and version settings, and only
changes the app target's asset catalog reference, app icon build setting, and
legacy icon entries in App/Info.plist.
"""

import argparse
import datetime
import hashlib
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]
ASSET_CATALOG_RELATIVE = Path("App/Assets.xcassets")
APP_ICONSET_RELATIVE = Path("AppIcon.appiconset")
INFO_PLIST_RELATIVE = Path("App/Info.plist")
MAIN_TARGET_NAME = "Mikansei"
APP_ICON_NAME = "AppIcon"


class RepairError(Exception):
    """An expected repair failure that should be reported without a traceback."""


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Repair the Mikansei iOS app icon configuration in an Xcode project."
    )
    parser.add_argument(
        "--root",
        required=True,
        type=Path,
        help="Project root containing Mikansei.xcodeproj and App/Info.plist.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Describe the changes without writing files or creating backups.",
    )
    return parser.parse_args()


def run_plutil(arguments, input_data=None):
    try:
        return subprocess.run(
            ["plutil"] + arguments,
            input=input_data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError as error:
        raise RepairError("需要 macOS plutil 来解析和验证 Xcode 工程文件。") from error


def load_pbxproj(path):
    result = run_plutil(["-convert", "xml1", "-o", "-", str(path)])
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RepairError("无法解析 project.pbxproj：{}".format(detail))
    try:
        project = plistlib.loads(result.stdout)
    except Exception as error:
        raise RepairError("plutil 输出的 Xcode 工程属性列表无效。") from error
    if not isinstance(project, dict) or not isinstance(project.get("objects"), dict):
        raise RepairError("project.pbxproj 不包含有效的 objects 字典。")
    return project


def find_project(root):
    preferred = root / "Mikansei.xcodeproj" / "project.pbxproj"
    if preferred.is_file():
        return preferred

    candidates = sorted(root.glob("*.xcodeproj/project.pbxproj"))
    if not candidates:
        raise RepairError("在 --root 下找不到 .xcodeproj/project.pbxproj。")

    matching = []
    for path in candidates:
        project = load_pbxproj(path)
        if find_main_target(project["objects"]) is not None:
            matching.append(path)
    if len(matching) != 1:
        raise RepairError(
            "无法唯一识别包含 Mikansei app target 的 Xcode 工程：{}".format(
                ", ".join(str(path) for path in matching or candidates)
            )
        )
    return matching[0]


def find_main_target(objects):
    matches = []
    for object_id, value in objects.items():
        if not isinstance(value, dict):
            continue
        if value.get("isa") != "PBXNativeTarget":
            continue
        if value.get("productType") != "com.apple.product-type.application":
            continue
        if MAIN_TARGET_NAME in (value.get("name"), value.get("productName")):
            matches.append((object_id, value))
    if len(matches) > 1:
        raise RepairError("project.pbxproj 中存在多个名为 Mikansei 的 app target。")
    return matches[0] if matches else None


def group_parents(objects):
    parents = {}
    for object_id, value in objects.items():
        if not isinstance(value, dict):
            continue
        if value.get("isa") not in ("PBXGroup", "PBXVariantGroup"):
            continue
        for child_id in value.get("children", []):
            parents.setdefault(child_id, []).append(object_id)
    return parents


def resolved_object_paths(object_id, objects, parents, root, visiting=None):
    value = objects.get(object_id)
    if not isinstance(value, dict):
        return []
    if visiting is None:
        visiting = set()
    if object_id in visiting:
        return []
    visiting = set(visiting)
    visiting.add(object_id)

    source_tree = value.get("sourceTree", "<group>")
    item_path = value.get("path")
    if source_tree == "SOURCE_ROOT":
        bases = [root]
    elif source_tree == "<absolute>":
        bases = [Path("/")]
    elif source_tree == "<group>":
        parent_ids = parents.get(object_id, [])
        if not parent_ids:
            bases = [root]
        else:
            bases = []
            for parent_id in parent_ids:
                bases.extend(
                    resolved_object_paths(parent_id, objects, parents, root, visiting)
                )
    else:
        return []

    if item_path:
        return [(base / str(item_path)).resolve(strict=False) for base in bases]
    if value.get("isa") in ("PBXGroup", "PBXVariantGroup"):
        return [base.resolve(strict=False) for base in bases]
    return []


def find_asset_catalog_reference(objects, root):
    parents = group_parents(objects)
    desired_path = (root / ASSET_CATALOG_RELATIVE).resolve(strict=False)
    matches = []
    for object_id, value in objects.items():
        if not isinstance(value, dict) or value.get("isa") != "PBXFileReference":
            continue
        if desired_path in resolved_object_paths(object_id, objects, parents, root):
            matches.append((object_id, value))
    if len(matches) > 1:
        exact = [
            item for item in matches
            if item[1].get("lastKnownFileType") == "folder.assetcatalog"
        ]
        if len(exact) == 1:
            return exact[0]
        raise RepairError("project.pbxproj 中有多个指向 App/Assets.xcassets 的文件引用。")
    return matches[0] if matches else None


def unique_object_id(objects, label):
    used = set(objects)
    counter = 0
    while True:
        material = "{}:{}".format(label, counter).encode("utf-8")
        candidate = hashlib.sha1(material).hexdigest()[:24].upper()
        if candidate not in used:
            return candidate
        counter += 1


def add_file_reference(objects, project):
    object_id = unique_object_id(objects, "MikanseiAppIconAssetCatalog")
    objects[object_id] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "folder.assetcatalog",
        "path": ASSET_CATALOG_RELATIVE.as_posix(),
        "sourceTree": "SOURCE_ROOT",
    }

    project_object = objects.get(project.get("rootObject"), {})
    main_group_id = project_object.get("mainGroup") if isinstance(project_object, dict) else None
    app_groups = [
        group_id
        for group_id, value in objects.items()
        if isinstance(value, dict)
        and value.get("isa") == "PBXGroup"
        and value.get("name") == "App"
    ]
    parent_id = app_groups[0] if len(app_groups) == 1 else main_group_id
    parent = objects.get(parent_id) if parent_id else None
    if isinstance(parent, dict) and parent.get("isa") == "PBXGroup":
        children = parent.setdefault("children", [])
        if object_id not in children:
            children.append(object_id)
    return object_id


def main_resource_phase(objects, target):
    phase_ids = target.get("buildPhases", [])
    matches = [
        phase_id
        for phase_id in phase_ids
        if isinstance(objects.get(phase_id), dict)
        and objects[phase_id].get("isa") == "PBXResourcesBuildPhase"
    ]
    if len(matches) != 1:
        raise RepairError(
            "Mikansei app target 应恰有一个 PBXResourcesBuildPhase，实际找到 {} 个。".format(
                len(matches)
            )
        )
    return matches[0], objects[matches[0]]


def ensure_catalog_in_resources(objects, target, catalog_ref_id):
    phase_id, phase = main_resource_phase(objects, target)
    files = phase.setdefault("files", [])
    for build_file_id in files:
        build_file = objects.get(build_file_id)
        if isinstance(build_file, dict) and build_file.get("fileRef") == catalog_ref_id:
            return False

    reusable_build_file = next(
        (
            object_id
            for object_id, value in objects.items()
            if isinstance(value, dict)
            and value.get("isa") == "PBXBuildFile"
            and value.get("fileRef") == catalog_ref_id
        ),
        None,
    )
    if reusable_build_file is None:
        reusable_build_file = unique_object_id(
            objects, "MikanseiAppIconAssetCatalogBuildFile"
        )
        objects[reusable_build_file] = {
            "isa": "PBXBuildFile",
            "fileRef": catalog_ref_id,
        }
    files.append(reusable_build_file)
    return True


def remove_legacy_icon_png_build_files(objects, target, root):
    _, phase = main_resource_phase(objects, target)
    files = phase.setdefault("files", [])
    parents = group_parents(objects)
    resource_directory = (root / "App/Resources").resolve(strict=False)
    kept = []
    removed_names = []
    for build_file_id in files:
        build_file = objects.get(build_file_id)
        file_ref_id = build_file.get("fileRef") if isinstance(build_file, dict) else None
        file_ref = objects.get(file_ref_id) if file_ref_id else None
        is_legacy_icon = False
        if isinstance(file_ref, dict) and file_ref.get("isa") == "PBXFileReference":
            for path in resolved_object_paths(file_ref_id, objects, parents, root):
                if (
                    path.parent == resource_directory
                    and path.name.startswith("AppIcon")
                    and path.suffix.lower() == ".png"
                ):
                    is_legacy_icon = True
                    removed_names.append(path.name)
                    break
        if not is_legacy_icon:
            kept.append(build_file_id)
    if removed_names:
        phase["files"] = kept
    return sorted(set(removed_names))


def set_app_icon_build_setting(objects, target):
    config_list = objects.get(target.get("buildConfigurationList"))
    if not isinstance(config_list, dict) or config_list.get("isa") != "XCConfigurationList":
        raise RepairError("Mikansei app target 的 buildConfigurationList 无效。")
    configuration_ids = config_list.get("buildConfigurations", [])
    if not configuration_ids:
        raise RepairError("Mikansei app target 没有 build configurations。")

    changed = []
    for configuration_id in configuration_ids:
        configuration = objects.get(configuration_id)
        if (
            not isinstance(configuration, dict)
            or configuration.get("isa") != "XCBuildConfiguration"
        ):
            raise RepairError(
                "Mikansei app target 引用了无效的 build configuration：{}".format(
                    configuration_id
                )
            )
        settings = configuration.setdefault("buildSettings", {})
        if not isinstance(settings, dict):
            raise RepairError(
                "Build configuration {} 的 buildSettings 不是字典。".format(
                    configuration_id
                )
            )
        if settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") != APP_ICON_NAME:
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = APP_ICON_NAME
            changed.append(configuration_id)
    return changed


def validate_iconset(path):
    contents_path = path / "Contents.json"
    try:
        contents = plistlib.loads(contents_path.read_bytes())
    except Exception:
        try:
            import json
            contents = json.loads(contents_path.read_text(encoding="utf-8"))
        except Exception as error:
            raise RepairError("AppIcon.appiconset/Contents.json 无效：{}".format(path)) from error

    images = contents.get("images") if isinstance(contents, dict) else None
    if not isinstance(images, list):
        raise RepairError("AppIcon.appiconset/Contents.json 缺少 images 列表：{}".format(path))
    matching = [
        image
        for image in images
        if isinstance(image, dict)
        and image.get("idiom") == "universal"
        and image.get("platform") == "ios"
        and image.get("size") == "1024x1024"
    ]
    if not matching:
        raise RepairError(
            "AppIcon.appiconset 必须包含 iOS universal 1024x1024 图标：{}".format(path)
        )
    for image in matching:
        filename = image.get("filename")
        if not isinstance(filename, str) or not (path / filename).is_file():
            raise RepairError(
                "AppIcon.appiconset 的 1024x1024 图标文件缺失：{}".format(path)
            )


def asset_copy_plan(root):
    catalog = root / ASSET_CATALOG_RELATIVE
    iconset = catalog / APP_ICONSET_RELATIVE
    if catalog.exists() and iconset.exists():
        validate_iconset(iconset)
        return None

    source_catalog = SOURCE_ROOT / ASSET_CATALOG_RELATIVE
    source_iconset = source_catalog / APP_ICONSET_RELATIVE
    validate_iconset(source_iconset)
    if catalog.exists():
        if not catalog.is_dir():
            raise RepairError("App/Assets.xcassets 已存在但不是目录。")
        return ("iconset", source_iconset, iconset)
    return ("catalog", source_catalog, catalog)


def remove_legacy_icons(info):
    removed = []
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        if key in info:
            del info[key]
            removed.append(key)
    return removed


def serialize_xml_plist(value):
    try:
        return plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=False)
    except Exception as error:
        raise RepairError("无法序列化修改后的属性列表。") from error


def validate_plist_bytes(data, label):
    result = run_plutil(["-lint", "-"], input_data=data)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        if not detail:
            detail = result.stdout.decode("utf-8", errors="replace").strip()
        raise RepairError("{} 校验失败：{}".format(label, detail))


def backup_path(path, timestamp):
    candidate = path.with_name(path.name + ".backup." + timestamp)
    counter = 1
    while candidate.exists():
        candidate = path.with_name(
            path.name + ".backup.{}-{}".format(timestamp, counter)
        )
        counter += 1
    return candidate


def write_atomic(path, data):
    file_mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="." + path.name + ".repair-",
        dir=str(path.parent),
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary_path, file_mode)
        os.replace(str(temporary_path), str(path))
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def stage_asset_copy(copy_plan):
    if copy_plan is None:
        return None
    kind, source, destination = copy_plan
    destination.parent.mkdir(parents=True, exist_ok=True)
    staged = Path(
        tempfile.mkdtemp(
            prefix=".repair-ios-icons-",
            dir=str(destination.parent),
        )
    )
    staged.rmdir()
    try:
        shutil.copytree(source, staged)
    except Exception:
        if staged.exists():
            shutil.rmtree(staged)
        raise
    return kind, staged, destination


def install_staged_asset(staged_asset):
    if staged_asset is None:
        return
    kind, staged, destination = staged_asset
    if destination.exists():
        shutil.rmtree(staged)
        raise RepairError(
            "安装图标资源前发现目标已存在，已停止以避免覆盖：{}".format(destination)
        )
    if kind == "iconset":
        destination.parent.mkdir(parents=True, exist_ok=True)
    os.replace(str(staged), str(destination))


def main():
    args = parse_arguments()
    root = args.root.expanduser().resolve()
    if not root.is_dir():
        raise RepairError("--root 不是目录：{}".format(root))

    project_path = find_project(root)
    project = load_pbxproj(project_path)
    objects = project["objects"]
    target_match = find_main_target(objects)
    if target_match is None:
        raise RepairError("工程中找不到名为 Mikansei 的 iOS application target。")
    target_id, target = target_match

    info_path = root / INFO_PLIST_RELATIVE
    if not info_path.is_file():
        raise RepairError("找不到 {}".format(info_path))
    try:
        info = plistlib.loads(info_path.read_bytes())
    except Exception as error:
        raise RepairError("无法解析 App/Info.plist。") from error
    if not isinstance(info, dict):
        raise RepairError("App/Info.plist 顶层不是字典。")

    catalog_path = root / ASSET_CATALOG_RELATIVE
    if not catalog_path.parent.is_dir():
        raise RepairError("找不到 App 目录：{}".format(catalog_path.parent))
    copy_plan = asset_copy_plan(root)

    catalog_reference = find_asset_catalog_reference(objects, root)
    if catalog_reference is None:
        catalog_ref_id = add_file_reference(objects, project)
        catalog_ref_changed = True
    else:
        catalog_ref_id, reference = catalog_reference
        catalog_ref_changed = False
        if reference.get("lastKnownFileType") != "folder.assetcatalog":
            reference["lastKnownFileType"] = "folder.assetcatalog"
            reference.pop("explicitFileType", None)
            catalog_ref_changed = True

    catalog_resource_added = ensure_catalog_in_resources(objects, target, catalog_ref_id)
    legacy_icon_pngs_removed = remove_legacy_icon_png_build_files(
        objects, target, root
    )
    resources_changed = catalog_resource_added or bool(legacy_icon_pngs_removed)
    changed_configurations = set_app_icon_build_setting(objects, target)
    removed_icons = remove_legacy_icons(info)

    project_changed = (
        catalog_ref_changed or resources_changed or bool(changed_configurations)
    )
    info_changed = bool(removed_icons)
    if not project_changed and not info_changed and copy_plan is None:
        print("已是修复状态；没有文件需要修改。")
        return 0

    actions = []
    if copy_plan is not None:
        kind = copy_plan[0]
        actions.append(
            "恢复 AppIcon 资源：{}".format(
                (root / ASSET_CATALOG_RELATIVE / APP_ICONSET_RELATIVE)
                if kind == "iconset"
                else root / ASSET_CATALOG_RELATIVE
            )
        )
    if catalog_ref_changed:
        actions.append("添加或修正 folder.assetcatalog 文件引用。")
    if resources_changed:
        if catalog_resource_added:
            actions.append("将 App/Assets.xcassets 加入 Mikansei app target 的资源阶段。")
        if legacy_icon_pngs_removed:
            actions.append(
                "从 Mikansei app target 资源阶段移除旧散图引用：{}。".format(
                    ", ".join(legacy_icon_pngs_removed)
                )
            )
    if changed_configurations:
        actions.append(
            "设置 {} 个 Mikansei app 配置使用 AppIcon。".format(
                len(changed_configurations)
            )
        )
    if removed_icons:
        actions.append("从 App/Info.plist 移除旧图标键：{}。".format(", ".join(removed_icons)))

    print("计划修改：")
    for action in actions:
        print("  - " + action)
    if args.dry_run:
        print("Dry run：未写入文件，也未创建备份。")
        return 0

    project_bytes = (
        serialize_xml_plist(project)
        if project_changed
        else project_path.read_bytes()
    )
    info_bytes = serialize_xml_plist(info) if info_changed else info_path.read_bytes()
    if project_changed:
        validate_plist_bytes(project_bytes, "project.pbxproj")
        # Reparse the serialized property list before any filesystem changes.
        try:
            serialized_project = plistlib.loads(project_bytes)
        except Exception as error:
            raise RepairError("修改后的 project.pbxproj 无法重新解析。") from error
        if find_main_target(serialized_project.get("objects", {})) is None:
            raise RepairError("修改后的工程无法重新识别 Mikansei app target。")
    if info_changed:
        validate_plist_bytes(info_bytes, "App/Info.plist")

    staged_asset = stage_asset_copy(copy_plan)
    changed_paths = []
    if project_changed:
        changed_paths.append(project_path)
    if info_changed:
        changed_paths.append(info_path)

    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backups = []
    try:
        for path in changed_paths:
            backup = backup_path(path, timestamp)
            shutil.copy2(path, backup)
            backups.append((path, backup))

        # Install resources first so the project never points at a catalog
        # that has not yet been restored.
        install_staged_asset(staged_asset)
        if project_changed:
            write_atomic(project_path, project_bytes)
        if info_changed:
            write_atomic(info_path, info_bytes)
    except Exception:
        if staged_asset is not None:
            _, staged, destination = staged_asset
            if staged.exists():
                shutil.rmtree(staged)
        raise

    for original, backup in backups:
        print("备份：{} -> {}".format(original, backup))
    print("修复完成：{}".format(root))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RepairError as error:
        print("repair_ios_icons.py: {}".format(error), file=sys.stderr)
        sys.exit(2)
