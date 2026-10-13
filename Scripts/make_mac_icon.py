#!/usr/bin/env python3
"""Export the approved flat character icon for macOS using Apple's image tools."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
with tempfile.TemporaryDirectory(prefix="mikansei-icon-") as temporary:
    iconset = Path(temporary) / "Mikansei.iconset"
    iconset.mkdir()
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            subprocess.run(["sips", "-z", str(points * scale), str(points * scale), str(source),
                            "--out", str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
    destination = root / "Mac/Resources/Mikansei.icns"
    destination.parent.mkdir(exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(destination)], check=True)
    print(destination)
