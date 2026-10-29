# App Store Connect 与 TestFlight 交接

面向原生 SwiftUI **Mikansei** iOS 应用。产品文案已准备；发布者须使用自己的 Apple Developer 和 App Store Connect 账号完成账号侧资料、签名及分发操作。

## 产品字段

| App Store Connect 字段 | 填写内容 |
| --- | --- |
| Platform | iOS |
| App Name | Mikansei |
| Primary Language | Chinese (Simplified) |
| SKU | 沿用既有应用记录；首次新建时才使用 `MIKANSEI-IOS-001` |
| Version / Build | `0.5.0 (11)`（本轮资料目标；上传前核对最终归档） |
| Minimum iOS Version | iOS 17.0 |
| TestFlight Group | `Friends Beta` |
| Feedback Email | `kikuchiheinr@qq.com` |
| Privacy Policy URL | [Mikansei Privacy Policy](https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/PRIVACY_POLICY.md) |
| Support URL | [Mikansei Support](https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/SUPPORT.md) |

应用支持 iPhone 和 iPad；原生 Mac 版使用同一可选云账号服务。本机功能可离线使用。用户主动选择邮箱 OTP 并在首次登录前确认后，才会将本机内容与该邮箱账号已有的云档案合并；首次请求验证码时，新邮箱可自动创建账号，完成验证码验证后才能登录。Mikansei 与 Mikanseta 共用 Supabase 项目和 `mikanseta_archives` 账号归档；未登录内容不上传。日历、通知、AlarmKit 闹钟、实时活动和 iCloud Drive 文件夹同步均为可选，其中 iCloud 文件夹同步独立于云账号。

## App Privacy 填写

请勿填写 **Data Not Collected**。根据当前隐私清单，至少选择下列类型，目的为 App Functionality，均与用户关联，Tracking 选 No：

- **Contact Info → Email Address**
- **Identifiers → User ID**
- **User Content → Other User Content**
- **Identifiers → Device ID**
- **Other Data → Other Data Types**

具体用途和范围见 [PRIVACY_AND_COMPLIANCE.md](PRIVACY_AND_COMPLIANCE.md)。发布者应核对提交时 App Store Connect 的现行分类、归档中实际 payload 和服务方日志处理。未登录用户的内容不会上传云账号服务，但这不把含可选账号功能的 App 变成“未收集数据”。

## 发布者账号侧字段

以下信息涉及实际发布账号，烦请发布者根据自己的 Apple 账号获取或填写；账号凭据由发布者自行保管，无需放进交接包：

- **Team ID：**使用实际签名团队的 Team ID。
- **本次 Bingyan 发布身份：**Team `6PVAPR495F`；App ID `6827965680`；主 Bundle ID `net.bingyan.KikuchiHeinrich.mikansei`；Widgets Bundle ID `net.bingyan.KikuchiHeinrich.mikansei.widgets`。本包已设置这些值，请继续使用已有应用记录。
- **App Store Connect Apple ID (App Record ID)：**其他团队首次创建 App 记录后由 Apple 分配；本次沿用上方既有记录。
- **Beta App Review Contact：**填写发布者本人的真实名、姓、电话号码和邮箱。
- **其他团队首次准备源码时：**按 `BUILD_GUIDE.md` 运行构建助手，将 `PREPARED_APP.json` 中主 App 与 Widget extension 的准确标识符填入记录和构建设置。助手默认主标识为 `com.personal.mikansei.beta.<team-id-lowercase>`，Widget 标识为主标识加 `.widgets`。本次 Bingyan 专用包无需改用默认 Beta ID。
- 如果生成标识冲突，使用构建助手的自定义 Bundle ID 选项，并按新的 `PREPARED_APP.json` 更新记录；不要直接修改原工程中的 Bundle ID。
- 使用发布者自己的团队、签名证书/描述文件与 App Store Connect 账号完成归档和上传。
- 源码中的 Supabase URL 和 public/anon 客户端 key 是公开客户端配置，可以嵌入 App；不要把 service-role key、项目管理密钥、数据库密码或签名私钥放入客户端、交接包或公开资料。服务端 RLS 负责按账号隔离，public key 不代表数据对项目管理员保密。

App Store Connect 只为主应用创建一条 App 记录并选择 `bundle_id`。`widget_bundle_id` 用于开发者团队中的扩展标识和签名，不需另建 Widgets App Store 记录。

## TestFlight 文案与审核信息

- **Beta App Description：**从 `BETA_DESCRIPTION.txt` 复制简体中文正文；英文版本使用 `BETA_DESCRIPTION_EN.txt`。
- **What to Test：**为 `0.5.0 (11)` 从 `WHAT_TO_TEST.txt` 复制简体中文正文；英文版本使用 `WHAT_TO_TEST_EN.txt`。每份文件均可单独粘贴。
- **Feedback Email：**`kikuchiheinr@qq.com`。
- **Beta App Review Information → Sign-in required：**No（本机核心功能无需登录；云账号同步为可选功能且需要邮箱 OTP）。不要描述成所有功能都无需登录。
- **Beta App Review Information → Contact：**填写本文件前述发布者真实审核联系人。
- **Beta App Review Information → Notes：**按审核语言使用 `REVIEW_NOTES_EN.txt` 或 `REVIEW_NOTES_ZH.txt`。审核本机功能建议先不登录。若希望审核云功能，请发布者先准备审核者可访问的专用邮箱和可用验证码投递方式；没有密码，也不能假定审核者可以访问发布者私人邮箱或一定能收到 OTP。Supabase Auth 与共享归档表已存在；本轮未在线验收邮件投递、登录或同步，账号删除 RPC 尚未部署。
- **External Testing Group：**创建 `Friends Beta`。构建处理完成且所需 TestFlight Beta Review 完成后，再邀请外部测试者。
- **Privacy Policy URL / Support URL：**使用上方公开链接。

## 构建与 TestFlight 范围

截至 2026 年 10 月 28 日，Apple 上传构建要求 Xcode 26 或更新版本，并使用 iOS 26 SDK 或更新版本。项目所有者本机为 Xcode 26.5；归档前仍须确认发布者构建环境选择的 Xcode 和 SDK。

本轮 `0.5.0 (11)` 已通过 iOS 无签名 Release 归档及 Mac 通用构建。此前记录的 `0.4.2 (10)` 属于历史结果。本资料不包含已签名归档或 IPA，也不表示签名、安装、上传、云端在线验收或 Beta Review 已成功。上传前以实际分发归档中的版本和构建号为准。

开放云账号测试前，请确认现有归档表的 RLS 和邮箱 OTP 邮件投递，并准备审核者可访问的测试邮箱。App 内账号删除须由项目管理员授权并部署 [原生云账号 SQL](../supabase-native-account.sql)，其中的 `mikansei_delete_account` RPC 当前尚未部署；部署前不要声称应用内删除可用。正式提交 App Store 时再准备商店截图即可；本 TestFlight 交接不要求先准备正式商店截图、定价或 App 内购买。

## Apple 官方说明

- [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)
- [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
