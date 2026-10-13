from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parents[1]
source = root / 'Artwork' / 'AppIcon.png'
source.parent.mkdir(exist_ok=True)
subprocess.run(['swift', str(root / 'Scripts/generate-icon.swift'), str(source)], check=True)
for platform in ('ios', 'macos'):
    folder = root / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
    for item in json.loads((folder / 'Contents.json').read_text())['images']:
        if 'filename' not in item:
            continue
        size = round(float(item['size'].split('x')[0]) * float(item.get('scale', '1x').removesuffix('x')))
        subprocess.run(['sips', '-z', str(size), str(size), str(source), '--out', str(folder / item['filename'])], check=True, stdout=subprocess.DEVNULL)
for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    target = root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
    subprocess.run(['sips', '-z', str(size), str(size), str(source), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)
print('Mikanseta kraft icons generated')
