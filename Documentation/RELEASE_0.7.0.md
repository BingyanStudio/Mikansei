# 0.7.0 (14) 发布准备记录

**记录日期：** 2026-10-31  
**原生 Mikansei 目标版本：** 0.7.0 (14)  
**Mikanseta Flutter 源码版本：** 0.6.0 (17)。

## 本轮范围

- 增加独立的番茄专注计时，主题必填，可选关联未完成任务；支持倒计时、不限时正计时、暂停、继续、结束和历史。
- 计时用时间戳恢复；专注数据写入独立的本机 `pomodoro.json`，不并入待办备份或清单云同步。
- Mikansei 与 Mikanseta 的 iOS 主屏幕只注册番茄专注小组件，按系统小、中、大网格尺寸适配。DDL 和 AlarmKit Live Activity 保留为独立功能。
- 桌面端提供独立浮动窗口，Android 使用启动器主屏小组件。小组件操作会打开 App，再校验会话编号后处理。
- “今日记录”按结束日期统计，正在进行的计时不计入；没有自动休息周期或专注闹钟。

平台行为与数据边界见[专注计时说明](POMODORO.md)。

## 验证与发布状态

- 原生 Mikansei iOS App + Widgets unsigned Release：**通过**。最后的 UI 快照会话保护修改后重新冻结构建，`BUILD SUCCEEDED`；App 与 Widget 版本均为 0.7.0 (14)。日志 `/private/tmp/Mikansei-Pomodoro-ios-build-frozen.log`，产物目录 `/private/tmp/Mikansei-Pomodoro-iOSDerivedData/Build/Products/Release-iphoneos/`。
- 原生 Mikansei Mac universal Release：**通过**，x86_64 + arm64，版本 0.7.0 (14)。日志 `/private/tmp/MikanseiMac-Pomodoro-Release-build-2.log`，xcresult `/private/tmp/MikanseiMac-Pomodoro-Release-2.xcresult`，产物 `/private/tmp/MikanseiMac-PomodoroUniversalDerived/Build/Products/Release/Mikansei.app`。
- Mikanseta Flutter iOS unsigned Release：**通过**；Widget 扩展已嵌入，App 与扩展版本均为 0.6.0 (17)。Flutter 未找到 `Release-Mikanseta` 专属构建配置，按提示使用通用 `Release` 配置完成构建。
- Mikanseta macOS universal Release：**通过**；产物包含 x86_64 与 arm64，版本为 0.6.0 (17)，为无 Team ID 的 ad-hoc 签名。
- macOS Xcode 构建出现 414 条指向旧工作区路径的 stale-file 警告；本次构建仍成功完成。
- 原生 iOS 构建保留 `EntryStore` 的 `WidgetSnapshot` 捕获与 `NotificationManager` 字典捕获两条 Sendable 警告；未阻止构建。
- Mikanseta `dart analyze lib`：**通过**，`No issues found!`。Android debug APK 构建：**通过**，产物 `Mikanseta/build/app/outputs/flutter-apk/app-debug.apk`。
- 未添加或运行自动化测试；原生 iPhone / Mac 与 Mikanseta Apple / Android 设备操作、Widget 挂载 / 尺寸验收：**待完成**。Windows CI 计划 push 后运行，当前未验证。
- TestFlight 上传：**尚未上传**。
- Git tag：**尚未创建**。

构建日志：原生 iOS `/private/tmp/Mikansei-Pomodoro-ios-build-frozen.log`、原生 Mac `/private/tmp/MikanseiMac-Pomodoro-Release-build-2.log`、Flutter iOS `/tmp/mikanseta-ios-0.6.0-17-release.log`、Flutter macOS `/tmp/mikanseta-macos-0.6.0-17-release.log`。源码版本号只表示工程目标，不代表云端或 TestFlight 构建号。
