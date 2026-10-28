#!/usr/bin/env python3
"""Seal the local beta and replace its bundle without touching sandbox data."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Scripts'))
from path_helpers import releases_dir, version_build

root = Path(__file__).resolve().parents[1]
source = root / 'build/macos/Build/Products/Release/Mikanseta.app'
source_info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
release_version = version_build(source_info)
destination = releases_dir(root.parent) / 'Mikanseta' / 'macOS' / release_version / 'Mikanseta-macOS.app'
expected = 'com.personal.mikanseta.macOS'

def identity(path):
    return plistlib.loads((path / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']

if identity(source) != expected:
    raise RuntimeError('安装标识已改变，请检查 Mac 工程后选择对应安装路径。')
if destination.exists() and identity(destination) != expected:
    raise RuntimeError('目标路径属于其他 App，未替换。')
destination.parent.mkdir(parents=True, exist_ok=True)

# Flutter may update App.framework after Xcode caches the outer resource seal.
# Seal the finished local Release bundle using only the beta's own entitlements.
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(root / 'macos/Runner/Release.entitlements'), str(source)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
stage = Path(tempfile.mkdtemp(prefix='.mikanseta-install-', dir=destination.parent))
candidate, backup = stage / 'Mikanseta.app', stage / 'previous.app'
try:
    subprocess.run(['ditto', str(source), str(candidate)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(candidate)], check=True)
    subprocess.run(['pkill', '-x', 'Mikanseta'], check=False)
    if destination.exists(): os.replace(destination, backup)
    try:
        os.replace(candidate, destination)
    except Exception:
        if backup.exists(): os.replace(backup, destination)
        raise
    if backup.exists(): shutil.rmtree(backup)
    subprocess.run(['open', str(destination)], check=True)
    print('Mikanseta 已打开。本机数据与 Mikansei 分别保存。')
finally:
    # Retain the previous bundle if a rollback itself failed.
    if not backup.exists(): shutil.rmtree(stage)
    else: print('旧安装包保留在：' + str(backup))
