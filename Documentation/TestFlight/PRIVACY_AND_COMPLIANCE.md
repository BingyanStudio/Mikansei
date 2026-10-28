# 原生 Mikansei：隐私与分发资料依据

核对日期：2026-10-28。适用原生 iOS App 与 Widgets；不适用 Mikanseta、macOS 或后续新增在线服务的版本。

## App Privacy 填写依据

当前原生版本没有账号注册、自建后端、在线消息解析、广告 SDK 或第三方统计 SDK。日历和用户内容在设备上处理；选择同步文件夹后，由用户选定的文件提供方同步。开发者不因启用此功能而获得这些文件。

据此，对当前 App 的自动业务数据收集，App Store Connect 的 App Privacy 可按 **“不从此 App 收集数据 / Data Not Collected”** 填写。此判断针对当前源码和构建中包含的组件，不表示数据不会交由 iCloud Drive、系统日历或其他用户选择的服务处理。发布者应核对实际上传构建与本交接源码一致；如新增 SDK、服务器或收集行为，应重新填写。

用户主动通过外部邮件提供的支持资料，以及 Apple TestFlight 平台提供的诊断和反馈，在隐私政策中单独说明。不得将“Data Not Collected”改写为“开发者在任何情况下都不会收到任何资料”。

## 隐私清单

| Target | 声明 |
| --- | --- |
| Mikansei | `NSPrivacyTracking=false`；无跟踪域名、无自动收集的数据类型；使用 `UserDefaults`，理由 `CA92.1` |
| MikanseiWidgets | `NSPrivacyTracking=false`；无跟踪域名、无自动收集的数据类型；本扩展直接源码未使用 required-reason API，API 数组为空 |

`CA92.1` 表示读写仅此 App 自身可访问的 UserDefaults。对应代码为外观和视图偏好、同步文件夹书签、闹钟记录、实时活动设置。

文件同步源码读取 `isRegularFileKey`、`ubiquitousItemDownloadingStatusKey`；本次未发现文件时间戳、磁盘容量、系统启动时间等受限 API 的直接调用，不因使用 FileManager 就添加无关理由。

小组件摘要通过 **Keychain Sharing** 共享，不是 App Groups 的 UserDefaults；不应因此填写 App Groups 理由 `1C8F.1`。

## 加密出口合规

当前源码未实现自定义加密算法，也未打包第三方密码库；使用系统提供的钥匙串、文件保护和用户选择的系统文件服务。`App/Info.plist` 声明 `ITSAppUsesNonExemptEncryption=false`。

这表示当前版本不使用需额外申报的非豁免加密，并非声称系统完全不使用加密。若后台仍要求回答具体问卷，请按“仅使用 Apple 操作系统提供的加密能力”的实际情况作答；后续新增加密实现需重新核对。

## 原生源码证据

| 内容 | 位置 |
| --- | --- |
| 无外部 Swift Package 依赖 | `Package.swift` |
| 本机档案与保存 | `App/EntryStore.swift`、`Sources/MikanseiCore/Archive.swift` |
| 用户选择文件夹及副本交换 | `Sync/FolderSyncManager.swift`、`Sources/MikanseiCore/FolderSyncTransport.swift` |
| 日历授权、导入和确认写入 | `App/CalendarSyncManager.swift`、`App/CalendarSyncView.swift` |
| 本地消息解析 | `App/MessageImportView.swift`、`Sources/MikanseiCore/MessageParser.swift` |
| 本地通知、AlarmKit | `App/NotificationManager.swift`、`App/NativeAlarmScheduler.swift` |
| 小组件共享摘要 | `Shared/WidgetSnapshotStore.swift`、`Sources/MikanseiCore/WidgetSnapshot.swift` |
| 权限说明、实时活动、出口合规 | `App/Info.plist` |

## Apple 官方核对入口

以下链接于 2026-10-28 核对；Apple 规则可能继续更新：

- [TestFlight 测试资料](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
- [外部测试与公开链接](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [App Privacy 说明](https://developer.apple.com/app-store/app-privacy-details/)
- [Required-reason API 与理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [出口合规概览](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [Apple 上传要求](https://developer.apple.com/news/upcoming-requirements/)
- [审核指南](https://developer.apple.com/app-store/review/guidelines/)

截至核对日，Apple 要求上传使用 Xcode 26 或更高版本及相应 iOS 26 SDK 或更高版本；原生 Mikansei 的最低运行系统 iOS 17 满足当前 iOS 13 或更高的最低部署要求。构建工具版本与最低运行系统是两个不同设置。
