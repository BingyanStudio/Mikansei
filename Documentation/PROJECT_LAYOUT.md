# 项目目录与构建输出

`Mikansei_Project/` 是工作区，`Mikansei/` 是唯一的源码 Git 仓库。源码工程保持原有位置：原生 Swift 工程、共享核心与资源仍在 `Mikansei/`，独立的 Flutter 工程仍在 `Mikansei/Mikanseta/`。不要把 Xcode、Swift Package 或 Flutter 模板要求的工程目录移到工作区其他位置。

## 工作区目录

| 目录 | 用途 |
| --- | --- |
| `Mikansei/` | 原生 Mikansei、Flutter Mikanseta、脚本、文档和 Git 历史 |
| `Releases/` | 可安装、运行或分享的最终成品，按产品、平台和版本归档 |
| `Design/` | 设计探索、预览图和可分享的设计导出 |
| `Archives/SourceSnapshots/` | 旧源码快照 |
| `Archives/Reference/` | 历史产品介绍、旧功能清单等参考资料 |
| `Archives/CIArtifacts/` | 从 CI 下载的原始打包文件 |
| `Archives/Builds/` | 未发布的初版或其他非发布构建 |

`Mikansei/Documentation/` 保存源码与开发说明；`Mikansei/LocalInstall/`、各工程的 `build/` 和本机工具链保存本地状态、凭据或中间文件，不是交付目录。签名配置、密钥、账号服务本地配置和设备安装日志不得复制到发布包或提交到 Git。

## 发布成品

本地安装和打包脚本默认把最终成品写到源码仓库旁的 `../Releases/`，按产品、平台、版本及构建号分层：

```text
Releases/
├── Mikansei/macOS/<version+build>/Mikansei-macOS.app
└── Mikanseta/
    ├── Android/<version+build>/
    │   ├── Mikanseta-<version+build>-android.apk
    │   └── Mikanseta-<version+build>-android.apk.sha256
    ├── macOS/<version+build>/Mikanseta-macOS.app
    └── Windows/<version+build>/
        ├── Mikanseta-Windows-x64-Setup.exe
        ├── Mikanseta-Windows-x64.zip
        └── build metadata and SHA-256 files
```

Android 和 Windows 的版本号及构建号读取 `Mikanseta/pubspec.yaml`。当前源码版本 `0.5.2+15` 的 Android APK 默认位于 `Releases/Mikanseta/Android/0.5.2+15/Mikanseta-0.5.2+15-android.apk`；本地 Windows 包默认写入 `Releases/Mikanseta/Windows/0.5.2+15/`。两个 macOS 安装脚本读取构建后 App 的 `Contents/Info.plist`，用内嵌版本和构建号选择目录。

可用 `MIKANSEI_RELEASES_DIR` 把整个 `Releases/` 根目录放到其他位置。相对路径以源码仓库为基准。Android 脚本支持 `MIKANSETA_OUTPUT_DIR` 指定 APK 和校验文件的精确输出目录。Windows 脚本按 `-OutputDirectory`、`MIKANSETA_OUTPUT_DIR`、默认版本目录的顺序选择输出位置；默认版本目录使用 `MIKANSEI_RELEASES_DIR` 指定的根目录（如有）。

历史发布包保留原始文件名和内容。现存的 `Releases/Mikansei/macOS/0.3.0/` 是旧版本压缩包；今后由原生安装脚本产生的 `.app` 使用版本加构建号目录。GitHub Release 附件名与下载地址独立于本地目录，不随本地重排改变。

## 工具链、凭据与中间文件

Flutter、Java、Android SDK 和 Gradle 缓存默认从源码仓库开始逐层向上查找第一个 `.toolchains/` 目录，因此工具链可放在工作区或更高层目录。设置 `MIKANSEI_TOOLCHAINS_DIR` 可指定工具链根目录。`FLUTTER_SDK`、`JAVA_HOME`、`ANDROID_HOME`、`PUB_CACHE` 和 `GRADLE_USER_HOME` 可分别覆盖对应工具或缓存路径。

Flutter 各平台生成的 `build/` 和其他工程中间文件留在源码仓库并由忽略规则排除。Dart 包缓存默认写到已找到的工具链目录 `pub-cache/`，也可用 `PUB_CACHE` 覆盖。Android 发布签名配置 `Mikanseta/android/key.properties`、本机 `.toolchains/` 下的密钥材料，以及 `LocalInstall/` 中的本地配置不属于源码或发行件；使用时由开发者在本机自行配置。CI Windows 打包显式输出到 `Mikanseta/build/windows-delivery/`，供同一工作流的安装检查和 artifact 上传使用，不改变本地默认输出规则。
