#!/bin/bash
MIKANSEI_PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "需要 Xcode 附带的 Python 3。请先安装完整 Xcode 和命令行工具。"
else
  python3 "$MIKANSEI_PROJECT_DIR/Scripts/install_iphone.py"
fi
echo
read -r -p "按回车关闭此窗口…" _mikansei_close
