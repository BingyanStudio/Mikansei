# Mikanseta · Flutter 测试版

**当前源码版本：0.5.0 (13)**。笔记为苹果备忘录式全页编辑；本轮新增「规划」（日程涂色 + 小时拖拽）、列表长按拖动排序、锁屏番茄钟倒计时与对比色重做（正在做整块变色）。最新已公开的 Windows 包仍为 **0.4.3 (9)**，提供安装程序与免安装 ZIP，支持本机存储、备份与共享文件夹同步，下载及功能范围见 [Windows 安装与打包](INSTALL_WINDOWS.md)。该 Windows 公开包已加入经授权的账号同步服务连接，真实 Windows 登录与跨设备同步仍待端到端验收。Mikansei 的独立 Flutter 迁移项目，主题改为牛皮浅棕，搭配深棕文字、棕色操作按钮和跟随系统的深色模式。清单操作放在首位，手机使用底部导航，电脑使用侧边导航与键盘快捷键。本轮对齐原生 Mikansei 的手机布局：大标题与胶囊添加按钮、胶囊搜索框、分段式筛选条、白卡 + 图标化元信息、悬浮胶囊底栏。此前已加入 Supabase 账户登录与同账号多设备同步，以及 macOS / iOS / Android 的共享文件夹同步（与原生 Mikansei 自动互通）。

本项目放在 Mikansei 仓库的 `Mikanseta/` 目录中，一起提交和推送。原版 Mikansei 0.3.0 的工程、安装标识、签名、绿色主题和数据目录继续保留。

## 已可用功能

- 一句话快速添加，待办 / 作业 / 日程 / 笔记四种类型，详细字段按需展开。
- 「已超时」优先显示；同栏目内按紧急 → 重要 → 普通，再按 DDL / 日程开始时间排序。无日期事项仍在清单里。
- 完成后划线并以动画移到今日已完成区，次日自动进入历史。重新打开事项会保留步骤记录；开启系统减弱动态效果时减少动画。
- Checklist、科目 / 分类、备注、提交平台、处理地点和预计用时。首页和各清单卡片直接显示前三个可勾选子事项、完成进度和划线；点击子事项文字也能勾选，更多步骤通过“查看全部”进入详情。修改步骤列表时保留未改名步骤的编号和勾选状态。
- 勾选子事项自动保存，不会自动完成整件事项；在已完成事项中取消某一步的勾选，会恢复整件事项为未完成。
- 普通事项只需 DDL；新建日程使用开始 / 结束时间或全天。月历可点选日期，长按日期直接添加当天日程。
- 每天、每三天、每周多选星期、每两周、每月、自定义间隔和指定日期循环。完成时产生下一条记录，保留原来的月末锚点并避免重复生成。
- 专注计时：开始另一件事项自动暂停上一件；暂停、继续和完成保留累计用时，重启后根据保存的时间恢复。
- 原子保存，串行写入，失败时提示重试；本地文件损坏时进入只读状态并保留原文件。
- Mikansei v1 JSON 备份合并导入和导出。保持事项编号，保留较新的记录和尚未迁移的原生字段，包括提醒设置、日历关联、日历选择与课表。
- 电脑快捷键：⌘ / Ctrl + N 添加；⌘ / Ctrl + F 搜索。原生文件选择与保存窗口用于备份。
- 设置里的版本号直接读取安装包，包含构建编号。
- 安卓系统日历：勾选来源，导入今天起 30 天的日程；可在打开或返回 App 时自动更新，首次不勾选节假日等任何来源。
- 安卓事项详情可查看系统事件、预填系统日历新增页，以及创建系统闹钟和倒计时；铃声、重复和振动由系统时钟设置。
- Supabase 账户登录（邮箱验证码）与同账号多设备同步：本机保存后约 2 秒上传，其他设备实时收到并合并；删除带墓碑标记，不会因旧副本复活；系统日历来源按设备设置。配置见 [Supabase 配置指南](Documentation/SUPABASE_SETUP.md)。
- 共享文件夹同步：macOS、iOS、Android 各选一次文件夹，之后自动与原生 Mikansei 及其它 Mikanseta 设备交换合并；协议与原生版 iCloud 文件夹同步一致（每设备一个 replica 文件、修订号、永久墓碑）。设置见 [共享文件夹同步说明](Documentation/LOCAL_SYNC_SETUP.md)。
- 手机布局对齐原生 Mikansei：大标题 + 胶囊添加按钮、无描边胶囊搜索框、分段式筛选条与日历视图切换、白卡圆角与图标化元信息、悬浮胶囊底栏；桌面布局与快捷键保持不变。
- 笔记采用苹果备忘录式全页编辑：大标题 + 正文直接可写、清单项行内增删勾选；未保存退出需确认，已有笔记可整页删除（iOS/Android/macOS/Windows 一致）。
- 规划：今日页「规划」入口分两种——日程规划在月历上涂色选「哪几天做」（Routine 视为自动规划），小时规划把今日待办长按拖入 24 小时时间轴定「今天哪个时段做」（任务类型不变，可同步系统日历）；今日/清单列表长按拖动调整顺序；iOS 锁屏番茄钟组件在无计时且 60 分钟内有规划块时显示「距开始」倒计时，规划开始时本地通知可一键开始专注。

## 迁移进度

本轮迁移源码已通过 Dart 静态检查与 74 项 Flutter 测试、macOS Release 构建与集成测试、Swift 原版备份往返、共享文件夹 replica 文件的原生 Swift 解码兼容测试，以及 Android Release 构建；APK 签名与版本元数据也已校验。Supabase 登录与跨设备同步、共享文件夹同步尚未在真实设备上完成端到端验证（需要在各端选择同一个文件夹）。Android 系统提醒、小组件、前台响铃、Apple 日历和实时活动尚未在真实设备上验证。Android 的系统日历编辑结果即时回流仍未实现。表中的「源码已接入」不代表相关系统服务已在设备上验收。详见 [验证记录](VALIDATION.md)。

| 能力 | 当前状态 |
| --- | --- |
| 清单、Checklist、完成 / 历史、排序、快速添加 | 已迁移并验证 |
| 日程起止时间、全天、月历、长按添加 | 已迁移基础操作并验证 |
| 日 / 周日历与拖动选时段 | 静态检查与 Widget 测试通过，含只读模式不创建日程的回归 |
| 循环规则、完成后产生下一次事项 | 已迁移并验证；月历尚未预展开未来循环实例 |
| 专注计时、本机保存、JSON 备份 | 已迁移并验证 |
| iOS、macOS 原生文件桥接 | 本机读写与版本接口通过集成测试；系统文档窗口已实现，未自动化操作 |
| Apple 日历来源选择、自动导入和反向录入 | 源码已接入，未验证 |
| 系统弹窗、AlarmKit 闹钟、铃声与持续催办 | 源码已接入，未验证 |
| 主屏幕 / 锁屏小组件、正在做与 DDL 实时活动 | 源码已接入，未验证 |
| 课表编辑、CSV / ICS、课后作业登记 | 源码已接入；CSV / ICS 解析有单元测试通过，界面与原生未验证 |
| 粘贴消息解析 | 源码已接入；单元测试通过 |
| Android 工程、原生文件桥接、系统日历与时钟 | 已生成发布签名通用 APK；Android 16 / x86_64 模拟器核心操作测试通过，尚未安卓真机验证 |
| Android 系统服务：本地提醒、小组件、前台响铃 | Release 编译通过；设备行为未验证 |
| Android 系统日历编辑结果即时回流 | 尚未实现；需后续完成原生异步结果与事项匹配 |
| iCloud Drive 同一 Apple ID 自动同步 | 已由共享文件夹同步覆盖：三端选择同一文件夹即可与原生版互通 |
| Supabase 账户登录与同账号多设备同步 | 0.3.0 新增：源码、单元与 Widget 测试通过；真实设备登录同步待验证，见 [配置指南](Documentation/SUPABASE_SETUP.md) |
| 共享文件夹同步（原生 Mikansei / 多设备） | 0.4.0 新增：协议移植、Apple 书签与 Android SAF 通道完成；单元测试与原生 Swift 解码兼容测试通过，设备端到端待验证 |

这些原生功能仍可在原版 Mikansei 中使用。测试版尚未代替原版作为唯一提醒工具。

## 在 Mac 上试用

当前工作区已有 Flutter 3.47.7 开发工具和构建产物。双击本目录的 **`打开Mac测试版.command`** 会构建、复制到工作区的 `Mikanseta-macOS.app` 并打开。数据保存在 App 的应用支持目录中，更新应用包不会清空数据。

本轮 macOS Release 构建通过并已安装到 `Projects/Mikanseta-macOS.app`（0.4.2 (8)，x86_64 + arm64 通用，含共享文件夹书签权限），启动成功；Mac 原生界面仍未逐项验证，见 [验证记录](VALIDATION.md)。

第一次试用没有示例事项。在原版 Mikansei 的设置导出 JSON，再在测试版的设置导入，即可比较同一批事项。

## 安装到安卓手机

已生成 **0.4.2 (8)** 发布签名通用 APK，最低 Android 7.0，包含 ARM64、32 位 ARM 与 x86_64。安装方式、构建与签名说明见 [安卓安装说明](INSTALL_ANDROID.md)。工作区交付文件位于 `../../Deliveries/Mikanseta/`，没有将安装包或私钥提交到 Git 历史。

本轮已重新构建并导出 **0.4.2 (8)** Release APK，60.5 MB（含 Supabase 连接值读取、共享文件夹同步与对齐原生 Mikansei 的手机布局），SHA-256 `2a0217153e20a605947a494798191abed62426f92535178f961d3223221048c5`。

双击 `生成安卓安装包.command` 可重新打包并按版本输出 APK 和 SHA-256 校验文件。此前 Android 模拟器已通过新建作业、首页子事项勾选、原生读写、重新读取、计时和完成状态的集成测试；本轮 Android 设备未连接，新加入的提醒和小组件仍待设备验证。

Android 联动的权限、入口与边界见 [安卓使用说明](INSTALL_ANDROID.md)。

## 安装到 iPhone

1. 在 Xcode 打开 **`ios/Mikanseta.xcworkspace`**，选择 `Mikanseta`，在 Signing & Capabilities 中选择自己的 Personal Team，保持自动签名。
2. 连接并解锁手机，确认信任这台 Mac。
3. 双击 **`安装到iPhone.command`**。脚本只安装 Mikanseta，保留原版 Mikansei。

沿用已有 Team；新 App 的签名需要 Xcode 账号与对应描述文件。2026-10-13 已完成 Release 自动签名并安装到 XYLiPhone，当时手机上的版本为 0.1.1 (2)，原版 Mikansei 0.3.0 (4) 同时保留。解锁后系统启动成功，并确认 Mikanseta 真机进程持续运行；手机界面操作尚未逐项实测。iPhone 模拟器已经构建并验证。

0.2.0 (4) 没有安装到 iPhone：当前工作区的 iOS 侧改动只是源码接入，尚未编译，也没有在设备上运行；Dart 侧静态检查与测试通过只覆盖 Dart 与 Widget 层。iPhone 上的实际版本以设备显示为准，见 [验证记录](VALIDATION.md)。

免费签名的有效期与可安装数量由 Apple 管理；安装失败时脚本显示实际原因，不会卸载其他 App。

Xcode 工程、运行方案和 App 目标均名为 `Mikanseta`。源码目录 `ios/Runner/` 保留 Flutter 模板的路径，供插件注册代码自动生成；这不会影响 App 名称。直接使用 Flutter 构建、运行或测试 iOS 时，加上 `--flavor Mikanseta` 选择该方案；一键安装脚本已包含这一参数。

## 数据边界

| 平台 | 安装标识 | 本地数据 |
| --- | --- | --- |
| iOS | `com.personal.mikanseta` | App 沙盒应用支持目录的 `Mikanseta/entries.json` |
| macOS | `com.personal.mikanseta.macOS` | App 沙盒应用支持目录的 `Mikanseta/entries.json` |
| Android | `com.personal.mikanseta` | App 私有目录的 `Mikanseta/entries.json` |

备份导入会复制并合并数据，两端的后续编辑不会自动共享。原版课表与 Apple 日历配置在备份中保留，不触发原版服务。Android 日历来源与关联按本机安装身份隔离，换手机或重装后需重新选择来源；安装身份不随 Android 系统备份恢复，以免复用另一部手机的日历编号。原设备的 `replica` 同步副本不会随备份复制或回传；原版导入时由原版重建本机同步记录，避免复用另一个设备的同步身份。本版不写入原版 iCloud 同步文件夹。

Mikanseta 登录 Supabase 账号后，本机保存的数据（含课表与完成状态，不含 Android 日历来源选择）整份加密传输到你自己项目的 `mikanseta_archives` 表，行级安全保证只有登录者本人可读写；数据在服务器端为明文，详见 [Supabase 配置指南](Documentation/SUPABASE_SETUP.md)。本机与账户的合并规则与备份导入一致：同编号保留较新版本，删除带墓碑标记。

开启共享文件夹同步后，Mikanseta 会在所选文件夹的 `Mikansei-sync/` 里写一个只属于本设备的 `replica-<设备UUID>.json`，并读取该目录下其它设备的文件；协议、修订号与删除墓碑与原生 Mikansei 相同。请使用个人云盘或 iCloud 的私有文件夹，不要选择公开共享目录。

原版日期使用 UTC ISO 8601 整秒字符串，测试版导出保持这一格式；连续编辑保证更新时间递增，避免备份合并时丢失同一秒内的改动。导出已与原版 `EntryArchive.decode` 实际往返验证，详见 [验证记录](VALIDATION.md)。

## 开发与验证

已验证版本为 Flutter **3.47.7** / Dart **3.13.5** / Xcode **26.5**。版本固定在 `.flutter-version`，依赖固定在 `pubspec.lock`。

本轮的实测结果：`./Scripts/flutter.sh analyze` 通过，`No issues found!`；`./Scripts/flutter.sh test` 74 项全部通过（0.3.0 新增 16 项；0.4.0 新增共享文件夹协议与设置页测试 14 项；0.4.2 布局重构复用现有用例全部通过，并在模拟器完成浅色 / 深色视觉验收）；洛杉矶时区下的 domain、cloud 与 local sync 测试通过；`./Scripts/verify-backup.sh` 原版往返通过；Mikanseta 生成的 replica 文件经原生 `WorkspaceSyncDocument.decode` 实际解码并重新编码通过；macOS Release 构建与集成测试通过；Android Release 构建通过并导出签名 APK。Android 构建曾因国内网络访问 Maven Central 被拒（403）与集成测试残留的 `GeneratedPluginRegistrant.java` 引用 dev 依赖失败，已分别通过阿里云镜像与构建前清理生成文件修复，详见 [验证记录](VALIDATION.md)。命令要以正常权限（非受限沙箱）运行：受限沙箱里 Dart 3.13.5 会在创建 isolate 前报 `runtime/vm/cpuinfo_macos.cc: 42: error: unreachable code`，elevated 主机环境下同样的命令正常。Android `apksigner` 需要把 `JAVA_HOME` 指向工作区 `.toolchains/jdk21`，之后校验通过。日志见 [验证记录](VALIDATION.md)。

`Scripts/flutter.sh` 优先使用 `FLUTTER_SDK` 指定的工具，或工作区 `.toolchains/flutter`，否则查找已安装的 Flutter。缓存存放于工作区 `.toolchains/pub-cache`。下载默认使用 [Flutter 文档列出的中国网络镜像](https://docs.flutter.dev/community/china)，可用 `FLUTTER_STORAGE_BASE_URL` 覆盖；不会修改全局设置。

```sh
./Scripts/flutter.sh pub get
./Scripts/flutter.sh analyze
./Scripts/flutter.sh test
TZ=America/Los_Angeles ./Scripts/flutter.sh test test/domain_test.dart
./Scripts/verify-backup.sh
./Scripts/flutter.sh test integration_test/app_test.dart -d macos
./Scripts/flutter.sh test integration_test/app_test.dart -d <模拟器编号> --flavor Mikanseta
./Scripts/flutter.sh build macos --release
./Scripts/flutter.sh build ios --simulator --flavor Mikanseta
# 配置 Android SDK 和发布签名后：
./Scripts/build-android.sh
```

账户同步的连接值放在 git 忽略的 `LocalInstall/supabase.env`；三个一键安装 / 打包脚本会自动通过 `--dart-define` 注入，手动构建时参考 `Scripts/dart-defines.sh`。未配置时应用照常构建运行，设置页显示"未配置"。

新机器可按 [Flutter 安装文档](https://docs.flutter.dev/install/manual) 安装本项目固定版本，再设置 `FLUTTER_SDK`。iPhone 测试需 iOS 15 或更新，Mac 构建目标为 macOS 12 或更新。Mac 发布包同时包含 x86_64 和 arm64，本轮运行验证使用 Intel Mac；Apple Silicon 运行尚未实测。

### 代码组织

- `lib/src/domain.dart`：事项、排序、循环、计时计算、备份验证和合并；纯 Dart，可单独验证。
- `lib/src/store.dart`：操作状态、串行保存、失败重试；通过可替换存储接口调用平台能力。
- `lib/src/cloud_sync.dart`：Supabase 账户登录、账户行拉取合并与实时上传；传输层可替换，便于测试注入。
- `lib/src/local_folder_sync.dart`：与原生 Mikansei 互通的文件夹同步协议（修订号、墓碑、采集/合并/投影）与自动交换调度；平台文件访问可替换。
- `lib/src/app.dart` / `editor.dart` / `theme.dart`：自适应界面、录入表单和牛皮浅棕主题。
- `lib/src/calendar_view.dart`：月历、周视图与日视图，长按拖动选时段。
- `lib/src/student_tools.dart`：课程模型、CSV / ICS 解析与粘贴消息解析。
- `lib/src/system_services.dart`：把提醒计划交给原生服务的桥接层。
- `native/Apple/NativeArchiveBridge.swift`：iOS 和 Mac 共用文件桥接；耗时读写在后台队列，iPhone 写入受后台任务保护。
- `native/Apple/AppleSystemServices.swift`、`native/Apple/Ported/`：Apple 日历、通知 / 闹钟调度、小组件摘要与实时活动数据。
- `lib/src/android_system.dart`：Android 来源选择、导入协调与系统应用入口。
- `android/.../LocalServices.kt`：Android 本地提醒、前台响铃、小组件与系统日历写入。
- `ios/Widgets/`：Mikanseta Widgets 扩展，含主屏幕 / 锁屏小组件与实时活动。
- `android/.../MainActivity.kt`：私有原子文件、系统文档选择、版本信息、Calendar Provider 和系统日历 / 时钟 Intent。
- `test/`、`integration_test/`：数据规则、手机 / 电脑界面和真实原生存储测试。
- `Scripts/verify-backup.sh`：使用原版 Swift 核心生成备份，经 Dart 编辑，再交回原版解码器验证。
- `Scripts/configure-native-services.py`：把共享原生核心与独立命名的 Widget 扩展挂进 Xcode 工程，保留现有签名设置。

后续平台能力从桥接层接入；清单与交互代码继续共享。提醒、日历、WidgetKit / ActivityKit 扩展和同步协议将分别迁移，不把系统服务混入界面代码。
