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

is_mikanseta_cloud_build() {
    [ "${CI_XCODE_SCHEME:-}" = "Mikanseta" ] || return 1
    [ -n "${CI_PROJECT_FILE_PATH:-}" ] || return 1

    project_path="$CI_PROJECT_FILE_PATH"
    case "$project_path" in
        /*) ;;
        *) project_path="$repository_root/$project_path" ;;
    esac
    project_parent="${project_path%/*}"
    project_name="${project_path##*/}"
    project_path="$(CDPATH= cd -- "$project_parent" && pwd -P)/$project_name"
    project_dir="$(CDPATH= cd -- "$repository_root/Mikanseta/ios" && pwd -P)"
    case "$project_path" in
        "$project_dir/Mikanseta.xcworkspace"|"$project_dir/Mikanseta.xcodeproj") ;;
        *) return 1 ;;
    esac

    case "${CI_XCODE_PROJECT:-}" in
        ""|Mikanseta|Mikanseta.xcodeproj|Mikanseta.xcworkspace) ;;
        *) return 1 ;;
    esac
    return 0
}

if [ "${CI_XCODE_SCHEME:-}" = "Mikanseta" ] ||
   [ "${CI_XCODE_PROJECT:-}" = "Mikanseta" ] ||
   [ "${CI_XCODE_PROJECT:-}" = "Mikanseta.xcodeproj" ] ||
   [ "${CI_XCODE_PROJECT:-}" = "Mikanseta.xcworkspace" ]; then
    if ! is_mikanseta_cloud_build; then
        printf '%s\n' "ERROR: Xcode Cloud selected the Mikanseta scheme without its expected iOS project/workspace path."
        exit 1
    fi
    exec "$repository_root/Mikanseta/Scripts/prepare-testflight.sh" --verify-archive "$CI_ARCHIVE_PATH"
fi

python3 Scripts/check_xcode_cloud_release.py --root "$repository_root" --archive "$CI_ARCHIVE_PATH"
