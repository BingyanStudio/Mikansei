# 验证记录

## Routine 待办 frontier 与跨格式完成身份 · 0.3.2 (6) · 2026-10-22

- **根因**：随待办轮询按 occurrence 逐次导入循环日历事件后，`TaskBoard.open` 将所有未来 occurrence 都当作独立开放项；Mac“常态”列表又直接读取原始 `store.entries`。同时 Swift `Entry` 的显式 CodingKeys 会丢弃 Flutter 的日历关联字段，跨格式保存后可能失去系列和原始 occurrence，造成再次导入时重复或把已完成 occurrence 重新露出来。
- **列表投影**：保留全部底层 occurrence、完成历史和用户修改，只在列表、今日、常态、设置计数与小组件入口建立 active frontier。每系列只显示当前最早尚未完成的一项；完成或撤销完成后按原数据重新投影，不伪造完成，也不按标题合并。
- **可靠系列关系**：本地 routine 仅沿 `previousOccurrenceID` 血缘归组；Apple 循环日历仅在同一 `calendarID + sourceTitle + eventID` 作用域内，以非空原始 occurrence 归组。不同日历、同名事项、独立事项和非循环单次日程保持分开。日历月 / 日视图仍显示原始 future occurrence。
- **共享身份**：新增可选 Codable `routineSeriesID` 与 `routineOccurrenceID`。旧 Android `androidCalendarLink` 在加载 / 导入时只补缺失身份，不删除或改写原事项；provider series 以原始 occurrence 参与完成去重和排序。provider / 循环日历不会再由本地 `nextOccurrence` 生成竞争后继；单次日历事件上手动设置的本地 routine 仍可生成。
- **大输入保护**：血缘归组使用迭代 root、路径压缩和 rank；重复完成 occurrence 按“系列族 + 原始 occurrence”抑制 stale open 副本，本地血缘按 `previousOccurrenceID + recurrenceDate` 区分同一代副本与合法后继。
- **原生构建与安装**：最终共享核心 `swift build --disable-sandbox` 通过。主代理使用工程已配置的 Team 完成 iPhone Debug 签名构建，主 App 与 Widget 均安装成功；`devicectl` 启动成功，已安装 App 查询确认 `com.personal.mikansei` 为 `0.3.2 (6)`。Mac 通用安装包构建与安装完成，产物为 `/Users/xuyilin/Desktop/Projects/Mikansei-macOS.app`，版本为 `0.3.2 (6)`。签名主 App 与 Widget 的 `codesign --verify --deep --strict` 均通过；首次检查在沙箱内因 `CSSMERR_TP_NOT_TRUSTED` 无法建立信任链，宿主环境重试通过。Mac App 关闭后重新打开成功；首次重开与退出重叠返回 `-600`，重试后正常打开。
- **测试状态**：修复前基线为 91 项执行、90 通过，唯一失败是沙箱内 `NSFileCoordinator` 无法创建临时同步目录。临时新增的 frontier 回归用例曾取得 10 个断言失败并复现问题，随后按要求移除，测试文件无差异。当前没有最终功能测试或 UI 测试通过记录；本轮没有使用真实个人日历验证导入、列表 frontier、完成推进或撤销完成等交互，因此不将构建、安装和启动成功表述为设备端功能验收。
- **已知限制**：日历导入窗口仍是今天起 30 天。若下一次 occurrence 位于窗口之外且尚未作为 Entry 导入，frontier 不能凭空生成它，需要后续窗口扩展或再次导入后才会出现。

2026-10-13

## 完成圈划线修复与待办页顶部控件固定 · 0.3.1 (5) · 2026-10-18

- **问题复现**：把用户真实同步数据投影到 "Mikansei QA" 模拟器后，部分已完成事项只显示实心勾选圈、标题没有删除线；对比全部条目发现规律——**正文非空**的已完成事项划线丢失，正文为空的正常。仅清空正文（不改代码、同一二进制）后划线立即恢复，确认为 iOS 26 SwiftUI 的渲染问题：标题与正文处于同一个 Button 内时，标题的 `.strikethrough` 被丢弃。
- **尝试与结论**：显式删除线颜色、调整修饰符顺序、`AttributedString` 删除线属性均被同一路径丢弃；`GeometryReader` / `Canvas` overlay 在该布局中拿不到尺寸；细于约 2.5pt 的 overlay 线会被折叠为 0 高度。最终改为条件 overlay 的 3pt `UIColor.label` 矩形线（`StruckTitle.overlay`），模拟器截图确认：正文非空的已完成事项（微积分练习册、乐队演唱信息提交、询问表演键盘配置）全部恢复划线，未完成及无正文事项表现不变。
- **动效统一**：待办页的类型切换条与状态/分类筛选行从 `ScrollView` 内移到滚动区外的固定头部，与日程页一致；滑动两次后的截图确认列表内容滚动时顶部控件保持在原位。自动化 `isHittable` 断言在滑动动画期间不稳定，因此以截图为准，未计为通过。
- **回归**：`swift test` **91 项核心测试全部通过**；iPhone UI 用例 `testFolderSyncSettingsAndVersionAreVisible`（版本已更新为 0.3.1 (5)）与 `testCreateHomeworkAndCompleteItsChecklist` 均通过。
- **版本**：主 App 与小组件扩展均由 0.3.0 (4) 升至 **0.3.1 (5)**。
- **真机安装**：本轮结束时 iPhone 未连接，`Scripts/install_iphone.py` 报告未找到设备；安装待手机连接后执行。模拟器验证覆盖视觉与交互，真机最终确认仍待完成。

## iCloud Drive 同步、原生 macOS 与角色图标 · 0.3.0 (4)

- 沿用免费 Personal Team；用户在两端各选择一次同一个 iCloud Drive 文件夹。共享事项、笔记、Checklist、完成状态、计时、课表和删除标记；来源日历选择与权限保持本机设置。文件交换使用安全作用域授权、NSFileCoordinator、每设备副本和原子写入；保存成功、前台恢复及前台 30 秒轮询合并。
- **91 项核心测试通过，0 失败**，其中 18 项同步测试覆盖独立离线编辑、同事项冲突收敛、完成 / 步骤状态、删除与重启、旧备份兼容、错误格式 / 时钟防护、真实本地文件夹两设备往返、损坏远端暂停上传、日历排除记录、跨设备日历编号、导入与常态去重、专注冲突。实际文件夹测试使用临时本机目录；不等同于真实 Apple ID 的云端传输验证。
- **iPhone 设置 UI 用例通过**：跨设备同步入口可点击，版本实际显示 0.3.0 (4)，使用独立测试数据，未选择个人 iCloud 文件夹。arm64 签名构建与主 App / Widget 扩展严格签名检查通过；Team / Bundle Identifier 未变。覆盖安装至 XYLiPhone 后，手机锁定先拒绝启动；用户解锁后已于 20:03 成功启动 0.3.0，原数据目录保留。
- **Mac 原生 UI 用例通过**：⌘N 新建、输入、⌘S 保存、详情完成 / 重新打开、完成后只有一行、设置按钮及同步入口。截图查看确认侧栏、列表、详情三列与划线显示。当前 Mac 输入法下 XCTest 英文 `typeText` 会出现分词空格，最终自动化输入使用数字标题；不是据此宣称所有输入法或快捷键均已验证。
- Mac Release 同时编译 **x86_64 / arm64**，macOS 14+，本地签名严格校验通过；已打包 `Mikansei-macOS.app` 和 `Mikansei-macOS-0.3.0.zip` 并在本机打开。提醒使用原生通知，保留共享事项的 iPhone AlarmKit 配置；点击提醒路由、真实通知授权、真实日历授权和课表通知需日常使用验证。
- 图标使用批准的第二版平面绿色角色原稿（SHA256 `16f2a433ec81a71cff9912e8998c0a405e90b17dfa08de0c08991480c9880dd5`），已导出 iPhone / iPad 及 Mac ICNS。14 张手机安装包图标经 Apple PNG 优化还原后，逐像素与导出图一致；原稿留存且导出可重现。看板娘立绘仍未实装。
- 设置页、iPhone App、扩展及 Mac 安装包均为 **0.3.0 (4)**。核心、两端工程构建、最终针对性 UI 用例通过；不是整套历史 UI 测试全部通过的声明。真实 iCloud 上传 / 下载、跨账号切换、书签重授权和两端实际同时操作，还需用户选择同一文件夹后验证；不读取个人 Apple ID 密码或自动选择个人文件夹。

## 角色图标 · 0.2.1 (3)

- 第二版绿色角色图标首次于 18:55 随 0.2.1 安装并启动；本次 0.3.0 保留并扩展到 macOS。此中间版本没有单独提交，图标源码与资源随 0.3.0 一起提交，不补造历史快照。

## DDL 实时活动 · 0.2.0 (2)

- 新增独立 ActivityKit 实时活动，锁屏显示最重要事项、系统倒计时、两件其他今日未办及剩余数量，灵动岛提供展开 / 紧凑 / 最小布局。设置可开启、结束和重新显示；保存、完成、改期与前台恢复时更新，清单为空时结束，并合并并发更新、恢复已有活动、清理重复和旧日期活动。
- 今日筛选与排序使用不含备注 / 平台 / 原文的摘要，最多三件、标题截断；计时到零停止，日程计到开始时间。新日午夜设过期时间，系统 8 小时寿命仍适用；App 未运行时没有服务器刷新事项。
- **73 项核心测试通过，0 失败**：新 6 项覆盖今日 / 超时 / 无日期筛选、排除未来 / 已完成 / 笔记、重要级与 DDL 排序、完成后替换、日程开始计时、空清单、摘要大小与隐私、23 / 25 小时日长。
- iPhone arm64 签名构建通过，主 App 与扩展严格签名校验通过；保持 Team / Bundle Identifier。已于 2026-10-13 18:09 安装到 XYLiPhone 并自动启动，覆盖更新保留本地数据，两个安装包版本均为 0.2.0 (2)。
- **原生 ActivityKit UI 用例通过，0 失败**（iOS 26.5 / Mikansei QA）：合成数据启动显示 4 件，勾选后同一活动更新为 3 件，关闭开关后状态变为“未开启”。已目视确认原生灵动岛倒计时与设置版本；测试不读取个人日历。测试先后修正离屏状态行、无障碍容器类型、开关整行点击位置及进程沿用导致的演示数据未加载；最终显式终止后启动并先确认演示数据，完整通过。结果为 `/private/tmp/mikansei-deadline-ui-cleanlaunch.xcresult`。
- 真实 iPhone 锁屏布局、手动收起与 8 小时系统结束后的恢复仍需人工体验；真机安装与自动启动已验证，不将模拟器界面结果写成真机体验结果。
- 设置页版本改为读取 CFBundleShortVersionString / CFBundleVersion；App 与扩展版本均递增到 0.2.0 (2)。

## 修复：开始做后就地更新、去掉卡顿

- 「开始做 / 暂停」不再用 `withAnimation(.smooth)` 包住状态更新：给 `Text(timerInterval:)` 的插入套大弹簧动画时，卡片会停在旧画面（仍显示「开始做」、计时不动），要暂停一次才刷新。现在点击即时就地更新，计时文字随后每秒走动。
- 待办分组改成一条带稳定 id 的 `ForEach`（`section-*` / `entry-*`）：卡片在「已超时 / 正在做 / 待完成 / 今日已完成」之间是移动，而不是销毁重建，避免 LazyVStack 残留旧卡片；分组移动动画从 `.smooth` 弹簧改为 0.16s easeOut。
- 模拟器 UI 测试（Xcode 26.5 / iPhone 17 / iOS 26.5）：新增「开始做后就地更新」用例（点击后不再存在「开始做」卡片、只有一个 focus-clock、计时数字持续变化）通过；`testFocusTimerStartPauseAndResume`、`testRapidCompletionAndReopenDoesNotLoseState`、`testCreateHomeworkAndCompleteItsChecklist` 一并重跑通过。
- 与本轮无关的既有失败（stash 本轮改动后重跑同样失败，属此前从未在 iOS 上运行的用例自身问题）：`testCalendarAutoImportDeduplicatesAndPreservesCompletion`（选择来源后未出现导入事项）、`testScheduleDurationRoutineDatesAndReminderCanBeEdited`（找不到 `routine-rule`）。

## 真机安装：main 最新版本已装到 iPhone

- 在 Mac 用 Xcode 26.5 对 `main`（8dfc658）编译并签名 `Mikansei` 与内嵌 `MikanseiWidgets`，`BUILD SUCCEEDED`，`codesign --verify --strict` 通过；沿用原 Team `7JMRL8X34C`、自动签名与 Bundle Identifier `com.personal.mikansei`。
- 用安装助手安装到已连接的 iPhone 17（XYLiPhone，UDID `00008150-000D758A369BC01C`，开发者模式已开启），安装后自动启动成功；设备端查询为 Mikansei 0.1.0 (1)，App 与小组件进程均在运行。
- 未做：UI 测试、真实日历来源导入、锁屏闹钟响铃、小组件真实布局与读取手感仍需在手机上人工确认。

## 本次：日历来源、日程、常态与勾选性能

- 首次授权改为明确勾选日历来源；旧版默认导入的节假日、生日来源迁移时取消选择一次。保存苹果日历事件不会自动打开整个来源的导入。仅选中的查询来源可产生导入事项。
- 新增“日程”：开始时间 + 持续时间，自动结束，全天按日历日计算，默认使用开始时间闹钟。批量导入保留苹果日历的提醒，不默认额外开启 Mikansei 闹钟。
- 常态作为待办 / 日程的标签，支持每日、自定义间隔、每周多选星期、月度间隔（月底不漂移）、跨月不规律选日。完成后生成下一次并重置 Checklist / 计时；未来日期展示与提醒使用同一规则，重新打开旧发生事项不会重复投影已生成的后继事项。
- 月历日期与日时间轴空白处增加长按添加；时轴按位置对齐至 15 分钟，并限制在当天，支持夏令时日长。
- 勾选移除 180ms 人为等待与跨分组整卡片弹簧动画，改为即时状态和短动画；使用 LazyVStack，缓存单次筛选 / 排序，移除今日归组的平方级扫描。JSON 校验 / 原子写入在后台串行执行，小组件钥匙串写入移到后台并合并刷新，提醒规划在后台计算。写入期间使用系统后台任务；失败保留内存数据、显示重试，不假装已保存。
- **67 项 XCTest 核心测试通过，0 失败**，其中新增 19 项覆盖默认日程提醒、重复推进与状态重置、月底 / 多月、周常多选、不规律日期、提前提醒与独立 DDL / 执行时段、夏令时与跨午夜、旧数据、来源选择迁移、清理保护、40 次连续保存顺序与无效写入后的恢复。测试使用官方 Swift 6.2.3 Linux 工具链；下载包已通过官方签名验证。
- App、Shared、Widgets 和 UITests 通过 Swift 前端语法解析；`git diff --check` 通过。新增 3 项 UI 用例，并更新合成日历同步用例为先明确勾选来源。
- **在 Linux 上未运行 iOS 编译、签名构建、UI 测试、截图或真机性能测量**（缺少 Xcode / Apple SDK）；其后已在 Mac 补跑 iOS 签名构建与真机安装，见上。下方旧版构建和模拟器记录不代表本轮改动的界面行为已通过验证。工程文件、Team、Bundle Identifier 和共享签名组未修改。

在 Mac / iPhone 上仍需执行：

1. Xcode 构建 Mikansei 与小组件，并运行 UI 测试（长按月历 / 时轴、日程持续时间、Routine 跨月选日、快速勾选 / 重开、来源选择与同步去重）。
2. 真机选择真实 iCloud / 订阅来源，确认节假日不再默认导入；清理只移除未修改的旧导入，完成记录和个人数据保留。
3. 在大量事项下连续勾选，核对流畅度、完成分组与重启后的保存状态；锁屏 / 后台期间写入失败应显示重试。
4. iOS 26 验证闹钟授权、按开始时间提醒和全天持续时间；旧系统明确选择弹窗。检查 Mikansei 提醒与日历原提醒不会无意重复。

## 历史验证记录（2026-10-12）

## 上一版：可切换月历与日时间轴

- 日程页可选今日聚焦、列表或日历；日历支持月历、按小时的日视图，模式和已完成显示偏好使用 AppStorage 保存。
- 月历支持选日、前后月份及回到今天，日期标记区分实际执行时段和 DDL；全天 / DDL 单独列出，执行时段的重叠按列布局。事件点击打开同一个事项，日期和空白小时格可预填新事项。
- **48 项核心测试通过，0 失败**。新增 6 项涵盖闰年和月边界、跨午夜 / 全天排他结束、DDL 不占据时段、完成过滤、重叠和相邻事件、短时段点击范围、23 / 25 小时的夏令时切换日期。
- 初版模拟器交互测试通过：翻月、回到今天、月历 / 日视图切换、事件点击编辑、重启保留视图。截图检查发现时间轴初始停在凌晨，已改用实际纵向行布局定位；同时改为紧凑日历页头，补充“事件已可点击”的自动定位断言后重新验收通过。最终结果：`/private/tmp/mikansei-calendar-view-ui-final.xcresult`。已目视检查最终月历和日时间轴截图，09:00–11:00 重叠事件并排显示且初始定位到 08:00。
- 测试只使用 App 内合成事件，不读取或改写个人日历。iPhone arm64 签名构建通过，App 与小组件均通过严格签名校验；现有免费 Personal Team 与 Bundle Identifier 保留。真机触摸手感仍需安装后确认。

## 上一版：清单 / 日历分工与提醒方式

- DDL 与执行时段分别持久化；只有显式操作并在 EventKitUI 编辑页保存，才写入日历。普通保存、勾选和清单删除不删除日历事件。来源改期保留 Checklist、计时、完成与个人 DDL。
- 使用 iOS 26 AlarmKit；旧系统通过 availability 判断保留通知支持。新增闹钟用途声明、Live Activity 与原创 PCM 铃声资源。停铃不标为完成，稍后提醒为 5 / 10 / 15 分钟。
- 原免费 Personal Team 的 iPhone 编译与签名构建通过。尚未进行真实 iPhone 锁屏响铃、静音 / 专注模式、AlarmKit 授权与系统日历回写测试；自动化 UI 使用合成日历和禁用实际提醒调度，避免访问个人数据。
- **42 项核心测试通过，0 失败**：覆盖提醒模式 / 铃声 / 周期传递、正在响铃或稍后提醒的保留与取消、DDL 与时段分离、旧导入迁移、原日历调整后的状态保留以及新建事件外部 ID 到达后的去重。
- **5 项模拟器 UI 用例通过**（首轮 4 项通过，铃声用例改为验证选中按钮后补跑通过）：铃声选择与保存、日历合成导入去重 / 完成保留、作业与 Checklist、计时起停恢复、清单 / 笔记截图。首轮只因在导航行中查找单独“清脆”静态文本失败，实际选中和保存可见。测试结果：`/private/tmp/mikansei-reminder-calendar-ui.xcresult`、`/private/tmp/mikansei-reminder-ui-retest.xcresult`。
- 已目视检查深色铃声与提醒设置截图，并提高铃声行文字对比度。3 个铃声已确认包含在签名 App 中，均为 4 秒、单声道、16-bit PCM WAV。AlarmKit 在二进制中弱链接，避免旧 iOS 启动时要求存在该框架。主 App 与小组件严格签名校验通过，共享 Keychain 与原 Team 配置保留。

## 上一版：系统日历自动导入

- **35 项核心测试通过，0 失败**。新增 9 项验证重复读取不新增或改写、改期与独立重复发生、跨日历副本与账号重同步标识、保留手动编辑 / 完成 / Checklist / 计时、删除排除、读取窗口边界 / 未选日历、全天排他结束时间、导入方式切换、取消来源、备份设置与旧备份兼容。
- 通过 EventKit 的 iOS 17 完整读取授权 API 获取事件；主 App 已增加 `NSCalendarsFullAccessUsageDescription`。未调用日历保存或删除 API。
- App 与小组件 iPhone arm64 签名编译成功，沿用已有 Personal Team、Bundle Identifier 与共享组。
- **合成事件 UI 用例已通过**：启动自动导入、重复同步不新增与完成状态保留。首轮用例返回时误在子页面寻找“完成”，修正导航返回后补跑成功；真实 EventKit 授权、iCloud / 订阅账号、全天与重复事件适配仍需在 iPhone 上验证。不会在 UI 测试中读取个人日历。
- 日历同步设置、来源关联及删除排除记录纳入同一份原子 JSON 持久化与备份。

## 本次：清单完成保留、小组件、计时与文字对比度

- **26 项核心测试通过，0 失败**。新增测试覆盖当天完成保留与跨午夜归入历史、重新打开、优先级 / 截止时间排序、超时分组优先、旧完成记录、摘要不含私有详情、小组件 URL 路由，以及计时暂停 / 恢复 / 完成 / routine 清零、只运行一个计时、重复小组件操作、备份持久化与旧数据默认值。
- `Mikansei` 与 `MikanseiWidgets` 均通过 iPhone arm64 编译；扩展已嵌入 App 并通过 Xcode 校验。
- **免费 Personal Team 签名编译成功**，未启用 App Groups。使用现有 Team 和 Bundle Identifier；新扩展继承同一 Team。
- `codesign --verify --strict` 已验证两个签名产物；两个二进制的钥匙串访问组与各自 Info.plist 中展开后的共享组一致。
- 工程生成器保留 Xcode 中现有的 buildSettings 和项目签名属性；重建后逐字段对照，既有配置未被修改。
- 完成 UI 添加划线反馈与弹簧位移动画，并尊重“减弱动态效果”；可点击文字提高对比度，类型和视图切换采用实色选中态。
- iOS 26.5 / iPhone 17 的独立 Mikansei QA 模拟器上，**三项 UI 测试均已通过**：录入作业与 Checklist、完成项留在今日清单且不提前进入历史；示例待办与笔记；计时持续增长、暂停保持、恢复继续。首轮历史筛选测试的旧文字定位失败，改用明确的 accessibilityIdentifier 后补跑该项通过，其余两项首轮通过。
- 已检查浅色和深色清单截图：可点击类型选项及未完成步骤为清晰文字，选中类型有实色底，深色模式强调色提高亮度。**小组件真实读取、各尺寸布局与点击、动画观感和午夜显示仍需 iPhone 确认**。本次未自动安装到手机。

下面保留先前验证记录，前置条件和测试数以本节为准。

项目改名为 Mikansei 后，重新验证 `Mikansei` iPhone target 编译成功，`MikanseiCore` 的 17 项测试全部通过；Git 仓库与 `main` 分支保留。

双击安装助手：Shell 与 Python 语法检查通过；`--check` 实测发现工程尚未设置 `DEVELOPMENT_TEAM`，正确停止且未进行签名或手机安装。使用的 `devicectl` 安装、启动参数已对照本机 Xcode 的 CLI 帮助；完整真机流程仍待验证。

- 使用 Xcode 26.5、iPhoneOS 26.5 SDK 编译 arm64 iOS 17+ target，未启用代码签名。
- 完整 SwiftUI、UIKit、UserNotifications 源码通过 iPhone SDK 类型检查。
- **17 项核心测试通过，0 失败**；iPhone arm64 target 显示 **BUILD SUCCEEDED**。
- Foundation 核心测试覆盖跨天与逾期、完成与子步骤、提醒过滤和容量、周期推进、未完成 routine 后续提醒、课后登记日期范围、备份合并、旧档案迁移、损坏文件保护、CSV、单双周 ICS、EXDATE、UTC 转换、复杂规则拒绝和消息建议。
- 已提供两项 Xcode 界面测试脚本；由于此机没有 iOS 模拟器运行时，**尚未执行界面测试**，也没有进行真机通知与签名安装验证。

图标使用普通 PNG 和 Info.plist 图标声明，避免本机缺少模拟器运行时导致 Asset Catalog 编译失败；App 不依赖资源编译服务。

首版仍需在实际 iPhone 上验证文字布局、通知权限、通知点击、课后预填、routine、多次催办、备份文件选择器和后台 / 锁屏通知投递。HUSToday 实际 ICS 导出格式还没有样例，尚未做专用兼容验证。

## 0.3.3 (7)：笔记全页编辑（iPhone）与右栏内联编辑（Mac）（2026-10-24）

- **iPhone**：新增 `App/NoteEditorView.swift`，笔记以 `fullScreenCover` 全屏编辑（关闭/完成顶栏、大标题、正文直写、清单项增删勾选、删除笔记二次确认）；`RootView` 按 kind 分流，任务/日程/作业仍走原 sheet；笔记 tab 工具栏 “+” 修正为新建笔记（原为待办）。工程由 `Scripts/generate_project.py` 重新生成以纳入新文件，保留签名设置。
- **Mac**：`MacEntryDetail` 对笔记改为右栏直接编辑（`MacNoteDetail`）：大标题/分类/正文内联，⌘S 或切换选中自动提交；笔记不再弹 650×720 sheet；右键“编辑”定位到详情栏；⌘N 在笔记页直接创建“无标题笔记”并选中。
- 版本：主 App 与小组件 0.3.2 (6) → **0.3.3 (7)**（iOS 与 Mac 工程分别更新；顺带修正 UITests 版本断言遗留的 0.3.1 (5)）。

| 验证 | 实际结果 |
| --- | --- |
| 核心测试 | `swift test` **91/91 通过**。 |
| iPhone UI 测试 | 新增 `testNoteOpensFullScreenEditor`（demo 笔记打开全页、存在完成/关闭、无 sheet 取消）；连同 `testFolderSyncSettingsAndVersionAreVisible`（断言 0.3.3 (7)）与 `testCreateHomeworkAndCompleteItsChecklist` 三项全部通过。 |
| 构建与安装 | iOS Debug 模拟器构建通过；Mac `install_mac.py` 构建并安装 `Mikansei-macOS.app` **0.3.3 (7)**。 |
| iPhone 真机 | 设备未连接，待安装。 |

## 0.4.0 (8)：规划、拖动排序与番茄钟联动（2026-10-24）

与 Mikanseta 0.5.0 同轮（动态工作流子任务实现）：Entry 新增 sortOrder/plannedDays（Codable 往返有单测）；TaskBoard.order 先比 sortOrder、today 并入 plannedDays；通知计划为今天规划时段的任务在开始时刻发「到点了」弹窗提醒（openURL=mikansei://focus/<id>?action=start，修复过一次跨目标编译：AppRoute 引用改为内联字符串以兼容 Mikanseta macOS 共享编译）；FocusTimerWidget 锁屏在无运行计时时显示下一规划块倒计时（60 分钟窗口）；iPhone 新增 App/PlanningView.swift（日程涂色 + 小时拖拽；列表排序因 iOS 26 List+onMove 冻结滚动改用 LazyVStack+drag&drop）；今日聚焦/待办组内长按拖动排序（Mac 用 List+onMove）；正在做 EntryCard 整块变色。版本 0.3.3 (7) → 0.4.0 (8)（App+Widgets+Mac）。

验证：`swift test` 96/96（新增 5 项）；iOS Debug 模拟器构建、iOS UI 两例（新规划涂色用例 + 版本）与相关 6 例 UI 回归通过；Mac Debug 构建通过；原生 Mac 0.4.0 (8) 已安装。iPhone 真机安装待连接。Mac 规划 sheet 与拖动仅编译验证。

## 0.4.1 (9)：首装内置「使用说明」笔记与 Markdown 预览（2026-10-24）

MikanseiCore 新增 `Entry.builtInGuideNote(now:)`（BuiltInGuide.swift，Markdown 使用指南）与 `NoteMarkdown` 行级解析（#/##/-/段落 + AttributedString 行内加粗）；iOS `EntryStore` 与 Mac `MacWorkspaceStore` 在「档案文件不存在 && !testing」时播种该笔记并落盘；`NoteEditorView` 顶栏 eye/eye.slash 切换预览（预览态行级渲染，不丢未保存内容）；版本 0.4.0 (8) → **0.4.1 (9)**（两 pbxproj 6 处 + UITests 断言）。主对话统一两端标题/分类为「使用说明/帮助」。

验证：`swift test` **99/99**（新增 NoteGuideTests 3 项）；iOS Debug 模拟器构建与版本 UI 用例通过；Mac Debug 构建通过；模拟器卸载重装端到端确认播种（容器 entries.json 含使用说明笔记）；原生 Mac 0.4.1 (9) 已安装。iPhone 真机待连接；预览渲染未在真机实拍。
