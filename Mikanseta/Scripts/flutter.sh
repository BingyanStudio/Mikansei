#!/bin/bash
set -euo pipefail
mks_root="$(cd "$(dirname "$0")/.." && pwd)"
mks_repo="$(cd "$mks_root/.." && pwd)"
source "$mks_repo/Scripts/toolchains-path.sh"
mks_toolchains="$(mikansei_toolchains_dir "$mks_repo")"
mks_default_sdk=""
if [[ -n "$mks_toolchains" ]]; then
  mks_default_sdk="$mks_toolchains/flutter"
fi
mks_sdk="${FLUTTER_SDK:-$mks_default_sdk}"
if [[ -n "$mks_sdk" && -x "$mks_sdk/bin/flutter" ]]; then
  mks_flutter="$mks_sdk/bin/flutter"
  if [[ -n "$mks_toolchains" ]]; then
    export PUB_CACHE="${PUB_CACHE:-$mks_toolchains/pub-cache}"
  fi
else
  mks_flutter="$(command -v flutter || true)"
fi
if [[ -z "$mks_flutter" ]]; then
  echo "请先安装 Flutter 3.47.7，或设置 FLUTTER_SDK。教程：https://docs.flutter.dev/install/manual"
  exit 1
fi
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export FLUTTER_SUPPRESS_ANALYTICS=true
cd "$mks_root"
exec "$mks_flutter" "$@"
