# Mikanseta Android 安装与更新

## 0.7.0 (18) 发布状态

Mikanseta 0.7.0 (18) 已在 [BingyanStudio/Mikansei GitHub Release](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0) 公开预发布（tag 指向 `cfe17a1d1cb04fff7de86106f469362a338a966d`）：[下载 Android APK](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-Android.apk) · [SHA-256 校验文件](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/SHA256SUMS.txt) · [构建信息](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/build-info.json)。Release 标记为 `draft=false`、`prerelease=true`。

旧版 Android 0.4.2 (8) 安装包仍作为历史版本保留：[下载旧版 APK](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.4.2/Mikanseta-Android.apk)。

## 安装与覆盖更新

本版 APK 发布并核实签名后，可按原有安装方式安装：将 APK 下载到手机，在浏览器或文件管理器中打开，按 Android 提示允许该来源安装应用，再确认安装。

从旧版更新时，请直接安装新 APK，不要先卸载旧版。Android 只有在应用 ID 和签名证书兼容时才允许覆盖更新；兼容更新会保留应用数据。本版 application ID 为 `com.personal.mikanseta`，最终 APK 签名已核实与公开的 0.4.2 APK 一致，支持按原有方式直接覆盖。安装前仍建议从设置导出 JSON 备份；本轮未在个人设备上实测覆盖升级。

## 本地构建

在仓库中的 `Mikanseta` 目录运行：

```sh
./Scripts/build-android.sh
```

脚本从 `pubspec.yaml` 读取当前 Flutter 版本，并构建 Android Release APK。默认按版本号输出到仓库旁的 `../Releases/Mikanseta/Android/<version+build>/`；可用 `MIKANSETA_OUTPUT_DIR` 指定输出目录，或用 `MIKANSEI_RELEASES_DIR` 更换 `Releases/` 根目录。本版发布资产名为 `Mikanseta-Android.apk`，可从上方 Release 下载。

Release 构建需要已配置的 Android 发布签名，不会回退到调试签名。覆盖更新需要与既有安装兼容的发布证书；本版已确认与旧 0.4.2 (8) 相同。不要将签名密钥或密码放入仓库或发布资产。可通过 Release 附带的 `SHA256SUMS.txt` 核对 APK 摘要；签名检查可使用 Android SDK 的 `apksigner verify --verbose <APK>`。

其他电脑需要 Java 21、Android SDK（API 36、Build Tools 36.0.0、NDK 28.2.13676358）及项目固定版本的 Flutter。可用 `JAVA_HOME`、`ANDROID_HOME` 和 `FLUTTER_SDK` 指向本机工具链。完整准备状态见 [Mikanseta 0.7.0 发布说明](../Documentation/RELEASE_MIKANSETA_0.7.0.md)；平台验证结果见 [Mikanseta 验证记录](VALIDATION.md)。
