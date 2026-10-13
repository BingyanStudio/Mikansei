# Mikanseta · Flutter 测试版

**0.1.0 (1)**。Mikansei 的独立 Flutter 迁移项目，主题改为牛皮浅棕，搭配深棕文字、棕色操作按钮和跟随系统的深色模式。清单操作放在首位，手机使用底部导航，电脑使用侧边导航与键盘快捷键。

本项目放在 Mikansei 仓库的 `Mikanseta/` 目录中，一起提交和推送。原版 Mikansei 0.3.0 的工程、安装标识、签名、绿色主题和数据目录继续保留。

## 首轮可用功能

- 一句话快速添加，待办 / 作业 / 日程 / 笔记四种类型，详细字段按需展开。
- 「已超时」优先显示；同栏目内按紧急 → 重要 → 普通，再按 DDL / 日程开始时间排序。无日期事项仍在清单里。
- 完成后划线并以动画移到今日已完成区，次日自动进入历史。重新打开事项会保留步骤记录；开启系统减弱动态效果时减少动画。
- Checklist、科目 / 分类、备注、提交平台、处理地点和预计用时。修改步骤列表时保留未改名步骤的编号和勾选状态。
- 普通事项只需 DDL；新建日程使用开始 / 结束时间或全天。月历可点选日期，长按日期直接添加当天日程。
- 每天、每三天、每周多选星期、每两周、每月、自定义间隔和指定日期循环。完成时产生下一条记录，保留原来的月末锚点并避免重复生成。
- 专注计时：开始另一件事项自动暂停上一件；暂停、继续和完成保留累计用时，重启后根据保存的时间恢复。
- 原子保存，串行写入，失败时提示重试；本地文件损坏时进入只读状态并保留原文件。
- Mikansei v1 JSON 备份合并导入和导出。保持事项编号，保留较新的记录和尚未迁移的原生字段，包括提醒设置、日历关联、日历选择与课表。
- 电脑快捷键：⌘ / Ctrl + N 添加；⌘ / Ctrl + F 搜索。原生文件选择与保存窗口用于备份。
- 设置里的版本号直接读取安装包，包含构建编号。

## 迁移进度

| 能力 | 本轮状态 |
| --- | --- |
| 清单、Checklist、完成 / 历史、排序、快速添加 | 已迁移 |
| 日程起止时间、全天、月历、长按添加 | 已迁移基础操作；尚未接入 Apple 日历 |
| 循环规则、完成后产生下一次事项 | 已迁移；月历尚未预展开未来循环实例 |
| 专注计时、本机保存、JSON 备份 | 已迁移 |
| iOS、macOS 原生文件桥接 | 本机读写与版本接口通过集成测试；系统文档窗口已实现，未自动化操作 |
| Android 工程和原生文件桥接 | 已加入源码；本机缺少 Android SDK，尚未构建或真机验证 |
| 系统弹窗、AlarmKit 闹钟、铃声与持续催办 | 后续接入；本版 DDL 暂不触发系统提醒 |
| 课表编辑、ICS / CSV、课后作业登记 | 后续接入；备份中的课表记录会保留 |
| Apple 日历来源选择、自动导入和反向录入 | 后续接入；备份中的日历设置与事件关联会保留 |
| 主屏幕 / 锁屏小组件、正在做与 DDL 实时活动 | 后续保留原生扩展并接入 Flutter 数据 |
| iCloud Drive 同一 Apple ID 自动同步 | 后续接入原有同步协议；本版使用独立本机数据与手动备份 |
| QQ 消息自动获取或辅助解析 | 本轮未迁移 |

这些原生功能仍可在原版 Mikansei 中使用。测试版尚未代替原版作为唯一提醒工具。

## 在 Mac 上试用

当前工作区已有 Flutter 3.47.7 开发工具和构建产物。双击本目录的 **`打开Mac测试版.command`** 会构建、复制到工作区的 `Mikanseta-macOS.app` 并打开。数据保存在 App 的应用支持目录中，更新应用包不会清空数据。

第一次试用没有示例事项。在原版 Mikansei 的设置导出 JSON，再在测试版的设置导入，即可比较同一批事项。

## 安装到 iPhone

1. 在 Xcode 打开 **`ios/Mikanseta.xcworkspace`**，选择 `Mikanseta`，在 Signing & Capabilities 中选择自己的 Personal Team，保持自动签名。
2. 连接并解锁手机，确认信任这台 Mac。
3. 双击 **`安装到iPhone.command`**。脚本只安装 Mikanseta，保留原版 Mikansei。

本轮沿用已有 Team；新 App 的签名需要 Xcode 账号与对应描述文件。2026-10-13 已完成 Release 自动签名并安装到 XYLiPhone，手机上的版本为 0.1.0 (1)，原版 Mikansei 0.3.0 (4) 同时保留。安装后手机锁定，系统拒绝自动启动；解锁后可直接打开 Mikanseta。iPhone 模拟器已经构建并验证。

免费签名的有效期与可安装数量由 Apple 管理；安装失败时脚本显示实际原因，不会卸载其他 App。

Xcode 工程、运行方案和 App 目标均名为 `Mikanseta`。源码目录 `ios/Runner/` 保留 Flutter 模板的路径，供插件注册代码自动生成；这不会影响 App 名称。直接使用 Flutter 构建、运行或测试 iOS 时，加上 `--flavor Mikanseta` 选择该方案；一键安装脚本已包含这一参数。

## 数据边界

| 平台 | 安装标识 | 本地数据 |
| --- | --- | --- |
| iOS | `com.personal.mikanseta` | App 沙盒应用支持目录的 `Mikanseta/entries.json` |
| macOS | `com.personal.mikanseta.macOS` | App 沙盒应用支持目录的 `Mikanseta/entries.json` |
| Android | `com.personal.mikanseta` | App 私有目录的 `Mikanseta/entries.json` |

备份导入会复制并合并数据，两端的后续编辑不会自动共享。课表与日历配置在备份中保留，但不会在本轮触发原生服务。原设备的 `replica` 同步副本不会随备份复制或回传；原版导入时由原版重建本机同步记录，避免复用另一个设备的同步身份。本版不写入原版 iCloud 同步文件夹。

原版日期使用 UTC ISO 8601 整秒字符串，测试版导出保持这一格式；连续编辑保证更新时间递增，避免备份合并时丢失同一秒内的改动。导出已与原版 `EntryArchive.decode` 实际往返验证，详见 [验证记录](VALIDATION.md)。

## 开发与验证

已验证版本为 Flutter **3.47.7** / Dart **3.13.5** / Xcode **26.5**。版本固定在 `.flutter-version`，依赖固定在 `pubspec.lock`。

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
# 安装并配置 Android SDK 后：
./Scripts/flutter.sh build apk --debug
```

新机器可按 [Flutter 安装文档](https://docs.flutter.dev/install/manual) 安装本项目固定版本，再设置 `FLUTTER_SDK`。iPhone 测试需 iOS 15 或更新，Mac 构建目标为 macOS 12 或更新。Mac 发布包同时包含 x86_64 和 arm64，本轮运行验证使用 Intel Mac；Apple Silicon 运行尚未实测。

### 代码组织

- `lib/src/domain.dart`：事项、排序、循环、计时计算、备份验证和合并；纯 Dart，可单独验证。
- `lib/src/store.dart`：操作状态、串行保存、失败重试；通过可替换存储接口调用平台能力。
- `lib/src/app.dart` / `editor.dart` / `theme.dart`：自适应界面、录入表单和牛皮浅棕主题。
- `native/Apple/NativeArchiveBridge.swift`：iOS 和 Mac 共用文件桥接；耗时读写在后台队列，iPhone 写入受后台任务保护。
- `android/.../MainActivity.kt`：私有原子文件、系统文档选择与版本信息。
- `test/`、`integration_test/`：数据规则、手机 / 电脑界面和真实原生存储测试。
- `Scripts/verify-backup.sh`：使用原版 Swift 核心生成备份，经 Dart 编辑，再交回原版解码器验证。

后续平台能力从桥接层接入；清单与交互代码继续共享。提醒、日历、WidgetKit / ActivityKit 扩展和同步协议将分别迁移，不把系统服务混入界面代码。
