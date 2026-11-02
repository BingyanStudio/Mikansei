# Changelog

## 原生 Mikansei 番茄专注锁屏实时活动 · 未发布 · 2026-11-02

新增原生番茄专注的锁屏 Live Activity 与 Dynamic Island，使用系统 timer 文本显示倒计时或正计时，并呈现主题、暂停 / 继续和结束并保存入口。恢复活动时复用当前 session；到期、收起及系统八小时活动期限均有明确状态，实时活动权限关闭时可前往系统设置，同时保留本机计时与历史。现有 DDL 实时活动保持独立。

源码 iOS App + Widget 在 iOS SDK 26.5 `generic/platform=iOS` 下完成无签名 Debug 构建；未做真机显示验收，未签名或归档、打 tag 或上传 TestFlight。当前安装的原生 Mikansei `0.7.0 (8)` 不含此未发布改动；版本字段未变。构建与验证边界见 [验证记录](../VALIDATION.md)。

## Mikanseta 0.7.0+18 — 核心操作对应，公开预发布

将 Mikanseta 明确为 Mikansei 的 Flutter 版本，并将手机主导航、日程视图、今日聚焦分组、卡片编辑、规划移入 / 恢复和日历语义色对齐原生操作。新增持久化规划标记；旧归档缺省为未规划，循环新事项重置规划状态。Flutter 主界面布局已适配手机和桌面；Mikanseta 图标采用浅色调和眨眼笑脸，应用内主图 `MikansetaArtwork` 是独立插图，原生 Mikansei 图标未替换。原生 `0.7.0 (14)` 版本不变。

Mikanseta `0.7.0+18` 已在 [BingyanStudio/Mikansei](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0) 作为公开预发布；tag 指向 `cfe17a1d1cb04fff7de86106f469362a338a966d`。Windows CI [41305090339](https://github.com/BingyanStudio/Mikansei/actions/runs/41305090339)、Flutter 107 项、全库分析、domain 34 项、备份往返、桌面设置导航专测通过。Android、macOS 和 Windows 四个安装资产，以及 SHA-256 和 `build-info.json` 已发布并与本地产物核对一致。macOS 包通过严格代码签名校验但未公证；Mikanseta iOS unsigned App + Widget 已构建，尚未上传 Mikanseta 的 TestFlight。设备交互与覆盖升级未逐项实测，详见 [Mikanseta 验证记录](../Mikanseta/VALIDATION.md)、[发布说明](RELEASE_MIKANSETA_0.7.0.md)、[TestFlight 准备说明](TestFlight/MIKANSETA_READINESS.md) 与 [操作对应说明](MIKANSETA_PARITY.md)。

## 0.7.0 (14) — 构建通过，待设备验收

新增独立的番茄专注计时：主题必填，可选关联未完成任务，支持倒计时和不限时正计时、暂停 / 继续 / 结束与历史记录。计时使用时间戳恢复，专注数据独立保存在本机 `pomodoro.json`，不进入待办备份或清单云同步。iOS 主屏幕只注册番茄专注小组件，适配系统小 / 中 / 大尺寸；DDL 与闹钟 Live Activity 保留为单独功能。计时数字作为主视觉居中显示，适配空间允许时暂停 / 继续在结束并保存上方。原生 Mikansei iOS App + Widgets 与 Mac universal Release 最新界面构建通过；Mac 隔离预览验证了约 266×248 小窗的显示与计时操作。Mikanseta `dart analyze lib` 无问题，最新界面的 iOS、macOS 与 Android debug 构建均通过。Windows CI 在时钟界面源码提交 `454ba5a` 上通过，包含分析、既有测试、集成、x64 构建 / 打包、安装器 Release 启动和产物上传。未新增测试；本机未运行自动化测试。真实设备与 Widget 宿主验收待完成。用户确认 TestFlight 中安装的原生 Mikansei 为 `0.7.0 (8)`；原生源码版本仍为 `0.7.0 (14)`。Xcode Cloud 对提交 `cfe17a1d1cb04fff7de86106f469362a338a966d` 的 `Mikansei | Internal TestFlight Build | Archive - iOS` check 为 `SUCCESS`，但现有记录不能单独证明该归档与已安装的 Build 8 一一对应。Mikanseta `0.7.0 (18)` iOS 仍只有 unsigned App + Widget 构建，未上传 TestFlight。Mikanseta macOS 产物为无 Team ID 的 ad-hoc 签名。详见 [0.7.0 发布准备记录](RELEASE_0.7.0.md)、[Mikanseta TestFlight 准备说明](TestFlight/MIKANSETA_READINESS.md) 和 [专注计时说明](POMODORO.md)。

## 0.6.1 (13) — 待验证

本版目标是修正待办卡片排序交互：恢复 0.5 的整卡宽度，长按卡片本体的拖动区域拿起并拖动，不增加独立抓手列；输入框保留文本编辑与选择。拖动时同组卡片自然让位并留下插入空位，不高亮目标卡或显示系统复制加号；放下后按空位排序，取消后不改顺序。子项勾选与左滑操作仍可用；保留真实拖动会话触感反馈与列表边缘自动滚动，并覆盖 60 / 120 Hz 屏幕表现。iOS App + Widgets 与 Mac universal 无签名 Release 构建已通过；未运行测试、进行设备验收或上传 TestFlight。`0.6.1 (13)` 是源码版本目标，不代表实际云端构建号，构建命令、警告及验证边界见 [发布记录](RELEASE_0.6.1.md)。

## 0.6.0 (12) — 尚未发布

当前源码目标已通过 iOS App + Widgets Release 和 macOS universal Release 无签名构建。没有运行自动化测试、没有做真机功能验收，也没有上传 TestFlight。实现状态、构建命令与验证边界见 [0.6.0 发布记录](RELEASE_0.6.0.md)。

本轮按以下顺序处理，顺序与用户给出的十项编号一致映射；“源码实现”不代表交互已在真机验收：

1. 三个主页面标题固定为 inline，避免大标题随滚动手势位移并与内容重叠；待办行使用独立抓手隔开标题、横滑操作与滚动手势，并由真实 UIKit 拖动会话触发反馈。
2. Apple 日历重复事件纳入常态和规划视图，不要求逐次手动规划；每次仍保留独立完成状态与 Checklist。
3. 规划日期网格突出今天，选中态仍与今天区分；小时模式显示“今天”。
4. 日程仅在实际执行区间覆盖当天时进入今日聚焦，并让当日 schedule 优先通过 routine frontier。
5. 拖动抓手在真实拖动开始、结束时提供触感反馈。
6. 抓手拖动接近可滚动列表上下缘时自动滚动，支持跨屏排序；规划页仍可用抓手拖入时间轴。
7. 首页卡片默认展开未完成 Checklist，可折叠、直接新增和逐项勾选。
8. 移除“从消息添加”的群消息粘贴界面入口；不读取 QQ 群消息。
9. 增加冰岩每日课表只读 API 和用户选取 JSON 导入，支持预览、明确时段过滤和稳定内容身份去重。
10. 笔记增加受限 Markdown 预览，编辑时保留原文。

## 其他变更

- 新工程默认版本与 build 设为 `0.6.0` / `12`；已有 Xcode 工程的手工版本与签名设置仍由原工程配置优先保留。当前 iOS App、Widgets 和 Mac 工程本次已一次性改为 `0.6.0 (12)`。
- TestFlight 文案注明该目标未上传；用户更新路径为 TestFlight 中打开现有 Mikansei 并点“更新”。
- 隐私说明补充冰岩 API Key 的本机钥匙串存储、CLI 授权独立、JSON 手动导入及导入内容仅在用户启用同步后进入同步范围。

