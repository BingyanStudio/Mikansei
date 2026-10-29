#!/bin/sh
set -eu

repository_root="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repository_root"

# The tracked public client configuration contains no administrative credentials.
# Generate the ignored application resource before Xcode reads the project.
python3 Scripts/generate_project.py
python3 Scripts/check_xcode_cloud_release.py --root "$repository_root"
