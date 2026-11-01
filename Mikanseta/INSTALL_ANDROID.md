# Mikanseta Android 安装与更新

## 0.7.0 (18) 发布状态

Mikanseta 0.7.0 (18) 目前处于发布准备中。Git tag `mikanseta-v0.7.0` 和 GitHub Release 尚未创建，APK 尚未作为本版资产发布。计划在 [BingyanStudio/Mikansei 的同一版本页](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0) 提供 `Mikanseta-Android.apk`；签名证书与现有安卓安装包的连续性仍待核实，因此当前不能确认可直接覆盖安装。

旧版 Android 0.4.2 (8) 安装包仍作为历史版本保留：[下载旧版 APK](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.4.2/Mikanseta-Android.apk)。

## 安装与覆盖更新

本版 APK 发布并核实签名后，可按原有安装方式安装：将 APK 下载到手机，在浏览器或文件管理器中打开，按 Android 提示允许该来源安装应用，再确认安装。

从旧版更新时，请直接安装新 APK，不要先卸载旧版。Android 只有在应用 ID 和签名证书兼容时才允许覆盖更新；兼容更新会保留应用数据。Mikanseta 的 Android application ID 为 `com.personal.mikanseta`，但本版与已发布 0.4.2 APK 的签名连续性尚待发布前核验。若系统提示签名不匹配，请停止安装并保留现有应用；卸载应用可能删除本机数据。安装前建议在设置中导出 JSON 备份。

## 本地构建

在仓库中的 `Mikanseta` 目录运行：

```sh
./Scripts/build-android.sh
```

脚本从 `pubspec.yaml` 读取当前 Flutter 版本，并构建 Android Release APK。默认按版本号输出到仓库旁的 `../Releases/Mikanseta/Android/<version+build>/`；可用 `MIKANSETA_OUTPUT_DIR` 指定输出目录，或用 `MIKANSEI_RELEASES_DIR` 更换 `Releases/` 根目录。计划上传到本版 GitHub Release 的资产名为 `Mikanseta-Android.apk`。

Release 构建需要已配置的 Android 发布签名，不会回退到调试签名。覆盖更新需要与既有安装兼容的同一发布证书；本版连续性核验待完成。不要将签名密钥或密码放入仓库或发布资产。签名检查可使用 Android SDK 的 `apksigner verify --verbose <APK>`。

其他电脑需要 Java 21、Android SDK（API 36、Build Tools 36.0.0、NDK 28.2.13676358）及项目固定版本的 Flutter。可用 `JAVA_HOME`、`ANDROID_HOME` 和 `FLUTTER_SDK` 指向本机工具链。完整准备状态见 [Mikanseta 0.7.0 发布说明](../Documentation/RELEASE_MIKANSETA_0.7.0.md)；平台验证结果见 [Mikanseta 验证记录](VALIDATION.md)。
