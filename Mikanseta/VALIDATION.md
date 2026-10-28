# Mikanseta 验证记录

本文件按时间记录各版本的验证范围，从 0.1.0 (1) 到当前 0.2.0 (4)。

首轮记录日期：2026-10-13。测试宿主：Intel Mac，Xcode 26.5；Flutter 3.47.7、Dart 3.13.5。源工程包含 iOS、Android、macOS；原版 Mikansei 源码与安装标识未改动。

| 验证 | 实际结果 |
| --- | --- |
| `flutter analyze` | 通过，无问题 |
| 数据与 Flutter 界面测试 | 24 项通过 |
| 洛杉矶时区的数据测试 | 15 项通过，包含春季夏令时切换时保留本地 09:00；之后新增 4 项备份 / 日期测试在默认时区完整套件中通过 |
| Mac 真实应用集成测试 | 通过：原生读写、快速添加、计时、完成保留、重新读取与设置页 |
| iPhone 17 / iOS 26.5 模拟器集成测试 | 通过：原生读写、快速添加、计时、完成保留与重新读取 |
| Swift → Dart → Swift 原版备份往返 | 通过，原版解码器接受 Flutter 编辑和新增的事项，保留课表、日历来源与关联、闹钟和铃声字段 |
| Mac Release 构建 | 通过，约 45.7 MB；主程序与 Dart App.framework 都含 x86_64、arm64 |
| Mac 本地包签名完整性 | `codesign --verify --deep --strict` 通过；本机打开成功 |
| iOS 模拟器普通启动构建 | 通过 |
| iPhone Release 不带签名构建 | 通过，约 17.9 MB |
| iPhone 自动签名 / 真机安装 | 后续通过：Mikanseta Release 0.1.0 (1) 已安装到 XYLiPhone / iOS 26.7.1；手机应用列表验证原版 Mikansei 0.3.0 (4) 同时保留。解锁后启动成功，设备进程列表确认 Mikanseta 正在运行；真机界面操作尚未逐项实测 |
| Android 构建 / 真机 | 未验证：本机没有 Android SDK。已加入工程和文件桥接源码，不将其报告为已运行 |
| 安装脚本 | Python 语法与 shell 语法检查通过；iPhone `--check` 准确返回需要连接解锁设备 |
| 图标与配色 | 1024×1024 源图无透明通道；平台尺寸由同一源图导出。模拟器实际检查浅色 / 深色、事项列表、计时和文字对比度 |

## 测试覆盖

排序包括已超时置顶、重要级、时间、无日期与稳定编号；完成记录在当天保留，按当地午夜进入历史；完成暂停计时并勾选所有步骤，重新勾选会恢复父事项。

循环覆盖月末不漂移、每周多选、有限指定日期、超过五年的指定日期、跨夏令时本地时刻、重新完成不产生重复后继。计时覆盖互斥运行、暂停累加、重启恢复。

保存覆盖串行写入、防止旧快照覆盖新快照、失败重试、损坏文件只读、导出原始损坏文本、无效导入不修改现有数据、保留未知扩展字段和日历设置，以及整秒更新时间的合并规则。

界面测试覆盖手机快速添加、完成划线、320 点屏宽且系统文字放大 1.5 倍、电脑侧栏、月历长按添加全天日程，以及删除 Checklist 某行后保留其余步骤的编号和进度。

真实应用集成测试对独立测试版的原文件先读取、最后恢复，未使用原版 Mikansei 沙盒。系统文件选择 / 分享窗口已实现并通过编译，本轮没有自动化操作系统文件窗口；备份格式与原生本机读写分别得到验证。

## 主题预览

以下是模拟器实际运行截图，使用虚构事项，预览后已经恢复测试版原始文件。

[浅色](Documentation/kraft-light.png) · [深色](Documentation/kraft-dark.png)

## 尚未迁移

截至 0.1.2 (3)，测试版不包含系统通知、AlarmKit 闹钟、课后提醒、Apple 日历双向同步、小组件、实时活动和 iCloud Drive 自动同步。这些能力在当时的设置页明确标为后续接入；原版仍可使用。Mac 包包含双架构，但 Apple Silicon 运行尚未实测。

当前工作区的未提交源码已接入其中的大部分能力，但尚未验证，见文末 0.2.0 (4) 一节。iCloud Drive 自动同步仍未迁移。

## iOS 工程改名与真机安装（2026-10-13）

Xcode 工程、工作区、App 目标和共享运行方案统一改为 Mikanseta，安装脚本同时更新。源码目录保留 `ios/Runner/`，供 Flutter 自动生成插件注册文件；开发命令通过 `--flavor Mikanseta` 选择新方案，继续使用已有 Debug / Profile / Release 配置。Team `7JMRL8X34C` 和 App 安装标识 `net.bingyan.KikuchiHeinrich.mikanseta` 保留。此次只调整工程名称与安装流程，App 版本保持 0.1.0 (1)。

工程列表与构建设置验证通过；模拟器普通启动包、真机 Release 不签名包与自动签名构建均通过。已签名发布包通过 `codesign --verify --deep --strict`，安装脚本成功安装，设备应用列表确认真实版本。初次自动启动因手机锁定返回 Locked；用户解锁后再次启动成功，随后设备进程列表确认 Mikanseta 仍在运行。这里只验证真机启动与进程存活，不将其报告为真机界面逐项验证通过。

改名后的 iPhone 17 / iOS 26.5 模拟器集成测试再次通过：启动、原生读写、快速添加、计时、完成保留、重新读取和设置页。测试后恢复测试版原文件。工程 XML / plist 及 Python 安装脚本语法检查通过。

## 0.1.1 (2)：卡片内直接勾选子事项（2026-10-13）

共享事项卡片展示前三个可勾选步骤、进度条与完成数量，更多步骤通过“查看全部”进入详情；已完成步骤划线，点击步骤不会打开详情。复用原有串行保存逻辑；步骤勾选不自动完成父事项，取消已完成父事项中的某一步会恢复父事项。只读状态禁用勾选。iOS、macOS 和 Android 使用同一界面实现。

- 静态检查通过，无问题；完整数据与界面套件 26 项通过。
- 界面验证覆盖直接点击步骤文字、划线与进度、超过三步的详情入口、取消完成后返回待办、重新读取保存数据及只读保护。320 点屏宽、文字放大 1.5 倍时勾选和布局通过。
- iPhone 17 / iOS 26.5 模拟器集成测试通过：新建含 Checklist 的作业、首页勾选、原生写入和重新读取、计时、父事项完成及设置页。测试前读取原文件，结束后恢复；没有操作个人真机的清单数据。
- Android 本轮仍未构建或真机验证。
- iPhone Release 构建、自动签名和安装通过：设备应用列表确认为 Mikanseta 0.1.1 (2)，原版 Mikansei 0.3.0 (4) 同时保留。启动命令成功，随后设备进程列表确认 Mikanseta 正在运行；没有将模拟器交互测试报告为真机逐项操作验证。
- macOS Release 构建通过；安装脚本重封装并校验包签名，工作区 Mac App 已更新到 0.1.1 (2)。再次打开后确认应用进程运行，安装包签名复核通过。Mac 本轮未重复运行原生界面集成测试，卡片交互由共享界面测试及 iOS 原生集成测试覆盖。

## 安卓首个 APK（2026-10-14）

- Mikanseta 0.1.1 (2) Release 通用 APK 构建通过，包名 `net.bingyan.KikuchiHeinrich.mikanseta`。54.0 MB，包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`；最低 API 24，目标 API 36。
- 发布签名使用独立 RSA 3072 密钥，`apksigner verify --verbose --print-certs` 通过（APK v2）。私钥及 `android/key.properties` 保存在本地，不提交 Git；提供不含凭据的配置样例。
- Gradle 9.3.1 使用官方 bin 下载源并固定 SHA-256；Java 21 与 Android 命令行工具下载校验和通过。SDK、NDK、模拟器和缓存位于工作区 `.toolchains`，未修改全局 Java / Flutter 配置。当前网络下 Maven Central 对 Gradle 请求返回 403，工作区专用 Gradle 缓存中设置了 Google 托管 Central 镜像与阿里云插件镜像；工程仍保留默认仓库设置。
- Android 16 / API 36、x86_64 独立模拟器集成测试通过：原生读写、快速添加、卡片内子事项勾选及重新读取、计时、完成保留与设置页。测试使用调试包和 `--no-enable-impeller`；Flutter 工具仅在此空白 QA 模拟器切换测试签名，测试后清理调试包。
- 初始 SwiftShader 模拟器图形后端出现启动画面与截图挂起，改用 host 图形后端并关闭模拟器 Vulkan 后，核心集成测试通过。这个结果不代替安卓真机 GPU、ARM 架构或系统文件选择器验证。
- 一键脚本输出按版本命名的 APK 与便携 SHA-256 文件到工作区 `Deliveries/Mikanseta/`；二者不提交 Git 历史。

交付 APK SHA-256：`54a64378c427230983ad503c60fdea3822d40fc290584177e5dcbf7893009514`。安卓真机尚未验证。

正式交付 APK 再次安装和默认启动通过：`am start -W` 返回 Status: ok / COLD，约 1.3 秒完成，随后确认应用进程运行并截图检查首屏；未向正式 APK 传入关闭 Impeller 的启动参数。

## 0.1.2 (3)：Android 日历与时钟联动（2026-10-14）

- 静态检查无问题；完整数据 / 界面测试 34 项通过，日历专项 8 项在 `TZ=America/Los_Angeles` 再次通过。覆盖幂等导入、改期不重复、重复实例独立、全天日期及读取范围边界、保留完成 / Checklist / 计时与手动修改、删除排除、导出令牌关联、跨安装来源隔离、编辑期间暂缓导入，以及来源默认不选、倒计时范围、外部处理应用缺失提示、日历确认 / 取消与 DDL 分离。
- Release 通用 APK 构建及发布签名校验通过，版本 0.1.2 (3)；原发布证书、包名、最低 API 24、目标 API 36 保持。设置页读取实际包版本；所有本地版本回退值同步更新。
- 专用 Android 16 / x86_64 QA 模拟器中创建两个虚构日历来源（课程、节假日）。在发布包实际界面勾选课程、保留节假日未选，保存后只导入 1 个日程。修改源事件后返回 App，原事项标题、备注和地点更新，未新增副本；打开 / 返回自动导入开关可保存。
- 实际系统时钟界面确认创建含事项标题的闹钟，重复、铃声和振动可见；系统 25 分钟倒计时启动并显示事项名称与递减时间。QA 时钟提示通知被阻止，故本轮不声称已验证锁屏响铃或后台可靠性。
- 系统日历新增 / 查看 Intent 的参数、确认、取消与本地数据保留已验证；完整外部编辑保存流程未通过。该 AOSP 镜像的 Calendar 新增组件在清单中声明但安装包缺少 `com.android.calendar.event.EditEventActivity`，启动时报 `ClassNotFoundException`。详情组件另有 String 强转 Long 与空值崩溃；仅对该 AOSP 组件使用其支持的 EventTime 路由绕开前一个错误，外部应用单独启动避免带走 Mikanseta 的任务栈，后续空值错误仍属外部日历限制。其他日历应用沿用标准 Android URI。依据为实际系统日志及 [AOSP EventInfoActivity 源码](https://android.googlesource.com/platform/packages/apps/Calendar/+/refs/heads/main/src/com/android/calendar/EventInfoActivity.kt)。
- 日历仅读取所选本机来源。安装身份放在 Android `noBackupFilesDir`，不会随系统备份恢复到另一部手机，避免错误复用 Calendar Provider 编号。没有读写个人日历；临时测试仅发生在专用模拟器。
- 本轮没有安装到 iPhone 或 Mac；它们的现有安装版本未改变。安卓品牌真机、ARM 架构运行、系统日历完整编辑保存及真实账号下载仍待验证。

Android 系统时钟采用 [官方通用 Intent](https://developer.android.com/guide/components/intents-common)，只设置时、分或倒计时时长。没有实现自动 DDL 调度、自动取消闹钟、后台持续同步或日历自动回写。

0.1.2 (3) 最终 APK SHA-256：`4fee5861fbce436bab62be63bedf0168dbbcdb0382f28f32f4279b5bf30b2ae3`。

## 0.2.0 (4)：未提交迁移源码（2026-10-16）

`pubspec.yaml` 已更新为 **0.2.0+4**，界面与设置页的版本回退值同步为 `0.2.0 (4)`；Android 与 Xcode 工程的构建配置都从 `pubspec.yaml` 读取版本。以下源码位于当前工作区，**尚未提交**：

- 日 / 周日历与拖动选时段：`lib/src/calendar_view.dart`。新增周视图；日视图空白处长按后拖动选择时段，15 分钟对齐。
- 课表与消息解析：`lib/src/student_tools.dart`。课程模型、CSV / ICS 解析，以及粘贴文本的日期、平台和耗时建议。
- 原生提醒、小组件与实时活动：`lib/src/system_services.dart`、`android/app/src/main/kotlin/com/personal/mikanseta/LocalServices.kt`、`ios/Widgets/`、`native/Apple/Ported/`。
- Apple 日历与 Android 系统服务迁移：`native/Apple/AppleSystemServices.swift`、`lib/src/android_system.dart`，以及把共享原生核心与独立命名的 Widget 扩展挂进 Xcode 工程并保留签名的 `Scripts/configure-native-services.py`。

这批改动**只完成源码接入**：Dart 侧静态检查与 Flutter 测试已经通过，原生提醒、小组件、实时活动、Apple 日历和 Android 系统服务仍未在真实设备上验证。iCloud Drive 云同步继续未迁移。

### 本轮验证结果（2026-10-16）

| 验证 | 实际结果 |
| --- | --- |
| 静态检查 | `./Scripts/flutter.sh analyze` 通过，`No issues found!`。 |
| 数据与界面测试 | `./Scripts/flutter.sh test` 通过：`+44: All tests passed!`。共 44 项，分布为 `domain_test.dart` 19、`widget_test.dart` 7、`android_system_test.dart` 8、`migration_test.dart` 10。新增的 `migration_test.dart` 覆盖时间轴、跨午夜与夏令时、循环展开、拖动选时段、月历 / 周历切换、CSV / ICS 解析、消息解析、提醒计划与日历清理。 |
| 只读回归修复 | `read-only timeline cannot create schedules and day/week choices persist` 曾失败一次：只读模式下拖动选择时段触发 null check 异常，报在 `test/migration_test.dart:157`。该回归已在工作区 `lib/src/calendar_view.dart` 修复，单独重跑该项通过；随后完整套件 44 项全部通过。修复前的那次失败不计入通过。 |
| Android 原生编译 | `:app:compileReleaseKotlin --offline` 通过；包含前台提醒降级和外部路由白名单修复。 |
| Android Release 构建 | `./Scripts/build-android.sh` 通过，导出 **0.2.0 (4)** 通用 APK，55.9 MB，最低 API 24、目标 API 36。 |
| Android APK 签名与元数据 | 设置工作区 JDK 后，`apksigner verify --verbose` 通过 APK Signature Scheme v2；`aapt` 确认包名 `net.bingyan.KikuchiHeinrich.mikanseta`、版本码 4。APK 声明通知、精确闹钟、全屏 Intent、开机接收和媒体播放前台服务权限。SHA-256：`b463a8de2d1c03b34dbe70b6bc0908f94cd405a8f0d1ac0e33e31c655d9b1d63`。 |
| iOS 模拟器构建 | `./Scripts/flutter.sh build ios --simulator --flavor Mikanseta` 通过，产物包含 `MikansetaWidgets.appex`，版本元数据为 0.2.0 (4)。Flutter 提示缺少 `Debug-Mikanseta` 配置并回退到 `Debug`；此项不是 Release 或真机签名验证。 |
| Android 真机 / 模拟器 | 未运行。本机 `adb devices -l` 未列出设备；无法据此确认通知授权、精确闹钟、全屏提醒、重启恢复或小组件的运行效果。 |
| Android 系统日历结果回流 | 尚未实现即时回流：`takeCalendarEdits` 仍返回空列表。通过系统日历编辑后，事项的本地关联可能要等所选来源的后续同步更新；从未选择来源时不会立即回写。 |
| macOS Release 构建 | `./Scripts/flutter.sh build macos --release` 通过，生成 50.4 MB `Mikanseta.app`。本轮未启动或安装该包。 |
| 原生与系统服务 | iOS Widget 扩展随模拟器构建编译；Android 原生已 Release 编译；macOS Release 编译通过。系统提醒、小组件、实时活动、Apple 日历及 Android 系统服务均未在真实设备完成行为验证。 |

Flutter 命令在受限沙箱里会让 Dart 3.13.5 运行时于创建 isolate 前报 `runtime/vm/cpuinfo_macos.cc: 42: error: unreachable code`（宿主 Intel Mac，macos_x64）；在获准的主机环境下运行正常，分析和测试结果如上。Android `apksigner` 也需把 `JAVA_HOME` 指向工作区 JDK。

### 本轮 APK 与源码

交付文件 `Deliveries/Mikanseta/Mikanseta-0.2.0+4-android.apk` 于 **2026-10-16 11:10 +0800** 由本轮 Release 构建生成，SHA-256 为 `b463a8de2d1c03b34dbe70b6bc0908f94cd405a8f0d1ac0e33e31c655d9b1d63`；相应 `.sha256` 文件已生成。旧的 2026-10-15 构建已由本轮构建替换。

此 APK 包含日 / 周视图、提醒、小组件与路由修复等当前构建源码；系统日历编辑结果即时回流仍未实现，设备行为也尚未实测。APK 构建成功不等于所有迁移功能均已验收。

## 0.3.0 (5)：Supabase 账户与跨设备同步（2026-10-17）

本轮新增：Supabase 邮箱验证码登录、每账号一行整份 Archive 的拉取-合并-上传同步、实时频道订阅（秒级推送）、条目与课表删除墓碑（防止跨设备复活）、回前台与手动同步入口；Android 主 manifest 补 INTERNET 权限，macOS 两个 entitlements 补 `network.client`；三个一键安装/打包脚本从 git 忽略的 `LocalInstall/supabase.env` 注入 `--dart-define`。配置与限制见 `Documentation/SUPABASE_SETUP.md` 与 `Documentation/supabase-schema.sql`。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查 | `./Scripts/flutter.sh analyze` 通过，`No issues found!`。修正过两处：`Supabase.hasInstance` 在 2.18.3 不存在（改为后端内部一次性初始化标记）、`anonKey` 参数已更名 `publishableKey`。 |
| 单元与 Widget 测试 | `./Scripts/flutter.sh test` 通过：`+60: All tests passed!`。新增 16 项：墓碑合并 4（删除跨设备不复活、删除后重建保留、旧备份导入不复活、课表墓碑）、`cloud_sync_test.dart` 10（新账号上传、已有账号双向合并、防抖上传、实时拉取合并、按 revision 忽略自己事件、Android 日历设置按设备保留、双端计时收敛、损坏远端报错不动本地、退出登录保留数据、删除墓碑上传与防复活）、设置页账户区块 2（未配置占位、登录流程）。 |
| 时区变体 | `TZ=America/Los_Angeles` 下 `test/domain_test.dart`（23 项）与 `test/cloud_sync_test.dart`（10 项）全部通过。 |
| 原版备份往返 | `./Scripts/verify-backup.sh` 通过：Swift → Dart → Swift；墓碑仅作为未知 metadata 键被原版忽略。 |
| macOS 集成测试 | `./Scripts/flutter.sh test integration_test/app_test.dart -d macos` 通过。首次运行因 `Failed to foreground app; open returned 1` 失败一次，重跑通过；未改动任何代码。 |
| macOS Release 构建 | `./Scripts/flutter.sh build macos --release` 通过，52.8 MB；`app_links`、`shared_preferences_foundation`、`url_launcher_macos` 插件随 supabase_flutter 编译通过，网络客户端 entitlement 已加入。本轮未在 Mac 上登录真实账号。 |
| Android Release 构建 | 首次失败两次后通过，详见下方两行。最终 `./Scripts/build-android.sh` 通过，导出 **0.3.0 (5)** 通用 APK 60.0 MB（59,960,480 字节）。 |
| Android 失败一：网络 | Gradle 解析 `kotlin-stdlib` 等构建插件时 `repo.maven.apache.org` 返回 403（国内网络中断）。已在 `android/settings.gradle.kts` 与 `android/build.gradle.kts` 的仓库列表前加阿里云镜像（gradle-plugin/google/public），官方源保留为后备。 |
| Android 失败二：残留生成文件 | `:app:compileReleaseJavaWithJavac` 报 `程序包dev.flutter.plugins.integration_test不存在`：此前 Android 模拟器集成测试以 debug 模式生成的 `GeneratedPluginRegistrant.java` 残留了 dev 依赖插件，而 release 构建按规则不链接它。删除该（被 gitignore 的）生成文件后，release 构建按 release 依赖集重新生成，编译通过；`build-android.sh` 已加入构建前清理该文件的步骤防复发。 |
| APK 校验 | 交付 `Deliveries/Mikanseta/Mikanseta-0.3.0+5-android.apk`，SHA-256 `f4781e8ee758287abbd50eff075e90278ac9488a57efd8272e954fca37dab3da`，`.sha256` 文件已生成。本轮 APK 未注入 Supabase 连接值（构建时本地 env 尚未创建），含完整账户同步代码，未配置时设置页显示"未配置"。 |
| 真实 Supabase 同步 | 未验证：需要用户创建项目（已注册）、执行 `Documentation/supabase-schema.sql`、在 `LocalInstall/supabase.env` 填入 URL 与 anon key 后重新构建安装并登录。Fake 后端单元测试覆盖了合并、防抖、防回声与防复活规则。 |

### 数据规则说明

墓碑存放于 archive metadata 的 `tombstones`（条目）与 `courseTombstones`（课表），键为大写编号、值为整秒 UTC 时间戳；`Archive.merge` 丢弃更新时间不晚于墓碑的记录，晚于墓碑的编辑视为重新创建并保留。墓碑永久保留（体量可忽略）。备份导入走同一合并规则，因此旧备份不会再复活已删除条目。Android 日历来源设置（`androidCalendarSync`）在应用云端副本时保留本机值，与原版"日历来源按设备"一致；云端数据明文存于用户自己的 Supabase 项目，行级安全限制本人读写。

## 0.4.0 (6)：共享文件夹同步（macOS + iOS + Android）（2026-10-17）

本轮新增：Mikanseta 与原生 Mikansei 的**共享文件夹自动同步**。三端各选一次文件夹后，自动交换 `Mikansei-sync/replica-<设备UUID>.json`（协议与原生版 iCloud 文件夹同步一致：Lamport 修订号 + 永久墓碑 + 每设备独立文件），无需手动导出/导入。macOS/iOS 使用安全作用域书签，Android 使用 SAF 持久授权；macOS 两个 entitlements 补充 `com.apple.security.files.bookmarks.app-scope`；iOS 小组件扩展版本同步为 0.4.0 (6)。使用说明见 `Documentation/LOCAL_SYNC_SETUP.md`。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查 | `./Scripts/flutter.sh analyze` 通过，`No issues found!`。修正过 `Archive.find` 不存在、未使用导入与 null-aware 元素三处。 |
| 单元与 Widget 测试 | `./Scripts/flutter.sh test` 通过：`+74: All tests passed!`。本轮新增 14 项：`local_folder_sync_test.dart` 13 项（首轮写出、远端合并、本地修改采集、删除墓碑与防复活、远端墓碑、修订号覆盖、无变化不重写、损坏远端中止且不动本地、设备号/计数器重启保持、null 归一化、课表同步与墓碑、按设备元数据保留、原生格式解码/再编码）与设置页共享文件夹连接 1 项。 |
| 时区变体 | `TZ=America/Los_Angeles ./Scripts/flutter.sh test test/local_folder_sync_test.dart` 通过（13 项）。 |
| 原生解码兼容 | 用 Dart 生成含条目、课表与墓碑的 replica 文件，在 `/tmp` 复制原生 `Sources/MikanseiCore` 并以 `swift test` 实际调用 `WorkspaceSyncDocument.decode`：解码、校验与原生再编码全部通过。首次失败是夹具课表日期写成日期-only，改为完整 ISO 时间戳后通过（真实数据格式即完整时间戳）。 |
| macOS 集成测试 | `./Scripts/flutter.sh test integration_test/app_test.dart -d macos` 通过。 |
| macOS Release 构建/安装 | `./Scripts/install-mac.sh` 通过，`Mikanseta.app` 53.1 MB；已安装到 `Projects/Mikanseta-macOS.app` 并启动。校验：版本 0.4.0 (6)、`x86_64 + arm64` 通用、签名含 `bookmarks.app-scope`、`codesign --verify --deep --strict` 通过。 |
| Android Release 构建 | `./Scripts/build-android.sh` 通过，导出 **0.4.0 (6)** 通用 APK 60.5 MB（60,468,624 字节），SHA-256 `36483aa3e9a0871fa8de92039ef2ed51bc14885d905b356110706b47d1fe8695`。首次编译即通过（SAF 使用系统 `DocumentsContract`，未新增依赖）。 |
| iOS Release 构建 | `install-iphone.py` 的构建阶段 **BUILD SUCCEEDED**（新的书签/文件夹选择代码编译通过），随后安装在设备定位阶段中断：`CoreDeviceService was unable to locate a device`（手机未连接/锁屏）。修正小组件扩展版本后的重新安装待手机可用时执行。 |
| 真实设备端到端 | 未验证：需要在 Mikanseta（Mac/iPhone/Android）与原生 Mikansei 上各选择同一个文件夹。原生 Mac 当前的 replica 文件为空（原生档案 0 条），格式解析通过。 |

### 协议与实现说明

- 文件结构 `{version:1, entries:[{id, revision:{counter, device}, value?}], courses:[...], deletedCalendarOccurrences?:[...]}`；无 `value` 即墓碑。修订号按 counter、再按 device 字符串排序，平手保留本地。
- 每轮交换顺序：读取全部远端文件（任一损坏即中止、不写任何文件）→ 本地变更采集（每批一个 counter）→ 合并远端 → 投影回 Archive（保留本机 preferences/日历设置，删除写 `tombstones`/`courseTombstones`）→ 有变化才提交 → 内容有变化才写自己的 replica → 持久化设备号/counter/文档。
- 触发：本机保存后 2 秒防抖、连接期间每 30 秒、回前台、手动“立即同步”。与 Supabase 同步可并行，二者都通过 `EntryStore` 的提交入口收敛。
- iOS 使用 `.minimalBookmark`，macOS 使用 `.withSecurityScope`；Android 严格校验 `replica-<UUID>.json` 文件名，防止路径穿越。

## 0.4.1 (7)：修复 iOS/macOS 文件夹授权保存（2026-10-17）

真机选择 `Mikansei Cloud` 后报 `选择文件夹失败：PlatformException(bookmark, The file couldn't be opened because it doesn't exist.)`：移植 `FolderSyncManager.connect` 时漏掉了它的 `startAccessingSecurityScopedResource()` 包裹（原版 Sync/FolderSyncManager.swift:39-40），对 iCloud 项创建书签会报"文件不存在"。已在 iOS `UIDocumentPicker` 与 macOS `NSOpenPanel` 两条路径补上同一处理，版本升至 0.4.1 (7)（含 iOS 小组件扩展）。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查与测试 | `analyze` 通过；widget 与 local sync 测试 23 项通过。 |
| iPhone 安装 | `install-iphone.py` 安装 0.4.1 (7) 成功（构建后手机锁定，需解锁打开）。 |
| macOS 安装 | `install-mac.sh` 构建并替换 `Projects/Mikanseta-macOS.app` 成功，启动正常。 |
| 真机重选文件夹 | 待用户在 Mikanseta（iPhone/Mac）重新选择 `Mikansei Cloud` 验证。 |

| Android Release 构建 | 为保持三端版本一致重建 **0.4.1 (7)** 通用 APK 60.5 MB，SHA-256 `602120bdc691cf0ba2b2ad9b44aa16d479974c9c93263f56f0d8f5641ebc8b1e`。该修复不影响 Android（SAF 持久授权不涉及书签），0.4.0+6 APK 亦含完整本机同步功能。 |

## 0.4.2 (8)：手机端布局对齐原生 Mikansei（2026-10-18）

本轮只调整视觉与布局，不改交互、数据与同步：

- **顶部栏**：所有 tab 使用大标题（26pt / w700），今日页保留“日期 · 一件一件，慢慢完成”副标题；手机端移除悬浮 FAB，改为右上角胶囊添加按钮（tooltip 仍为“添加事项”）。
- **概览**：三张指标卡合并为一张分段卡片（未完成 / 已超时 / 今日完成），细分隔线 + 22pt 数字，减少视觉噪音与高度。
- **搜索与筛选**：搜索框改为无描边胶囊（圆角 22、填充 surfaceContainerLow）；新增 `SegmentedStrip` 组件替换“我的清单”的 ChoiceChip 行，日程页的月/日/周/列表切换复用同一组件（保留 `calendar-*` ValueKey）。
- **卡片**：完成圈 24pt、标题 17pt/w600、元信息改为“图标 + 文本”（类型 / 重要级 / DDL），科目、平台、地点单独一行；进度条 64×3；Checklist 勾选框改为方形圆角；计时按钮改回轻量纯图标（tooltip 不变）。
- **分组标题**：13pt/w600 + 浅色数量徽标，超时保持 error 色。
- **底部导航**：改为悬浮胶囊（圆角 24、细描边与轻微阴影），仍为标准 `NavigationBar`；页面切换加入 160ms 淡入。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查 | `./Scripts/flutter.sh analyze` 通过，`No issues found!`。 |
| 全量测试 | `./Scripts/flutter.sh test` **74 项全部通过**；期间出现一次 `local_folder_sync_test` 偶发失败，单独与连续两次全量重跑均通过（与本次布局改动无关，属既有测试的时序波动）。 |
| 模拟器视觉验收 | “Mikansei QA” 模拟器（390×844）安装 0.4.2 调试包并种入示例数据（超时 / 带步骤作业 / 进行中计时 / 日程 / 笔记）：浅色与深色截图确认大标题、胶囊按钮与搜索、分段筛选条、指标分段卡、图标化元信息、方形步骤勾选框、悬浮胶囊底栏均按预期渲染；“我的清单”页分段条与计数徽标正常。日程页复用同一 `SegmentedStrip`，未单独截图。 |
| 构建与安装 | macOS Release（0.4.2 (8)，x86_64 + arm64）构建并安装启动；Android 签名 APK 0.4.2+8 导出（60.5 MB，SHA-256 `2a0217153e20a605947a494798191abed62426f92535178f961d3223221048c5`）；iPhone 本轮未连接，安装待设备可用后执行。 |
