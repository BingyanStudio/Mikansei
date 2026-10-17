#!/bin/bash
set -euo pipefail
mks_root="$(cd "$(dirname "$0")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$mks_root/../../.toolchains/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-$mks_root/../../.toolchains/jdk21/Contents/Home}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$mks_root/../../.toolchains/gradle-cache}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
if [[ ! -x "$JAVA_HOME/bin/java" || ! -d "$ANDROID_HOME/platforms" ]]; then
  echo "请先安装 Java 21 与 Android SDK，见 INSTALL_ANDROID.md。"
  exit 1
fi
if [[ ! -f "$mks_root/android/key.properties" ]]; then
  echo "缺少安卓发布签名配置 android/key.properties，见 INSTALL_ANDROID.md。"
  exit 1
fi
cd "$mks_root"
# 集成测试以 debug 模式生成时会把 dev 依赖插件（integration_test）写进
# GeneratedPluginRegistrant.java，导致 release 编译找不到程序包；删除后本次
# 构建会按 release 依赖集重新生成（该文件被 Flutter 模板 gitignore）。
rm -f "$mks_root/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
mks_defines=()
while IFS= read -r mks_flag; do
  [[ -n "$mks_flag" ]] && mks_defines+=("$mks_flag")
done < <("$mks_root/Scripts/dart-defines.sh")
"$mks_root/Scripts/flutter.sh" build apk --release ${mks_defines[@]+"${mks_defines[@]}"}
mks_version="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
mks_output="${MIKANSETA_OUTPUT_DIR:-$mks_root/../../Deliveries/Mikanseta}"
mkdir -p "$mks_output"
mks_output="$(cd "$mks_output" && pwd)"
mks_apk_name="Mikanseta-$mks_version-android.apk"
mks_apk="$mks_output/$mks_apk_name"
cp "$mks_root/build/app/outputs/flutter-apk/app-release.apk" "$mks_apk"
(cd "$mks_output" && shasum -a 256 "$mks_apk_name") > "$mks_apk.sha256"
echo "安装包：$mks_apk"
