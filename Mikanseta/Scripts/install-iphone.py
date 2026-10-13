#!/usr/bin/env python3
"""Build and install only the independent Mikanseta bundle; never uninstall apps."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', help='CoreDevice identifier or device UDID')
    parser.add_argument('--check', action='store_true', help='Check connection without installing')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mikanseta-') as folder:
        output = Path(folder) / 'devices.json'
        subprocess.run(['xcrun', 'devicectl', 'list', 'devices', '--json-output', str(output)], check=True, stdout=subprocess.DEVNULL)
        devices = json.loads(output.read_text()).get('result', {}).get('devices', [])
    ready = [d for d in devices if d.get('hardwareProperties', {}).get('platform') == 'iOS'
             and d.get('connectionProperties', {}).get('tunnelState') == 'connected']
    if args.device:
        ready = [d for d in ready if args.device in (d['identifier'], d.get('hardwareProperties', {}).get('udid'))]
    if len(ready) != 1:
        print('请连接并解锁一台 iPhone，确认信任这台 Mac。多台手机时用 --device 指定。')
        return 1
    device = ready[0]
    if args.check:
        print('iPhone 连接可用。尚未编译、签名或安装。')
        return 0
    local = root / 'LocalInstall'
    local.mkdir(exist_ok=True)
    log = local / 'install.log'
    with log.open('w') as stream:
        print('正在构建 Mikanseta，请保持手机解锁。', flush=True)
        subprocess.run([str(root / 'Scripts/flutter.sh'), 'build', 'ios', '--release', '--no-codesign'], cwd=root, stdout=stream, stderr=subprocess.STDOUT, check=True)
        subprocess.run(['xcodebuild', '-workspace', str(root / 'ios/Runner.xcworkspace'), '-scheme', 'Runner',
                        '-configuration', 'Release', '-destination', 'id=' + device['hardwareProperties']['udid'],
                        '-derivedDataPath', str(local / 'DerivedData'), '-allowProvisioningUpdates',
                        '-allowProvisioningDeviceRegistration', 'build'], cwd=root, stdout=stream, stderr=subprocess.STDOUT, check=True)
        app = local / 'DerivedData/Build/Products/Release-iphoneos/Runner.app'
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        if info['CFBundleIdentifier'] == 'com.personal.mikansei':
            raise RuntimeError('安装标识与原版冲突，安装已停止。')
        subprocess.run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', device['identifier'], str(app)], stdout=stream, stderr=subprocess.STDOUT, check=True)
        launch = subprocess.run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', device['identifier'], info['CFBundleIdentifier']], stdout=stream, stderr=subprocess.STDOUT)
    print('Mikanseta 安装完成。' if launch.returncode == 0 else 'Mikanseta 已安装，请解锁后在手机上打开。')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except subprocess.CalledProcessError:
        print('构建或安装未完成。若提示 No Accounts / No profiles，请在 Xcode 登录 Apple 账号，')
        print('打开 ios/Runner.xcworkspace，选 Runner → Signing & Capabilities → 你的 Personal Team。')
        print('详细记录：' + str(root / 'LocalInstall/install.log'))
        sys.exit(1)
    except Exception as error:
        print('安装未完成：' + str(error))
        sys.exit(1)
