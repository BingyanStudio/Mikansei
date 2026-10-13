#!/bin/bash
set -euo pipefail
mks_root="$(cd "$(dirname "$0")/.." && pwd)"
mks_temp="$(mktemp -d)"
trap 'rm -rf "$mks_temp"' EXIT
swiftc -o "$mks_temp/native-check" "$mks_root"/../Sources/MikanseiCore/*.swift "$mks_root/Scripts/NativeBackupCheck.swift"
"$mks_temp/native-check" fixture "$mks_temp/native.json"
"$mks_root/Scripts/flutter.sh" pub get
mks_sdk="${FLUTTER_SDK:-$mks_root/../../.toolchains/flutter}"
if [[ -x "$mks_sdk/bin/dart" ]]; then
  "$mks_sdk/bin/dart" "$mks_root/Scripts/backup_roundtrip.dart" "$mks_temp/native.json" "$mks_temp/flutter.json"
else
  dart "$mks_root/Scripts/backup_roundtrip.dart" "$mks_temp/native.json" "$mks_temp/flutter.json"
fi
"$mks_temp/native-check" verify "$mks_temp/flutter.json"
