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

Xcode 工程、工作区、App 目标和共享运行方案统一改为 Mikanseta，安装脚本同时更新。源码目录保留 `ios/Runner/`，供 Flutter 自动生成插件注册文件；开发命令通过 `--flavor Mikanseta` 选择新方案，继续使用已有 Debug / Profile / Release 配置。Team `7JMRL8X34C` 和 App 安装标识 `com.personal.mikanseta` 保留。此次只调整工程名称与安装流程，App 版本保持 0.1.0 (1)。

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

- Mikanseta 0.1.1 (2) Release 通用 APK 构建通过，包名 `com.personal.mikanseta`。54.0 MB，包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`；最低 API 24，目标 API 36。
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
| Android APK 签名与元数据 | 设置工作区 JDK 后，`apksigner verify --verbose` 通过 APK Signature Scheme v2；`aapt` 确认包名 `com.personal.mikanseta`、版本码 4。APK 声明通知、精确闹钟、全屏 Intent、开机接收和媒体播放前台服务权限。SHA-256：`b463a8de2d1c03b34dbe70b6bc0908f94cd405a8f0d1ac0e33e31c655d9b1d63`。 |
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

## macOS 中文文字纹理兼容开关（2026-10-20）

为规避 macOS Impeller 路径上的中文字形纹理异常，`macos/Runner/Info.plist` 仅新增 `FLTEnableImpeller=false`。该设置只影响 macOS renderer；中文内容、主题、App 数据、版本与应用标识均未改动。

SDK 证据来自固定 Flutter 3.47.7（`abaf9c523780a608bd46686fd5e53740a07077f8`，engine `deb287481e3ce9468f3434937ced4240a70539ca`）：

- `engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterDartProject.mm` 从主 App bundle 读取 `FLTEnableImpeller`，缺省返回 `YES`。
- `dev/devicelab/bin/tasks/hello_world_impeller_macos_sdfs.dart` 在同一 SDK 中把该键设为 `false`，并明确断言启动日志应显示 `Using the Skia rendering backend (Metal).`。
- 桌面工具源码及测试确认 `--no-enable-impeller` 会向 macOS 引擎传入 `enable-impeller=false`；`Info.plist` 是安装后直接启动时持久生效的配置入口。

| 验证 | 实际结果 |
| --- | --- |
| Plist 静态校验 | `plutil -lint` 通过，提取 `FLTEnableImpeller` 为 `false`。 |
| macOS Release 构建与安装 | `Scripts/install-mac.sh` 带入现有本机同步配置重新完成 Release 构建，产物 53.1 MB，并安装到 `/Users/xuyilin/Desktop/Projects/Mikanseta-macOS.app`；日志为 `LocalInstall/macos-renderer-install.log`。 |
| 安装包元数据与签名 | `CFBundleIdentifier` 为 `com.personal.mikanseta.macOS`，版本保持 0.4.2 (8)；安装包 `FLTEnableImpeller` 为 `false`，`codesign --verify --deep --strict` 通过。 |
| 实际安装包运行 | 已启动实际安装包；主代理捕获的 `LocalInstall/macos-renderer-runtime.log` 明确出现 `Using the Skia rendering backend (Metal).`。 |

限制：本机 `screencapture` 未能取得该窗口图像，因此尚未视觉复测截图中的中文标题和多个筛选状态。不能据此确认条纹已消失，也不能据此确定 Impeller 的具体缺陷。


## 0.4.3 (9)：Windows 桌面接入与打包（2026-10-20）

新增 Windows x64 runner、沿用现有牛皮浅棕主题与批准图标、Windows 原子本机保存、系统文件选择、备份、HTTP(S) 外链和共享文件夹同步适配。其他平台继续使用原有原生通道。Windows 明确显示系统日历、后台提醒、小组件与实时活动未接入，不将其表现为权限错误。

- 主机 Flutter 静态检查通过：No issues found。
- 完整 Flutter 数据与界面测试通过：83/83。新增 9 项覆盖 Unicode/步骤/计时持久化、替换失败保留原档、取消文件操作、文本与备份、共享文件夹与状态重启恢复、非法 replica 路径、文件夹失效、外链限制和 Windows 功能说明。
- Swift → Dart → Swift 备份往返通过。
- Windows 2022 GitHub Actions 首轮构建 [39435492858](https://github.com/KikuchiHeinrich/Mikansei/actions/runs/39435492858) 全部通过，源码提交 `c6c213ae916e566b8a1577d2440af79729f9e397`。包括静态检查、Flutter 数据与界面套件、Windows 应用集成、Release、ZIP、Inno Setup 安装、安装后进程存活 8 秒及卸载。该结果不代替个人 Windows 电脑上的视觉和长期运行验收。
- macOS Release 回归构建通过；本轮未替换本机已安装 App。
- 后续补充读取保护：本机档案不可读或为目录时报告错误，只有文件不存在才视为首次使用，避免误将读取失败当作空档案。对应回归用例在最终 Windows CI 中通过。
- 第二轮 CI 在旧课表同步检查中失败，Windows 档案读取保护用例通过。发现测试助手用 `contains('BAD')` 排除损坏样本，可能误排除随机 UUID 中包含相同片段的正常设备文件；已改为只排除准确样本名 `replica-BAD.json`，最终 CI 中通过。
- 最终 Windows 构建 [39438198255](https://github.com/KikuchiHeinrich/Mikansei/actions/runs/39438198255) 全部通过，源码提交 `c0854d33ed36a55ac5a469b8b6d86a44eaa65249`：静态检查、**84/84 数据与界面检查**、真实 Windows 应用集成、Release 编译、ZIP / Setup 打包、安装、启动存活 8 秒及卸载。
- 提供完整 ZIP 与每用户 Setup EXE 构建脚本，包含 VC 运行库与校验文件；不删除用户 AppData 清单。安装包暂未做 Windows 代码签名。
- 账号同步服务连接仅从经授权的 CI 配置或显式环境变量加入；未配置时仍可使用本地及共享文件夹功能。
- 经用户明确授权，将核验为 `publishable` 的公开客户端配置加入 Actions secrets。最终产物 `build-info.json` 确认 `supabaseConfigured=true`；未上传管理员密钥、登录会话或个人清单。真实 Windows 登录及跨设备账号同步仍未完成端到端验收。

公开发布：[Windows 0.4.3 (9)](https://github.com/KikuchiHeinrich/Mikansei/releases/tag/mikanseta-windows-v0.4.3)。下载产物的 SHA-256 与随附校验文件一致，ZIP 完整性、Windows x64 PE 架构及完整 VC 运行库已核对：

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| `Mikanseta-Windows-x64-Setup.exe` | 11,867,688 | `d914b58269b9aa2cf2af2dbb163dd557cc40426d8c27796d0368d9745e0ae893` |
| `Mikanseta-Windows-x64.zip` | 14,144,403 | `93ef172a5a21003ffce4299a6068fff35ee78cf52fd612ae50b8080ef9db8f7f` |

## 0.4.4 (10)：完成分组与卡片状态修复（2026-10-22）

复现到 `AnimatedEntryList` 的重排离场动画会保留之前缓存的 `Entry` 快照。连续完成多张卡片时，同一 ID 的新卡片已进入“今日已完成”，旧的离场卡片仍可能短暂显示未勾选和未划线。修复建立列表级 ID 快照索引，并仅让动画离场子树监听 store，再按 ID 读取最新条目；没有为每张正常卡片增加 `store.find` 或重复扫描。未修改 domain、store 数据模型、主题、布局或平台配置。

| 验证 | 实际结果 |
| --- | --- |
| 修复前回归 | 连续完成 8 张卡片中的 7 张时，60ms 动画帧发现“快速2”同时存在完成与未完成快照，针对性测试失败。失败发生在旧离场条目，稳定后状态本身正常；正常的 220ms 文字样式插值不是根因。 |
| 修复后回归 | 同一用例在 Android、iOS、macOS、Windows 四个 Material `TargetPlatform` 下通过：动画中同 ID 卡片均使用完成快照，稳定后每个 ID 仅一张卡片；图标、实际 `DefaultTextStyle` 删除线及恢复未完成状态一致。 |
| 清单与外部替换 | 含 checklist 的条目完成后步骤勾选、图标与删除线一致；同 ID 云端替换后继续显示正确标题和完成状态，恢复后同步清除。 |
| 静态检查 | Flutter 3.47.7 `flutter analyze` 通过，`No issues found!`。 |
| 版本 | `pubspec.yaml` 为 `0.4.4+10`；源码版本常量与 store 回退标签均为 `0.4.4 (10)`，未修改锁定依赖。 |
| 全量测试 | `flutter test` **87/87 通过**。 |
| Android | 0.4.4+10 构建、验签通过，签名证书与原有证书一致。APK 为 `/Users/xuyilin/Desktop/Projects/Deliveries/Mikanseta/Mikanseta-0.4.4+10-android.apk`，60,550,984 bytes，SHA-256 `9bb50acd5cfa2157d8751192c373797d0eb6cb46ab1207be87c33334c53d6353`。 |
| macOS | 使用现有安装脚本和本机配置构建 0.4.4 (10)，覆盖安装后 `codesign` 验证通过；`FLTEnableImpeller=false` 保留，实际运行进程 PID 84914。 |
| iOS 模拟器 | `Scripts/flutter.sh build ios --simulator --flavor Mikanseta --no-pub` 编译成功，耗时 102.9s；产物 `build/ios/iphonesimulator/Mikanseta.app` 为 x86_64 + arm64 通用模拟器应用，Bundle ID `com.personal.mikanseta`，版本 0.4.4 (10)。本任务未执行额外签名或安装；日志为 `LocalInstall/completion-fix-ios-simulator.log`。 |
| iPhone | 设备当前 unavailable，未安装。 |
| Windows | CI [39724313139](https://github.com/KikuchiHeinrich/Mikansei/actions/runs/39724313139) 已 completed success，对应修复提交 `51e6d3f2875bb64947c7a4ecf14939138b358d49`。Windows Analyze、全部单元测试、实际 `integration_test/app_test.dart`、Release 构建、Inno 安装及安装后启动/卸载验证、产物上传全部成功。下载 artifact 12402696936，归档 SHA-256 为 `6c6b92e7ec9fc43742849621c0f522b51180d37471c5e3ec72a7ddd713aee3e9`，解包后每个包的 `.sha256` 均一致。本地交付目录为 `/Users/xuyilin/Desktop/Projects/Deliveries/Mikanseta/Windows/0.4.4+10/`，`Setup.exe` 为 11,869,035 bytes，portable ZIP 为 14,145,112 bytes，`build-info.json` 确认 version `0.4.4`、buildNumber `10`。 |

限制：iOS 模拟器构建时因工程没有 `Debug-Mikanseta` 配置而由 Flutter 回退到通用 `Debug`，日志已如实记录，本次未修改工程配置。尚未完成 Android、iOS、macOS、Windows 真机 UI 验收；当前证据覆盖动画退出期间的旧快照问题，未在测试中复现稳定态持续错误，不能把本次修复解释为已覆盖所有可能场景。

## 0.4.5 (11)：循环事项活动 frontier 与跨备份系列身份（2026-10-22）

根因有两层：`TaskBoard.open` 直接返回全部未完成事项；日历桥接又会把 30 天窗口内每个 occurrence 保存为独立条目。因此同一循环会同时占用多张活动卡片。导入条目的本地 `repeatRule` 仍为 `never`，既会漏掉“常态”筛选，也无法表达来源系列与本地合成后继的边界。

本轮把存储与列表投影分开：

- `TaskBoard.open/visible/focus` 及依赖它们的常态、相关待办和系统摘要，按家族只返回一个活动项；历史仍返回全部已完成条目。独立事项不按标题、相同 `repeatRule` 或相同时间合并。
- 家族来源只使用显式 `previousOccurrenceID` 血缘或可靠日历身份。本地血缘先选择没有未完成前驱的 rootmost 候选；循环链没有根时回退到稳定排序。provider occurrence 用原始 occurrence 时间排序，用户移动显示开始时间不会改变系列顺序。
- 同名同父、同原始 occurrence 的离线重复后继只抑制 sibling，不删除底层记录。完成其中一项后，同一 sibling 不再出现；真实下一代即使被编辑到父项同一日期仍会显示。
- 共享 `routineSeriesID` 别名优先继承 provider 的原始 occurrence，其次使用 `routineOccurrenceID`；两者都缺失时才退回显示 recurrence 日期。
- 日历的未来展开继续读取原 `entries`，不应用待办 frontier；日 / 周 / 月 / 列表预测仍可显示 30 天窗口中的来源实例。

跨备份系列协议使用既有 `androidCalendarLink`，并新增两个可选顶层字符串：

```json
{
  "routineSeriesID": "[\"calendar\",\"phone\",\"1\",\"10\"]",
  "routineOccurrenceID": "1791878400000"
}
```

值是对 `["calendar", deviceID, calendarID, masterID]` 做紧凑 JSON 编码后的字符串。Android 的 `masterID` 为 `ORIGINAL_ID`（无例外时使用 `event_id`）；Apple 使用共享的 external event identifier。bridge 同时返回：

- `androidCalendarLink.seriesID`
- `androidCalendarLink.recurring`
- `androidCalendarLink.originalOccurrence`

`routineOccurrenceID` 精确保存 provider 的原始 occurrence，优先于显示 recurrence 日期；导入的 task timing 为 `end` 时仍保存来源 START 身份。新桥接导入会同时写入两个字段。旧 Android link 若 key 的末段是 Dart 可表示的 9–19 位 epoch 数字且不是 `single`，会在本地加载、日历导入、云同步或备份合并时回填两个字段；越界值、`recurring:false`、缺失可靠原始 occurrence 的记录不视为循环。Apple 备份中的 `calendarEvent.event.identity.occurrence` 非空时，按 `calendarID + sourceTitle + eventID` scope 识别，不使用可变的日历标题。

Android `Instances` 增加 `rdate` 投影，并把 RRULE、RDATE 或 `original_id` 任一存在视为循环来源。key 保持 `calendarID/master/originalOccurrence` 结构；detached 例外使用原 master，展示用 `event_id` 不参与系列归组。

共享 alias 的 occurrence 顺序是：provider 原始 occurrence → `routineOccurrenceID` → 显示 recurrence 日期。`routineSeriesID` 是 provider series marker：它参与 frontier 和“常态”展示，阻止 `nextOccurrence` 及 store 完成 transition 再合成本地后代；不写入伪造的本地 `repeatRule`，不改动计时、Checklist、完成状态或用户字段。

导入查找在 bridge key/token 未命中时，会按 `routineSeriesID` 与 `routineOccurrenceID` 的同时精确匹配恢复同一 provider occurrence；不使用标题或显示时间。命中多个历史副本时优先已完成项，再按更新时间和 ID 稳定选择，其他重复历史全部保留。失去 `androidCalendarLink` 的实际 fallback 会始终重新附着当前 link、snapshot 和共享身份；旧 snapshot 缺失且未确认外部编辑时，不覆盖任何来源 snapshot 字段，包括标题、备注、地点、`plannedStart`、`plannedEnd` 和 `plannedAllDay`。已有用户展示字段、完成状态、计时与 Checklist 因此保持不变。

| 验证 | 实际结果 |
| --- | --- |
| 源码冻结 | 主代理审阅后推送为 `d3d958d12c328a49a5c7facab1eacab7e52e73f8`；本记录仅追加打包结果，不再改实现。 |
| Flutter 静态分析 | 最终 `flutter analyze` 通过，`No issues found! (ran in 3.8s)`。受限沙箱在 Dart CPU 探测阶段报 `runtime/vm/cpuinfo_macos.cc: 42: error: unreachable code`，因此使用主机环境执行只读分析。 |
| 自动化测试 | 本机按本轮限制未新增、未运行测试；先前尝试在沙箱启动测试时仅发生上述 VM 崩溃，没有本地测试断言结果。Windows 最终源码 CI 的自动 Analyze、数据 / 界面测试与实际 Windows 应用集成结果见下方，不能表述为本机测试。 |
| Android Release | `d3d958d` 最终源码重建通过，耗时 62.2 秒。APK 为 `/Users/xuyilin/Desktop/Projects/Deliveries/Mikanseta/Mikanseta-0.4.5+11-android.apk`，大小 60,583,756 bytes；`apksigner verify` 通过，证书与 0.4.4 上一版一致；`aapt` 确认 `com.personal.mikanseta`、versionCode `11`、versionName `0.4.5`。SHA-256 为 `e7e2bb424db74d24521b43dd382ee28613e371035d605018e2e34e54ddebd1b6`，随附 `.sha256` 文件一致。 |
| 原生 Mikansei 0.3.2 | Mac 与 iPhone 已交付并完成对应验证。 |
| macOS | `d3d958d` 的 0.4.5 (11) 最终包安装完成，`codesign --verify --deep --strict` 通过，安装脚本启动成功。 |
| iPhone | `d3d958d` 的无签名构建在 80.1 秒后成功；设备专属 Xcode 构建因设备断开而超时，main 的通用 iOS 配置签名构建退出码为 0，严格深度签名校验通过。用户重新连接并解锁后，`devicectl` 安装精确的最终 `Mikanseta.app` 并启动成功（本地时间 14:40:50），完成 0.4.5 (11) 更新并保留数据。 |
| Windows | 最终源码 CI run `39732284200` 对应 head `d3d958d12c328a49a5c7facab1eacab7e52e73f8`，completed success。官方 jobs 工具确认 Analyze、数据 / 界面测试、实际 Windows 应用集成、Release 打包、Inno installer、安装后启动、卸载和 artifact 上传全部成功。artifact `12406021563` 的 SHA-256 为 `edb2be4b1cc9e78e536a0d076a14ee5e8d099500dfa8bfa840457a6d2960bc5e`，下载归档的本地 SHA-256 一致，解包后每个 `.sha256` 与对应包一致。交付目录为 `/Users/xuyilin/Desktop/Projects/Deliveries/Mikanseta/Windows/0.4.5+11/`；`Setup.exe` 为 11,878,285 bytes，portable ZIP 为 14,160,465 bytes。`build-info.json` 确认 version `0.4.5`、buildNumber `11`、sourceCommit `d3d958d12c328a49a5c7facab1eacab7e52e73f8`。 |
| 版本 | `pubspec.yaml`、源码版本常量和 store 回退标签均为 `0.4.5 (11)`。 |

限制：原生备份若同时丢弃 provider occurrence 与 `routineOccurrenceID`、只保留 `routineSeriesID`，仍可保持系列归组，但 occurrence 顺序会退回当前 recurrence 时间；这样不产生假完成或删数据，但移动过发生日期的入口可能改变回退排序。历史条目和未选中来源的显式清理行为保持原样。本轮构建、签名、安装和 CI 自动化结果不代表已重新完成全部人工设备 UI 验收，也未使用私有日历做端到端验收。

## 0.4.6 (12)：笔记全页编辑（苹果备忘录式）（2026-10-24）

笔记不再使用浮窗 Dialog：新增 `lib/src/note_editor_page.dart` 全屏页面（`fullscreenDialog` 路由），大标题 + 正文无边框直写、分类行、行内清单项（增删/勾选）、已有笔记可删除（二次确认）；未保存退出统一弹“放弃未保存的修改？”。入口分流：笔记 tab 新建、笔记卡片点击、`mikanseta://new?kind=note` 走全页；任务/日程/作业仍用原 Dialog 编辑器，所有既有键位与测试不受影响。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查与测试 | `analyze` 通过；`flutter test` **88/88 通过**，新增“notes open a full page editor with unsaved-change guard”覆盖新建→全页→保存→重开→未保存确认→保存生效。 |
| macOS | 0.4.6 (12) Release 构建并安装启动。 |
| Android | 签名 APK `Mikanseta-0.4.6+12-android.apk`（60.7 MB，SHA-256 `a24ec510646e968ec9c4dc616b4a57921f52d34d8f2c972f71e244c2b2a2ab56`）。 |
| iPhone | 设备未连接，待安装。 |
| Windows | 本机无法编译；随本次提交推送由 `mikanseta-windows.yml` CI 验证。 |

## 0.5.0 (13)：规划、拖动排序、锁屏番茄钟与对比色（2026-10-24）

本轮由 6 个 GLM-5.3-Flash 子任务（动态工作流）实现，主对话验收与交付：

- **数据模型**：条目新增 `sortOrder`（手动排序，空值垫底）与 `plannedDays`（日程规划日期）；`TaskBoard` 把 plannedDays 含当天的未完成任务视同「今天要做」；store 新增 `setPlannedDays` / `setPlannedTime`（任务安排时段但类型不变）/ `reorder`。小时规划直接写任务的 plannedStart/End，同步到系统日历走既有通道。
- **规划页**：今日页新增「规划」入口（全屏页）：日程规划=候选横条 + 月历涂色（点选/连续涂抹、月切换，routine 显示自动规则）；小时规划=左栏今日待办长按拖入 24 小时时间轴（15 分钟对齐、触觉反馈），任务块带「待办」徽标。
- **拖动排序**：今日/我的清单列表改为 ReorderableListView（分组标题不可拖），组内长按拖动写 sortOrder；AnimatedList 插入/删除动画因此移除（与拖动重排互斥，注释说明）。
- **锁屏番茄钟**（iOS）：规划时段开始时刻本地通知「到点了」（点开直达 mikansei://focus 深链开始专注）；FocusTimerWidget 无运行计时时显示下一规划块「距开始」倒计时（timerInterval 走秒），时间线在块开始时刻刷新。
- **正在做变色**：EntryTile 与正在做卡 startedAt 时整块 primaryContainer 底 + onPrimaryContainer 文字 + 描边（原生端 EntryCard 同步浅绿底+描边）。
- **对比色重做**：卡片更亮暖白 + 极浅描边、导航选中态加深、浅色 error 换暖红、超时 DDL 变红色胶囊、手机添加按钮改 primary 填充。
- 原生 iPhone 列表排序未用 List+onMove：iOS 26 模拟器上该组合会使内容尺寸翻倍并冻结滚动（二分排查后确认），改用 LazyVStack + drag&drop 实现同功能；Mac 仍用原生 List+onMove。

| 验证 | 实际结果 |
| --- | --- |
| 工作流门控 | `flutter analyze` 通过；全量 `flutter test` 通过（含新增 planning_page 3 项、domain 4 项、拖动重排等）；`swift test` **96/96**（新增 5 项：排序、plannedDays 今日、Codable 往返、规划块通知、nextPlannedBlock）。 |
| 修复记录 | ① 波3 子任务两次挂死：无参 pumpAndSettle 遇 1 秒周期 Timer 永不收敛 + store.settled 等 1ms 假计时器无帧可泵——已修测试写法并在工作流注入规则；② Mikanseta macOS 构建失败：Course.swift 引用了不在共享编译目标里的 AppRoute，改为内联 `mikansei://focus/...` 深链后 swift test 96/96 与 macOS 构建均通过。 |
| 模拟器实拍 | 390×844 种入示例：今日页新配色（亮卡+描边、超时红胶囊、正在做变色）与规划页两模式（涂色月历、小时拖拽轴）均按预期渲染。 |
| 构建/安装 | macOS 0.5.0 (13) 安装启动；Android 签名 APK `Mikanseta-0.5.0+13-android.apk`（61.2 MB，SHA-256 `dc9859a4…311b30c`）；原生 Mac 0.4.0 (8) 安装。iPhone 两 App 待设备连接。Windows 由推送触发 CI 验证。 |
| 既有问题（非本轮） | UITests 的 testScheduleDurationRoutineDatesAndReminderCanBeEdited 在干净 HEAD 上即失败、testRapidCompletionAndReopenDoesNotLoseState 随机失败——均与本次改动无关，未处理。 |

## 0.5.1 (14)：首装内置「使用说明」笔记与 Markdown 预览（2026-10-24）

由 GLM-5.3-Flash 子任务实现、主对话验收：

- **首装播种**：`EntryStore.load()` 在 content==null（无档案文件）且 storage 为 NativeStorage 时，播种「使用说明」笔记（分类「帮助」，正文为 Markdown 使用指南：快速上手/规划/同步备份/笔记预览）。MemoryStorage（全部单测）与已有档案设备不会播种。
- **Markdown 预览**：新增 flutter_markdown 0.7.7+1（pub 标记 discontinued，但与 Flutter 3.47.7/Dart 3.13.5 兼容，任务允许）；笔记编辑页右上角 visibility 图标切换「预览/编辑」，预览用 MarkdownBody 渲染（标题/清单/加粗），切换不丢未保存内容（dirty 判定不变）。
- 版本 0.5.0+13 → **0.5.1+14**（pubspec、appVersion、displayVersion、iOS 小组件三个配置）。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查与测试 | analyze 通过；新增 test/built_in_guide_test.dart 3 项（内置笔记构造、MemoryStorage 不播种、预览切换保留正文）与全量回归通过。 |
| 模拟器首装端到端 | 卸载重装 Mikanseta → 启动后容器 entries.json 含「使用说明」笔记（kind=note、分类帮助、正文 # 欢迎…）；集成测试驱动打开笔记并切预览，实拍确认渲染。 |
| 构建安装 | macOS 0.5.1 (14) 构建安装启动；Android APK `Mikanseta-0.5.1+14-android.apk`（SHA-256 `8a082ed9…d81e9d9`）。iPhone 待连接；Windows 由推送 CI 验证。 |
| 集成修正 | 原生端初始标题「欢迎使用 Mikansei/指南」与 Mikanseta 不一致，主对话统一为「使用说明/帮助」并同步单测断言；swift test 99/99 通过。 |

## 0.5.2 (15)：关键交互触觉反馈（2026-10-25）

由 GLM-5.3-Flash 子任务实现、主对话验收。统一风格：选中/切换=selectionClick，完成/落定=mediumImpact，开始/暂停与保存成功=lightImpact（macOS/Windows 上自动无操作）。接入点：完成圈、计时开始/暂停、行内 Checklist 勾选、列表拖动重排落定、SegmentedStrip 分段、规划页涂色与拖入时间轴（统一原有零散调用）、笔记保存成功。版本 0.5.1+14 → 0.5.2+15。

| 验证 | 实际结果 |
| --- | --- |
| 静态检查与测试 | analyze 通过；工作流门控 Dart 全量与 swift test（99/99）通过；子任务指定三测试文件 45 项通过。 |
| iPhone | 0.5.2 (15) 构建签名后经 devicectl 轮询直装成功（Supabase 连接值注入核验）。真机触感需用户实感确认。 |
| macOS / Android | macOS 0.5.2 安装启动；Android APK `Mikanseta-0.5.2+15-android.apk`（SHA-256 `a4022c62…9d2396b`）。 |
| 范围说明 | 详情面板内重复的完成/计时按钮与"正在做"横幅暂停未加（任务清单外）；真机震动属主观体验，无法自动化验证。 |
