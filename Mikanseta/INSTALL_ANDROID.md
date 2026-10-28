# Mikanseta 安卓测试版

## 在手机上安装

将 APK 文件发送到安卓手机，在浏览器或文件管理器中打开。如系统提示，允许该下载来源安装应用，再确认安装。

此版包含清单、卡片内子事项勾选、日程、循环、计时、本地保存与 JSON 备份，以及系统日历按来源导入和系统时钟联动。

0.2.0 (4) 新增日 / 周日历与拖动选时段、课表 / 消息解析，以及 Android 本地提醒、主屏幕小组件和前台响铃。Dart 静态检查、44 项 Flutter 测试、Release 编译和 APK 签名验证通过；本轮没有连接 Android 设备，提醒、小组件和响铃服务仍待实机验证。系统日历编辑结果即时回流尚未实现。跨设备云同步仍未迁移。

## 日历和时钟联动

1. **设置 → 系统日历来源 → 读取日历来源**，允许日历读取权限。只勾选需要的课程、工作等日历；首次所有来源均未选中，节假日不会自行导入。
2. 点击 **保存来源并导入**，导入今天本地零点起 30 天内的事件。可开启 **打开或返回 App 时自动导入**；系统账号自身的下载由日历 App 负责。
3. **事项详情 → 添加到系统日历**：预填标题、备注、地点和执行时段，在系统编辑页选择日历并确认保存；普通事项的 DDL 保留，不当作执行开始时间。取消编辑不会删除本地事项。
4. 导出的日历属于已勾选来源时，下次导入会关联回原事项，不另建待办。已关联事项可点 **查看系统日历**；执行时间、标题、备注和地点的后续来源更新仅应用于未被手动修改的字段，保留 Checklist、完成状态、估时和计时。编辑事项期间暂缓自动导入，关闭编辑页后重试。
5. **事项详情 → 创建系统闹钟 / 系统倒计时**，或 **设置 → 打开系统时钟**。闹钟预填事项名称与时、分，重复、铃声和振动由时钟 App 设置。倒计时支持 1–1440 分钟，与 App 内专注计时独立。

系统闹钟接口只传时、分，不含 DDL 日期，也不会在 DDL 改期、事项完成或删除后自动取消。请在系统时钟确认生效安排。日历与时钟中的记录独立保留；此版不会自动回写本地编辑或删除源事件。若系统没有对应处理应用，会显示错误提示。

取消勾选来源不会清除已经导入的事项；源事件删除后也保留待办供自行核对。在 Mikanseta 删除某次导入事项后，该次事件不会自动加回。重复事件按每次发生分别进入清单，全天事件保留原日历日期。

0.2.0 (4) 还声明 `POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`USE_FULL_SCREEN_INTENT`、`RECEIVE_BOOT_COMPLETED` 和媒体播放前台服务权限，用于提醒、锁屏响铃及重启后恢复。系统可能要求用户单独允许通知、精确闹钟或全屏提醒；相关设备行为尚未实测。日历读取使用 `READ_CALENDAR`，新增 / 编辑仍通过系统日历界面由用户确认。

系统日历编辑页结束后，App 当前不能即时读取其结果；需要所选来源在后续打开或返回时同步。尤其在未选择日历来源时，不会即时建立或更新本地关联。

测试限制：导入和系统时钟已在安卓模拟器操作验证；该测试镜像自带 Calendar 缺少新增页组件且详情页有内部崩溃，完整系统日历编辑保存仍需真机验证。详见 [验证记录](VALIDATION.md)。

## 安装包信息

当前版本为 **0.2.0 (4)**，包名 `com.personal.mikanseta`，最低 Android 7.0（API 24），目标 API 36。通用 APK 包含 ARM64、32 位 ARM 和 x86_64；使用专用发布证书签名。实际运行验证范围见 [VALIDATION.md](VALIDATION.md)。

本轮于 **2026-10-16 11:10 +0800** 重新构建并导出 APK，大小 55.9 MB。SHA-256 为 `b463a8de2d1c03b34dbe70b6bc0908f94cd405a8f0d1ac0e33e31c655d9b1d63`；签名验证通过 APK Signature Scheme v2。完整验证范围见 [VALIDATION.md](VALIDATION.md)。

## 重新构建

构建脚本从源码仓库及其祖先目录向上查找 `.toolchains/`，不会修改全局 Java 或 Flutter 设置。也可设置 `MIKANSEI_TOOLCHAINS_DIR` 指定工具链根目录。双击 `生成安卓安装包.command`，或执行：

```sh
./Scripts/build-android.sh
```

原始输出为 `build/app/outputs/flutter-apk/app-release.apk`，同时默认复制到源码仓库根目录旁的 `../Releases/Mikanseta/Android/<version+build>/`，按版本命名并附 SHA-256 文件。例如当前 `0.5.2+15` 输出为 `../Releases/Mikanseta/Android/0.5.2+15/Mikanseta-0.5.2+15-android.apk`。该相对路径以源码仓库根目录为基准，不随命令当前目录变化。这是包含多个 CPU 架构的单文件安装包，版本号读取 `pubspec.yaml`。`MIKANSETA_OUTPUT_DIR` 可指定精确的 APK 输出目录；`MIKANSEI_RELEASES_DIR` 可更换 `Releases/` 根目录。

其他电脑需要 Java 21、Android SDK（API 36、Build Tools 36.0.0、NDK 28.2.13676358）及本项目固定版本的 Flutter。可以用 `JAVA_HOME`、`ANDROID_HOME` 和 `FLUTTER_SDK` 指定现有工具。

将 `android/key.properties.example` 复制为 `android/key.properties`，填写本地发布密钥信息。Release 构建使用发布签名，不回退到调试签名。后续更新需沿用该发布密钥。

本工作区首次创建的密钥与密码单独保存在工具链目录的 `mikanseta-signing/` 中，请另行备份；它们不进入 Git 仓库，也不应随 APK 分发。

签名验证可使用 Android SDK 的 `apksigner verify --verbose`。实际构建和运行结果记录在 [VALIDATION.md](VALIDATION.md)。

校验时需要把 `JAVA_HOME` 指向实际 JDK 21 的 Home 目录，并确认 `$JAVA_HOME/bin/java` 可用。设置后 `apksigner verify` 退出码为 0，本轮 APK 已通过 APK Signature Scheme v2 校验。日志见 [VALIDATION.md](VALIDATION.md)。
