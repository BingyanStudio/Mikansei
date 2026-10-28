# 原生 Mikansei：隐私与分发资料依据

核对日期：2026-10-28。适用原生 Mikansei iOS App、Widgets 和云账号服务；原生 Mac 客户端使用同一云账号项目。

## App Store Connect App Privacy

不得再选择 **“不从此 App 收集数据 / Data Not Collected”**。登录用户选择启用云账号后，App 会向与 Mikanseta 共用的 Supabase 项目发送认证请求，并上传账号同步所需内容。未登录时，用户内容留在本机，不会上传到云账号服务；App Privacy 仍应按此应用中可选云功能实际涉及的数据披露。

当前建议至少申报以下类型，目的为 **App Functionality**，均与用户关联，且不用于 Tracking：

| Apple 数据类型 | 原因 |
| --- | --- |
| Contact Info → Email Address | 邮箱验证码登录、账号标识和找回/管理账号 |
| Identifiers → User ID | Supabase 账号用户 UUID，用于隔离并定位该用户的共享归档 |
| User Content → Other User Content | 用户选择登录后同步的待办、日程、笔记、Checklist、课表、完成状态和计时记录 |
| Identifiers → Device ID | 跨设备同步标识及可能用于日历设备关联的标识 |
| Other Data → Other Data Types | Supabase 认证网络请求和安全日志中未被其他分类覆盖的数据 |

上传内容和同步标识与登录用户关联。公开填写时应按 App Store Connect 当前的数据类型与目的选项映射上述分类；如实际请求、归档字段或服务方日志有变化，应先重新检查。Apple 指引要求按 IP 地址的实际用途和保留情况映射相关类别；保留的 IP 可能还需要申报 Device ID、诊断或位置类数据，而不是一概归入 Other Data Types。不要把“可选”“HTTPS”或“RLS”解释成没有数据收集或内容不可被项目管理员读取。

当前主 App 隐私清单声明 Email Address、User ID、Other User Content、Device ID 和 Other Data Types：`NSPrivacyTracking=false`、与用户关联、用途为 App Functionality。Widgets 不访问云账号网络，保持无收集数据类型的声明。请在归档前对照实际源码、App Store Connect 标签和隐私政策，确认三者一致。

## 云服务和安全说明

云账号可选，邮箱 OTP 登录成功并经用户确认合并后开始同步；同一 Auth 用户在 `mikanseta_archives` 中对应一条共享归档。Mikansei 与 Mikanseta 共用该项目和数据记录。首次请求验证码时，新邮箱可自动创建账号，完成验证码验证后才能登录。客户端使用 public/anon 客户端配置；该公开 key 可嵌入 App，不是管理凭据。数据隔离由服务端 RLS 等策略承担，公开 key 本身不阻止获授权项目管理员访问数据。

云数据通过 HTTPS 传输，但没有端到端加密。不要声称项目管理员无法读取已存储内容。Supabase 处理认证请求和安全日志；日志、备份及保留周期依服务方配置和政策。

账户删除使用 `mikansei_delete_account` RPC，SQL 脚本位于 [`Documentation/supabase-native-account.sql`](../supabase-native-account.sql)。函数仅凭当前认证用户 `auth.uid()` 确定删除对象，不接收调用者指定的目标账号。它会删除共享 Auth 用户及其云归档，影响 Mikansei 和 Mikanseta 登录。当前 Supabase Auth 与共享归档表已存在；仅此删除 RPC 的 SQL 尚未部署，故不要声称 App 内删除已可用。本轮未实际验证邮件投递、登录、同步或删除。

其他设备的离线副本不会自动清除，既有 JWT 可能在到期前仍有效。Supabase 备份和安全日志依服务提供方规则保留。登出会保留本机与服务端归档。

## 隐私清单、UserDefaults 与受限 API

| Target | 声明 |
| --- | --- |
| Mikansei | `NSPrivacyTracking=false`；收集 Email Address、User ID、Other User Content、Device ID、Other Data Types；均与用户关联，用途为 App Functionality；使用 `UserDefaults`，理由 `CA92.1` |
| MikanseiWidgets | `NSPrivacyTracking=false`；不访问云账号网络服务、无收集数据类型；本扩展直接源码未使用 required-reason API，API 数组为空 |

`CA92.1` 表示读写仅此 App 自身可访问的 UserDefaults。原有用途包括外观和视图偏好、同步文件夹书签、闹钟记录与实时活动设置。云账号令牌保存在系统钥匙串，不因而增加 UserDefaults 的用途声明。

文件同步源码读取 `isRegularFileKey`、`ubiquitousItemDownloadingStatusKey`；未因使用 FileManager 就添加无关的受限 API 理由。小组件摘要经 Keychain Sharing 共享，不是 App Groups 的 UserDefaults，不应因此填写 App Groups 理由 `1C8F.1`。

## 加密出口合规

账号同步使用 HTTPS 和系统提供的 TLS；系统钥匙串保护本机登录令牌。云内容没有端到端加密。当前 `App/Info.plist` 声明 `ITSAppUsesNonExemptEncryption=false`。此项应由发布者对照实际上传构建、所用系统网络能力和 Apple 当前出口合规问卷复核；不可把“无自定义密码算法”写成“网络未加密”或“端到端加密”。

## 原生源码与服务端证据

| 内容 | 位置 |
| --- | --- |
| 本机档案与保存 | `App/EntryStore.swift`、`Sources/MikanseiCore/Archive.swift` |
| 用户选择的文件夹同步 | `Sync/FolderSyncManager.swift`、`Sources/MikanseiCore/FolderSyncTransport.swift` |
| 邮箱账号、会话与云归档同步 | `Sync/CloudAccountManager.swift`、`Sync/CloudAccountSettings.swift` |
| 账号删除函数 | `Documentation/supabase-native-account.sql` |
| 日历、通知、AlarmKit | `App/CalendarSyncManager.swift`、`App/NotificationManager.swift`、`App/NativeAlarmScheduler.swift` |
| Widgets 隐私声明 | `Widgets/PrivacyInfo.xcprivacy` |

管理员对 Auth 配置的只读检查返回 HTTP 200，`external.email=true`、`disable_signup=false`。Supabase Auth 和共享归档表已存在；该配置检查不代表已实际发送邮件、登录或同步。当前仅删除 RPC 的 SQL 尚待项目管理员授权部署；本轮未对真实邮箱、设备或在线账号执行验收。

## Apple 官方核对入口

以下链接于 2026-10-28 核对；Apple 规则可能继续更新：

- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [App privacy data types](https://developer.apple.com/app-store/app-privacy-details/#data-types)
- [TestFlight 测试资料](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
- [外部测试与公开链接](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [Required-reason API 与理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [出口合规概览](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [审核指南](https://developer.apple.com/app-store/review/guidelines/)

发布者应在提交时检查 App Store Connect 的最新字段、隐私披露和构建要求，并以最终归档及服务方实际配置为准。
