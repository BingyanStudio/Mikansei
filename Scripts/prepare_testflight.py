#!/usr/bin/env python3
"""Prepare a clean, team-specific Mikansei iOS source bundle for TestFlight."""

import argparse
import json
import os
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from supabase_config import load_client_configuration, write_client_resource


SOURCE_ROOT = Path(__file__).resolve().parents[1]
PROJECT_RELATIVE_PATH = Path("Mikansei.xcodeproj")
NATIVE_DIRECTORIES = (
    "App",
    "Shared",
    "Widgets",
    "Sources",
    "Sync",
    "UITests",
)
DEFAULT_BUNDLE_ID_PREFIX = "com.personal.mikansei.beta"
WIDGET_SUFFIX = ".widgets"

EXCLUDED_DIRECTORY_NAMES = {
    ".build",
    ".git",
    "__pycache__",
    "build",
    "DerivedData",
    "LocalInstall",
    "TestResults",
    "xcuserdata",
}
EXCLUDED_FILE_SUFFIXES = {
    ".cer",
    ".crt",
    ".key",
    ".mobileprovision",
    ".p12",
    ".p8",
    ".pem",
    ".provisionprofile",
    ".xcconfig",
    ".xcsettings",
    ".xcuserstate",
}
EXCLUDED_SIGNING_KEYS = (
    "CODE_SIGN_IDENTITY",
    "PROVISIONING_PROFILE",
    "PROVISIONING_PROFILE_SPECIFIER",
)


class PrepareError(Exception):
    """An expected preparation failure that should be shown without a traceback."""


def parse_arguments():
    parser = argparse.ArgumentParser(
        description=(
            "Create a clean Mikansei iOS source bundle for a friend's Apple "
            "Developer team. Default mode prepares files and prints a command."
        )
    )
    parser.add_argument(
        "--team",
        help="Apple Developer Team ID (exactly 10 letters or digits); required unless --unsigned-check is used.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output directory. It may be new or an existing empty directory.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--archive",
        action="store_true",
        help="Run a signed Release archive with automatic provisioning updates.",
    )
    mode.add_argument(
        "--unsigned-check",
        action="store_true",
        help=(
            "Clear the Team and run an unsigned archive for compile checking. "
            "This is not a TestFlight distribution check."
        ),
    )
    parser.add_argument(
        "--bundle-id",
        help="Override the app's base bundle ID; the widget uses this ID plus '.widgets'.",
    )
    parser.add_argument(
        "--build-number",
        help="Override the numeric build number for both app and widget.",
    )
    return parser, parser.parse_args()


def validate_team(team):
    if team is None:
        return None
    normalized = team.strip().upper()
    if re.fullmatch(r"[A-Z0-9]{10}", normalized) is None:
        raise PrepareError("Team ID 必须是 Apple Developer 提供的 10 位字母或数字。")
    return normalized


def validate_bundle_id(bundle_id):
    if re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id) is None:
        raise PrepareError(
            "Bundle ID 必须是由字母、数字或连字符组成的反向域名，例如 com.example.mikansei.beta。"
        )
    return bundle_id


def validate_build_number(build_number):
    if re.fullmatch(r"[0-9]+", build_number) is None or int(build_number) < 1:
        raise PrepareError("Build number 必须是大于 0 的纯数字。")
    return build_number


def path_is_within(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_paths(output):
    source = SOURCE_ROOT.resolve()
    if output.is_symlink():
        raise PrepareError("为避免覆盖链接目标，--output 不能是符号链接。")
    resolved_output = output.resolve()
    if (
        resolved_output == source
        or path_is_within(resolved_output, source)
        or path_is_within(source, resolved_output)
    ):
        raise PrepareError("输入源码目录与输出目录不能相同，也不能互相包含。")
    if resolved_output.exists():
        if not resolved_output.is_dir():
            raise PrepareError("--output 已存在且不是目录。")
        if next(resolved_output.iterdir(), None) is not None:
            raise PrepareError("--output 已存在且非空；为避免覆盖，已拒绝继续。")
    return resolved_output


def should_skip_directory(path):
    name = path.name
    lower_name = name.lower()
    return (
        name.startswith(".")
        or lower_name in {value.lower() for value in EXCLUDED_DIRECTORY_NAMES}
        or lower_name.startswith("signingprofilebackup")
    )


def should_skip_file(path):
    name = path.name
    lower_name = name.lower()
    if name.startswith(".") or lower_name.endswith(".xcuserstate"):
        return True
    if path.suffix.lower() in EXCLUDED_FILE_SUFFIXES:
        return True
    if lower_name.endswith((".local", ".secret", ".credentials")):
        return True
    return False


def copy_filtered_tree(source, destination):
    if not source.is_dir() or source.is_symlink():
        raise PrepareError("必要的原生源码目录缺失或为符号链接: {}".format(source.name))

    destination.mkdir(parents=True, exist_ok=True)
    for current, directory_names, file_names in os.walk(
        str(source), topdown=True, followlinks=False
    ):
        current_path = Path(current)
        relative = current_path.relative_to(source)
        destination_directory = destination / relative
        destination_directory.mkdir(parents=True, exist_ok=True)

        kept_directories = []
        for name in directory_names:
            candidate = current_path / name
            if candidate.is_symlink() or should_skip_directory(candidate):
                continue
            kept_directories.append(name)
        directory_names[:] = kept_directories

        for name in file_names:
            source_file = current_path / name
            if source_file.is_symlink() or should_skip_file(source_file):
                continue
            if not source_file.is_file():
                continue
            shutil.copy2(source_file, destination_directory / name)


def copy_shared_project(project_source, project_destination):
    project_file = project_source / "project.pbxproj"
    schemes_source = project_source / "xcshareddata" / "xcschemes"
    if not project_file.is_file() or project_file.is_symlink():
        raise PrepareError("Mikansei.xcodeproj/project.pbxproj 不存在或不是普通文件。")

    project_destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(project_file, project_destination / "project.pbxproj")

    scheme_files = []
    if schemes_source.is_dir() and not schemes_source.is_symlink():
        for candidate in schemes_source.iterdir():
            if (
                candidate.is_file()
                and not candidate.is_symlink()
                and not candidate.name.startswith(".")
                and candidate.suffix == ".xcscheme"
            ):
                scheme_files.append(candidate)
    if not scheme_files:
        raise PrepareError("Mikansei.xcodeproj 中没有可分享的 .xcscheme。")

    schemes_destination = project_destination / "xcshareddata" / "xcschemes"
    schemes_destination.mkdir(parents=True, exist_ok=True)
    for scheme in sorted(scheme_files):
        shutil.copy2(scheme, schemes_destination / scheme.name)


def copy_handoff_files(stage):
    scripts_destination = stage / "Scripts"
    scripts_destination.mkdir(parents=True, exist_ok=True)
    for script_name in (
        "generate_project.py",
        "prepare_testflight.py",
        "supabase_config.py",
        "check_ios_archive_icons.py",
        "repair_ios_icons.py",
    ):
        source = SOURCE_ROOT / "Scripts" / script_name
        if not source.is_file() or source.is_symlink():
            raise PrepareError("必要脚本缺失或不是普通文件: {}".format(script_name))
        shutil.copy2(source, scripts_destination / script_name)

    guide_source = SOURCE_ROOT / "Documentation" / "TestFlight"
    guide = guide_source / "BUILD_GUIDE.md"
    if not guide.is_file() or guide.is_symlink():
        raise PrepareError("Documentation/TestFlight/BUILD_GUIDE.md 缺失。")
    guide_destination = stage / "Documentation" / "TestFlight"
    copy_filtered_tree(guide_source, guide_destination)

    for relative in (
        "Documentation/SUPABASE_NATIVE.md",
        "Documentation/supabase-native-account.sql",
        "Configuration/README.md",
        "Configuration/SupabaseClient.example.plist",
        "Mikanseta/Documentation/SUPABASE_SETUP.md",
        "Mikanseta/Documentation/supabase-schema.sql",
    ):
        source = SOURCE_ROOT / relative
        if not source.is_file() or source.is_symlink():
            raise PrepareError("必要的云账号交接资料缺失或不是普通文件: {}".format(relative))
        destination = stage / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def copy_minimal_source(stage):
    for directory_name in NATIVE_DIRECTORIES:
        copy_filtered_tree(
            SOURCE_ROOT / directory_name,
            stage / directory_name,
        )
    copy_shared_project(
        SOURCE_ROOT / PROJECT_RELATIVE_PATH,
        stage / PROJECT_RELATIVE_PATH,
    )
    copy_handoff_files(stage)
    configuration = load_client_configuration(SOURCE_ROOT)
    if configuration is not None:
        write_client_resource(stage, configuration)


def load_project_json(project_file):
    try:
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(project_file)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
    except FileNotFoundError:
        raise PrepareError("需要 macOS 自带的 plutil 命令才能处理 Xcode 工程。")
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        raise PrepareError("plutil 无法读取 project.pbxproj: {}".format(detail))
    try:
        return json.loads(result.stdout)
    except ValueError as error:
        raise PrepareError("plutil 输出无法解析为 JSON: {}".format(error))


def write_project_xml(project_file, project):
    project_directory = project_file.parent
    with tempfile.TemporaryDirectory(
        prefix=".testflight-project-", dir=str(project_directory)
    ) as temporary_directory:
        xml_file = Path(temporary_directory) / "project.pbxproj"
        with xml_file.open("wb") as handle:
            plistlib.dump(project, handle, fmt=plistlib.FMT_XML, sort_keys=False)
        os.replace(str(xml_file), str(project_file))


def target_build_settings(project, target_name):
    objects = project.get("objects", {})
    targets = [
        value
        for value in objects.values()
        if value.get("isa") == "PBXNativeTarget" and value.get("name") == target_name
    ]
    if len(targets) != 1:
        raise PrepareError(
            "工程中应恰有一个名为 {} 的 PBXNativeTarget。".format(target_name)
        )

    config_list_id = targets[0].get("buildConfigurationList")
    config_list = objects.get(config_list_id, {})
    if config_list.get("isa") != "XCConfigurationList":
        raise PrepareError("{} 缺少 XCConfigurationList。".format(target_name))

    configurations = []
    for config_id in config_list.get("buildConfigurations", []):
        config = objects.get(config_id, {})
        if config.get("isa") != "XCBuildConfiguration":
            raise PrepareError("{} 有无法识别的构建配置。".format(target_name))
        settings = config.setdefault("buildSettings", {})
        if not isinstance(settings, dict):
            raise PrepareError("{} 的构建设置格式无效。".format(target_name))
        configurations.append(settings)
    if not configurations:
        raise PrepareError("{} 没有构建配置。".format(target_name))
    return configurations


def read_release_metadata(project_file):
    project = load_project_json(project_file)
    objects = project.get("objects", {})
    targets = [
        value
        for value in objects.values()
        if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Mikansei"
    ]
    if len(targets) != 1:
        raise PrepareError("无法从工程中唯一定位 Mikansei App target。")
    config_list = objects.get(targets[0].get("buildConfigurationList"), {})
    if config_list.get("isa") != "XCConfigurationList":
        raise PrepareError("Mikansei App 缺少 XCConfigurationList。")
    for config_id in config_list.get("buildConfigurations", []):
        configuration = objects.get(config_id, {})
        if configuration.get("name") != "Release":
            continue
        settings = configuration.get("buildSettings", {})
        version = settings.get("MARKETING_VERSION")
        build_number = settings.get("CURRENT_PROJECT_VERSION")
        if not isinstance(version, str) or not version:
            raise PrepareError("Mikansei App Release 缺少 MARKETING_VERSION。")
        if not isinstance(build_number, str) or not build_number:
            raise PrepareError("Mikansei App Release 缺少 CURRENT_PROJECT_VERSION。")
        if re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version) is None:
            raise PrepareError(
                "Mikansei App Release 的 MARKETING_VERSION 格式无效: {}".format(
                    version
                )
            )
        return version, validate_build_number(build_number)
    raise PrepareError("Mikansei App 缺少 Release 构建配置。")


def remove_team_and_manual_signing(settings):
    for key in list(settings.keys()):
        if key == "DEVELOPMENT_TEAM" or key.startswith("DEVELOPMENT_TEAM["):
            del settings[key]
            continue
        if any(
            key == prefix or key.startswith(prefix + "[")
            for prefix in EXCLUDED_SIGNING_KEYS
        ):
            del settings[key]
            continue
        if key == "CODE_SIGN_IDENTITY" or key.startswith("CODE_SIGN_IDENTITY["):
            del settings[key]


def configure_project(project_file, team, bundle_id, version, build_number):
    project = load_project_json(project_file)
    app_configurations = target_build_settings(project, "Mikansei")
    widget_configurations = target_build_settings(project, "MikanseiWidgets")
    widget_bundle_id = bundle_id + WIDGET_SUFFIX

    for settings in app_configurations:
        remove_team_and_manual_signing(settings)
        if team is not None:
            settings["DEVELOPMENT_TEAM"] = team
        settings["CODE_SIGN_STYLE"] = "Automatic"
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
        settings["MARKETING_VERSION"] = version
        settings["CURRENT_PROJECT_VERSION"] = build_number
        settings["MIKANSEI_SHARED_KEYCHAIN_SUFFIX"] = (
            "$(PRODUCT_BUNDLE_IDENTIFIER).shared"
        )

    for settings in widget_configurations:
        remove_team_and_manual_signing(settings)
        if team is not None:
            settings["DEVELOPMENT_TEAM"] = team
        settings["CODE_SIGN_STYLE"] = "Automatic"
        settings["PRODUCT_BUNDLE_IDENTIFIER"] = widget_bundle_id
        settings["MIKANSEI_HOST_BUNDLE_IDENTIFIER"] = bundle_id
        settings["MIKANSEI_SHARED_KEYCHAIN_SUFFIX"] = (
            "$(MIKANSEI_HOST_BUNDLE_IDENTIFIER).shared"
        )
        settings["MARKETING_VERSION"] = version
        settings["CURRENT_PROJECT_VERSION"] = build_number

    write_project_xml(project_file, project)
    return widget_bundle_id


def validate_configured_project(
    project_file, team, bundle_id, widget_bundle_id, version, build_number
):
    project = load_project_json(project_file)
    expected_targets = (
        ("Mikansei", bundle_id),
        ("MikanseiWidgets", widget_bundle_id),
    )
    for target_name, expected_bundle_id in expected_targets:
        for settings in target_build_settings(project, target_name):
            if settings.get("PRODUCT_BUNDLE_IDENTIFIER") != expected_bundle_id:
                raise PrepareError(
                    "{} Bundle ID was not preserved by the project generator.".format(
                        target_name
                    )
                )
            if settings.get("MARKETING_VERSION") != version:
                raise PrepareError(
                    "{} version was not preserved by the project generator.".format(
                        target_name
                    )
                )
            if settings.get("CURRENT_PROJECT_VERSION") != build_number:
                raise PrepareError(
                    "{} build number was not preserved by the project generator.".format(
                        target_name
                    )
                )
            if team is None:
                if "DEVELOPMENT_TEAM" in settings:
                    raise PrepareError(
                        "{} still contains a Team in unsigned-check mode.".format(
                            target_name
                        )
                    )
            elif settings.get("DEVELOPMENT_TEAM") != team:
                raise PrepareError(
                    "{} Team was not preserved by the project generator.".format(
                        target_name
                    )
                )


def make_archive_command(unsigned, archive_path="Mikansei.xcarchive"):
    command = [
        "xcodebuild",
        "-project",
        "Mikansei.xcodeproj",
        "-scheme",
        "Mikansei",
        "-configuration",
        "Release",
        "-destination",
        "generic/platform=iOS",
        "-archivePath",
        archive_path,
        "archive",
    ]
    if unsigned:
        command.extend(
            [
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
            ]
        )
    else:
        command.append("-allowProvisioningUpdates")
    return command


def run_logged(command, working_directory, log_file):
    rendered_command = shlex.join(command)
    heading = "$ {}".format(rendered_command)
    print(heading)
    log_file.write(heading + "\n")
    log_file.flush()
    try:
        process = subprocess.Popen(
            command,
            cwd=str(working_directory),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
        )
    except OSError as error:
        message = "无法启动命令: {}".format(error)
        print(message, file=sys.stderr)
        log_file.write(message + "\n")
        log_file.flush()
        return 127

    if process.stdout is not None:
        for line in process.stdout:
            sys.stdout.write(line)
            log_file.write(line)
            log_file.flush()
    return process.wait()


def write_manifest(
    stage,
    team,
    bundle_id,
    widget_bundle_id,
    version,
    build_number,
    mode,
    archive_code,
):
    archive_status = "not_requested"
    if archive_code is not None:
        archive_status = "succeeded" if archive_code == 0 else "failed"

    manifest = {
        "team": team,
        "bundle_id": bundle_id,
        "widget_bundle_id": widget_bundle_id,
        "version": version,
        "build_number": build_number,
        "source_path": ".",
        "mode": mode,
        "archive_status": archive_status,
        "archive_path": "Mikansei.xcarchive",
    }
    manifest_file = stage / "PREPARED_APP.json"
    with manifest_file.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def publish_stage(stage, output):
    if output.exists():
        if not output.is_dir():
            raise PrepareError("--output 在准备期间变成了非目录。")
        if next(output.iterdir(), None) is not None:
            raise PrepareError("--output 在准备期间变成了非空目录，拒绝覆盖。")
        output.rmdir()
    os.replace(str(stage), str(output))


def print_archive_command(output):
    command = make_archive_command(unsigned=False)
    printable = "cd {} && {}".format(shlex.quote(str(output)), shlex.join(command))
    print("已准备好源包。需要归档时可复制执行：")
    print(printable)


def main():
    parser, arguments = parse_arguments()
    stage = None
    try:
        team = validate_team(arguments.team)
        if arguments.unsigned_check:
            if team is not None:
                raise PrepareError("--unsigned-check 不接受 --team；此模式会清空 Team。")
        elif team is None:
            raise PrepareError("签名准备必须提供 --team，除非使用 --unsigned-check。")

        if arguments.bundle_id:
            bundle_id = validate_bundle_id(arguments.bundle_id)
        elif team is not None:
            bundle_id = "{}.{}".format(DEFAULT_BUNDLE_ID_PREFIX, team.lower())
        else:
            bundle_id = DEFAULT_BUNDLE_ID_PREFIX + ".unsigned"

        output = validate_paths(Path(arguments.output).expanduser())
        output.parent.mkdir(parents=True, exist_ok=True)

        stage = Path(
            tempfile.mkdtemp(
                prefix=".{}.testflight-".format(output.name),
                dir=str(output.parent),
            )
        )
        mode = (
            "unsigned-check"
            if arguments.unsigned_check
            else "signed-archive"
            if arguments.archive
            else "prepare-only"
        )
        archive_code = None
        log_path = stage / "build.log"
        with log_path.open("w", encoding="utf-8") as log_file:
            log_file.write("Mikansei TestFlight preparation log\n")
            log_file.write("Mode: {}\n".format(mode))
            log_file.flush()

            copy_minimal_source(stage)
            generator = stage / "Scripts" / "generate_project.py"
            generator_code = run_logged(
                [sys.executable, str(generator)],
                stage,
                log_file,
            )
            if generator_code != 0:
                raise PrepareError(
                    "复制品的首次 generate_project.py 失败，退出码 {}。".format(
                        generator_code
                    )
                )

            project_file = stage / "Mikansei.xcodeproj" / "project.pbxproj"
            version, source_build_number = read_release_metadata(project_file)
            build_number = validate_build_number(
                arguments.build_number or source_build_number
            )
            widget_bundle_id = configure_project(
                project_file,
                team,
                bundle_id,
                version,
                build_number,
            )

            generator_code = run_logged(
                [sys.executable, str(generator)],
                stage,
                log_file,
            )
            if generator_code != 0:
                raise PrepareError(
                    "复制品的第二次 generate_project.py 未能恢复 OpenStep 工程格式，退出码 {}。".format(
                        generator_code
                    )
                )
            validate_configured_project(
                project_file,
                team,
                bundle_id,
                widget_bundle_id,
                version,
                build_number,
            )

            if arguments.archive or arguments.unsigned_check:
                command = make_archive_command(
                    unsigned=arguments.unsigned_check
                )
                archive_code = run_logged(command, stage, log_file)
                if archive_code == 0:
                    checker = stage / "Scripts" / "check_ios_archive_icons.py"
                    archive_code = run_logged(
                        [
                            sys.executable,
                            str(checker),
                            str(stage / "Mikansei.xcarchive"),
                        ],
                        stage,
                        log_file,
                    )

        write_manifest(
            stage,
            team,
            bundle_id,
            widget_bundle_id,
            version,
            build_number,
            mode,
            archive_code,
        )
        publish_stage(stage, output)

        print("准备包: {}".format(output))
        print("清单: {}".format(output / "PREPARED_APP.json"))
        print("日志: {}".format(output / "build.log"))
        if arguments.unsigned_check:
            print(
                "无签名归档结果仅用于编译检查；不能安装或分发到 TestFlight。"
            )
        elif not arguments.archive:
            print_archive_command(output)

        return archive_code if archive_code is not None else 0
    except (PrepareError, OSError) as error:
        if stage is not None and stage.exists():
            log_path = stage / "build.log"
            try:
                with log_path.open("a", encoding="utf-8") as log_file:
                    log_file.write("Preparation failed: {}\n".format(error))
            except OSError:
                pass
            print(
                "准备失败的现场已保留（如已创建 build.log，也在此目录）：{}".format(
                    stage
                ),
                file=sys.stderr,
            )
        parser.error(str(error))
    return 2


if __name__ == "__main__":
    sys.exit(main())
