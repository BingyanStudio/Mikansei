#!/bin/bash
MIKANSEI_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 "$MIKANSEI_PROJECT_DIR/Scripts/install_mac.py"
echo
read -r -p "按回车关闭此窗口…" _mikansei_close
