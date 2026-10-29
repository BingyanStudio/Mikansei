#!/bin/sh
set -eu

if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]; then
    printf '%s\n' "Xcode build failed; preserving its failure without checking a partial archive."
    exit 0
fi

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    printf '%s\n' "No archive action; archive resource checks do not apply."
    exit 0
fi

: "${CI_ARCHIVE_PATH:?Xcode Cloud did not provide the completed archive path.}"
repository_root="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repository_root"
python3 Scripts/check_xcode_cloud_release.py --root "$repository_root" --archive "$CI_ARCHIVE_PATH"
