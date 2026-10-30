# Mikansei 0.6.1（13）发布准备记录

首次准备：2026-10-30；最终构建与更新：2026-10-31

## 发布状态

`0.6.1 (13)` 是源码版本目标。拖动交互源码稳定后已重新生成 iOS / Mac 工程；iOS App + Widgets 与 Mac universal 无签名 Release 构建均成功。当前尚未运行测试、进行 iPhone / Mac 真机拖动或触感验收，也未上传 0.6.1 TestFlight。

上一版 `0.6.0 (12)` 的 Xcode Cloud Internal TestFlight Build 已在提交 `0c4f9575239c56582c2c01755aafb2ec54202a90` 上成功完成：正式 check `124123904848` 于 2026-10-30 22:39:58（上海时间）完成，0 errors、3 个既有 warnings；该提交的 `Mikansei | Internal TestFlight Build` 状态为 `succeeded`。旧 check `124121262794` 仍显示 `in_progress`，是同一 action 留下的残留记录，不代表整体状态。TestFlight 界面尚未核实实际构建号、处理完成或可下载状态；不能从源码 `0.6.1 (13)` 推断云端或 TestFlight 构建号。此记录不表示 `0.6.0` 或 `0.6.1` 已可供用户安装。

## 本版交互目标

| 内容 | 目标 | 状态 |
| --- | --- | --- |
| 待办卡片排序 | 恢复 0.5 的整卡宽度。长按卡片本体的拖动区域拿起并拖动整张卡片，不增加独立抓手列；输入框仍可编辑与选择文本；保留真实拖动会话触感与列表边缘自动滚动。 | 源码完成、Release 编译通过；真机交互待验收。 |

本轮只记录上述拖动交互调整，不表示回滚其他功能，也不修改 `0.6.0` 的历史记录。

### 关键验收点

- 长按卡片本体的拖动区域时整张卡片拿起并显示完整拖动预览，没有独立抓手列；输入框长按仍支持文本编辑与选择，不启动拖动。
- 拖过其他卡片时，同组卡片自然让位并留下插入空位；没有目标卡高亮或系统复制加号。放下后按空位排序。
- 取消拖动或拖动期间组成员变化时，预览复位、原顺序不变，不写入排序变更。
- 子项勾选、输入框文本编辑 / 选择与卡片左滑仍能正常操作；触感只跟随真实拖动拿起 / 放下。
- 长列表靠近上下边缘时持续自动滚动；在 60 Hz 与 120 Hz 屏幕上分别验收。

以上验收点目前均待设备验证。

## 工程版本

- `Scripts/generate_project.py` 与 `Scripts/generate_macos_project.py` 的新工程默认目标为 `MARKETING_VERSION=0.6.1`、`CURRENT_PROJECT_VERSION=13`；已有工程的 `previous_objects` 构建设置仍优先覆盖默认值。
- `Mikansei.xcodeproj` 的 App / Widgets 和 `MikanseiMac.xcodeproj` 的 Mac App 版本字段已一次性改为 `0.6.1 (13)`。Team 与各 Bundle Identifier 保留原值。
- 两端工程均在拖动源码稳定后重新生成。最终 iOS App、Widget 和 Mac App 产物版本均核对为 `0.6.1 / 13`；iOS Team `6PVAPR495F` 与 Bundle ID `net.bingyan.KikuchiHeinrich.mikansei`、`net.bingyan.KikuchiHeinrich.mikansei.widgets`，以及 Mac Bundle ID `com.personal.mikansei.macOS` 均保留原值。Mac 原有手动 ad-hoc 签名配置未改；本轮 Release 构建使用无签名选项。

## 验证记录

- **iOS Release（App + Widgets）**：Xcode 26.5 / iOS SDK 26.5，scheme `Mikansei`，`generic/platform=iOS`，`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，最终增量构建 `BUILD SUCCEEDED`（2026-10-31）。日志：`/private/tmp/mikansei-0.6.1-13-ios-build-final.log`；产物目录：`/private/tmp/mikansei-0.6.1-13-ios-derived/Build/Products/Release-iphoneos/`。
- **Mac universal Release**：Xcode 26.5 / macOS SDK 26.5，scheme `MikanseiMac`，`generic/platform=macOS`，`ARCHS=x86_64 arm64`、`ONLY_ACTIVE_ARCH=NO`（未使用 `-arch`），`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`，`BUILD SUCCEEDED`。`lipo -archs` 确认为 `x86_64 arm64`。日志：`/private/tmp/mikansei-0.6.1-13-mac-build.log`；产物目录：`/private/tmp/mikansei-0.6.1-13-mac-derived/Build/Products/Release/`。
- 构建警告：iOS 保留 `EntryStore.swift:328` 对非 Sendable `WidgetSnapshot` 的 `@Sendable` 闭包捕获警告，以及 `NotificationManager.swift:182` 对非 Sendable `[AnyHashable: Any]` 的捕获警告；后者提示在 Swift 6 语言模式下会成为错误。Mac 的 AppIntents 元数据步骤提示未找到 `AppIntents.framework`，因此跳过提取。以上均未阻止构建。
- 自动化测试：按本轮要求未运行。
- iPhone / Mac 真机交互验收：未做；当前没有真机触感或拖动体验验证结果。
- TestFlight：未确认有本版上传或处理结果；不能从源码 build 13 推断实际云端构建号。

## 云端发布状态追踪

0.6.0 的上述成功状态来自提交的全部 check runs 和 commit status 汇总，不是对单一旧 check 的轮询结果。跟踪 0.6.1 云端发布时，需检查对应提交的 `check-runs?filter=all` 与 `commit/status`，并在 TestFlight 界面另行核实实际构建号和可用状态。
