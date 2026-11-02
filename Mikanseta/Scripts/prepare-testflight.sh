#!/bin/bash
set -euo pipefail
set +x
umask 077

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
mks_root="$(cd "$script_dir/.." && pwd -P)"
repo_root="$(cd "$mks_root/.." && pwd -P)"
install_stage=""
temp_dir=""
cleanup() {
  [[ -z "$install_stage" ]] || rm -rf -- "$install_stage"
  [[ -z "$temp_dir" ]] || rm -rf -- "$temp_dir"
}
trap cleanup EXIT

if [[ "${1:-}" == "--verify-archive" ]]; then
  [[ $# == 2 ]] || { printf '%s\n' "Usage: prepare-testflight.sh --verify-archive <archive.xcarchive>" >&2; exit 2; }
  exec python3 "$script_dir/check-testflight-archive.py" --root "$repo_root" --archive "$2"
fi
[[ $# == 0 ]] || { printf '%s\n' "Usage: prepare-testflight.sh" >&2; exit 2; }

flutter_version="$(tr -d '\r\n' < "$mks_root/.flutter-version")"
if [[ ! "$flutter_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' "ERROR: Mikanseta/.flutter-version must contain a pinned stable Flutter version." >&2
  exit 1
fi

case "$(uname -m)" in
  arm64) sdk_arch="arm64"; archive_name="flutter_macos_arm64_${flutter_version}-stable.zip" ;;
  x86_64) sdk_arch="x64"; archive_name="flutter_macos_${flutter_version}-stable.zip" ;;
  *) printf '%s\n' "ERROR: iOS release preparation requires an arm64 or x86_64 macOS host." >&2; exit 1 ;;
esac

toolchain_root=""
if [[ -n "${MIKANSEI_TOOLCHAINS_DIR:-}" ]]; then
  case "$MIKANSEI_TOOLCHAINS_DIR" in
    /*) toolchain_root="$MIKANSEI_TOOLCHAINS_DIR" ;;
    *) toolchain_root="$repo_root/$MIKANSEI_TOOLCHAINS_DIR" ;;
  esac
elif [[ "${CI_XCODE_CLOUD:-}" == "TRUE" && -n "${CI_WORKSPACE_PATH:-}" ]]; then
  toolchain_root="$CI_WORKSPACE_PATH/toolchains/mikanseta"
else
  toolchain_root="$mks_root/.dart_tool/testflight-toolchains"
fi
cache_root="$toolchain_root/flutter-$flutter_version-$sdk_arch"
mkdir -p "$cache_root"
export PUB_CACHE="${PUB_CACHE:-$cache_root/pub-cache}"
export FLUTTER_SUPPRESS_ANALYTICS=true
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

flutter_bin=""
if [[ "${CI_XCODE_CLOUD:-}" != "TRUE" && -n "${FLUTTER_SDK:-}" ]]; then
  if [[ ! -x "$FLUTTER_SDK/bin/flutter" ]]; then
    printf '%s\n' "ERROR: FLUTTER_SDK does not point to an installed Flutter SDK." >&2
    exit 1
  fi
  flutter_bin="$FLUTTER_SDK/bin/flutter"
elif [[ "${CI_XCODE_CLOUD:-}" != "TRUE" ]] && command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
fi

flutter_binary_version() {
  "$1" --version --machine 2>/dev/null | python3 -c 'import json,sys
try:
 print(json.load(sys.stdin).get("frameworkVersion", ""))
except (ValueError, TypeError):
 pass'
}

if [[ -n "$flutter_bin" ]]; then
  actual_version="$(flutter_binary_version "$flutter_bin" || true)"
  if [[ "$actual_version" != "$flutter_version" ]]; then
    if [[ -n "${FLUTTER_SDK:-}" ]]; then
      printf '%s\n' "ERROR: FLUTTER_SDK version does not match Mikanseta/.flutter-version." >&2
      exit 1
    fi
    flutter_bin=""
  fi
fi

if [[ -z "$flutter_bin" ]]; then
  releases_url="https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json"
  install_dir="$cache_root/flutter-sdk-${flutter_version}-${sdk_arch}"
  if [[ -x "$install_dir/bin/flutter" ]]; then
    actual_version="$(flutter_binary_version "$install_dir/bin/flutter" || true)"
    if [[ "$actual_version" != "$flutter_version" ]]; then
      printf '%s\n' "ERROR: A cached Flutter SDK does not match the pinned version; refusing to replace it." >&2
      exit 1
    fi
    flutter_bin="$install_dir/bin/flutter"
  else
    [[ ! -e "$install_dir" ]] || { printf '%s\n' "ERROR: An incomplete cached Flutter SDK exists; refusing to replace it." >&2; exit 1; }
    install_stage="$(mktemp -d "$cache_root/.flutter-install.XXXXXX")"
    metadata="$install_stage/releases_macos.json"
    sdk_archive="$install_stage/flutter-sdk.zip"
    curl --fail --location --retry 3 --silent --show-error "$releases_url" --output "$metadata"
    release_fields="$(python3 - "$metadata" "$archive_name" <<'PY'
import json
import sys
from urllib.parse import urlparse

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    base_url = metadata.get("base_url", "")
    parsed = urlparse(base_url)
    if parsed.scheme != "https" or parsed.netloc != "storage.googleapis.com":
        raise ValueError
    expected_name = sys.argv[2]
    matches = [
        release for release in metadata.get("releases", [])
        if release.get("channel") == "stable"
        and release.get("archive", "").rsplit("/", 1)[-1] == expected_name
    ]
    if len(matches) != 1:
        raise ValueError
    release = matches[0]
    checksum = release.get("sha256", "")
    if len(checksum) != 64 or any(ch not in "0123456789abcdef" for ch in checksum.lower()):
        raise ValueError
    print(base_url.rstrip("/") + "/" + release["archive"])
    print(checksum.lower())
except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
    print("ERROR: Official Flutter release metadata did not contain the pinned macOS SDK.", file=sys.stderr)
    raise SystemExit(1)
PY
)"
    sdk_url="$(printf '%s\n' "$release_fields" | sed -n '1p')"
    sdk_sha256="$(printf '%s\n' "$release_fields" | sed -n '2p')"
    curl --fail --location --retry 3 --silent --show-error "$sdk_url" --output "$sdk_archive"
    printf '%s  %s\n' "$sdk_sha256" "$sdk_archive" | shasum -a 256 --check >/dev/null
    mkdir -p "$install_dir"
    unzip -q "$sdk_archive" -d "$install_stage"
    if [[ ! -x "$install_stage/flutter/bin/flutter" ]]; then
      printf '%s\n' "ERROR: The official Flutter archive did not contain the expected SDK layout." >&2
      exit 1
    fi
    rmdir "$install_dir"
    mv "$install_stage/flutter" "$install_dir"
    actual_version="$(flutter_binary_version "$install_dir/bin/flutter" || true)"
    if [[ "$actual_version" != "$flutter_version" ]]; then
      printf '%s\n' "ERROR: Downloaded Flutter SDK does not match the pinned version." >&2
      exit 1
    fi
    flutter_bin="$install_dir/bin/flutter"
  fi
fi

export FLUTTER_SDK="$(cd "$(dirname "$flutter_bin")/.." && pwd -P)"
export PATH="$(dirname "$flutter_bin"):$PATH"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mikanseta-testflight.XXXXXX")"
dart_defines_file="$temp_dir/public-dart-defines.json"

python3 - "$repo_root" "$dart_defines_file" <<'PY'
import json
import os
import plistlib
import sys

root, output = sys.argv[1:]
sys.path.insert(0, os.path.join(root, "Scripts"))
from supabase_config import CLIENT_KEY, PUBLIC_RESOURCE_PATH, URL_KEY, validate_client_configuration

try:
    with open(os.path.join(root, str(PUBLIC_RESOURCE_PATH)), "rb") as handle:
        client = validate_client_configuration(plistlib.load(handle))
    if client is None:
        raise ValueError
    defines = {
        "SUPABASE_URL": client[URL_KEY],
        "SUPABASE_ANON_KEY": client[CLIENT_KEY],
    }
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(defines, handle, separators=(",", ":"))
        handle.flush()
    os.chmod(output, 0o600)
except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException):
    print("ERROR: The tracked public Supabase client configuration is missing or invalid.", file=sys.stderr)
    raise SystemExit(1)
PY

cd "$mks_root"
"$flutter_bin" precache --ios
"$flutter_bin" pub get --enforce-lockfile

# Flutter 3.44+ uses Swift Package Manager by default. Keep CocoaPods available
# only for a legacy plugin or repository revision that actually has a Podfile.
if [[ -f "$mks_root/ios/Podfile" ]]; then
  if ! command -v pod >/dev/null 2>&1; then
    printf '%s\n' "ERROR: This Flutter iOS revision has a Podfile but CocoaPods is unavailable." >&2
    exit 1
  fi
  pod install --project-directory="$mks_root/ios"
fi

"$flutter_bin" build ios --config-only --flavor Mikanseta --no-pub --dart-define-from-file="$dart_defines_file"
python3 - "$repo_root" "$FLUTTER_SDK" <<'PY'
import base64
import os
import plistlib
import sys

root, flutter_root = sys.argv[1:]
sys.path.insert(0, os.path.join(root, "Scripts"))
from supabase_config import CLIENT_KEY, PUBLIC_RESOURCE_PATH, URL_KEY, validate_client_configuration

try:
    with open(os.path.join(root, str(PUBLIC_RESOURCE_PATH)), "rb") as handle:
        client = validate_client_configuration(plistlib.load(handle))
    if client is None:
        raise ValueError
    generated = os.path.join(root, "Mikanseta/ios/Flutter/Generated.xcconfig")
    with open(generated, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    settings = {}
    for line in lines:
        if "=" in line:
            key, value = line.split("=", 1)
            settings[key] = value
    if os.path.realpath(settings.get("FLUTTER_ROOT", "")) != os.path.realpath(flutter_root):
        raise ValueError
    encoded_defines = settings.get("DART_DEFINES", "")
    decoded = []
    for item in encoded_defines.split(","):
        if item:
            decoded.append(base64.b64decode(item, validate=True).decode("utf-8"))
    expected = {
        "SUPABASE_URL=" + client[URL_KEY],
        "SUPABASE_ANON_KEY=" + client[CLIENT_KEY],
    }
    if not expected.issubset(set(decoded)):
        raise ValueError
    if not os.path.isfile(os.path.join(root, "Mikanseta/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift")):
        raise ValueError
except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException):
    print("ERROR: Flutter iOS configuration did not contain the pinned SDK, plugin package and validated public client defines.", file=sys.stderr)
    raise SystemExit(1)
PY

printf 'Mikanseta iOS preparation complete: Flutter %s, locked Dart dependencies, Swift package/configuration and public client defines are ready.\n' "$flutter_version"
