#!/usr/bin/env python3
"""Build, sign and install Mikansei with Xcode's configured Apple account.

No passwords, certificate exports, device erases, or app uninstalls.
Use --check to inspect setup without signing, installing, or opening Xcode.
"""
import argparse
import json
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Mikansei.xcodeproj"
BUILD = ROOT / "LocalInstall"


class InstallError(Exception):
    pass


def command(arguments, *, timeout=90, log=None):
    if log is not None:
        result = subprocess.run(arguments, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            raise InstallError(f"步骤未完成，详细原因见：{BUILD / 'install.log'}")
        return ""
    result = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        details = (result.stderr or result.stdout).strip()
        raise InstallError(details[-2000:] or f"命令失败：{arguments[0]}")
    return result.stdout


def build_settings():
    raw = command([
        "xcodebuild", "-project", str(PROJECT), "-target", "Mikansei",
        "-configuration", "Debug", "-sdk", "iphoneos", "-showBuildSettings", "-json",
    ])
    settings = json.loads(raw)
    app = next((item for item in settings if item.get("target") == "Mikansei"), None)
    if app is None:
        raise InstallError("未找到 Mikansei target，请重新打开项目检查工程。")
    return app["buildSettings"]


def devices():
    with tempfile.TemporaryDirectory(prefix="mikansei-devices-") as folder:
        output = Path(folder) / "devices.json"
        command(["xcrun", "devicectl", "list", "devices", "--timeout", "30", "--json-output", str(output)], timeout=40)
        payload = json.loads(output.read_text())
    candidates = []
    for device in payload.get("result", {}).get("devices", []):
        hardware = device.get("hardwareProperties", {})
        connection = device.get("connectionProperties", {})
        properties = device.get("deviceProperties", {})
        platform = str(hardware.get("platform", "")).lower()
        if platform not in {"ios", "iphoneos"}:
            continue
        # An iPad also reports iOS; this installer selects iPhones only.
        device_type = str(hardware.get("deviceType", "")).lower()
        if device_type and device_type != "iphone":
            continue
        if connection.get("tunnelState") != "connected":
            continue
        identifier = device.get("identifier")
        udid = hardware.get("udid")
        if not identifier or not udid:
            continue
        candidates.append({"identifier": identifier, "udid": udid, "name": properties.get("name", "iPhone"), "developerMode": properties.get("developerModeStatus")})
    return candidates


def choose_device(candidates, requested, check):
    if requested:
        matches = [d for d in candidates if requested in {d["identifier"], d["udid"], d["name"]}]
        if len(matches) != 1:
            raise InstallError("未唯一找到指定的已连接 iPhone，请检查连接或设备名称。")
        return matches[0]
    if not candidates:
        raise InstallError("没有找到已连接的 iPhone。请用数据线连接、解锁，点“信任此电脑”，并在 Xcode 中配对。")
    if len(candidates) == 1:
        return candidates[0]
    if check:
        print(f"检测到 {len(candidates)} 台 iPhone，安装时会让你选择。")
        return None
    print("连接了多台 iPhone，请选择安装目标：")
    for index, device in enumerate(candidates, 1):
        print(f"  {index}. {device['name']}")
    value = input("输入序号：").strip()
    if not value.isdigit() or not 1 <= int(value) <= len(candidates):
        raise InstallError("未选择有效设备，已停止；没有安装到任何手机。")
    return candidates[int(value) - 1]


def main():
    parser = argparse.ArgumentParser(description="自动编译并安装 Mikansei 到已连接的 iPhone")
    parser.add_argument("--check", action="store_true", help="只检查前置条件，不签名、不安装")
    parser.add_argument("--device", help="指定已连接 iPhone 的名称或标识")
    args = parser.parse_args()
    print("Mikansei · iPhone 安装助手", flush=True)
    if sys.platform != "darwin":
        raise InstallError("此安装助手需要安装了完整 Xcode 的 Mac。")
    if not PROJECT.exists():
        raise InstallError("找不到工程，请保留安装入口与项目文件的相对位置。")
    command(["xcrun", "--find", "devicectl"])
    print("检查 Xcode 签名配置…", flush=True)
    settings = build_settings()
    team = settings.get("DEVELOPMENT_TEAM", "").strip()
    if not team:
        if not args.check:
            subprocess.run(["open", str(PROJECT)], check=False)
        raise InstallError(
            "还没有选择签名 Team。只需配置一次：\n"
            "  Xcode → Settings → Accounts：登录 Apple 账号。\n"
            "  Mikansei target → Signing & Capabilities：勾选自动签名，选择你的 Team。\n"
            "  然后重新双击“安装到iPhone.command”。"
        )
    if settings.get("CODE_SIGN_STYLE") != "Automatic":
        raise InstallError("请在 Signing & Capabilities 中勾选 Automatically manage signing，再重试。")
    selected = choose_device(devices(), args.device, args.check)
    if selected:
        print(f"设备：{selected['name']}", flush=True)
        if selected["developerMode"] in {"disabled", "off"}:
            raise InstallError("请在 iPhone：设置 → 隐私与安全性 → 开发者模式，开启后重启并确认。")
    if args.check:
        print("检查通过。尚未编译、签名、安装；正式安装时 Xcode 仍可能要求更新签名或平台组件。")
        return

    BUILD.mkdir(exist_ok=True)
    log_path = BUILD / "install.log"
    with log_path.open("w") as log:
        print("编译并签名…（首次可能需要几分钟）", flush=True)
        print(f"详细日志：{log_path}", flush=True)
        command([
            "xcodebuild", "-project", str(PROJECT), "-scheme", "Mikansei",
            "-configuration", "Debug", "-destination", f"id={selected['udid']}",
            "-derivedDataPath", str(BUILD / "DerivedData"),
            "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration", "build",
        ], timeout=1800, log=log)
        app = BUILD / "DerivedData/Build/Products/Debug-iphoneos/Mikansei.app"
        if not app.is_dir():
            raise InstallError("编译没有生成 iPhone App，安装已停止。")
        with (app / "Info.plist").open("rb") as file:
            bundle_id = plistlib.load(file)["CFBundleIdentifier"]
        print("安装到 iPhone…请保持手机解锁。", flush=True)
        command(["xcrun", "devicectl", "device", "install", "app", "--device", selected["identifier"], str(app), "--timeout", "120"], timeout=135, log=log)
        print("安装成功，尝试启动…", flush=True)
        try:
            command(["xcrun", "devicectl", "device", "process", "launch", "--device", selected["identifier"], bundle_id, "--timeout", "30"], timeout=40, log=log)
        except (InstallError, subprocess.TimeoutExpired):
            print("App 已安装，但未能自动启动。请在手机上点击 Mikansei；如提示未信任开发者，请按系统提示在“通用 → VPN 与设备管理”中信任。")
            return
    print("完成。首次进入 App 时，请按需允许通知。")


if __name__ == "__main__":
    try:
        main()
    except (InstallError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"\n尚未完成：{error}", file=sys.stderr)
        print("安装帮助：" + str(ROOT / "INSTALL.md"), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n已取消。")
        sys.exit(130)
