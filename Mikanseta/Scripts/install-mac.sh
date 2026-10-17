#!/bin/bash
set -euo pipefail
mks_root="$(cd "$(dirname "$0")/.." && pwd)"
mks_defines=()
while IFS= read -r mks_flag; do
  [[ -n "$mks_flag" ]] && mks_defines+=("$mks_flag")
done < <("$mks_root/Scripts/dart-defines.sh")
"$mks_root/Scripts/flutter.sh" build macos --release ${mks_defines[@]+"${mks_defines[@]}"}
python3 "$mks_root/Scripts/install-mac.py"
