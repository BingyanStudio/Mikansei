#!/usr/bin/env python3
"""Build a universal, locally signed Mac app; keep its data outside the app bundle."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

from path_helpers import releases_dir, version_build

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "LocalInstall"

def main():
    parser = argparse.ArgumentParser(description="编译并打开 Mikansei 的原生 Mac 版")
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    log = BUILD / "install-mac.log"
    print("正在准备 Mikansei Mac 版，首次编译需要几分钟…", flush=True)
    derived = BUILD / "MacReleaseDerivedData"
    with log.open("w") as output:
        subprocess.run(["xcodebuild", "-project", "MikanseiMac.xcodeproj", "-scheme", "MikanseiMac",
                        "-configuration", "Release", "-destination", "generic/platform=macOS",
                        "-derivedDataPath", str(derived), "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "build"],
                       cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=1200, check=True)
    source = derived / "Build/Products/Release/Mikansei.app"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(source)], check=True)
    with (source / "Contents/Info.plist").open("rb") as file:
        source_info = plistlib.load(file)
    release_version = version_build(source_info)
    destination = releases_dir(ROOT) / "Mikansei" / "macOS" / release_version / "Mikansei-macOS.app"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        with (destination / "Contents/Info.plist").open("rb") as file:
            previous = plistlib.load(file)
        if previous.get("CFBundleIdentifier") != "com.personal.mikansei.macOS":
            raise RuntimeError("目标位置有另一个应用，请先为它改名。")
        shutil.rmtree(destination)
    subprocess.run(["ditto", str(source), str(destination)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(destination)], check=True)
    print(f"Mac 版 {source_info['CFBundleShortVersionString']} ({source_info['CFBundleVersion']}) 已准备好：{destination}", flush=True)
    if not args.no_open:
        subprocess.run(["open", str(destination)], check=True)
    print("在 iPhone 和 Mac 的设置里，各选择一次同一个 iCloud Drive 文件夹即可同步。")

if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"未完成：{error}\n编译详情：{BUILD / 'install-mac.log'}", file=sys.stderr)
        sys.exit(1)
