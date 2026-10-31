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

- 原生 Mikansei iOS App + Widgets unsigned Release：**通过**。最新时钟界面源码构建 `BUILD SUCCEEDED`；App 与 Widget 版本均为 0.7.0 (14)。日志 `/private/tmp/Mikansei-Pomodoro-Clock-iOS-final-build.log`，xcresult `/private/tmp/Mikansei-Pomodoro-Clock-iOS-final.xcresult`。
- 原生 Mikansei Mac universal Release：**通过**，x86_64 + arm64，版本 0.7.0 (14)。最新界面构建日志 `/private/tmp/Mikansei-Pomodoro-Clock-Mac-build.log`。
- Mac 隔离手工预览使用合成主题：约 266×248 小窗中大号居中时钟和竖排暂停 / 继续、结束并保存按钮无重叠；空主题时开始不可用。开始后点击暂停，等待后按钮显示“继续”，再结束并保存；本次未实际点击“继续”。共生成 1 条 98.698852 秒的合成记录，活动计时为空。此结果只覆盖该窗口尺寸，不代表所有桌面尺寸或真实 Widget 主机验收。
- Mikanseta Flutter `dart analyze lib`：**通过**，`No issues found!`。最新时钟界面的 macOS universal Release：**通过**，版本 0.6.0 (17)，产物包含 x86_64 与 arm64，输出为无 Team ID 的 ad-hoc 签名。
- Mikanseta 最新界面的 iOS unsigned Release：**通过**，版本 0.6.0 (17)，产物 `Mikanseta/build/ios/iphoneos/Mikanseta.app`（26.9 MB）。Flutter 使用通用 `Release` 配置；此前构建日志 `/tmp/mikanseta-ios-0.6.0-17-release.log`。
- Mikanseta 最新界面的 Android debug APK：**通过**，产物 `Mikanseta/build/app/outputs/flutter-apk/app-debug.apk`。
- Mikanseta macOS 构建曾记录 414 条指向旧工作区路径的 stale-file 警告；未阻止此前构建。
- Windows 基线 CI：提交 `eeefa77` 的 [run 41203404752](https://github.com/KikuchiHeinrich/Mikansei/actions/runs/41203404752) 成功，包含分析、既有测试、集成、Windows x64 构建 / 打包、安装器启动与产物生成。该 CI 不包含最新时钟界面修改；最新提交的 Windows CI **待推送后运行**。
- 未新增测试；本机未运行自动化测试。基线 Windows CI 执行了既有测试与集成检查；未完成原生 iPhone / Mikanseta Apple / Android 真机操作、iOS WidgetKit 实际挂载或各尺寸、辅助文字大小验收。Mac 手工预览不代表所有窗口尺寸已验收。
- TestFlight 上传：**尚未上传**。
- Git tag：**尚未创建**。

`dart analyze lib` 输出 `No issues found!`；Flutter 最新 iOS / macOS / Android 构建通过，无单独保存的本轮 Flutter 构建日志。源码版本号只表示工程目标，不代表云端或 TestFlight 构建号。
