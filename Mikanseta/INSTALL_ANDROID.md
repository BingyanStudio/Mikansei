# Mikanseta 安卓测试版

## 在手机上安装

将 APK 文件发送到安卓手机，在浏览器或文件管理器中打开。如系统提示，允许该下载来源安装应用，再确认安装。

此版包含清单、卡片内子事项勾选、日程、循环、计时、本地保存与 JSON 备份。系统通知、日历同步、小组件及跨设备云同步尚未接入，DDL 暂不触发系统提醒。

## 安装包信息

当前版本为 **0.1.1 (2)**，包名 `com.personal.mikanseta`，最低 Android 7.0（API 24），目标 API 36。通用 APK 包含 ARM64、32 位 ARM 和 x86_64；使用专用发布证书签名。实际运行验证范围见 [VALIDATION.md](VALIDATION.md)。

## 重新构建

工作区构建工具位于 `../../.toolchains/`，不会修改全局 Java 或 Flutter 设置。双击 `生成安卓安装包.command`，或执行：

```sh
./Scripts/build-android.sh
```

原始输出为 `build/app/outputs/flutter-apk/app-release.apk`，同时复制到工作区 `../../Deliveries/Mikanseta/`，按版本命名并附 SHA-256 文件。这是包含多个 CPU 架构的单文件安装包，版本号读取 `pubspec.yaml`。可通过 `MIKANSETA_OUTPUT_DIR` 指定交付目录。

其他电脑需要 Java 21、Android SDK（API 36、Build Tools 36.0.0、NDK 28.2.13676358）及本项目固定版本的 Flutter。可以用 `JAVA_HOME`、`ANDROID_HOME` 和 `FLUTTER_SDK` 指定现有工具。

将 `android/key.properties.example` 复制为 `android/key.properties`，填写本地发布密钥信息。Release 构建使用发布签名，不回退到调试签名。后续更新需沿用该发布密钥。

本工作区首次创建的密钥与密码单独保存在 `../../.toolchains/mikanseta-signing/`，请另行备份；它们不进入 Git 仓库，也不应随 APK 分发。

签名验证可使用 Android SDK 的 `apksigner verify --verbose`。实际构建和运行结果记录在 [VALIDATION.md](VALIDATION.md)。
