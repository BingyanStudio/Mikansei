# Mikanseta 0.7.0 (18) 发布说明

**状态：公开预发布。** GitHub Release `mikanseta-v0.7.0` 已发布，`draft=false`、`prerelease=true`。tag 指向源码提交 `cfe17a1d1cb04fff7de86106f469362a338a966d`。Mikanseta 是 Mikansei 的 Flutter 版本；原生 Mikansei 仍为 `0.7.0 (14)`，本次未更新 TestFlight。

## 下载

所有平台资产都在同一个 [BingyanStudio/Mikansei 版本页](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0)。远端六项资产的文件大小和摘要均与本地产物匹配；校验值也可下载 `SHA256SUMS.txt` 核对。

| 平台 / 文件 | 下载 | 大小 | 说明 |
| --- | --- | ---: | --- |
| Android `Mikanseta-Android.apk` | [下载 APK](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-Android.apk) | 64,007,120 bytes | 发布证书与旧版 Android 0.4.2 (8) 一致；支持以相同 application ID 覆盖更新 |
| macOS `Mikanseta-macOS.zip` | [下载 ZIP](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-macOS.zip) | 24,998,133 bytes | universal App，包含 arm64 与 x86_64；未公证 |
| Windows `Mikanseta-Windows-x64-Setup.exe` | [下载安装版](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-Windows-x64-Setup.exe) | 见校验清单 | x64 安装版 |
| Windows `Mikanseta-Windows-x64.zip` | [下载免安装版](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-Windows-x64.zip) | 见校验清单 | 完整解压后运行 `Mikanseta.exe`，保留同目录运行库和 `data` |
| `SHA256SUMS.txt` | [下载校验清单](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/SHA256SUMS.txt) | — | 校验三个平台的四份安装文件 |
| `build-info.json` | [下载构建信息](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/build-info.json) | — | 跨平台联合清单，包含版本、源码、Android 签名信息与四份安装文件摘要 |

## 本版变化

Flutter 界面按手机和桌面窗口重新布局。手机使用「待办、日程、笔记」三个主入口，默认进入待办；日程包含「今日聚焦、列表、日历」及规划入口。待办支持类型、分类、清单、历史筛选，卡片直达编辑，并保留完成 / 重开、计时、Checklist、移入规划和恢复等对应操作。DDL 与执行时段分别展示。桌面使用侧栏、列表与详情组合，并保留课表、专注、账户同步、本机同步、备份与系统功能入口。

卡片颜色遵循事项类型和状态：待办 / 日程为绿色、作业为蓝紫色、笔记为暖色；DDL 使用暖色、完成项使用中性色、正在做的事项使用浅强调色。本版应用图标换为浅色调的眨眼笑脸。应用内主图 `MikansetaArtwork` 是独立插图；原生 Mikansei App 图标与版本均未替换。

旧 Android 0.4.2 (8) 与 Windows 0.4.3 (9) 下载继续保留在历史链接中，不是本版安装包。

## 验证

- Flutter 全套 107 项、全库分析、domain 34 项、Swift → Dart → Swift 备份往返和桌面设置导航专测通过。桌面专测日志：`/private/tmp/Mikanseta-desktop-navigation-final-test.log`。
- Windows CI [run 41305090339](https://github.com/BingyanStudio/Mikansei/actions/runs/41305090339) 在提交 `cfe17a1` 上通过。前两轮 Windows CI 失败由测试未适配设置页导航 locator 引起；测试修正后最终 run 通过。
- 所有发布资产的远端大小和摘要均与本地产物匹配。Android APK 为 64,007,120 bytes，27.1 秒构建完成，并核实与旧 0.4.2 包使用相同发布签名。日志：`/private/tmp/Mikanseta-release-0.7.0-android-published.log`。
- macOS universal App 为 59.2 MB；导出的 ZIP 为 24,998,133 bytes。`codesign --verify --deep --strict` 通过，但本版未公证。日志：`/private/tmp/Mikanseta-release-0.7.0-macos.log`。
- iOS unsigned Release 主 App + Widget，版本 `0.7.0 / 18`，28.6 MB，124.8 秒构建成功；构建包含浅色图标与公开客户端配置。本轮没有上传 TestFlight。日志：`/private/tmp/Mikanseta-release-0.7.0-ios-icons.log`。
- 8 张合成内存数据预览覆盖手机浅 / 深色、320 点宽大字、桌面、日程、编辑与笔记；中文可读且没有布局溢出。

构建、CI 安装检查和合成预览不代表个人 Android、macOS、Windows 或 iOS 设备上的逐项交互验收。本轮没有在个人设备上验证升级保留数据，也未更新 TestFlight。完整记录见 [Mikanseta 验证记录](../Mikanseta/VALIDATION.md) 与 [原生操作对应说明](MIKANSETA_PARITY.md)。

## 安装与数据保留

- **Android**：`applicationId` 为 `com.personal.mikanseta`，发布证书与旧版 0.4.2 (8) 相同，可按原安装方式直接覆盖，兼容覆盖会保留本机数据。不要先卸载；建议先导出 JSON 备份。若系统提示签名不匹配，先停止安装并保留旧应用。详见 [Android 安装说明](../Mikanseta/INSTALL_ANDROID.md)。
- **macOS**：下载并解压 ZIP，以 `Mikanseta.app` 替换旧应用。数据保存在应用支持目录。App 未公证；没有在用户设备上确认首次启动体验。不要用绕过 Gatekeeper 的方式启动。详见上方 Release 版本页。
- **Windows**：使用 Setup 覆盖更新，或完整解压 ZIP 后运行 `Mikanseta.exe`，并保留配套文件。归档保存在 AppData 应用支持目录，独立于安装目录；仍建议先导出 JSON 备份。CI 安装与启动检查通过，个人设备行为未逐项验收。详见 [Windows 安装说明](../Mikanseta/INSTALL_WINDOWS.md)。
- **iOS**：unsigned Release 不是可直接安装到普通设备的通用 IPA。本轮没有上传 TestFlight；需由用户自行签名部署，或待后续实际上传 TestFlight 后从 TestFlight 安装。
