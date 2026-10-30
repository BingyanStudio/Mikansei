# Mikansei 0.6.0（12）发布记录

记录日期：2026-10-30

## 发布状态

`0.6.0 (12)` 是当前源码发布目标。iOS 和 Mac 工程已重新生成，两端 Release 无签名构建成功；未运行测试，也没有完成 iPhone / Mac 设备交互验收。`experimental/sync` 已推送到 `0c4f9575239c56582c2c01755aafb2ec54202a90`，annotated tag `v0.6.0` 已推送并指向该提交（tag object `6cfd87525d299bf5ae77d56303cb188ebf86aea7`）。

该 tag 已触发 Xcode Cloud `Mikansei | Internal TestFlight Build | Archive - iOS`。Check run `124121262794` 在 2026-10-30 晚间最近 7 次状态读取均为 `in_progress`、`conclusion=null`、无 annotations；[查看 Cloud build](https://appstoreconnect.apple.com/teams/69a6de96-390e-47e3-e053-5b8c7c11a4d1/apps/6827965680/ci/builds/7e2116be-b070-4f2e-88b6-755c2a6e6f37/action/0aa50a67-e1e2-4603-ac71-5834d49abe12)。因此目前还不能确认 Cloud 归档已完成、签名上传成功、TestFlight 已处理或用户可更新。源码工程 build number `12` 不等于实际 Cloud / TestFlight build number；后者尚未知。App Store Connect 的 TestFlight 界面读取超时，未能核实处理状态或外部测试可用性。

上次核实的 TestFlight 安装截图显示 `0.5.0 (Build 5)`。提交 `9bb9c94` 没有后续 Xcode Cloud 构建记录，因此这次 schedule focus 修正不在该已核实的构建中。不要把本地源码目标描述成已分发版本。

## 十项处理状态与优先顺序

以下按处理优先级排列，括号内保留用户原始编号。源码改动及编译通过只证明对应目标能构建，不代表设备交互已验证。

| 优先级 | 原始项 | 源码状态 | 验证边界 |
| --- | --- | --- | --- |
| 1 | #1 日程标题随拖动移动、UI 重叠 | 待办、日程、笔记三个主页面标题固定为 inline，避免大标题随滚动手势位移并与内容重叠；iOS 待办行另用独立右侧抓手隔开标题和横滑卡面。 | iOS Release 构建通过；未做真机手势验收。 |
| 2 | #3 苹果日历重复事件作为 routine | routine 计算、常态筛选、规划页和日历投影识别日历来源重复；不合成竞争副本，保留 occurrence 完成状态及 Checklist。旧导入项在下次同步时补 series 身份。 | 两端 Release 构建通过；未读个人日历或验证系统日历交互。 |
| 3 | #4 规划视图高亮今天 | 日期格显示今天边框和辅助标记，小时模式显示“今天”，选中日期仍有独立选中态。 | 两端 Release 构建通过；未做视觉设备验收。 |
| 4 | #5 schedule 只在实际时段覆盖当天时 focus | 今日筛选依据执行时段，并在当日来源重复候选间优先选择覆盖今天的实例；不改变 `TaskBoard.open` 全局排序语义。 | iOS / Mac Release 构建通过；未做运行时功能测试。修正不包含在上次核实的 0.5.0（Build 5）中。 |
| 5 | #6 抓手拿起 / 放下触感 | iOS 抓手使用 UIKit drag session 生命周期反馈；规划页复用该抓手，落点不再另发重复触感。 | iOS Release 构建通过；未在 iPhone 实机确认触感。 |
| 6 | #7 拖动边缘自动滚动、跨屏排序 | 抓手在可滚动列表视口边缘按帧间隔滚动，支持跨屏排序；规划页使用同一真实拖动抓手安排时间轴。 | iOS Release 构建通过；未做长列表真机操作验收。 |
| 7 | #8 Checklist 默认展开、可收起并直接新增 | 卡片默认展开未完成子项，支持收起、直接新增和勾选。 | iOS Release 构建通过；未做设备交互验收。 |
| 8 | #9 删除群消息粘贴 | 删除“从消息添加”视图入口及对应界面文件；不会自动读取 QQ 群消息。解析核心类型仍在源码中，但当前 UI 不再调用。 | iOS Release 构建通过；未做运行时 UI 检查。 |
| 9 | #2 冰岩课表 API 接入并转日程 | 支持用户个人课表只读 API 与手选每日 JSON 文件；预览后导入课程提醒记录和有有效明确时段的逐次日程。课程及日程按稳定内容 source 原子保存；缺失时间不从节次推断，重复导入不覆盖现有编辑，是快照而非自动同步。 | iOS Release 构建通过；未使用个人 API Key 或真实课表进行联机验收。CLI 已保存授权与 App API Key 相互独立。 |
| 10 | #10 Markdown 笔记 | iOS / Mac 编辑器提供 Markdown 预览；支持常见标题、列表、引用、代码块、分隔线和行内强调 / 链接。 | 两端 Release 构建通过；未做 UI 验收。不是完整 CommonMark：表格不解析，HTML 不作为网页渲染，图片语法显示替代文字，链接仅允许安全 HTTP(S)。 |

## 工程与版本

- `Scripts/generate_project.py` 与 `Scripts/generate_macos_project.py` 对新工程默认 `MARKETING_VERSION=0.6.0`、`CURRENT_PROJECT_VERSION=12`；对已有工程保留 `previous_objects` 的版本和签名设置。
- 本轮一次性把 `Mikansei.xcodeproj` 的 App / Widgets 与 `MikanseiMac.xcodeproj` 的 Mac App 更新到 0.6.0（12），随后运行两端生成器。iOS Team、主 App Bundle ID、Widgets Bundle ID 以及 Mac Bundle ID 保持现有值。
- 最终构建产物的版本字段核对为 iOS App `0.6.0 / 12`、Widgets `0.6.0 / 12`、Mac App `0.6.0 / 12`。

## 构建结果

- **iOS Release（App + Widgets）**：Xcode 26.5、iOS SDK 26.5，scheme `Mikansei`，`generic/platform=iOS`，`CODE_SIGNING_ALLOWED=NO`。包含拖动边缘帧率修正和无效 delegate 回调清理的最终构建 `BUILD SUCCEEDED`。日志：`/private/tmp/mikansei-0.6.0-12-ios-build-final3.log`；产物目录：`/private/tmp/mikansei-0.6.0-12-ios-derived/Build/Products/Release-iphoneos/`。保留既有 `EntryStore` WidgetSnapshot 和 `NotificationManager` 的 Swift 6 Sendable 警告。
- **Mac Release universal**：Xcode 26.5、macOS SDK 26.5，scheme `MikanseiMac`，`ARCHS=x86_64 arm64`、`ONLY_ACTIVE_ARCH=NO`、`CODE_SIGNING_ALLOWED=NO`。`BUILD SUCCEEDED`；`lipo -archs` 确认 `x86_64 arm64`。日志：`/private/tmp/mikansei-0.6.0-12-mac-build-final.log`；产物目录：`/private/tmp/mikansei-0.6.0-12-mac-derived/Build/Products/Release/`。AppIntents 元数据步骤提示该 App 未依赖 AppIntents framework。
- 未运行自动化测试、未签名、未安装、未进行云账号或 Apple 日历联机操作、未上传 TestFlight，也未进行 App Review 或 App Store 上架。

## TestFlight 更新路径

新版实际处理并出现在 TestFlight 后，在 iPhone 打开 **TestFlight → Mikansei → 更新**，更新既有 Mikansei 安装，不安装新的 Beta App。发布者应核对 TestFlight 显示的实际 build 后再通知用户。若用户想另留个人备份，可在更新前从“我的 → 数据与备份”自行导出 JSON；本记录不要求向外提供备份。

