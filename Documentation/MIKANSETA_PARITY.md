# Mikanseta 原生操作对应说明

Mikanseta 是 Mikansei 的 Flutter 版本，使用同一事项语义和 JSON 归档格式；它不是另一个产品或独立迁移项目。本轮发布版本为 Mikanseta `0.7.0+18`，原生 Mikansei 源码版本仍为 `0.7.0 (14)`。用户确认从 TestFlight 安装的原生 Mikansei 版本为 `0.7.0 (8)`；该安装版本与源码构建号分别记录。

Mikanseta 已在 [BingyanStudio/Mikansei 的 `mikanseta-v0.7.0` Release](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0) 公开预发布，tag 指向提交 `cfe17a1d1cb04fff7de86106f469362a338a966d`。版面按 Flutter 手机与桌面窗口重新适配；专属图标使用浅色调和眨眼笑脸。`MikansetaArtwork` 是独立的应用内插图，原生 Mikansei App 图标未替换。

Xcode Cloud 对该提交有 `Mikansei | Internal TestFlight Build | Archive - iOS` 成功归档记录；该 check 单独不能证明归档就是用户确认安装的原生 TestFlight `0.7.0 (8)`。Mikanseta iOS `0.7.0 (18)` 目前只有 unsigned App + Widget 构建，尚未上传 TestFlight。两款 iOS App 的 bundle ID 和分发记录彼此独立，详见 [Mikanseta TestFlight 准备说明](TestFlight/MIKANSETA_READINESS.md)。

## 核心操作映射

| 原生 Mikansei 操作 | Mikanseta 对应操作 | 关键实现 |
| --- | --- | --- |
| 手机默认进入「待办」，主入口为待办、日程、笔记 | 手机默认待办；三项底部导航相同。桌面使用侧栏，设置、课表与专注作为辅助入口 | `App/RootView.swift`；`Mikanseta/lib/src/app.dart` |
| 「日程」包含今日聚焦、列表、日历，并可打开规划 | 日程页提供同名三视图与规划按钮；课表和新增日程放在辅助菜单 | `App/RootView.swift`、`App/CalendarScheduleView.swift`；`Mikanseta/lib/src/workspace_ui.dart`、`Mikanseta/lib/src/calendar_view.dart` |
| 今日聚焦按逾期、今天事项、无日期 / 过期未完成和当天完成项整理 | 使用相同分组；历史事项可按类型和分类筛选。规划中的条目不出现在聚焦页 | `Sources/MikanseiCore/Entry.swift` 的 `TaskBoard`；`Mikanseta/lib/src/domain.dart` 的 `TaskBoard`、`Mikanseta/lib/src/workspace_ui.dart` |
| 日程只有在实际执行时段覆盖某天时才属于当天 | 使用本地日期边界判断；例如前一日 23:30 至当日 00:30 的日程会出现在这两天的视图中 | `Sources/MikanseiCore/Entry.swift` 的 `scheduleOccurs(on:)`；`Mikanseta/lib/src/domain.dart` 的 `Entry.scheduleOccurs` |
| 从卡片直接编辑；完成、Checklist 和只读状态遵循事项语义 | 卡片点击进入编辑，任务完成和子项直接操作；只读恢复时保留阅读能力并禁写 | `App/Theme.swift` 的 `EntryCard`；`Mikanseta/lib/src/entry_widgets.dart`、`Mikanseta/lib/src/editor.dart` |
| 将未完成事项暂移出今日聚焦，并从规划区恢复 | 左滑可移入规划；规划标记写入事项归档，重启和备份往返后仍保留；规划页提供恢复操作 | `App/EntryStore.swift`；`Mikanseta/lib/src/store.dart`、`Mikanseta/lib/src/entry_widgets.dart`、`Mikanseta/lib/src/planning_page.dart` |
| 以日期或时段重新安排待办；事项类型继续是待办 | 保存新的规划日期或有效时段会清除暂缓标记；类型保持不变。新生成的循环事项重置暂缓标记 | `Sources/MikanseiCore/Entry.swift`、`App/EntryStore.swift`；`Mikanseta/lib/src/domain.dart`、`Mikanseta/lib/src/store.dart` |
| 事项卡片与进度按类型着色；日历 / 规划根据执行、DDL 与完成状态着色 | 卡片中的待办 / 日程为绿色、作业为靛蓝色、笔记为暖橙色；日历和规划中的执行时段统一绿色，DDL 使用暖色，完成项使用中性色。正在做的卡片以浅强调色突出 | `App/Theme.swift`、`App/CalendarScheduleView.swift`；`Mikanseta/lib/src/theme.dart`、`Mikanseta/lib/src/entry_widgets.dart`、`Mikanseta/lib/src/calendar_view.dart` |
| 快速创建待办、作业、日程和笔记，并按日期与类型显示字段 | 保留四类快速创建；日程入口默认创建日程，卡片与笔记继续使用各自编辑流程 | `App/RootView.swift`、`App/EntryEditor.swift`；`Mikanseta/lib/src/app.dart`、`Mikanseta/lib/src/editor.dart`、`Mikanseta/lib/src/note_editor_page.dart` |

## 数据兼容

`isInPlanning` 是新增的可选布尔字段。旧归档没有此字段时按 `false` 处理；如果字段存在但不是布尔值，归档验证会拒绝它。笔记不能保留规划标记。保存和备份合并保留其他未知事项字段。日历清理会保留已规划或有规划日期的导入项。循环事项生成新 occurrence 时会清除旧 occurrence 的 `isInPlanning` 状态。

本轮不更改云同步字段合并策略。`isInPlanning` 跟随完整事项归档进入现有同步路径；同步字段的冲突处理仍由既有归档合并规则决定。

## 平台能力边界

- **冰岩课表接口：** 原生版提供冰岩只读 API 导入。Flutter 版目前提供课表编辑与 ICS / CSV 导入，没有移植这项 API 连接；不要在 Flutter 版中要求输入或复制原生 API Key。相关代码见 `App/BingyanScheduleImport.swift`、`Mikanseta/lib/src/student_tools.dart`。
- **系统日历：** Flutter 版在 iOS / macOS 通过 Apple EventKit、在 Android 通过 Calendar Provider 读取已选日历并处理关联事件；相应桥接见 `Mikanseta/native/Apple/AppleSystemServices.swift`、`Mikanseta/android/app/src/main/kotlin/com/personal/mikanseta/MainActivity.kt`。Android 的编辑操作交给外部日历应用，返回后的同步依赖再次导入，不能保证像 iOS/macOS 原生编辑器那样即时回传结果。Windows 目前没有对应的系统日历读写服务。
- **桌面操作：** 桌面侧栏和布局随窗口宽度调整，保留添加、搜索快捷键；它不模拟手机底部导航。
- **其他系统服务：** 提醒、原生小组件、前台响铃和专有实时活动由各平台实现决定；其存在或编译状态不代表本轮核心流程验收通过。

## 验证状态

Flutter 全套 107 项、全库分析、34 项 domain 单测、Swift → Dart → Swift 备份往返及桌面设置导航专测通过。Windows CI [run `41305090339`](https://github.com/BingyanStudio/Mikansei/actions/runs/41305090339) 在提交 `cfe17a1` 上成功；此前 run `41303398033` 与下一轮因测试 locator 未适配设置导航而失败，修正后通过。Android、macOS 与 Windows 安装资产、`SHA256SUMS.txt` 和 `build-info.json` 已发布，远端大小和摘要与本地产物匹配。macOS universal ZIP 通过 `codesign --verify --deep --strict`，但未公证；Mikanseta iOS unsigned App + Widget 构建通过，尚未上传 Mikanseta 的 TestFlight。八张合成预览已目视检查；这不代表个人设备上的交互或升级验证。完整日志与限制见 [Mikanseta 验证记录](../Mikanseta/VALIDATION.md)、[0.7.0 发布说明](RELEASE_MIKANSETA_0.7.0.md) 和 [TestFlight 准备说明](TestFlight/MIKANSETA_READINESS.md)。
