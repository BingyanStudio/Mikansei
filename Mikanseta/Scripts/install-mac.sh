#!/bin/bash
set -euo pipefail
mks_root="$(cd "$(dirname "$0")/.." && pwd)"
"$mks_root/Scripts/flutter.sh" build macos --release
python3 "$mks_root/Scripts/install-mac.py"
