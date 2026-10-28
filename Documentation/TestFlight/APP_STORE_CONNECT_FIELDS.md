# App Store Connect 与 TestFlight 交接

面向原生 SwiftUI **Mikansei** iOS 应用。产品文案已经准备好；发布者须使用自己的 Apple Developer 和 App Store Connect 账号完成账号侧资料、签名及分发操作。

## 已准备的产品字段

| App Store Connect 字段 | 填写内容 |
| --- | --- |
| Platform | iOS |
| App Name | Mikansei |
| Primary Language | Chinese (Simplified) |
| SKU | `MIKANSEI-IOS-001` |
| Version / Build | `0.4.2 (10)`，归档后核对实际二进制 |
| Minimum iOS Version | iOS 17.0 |
| TestFlight Group | `Friends Beta` |
| Feedback Email | `kikuchiheinr@qq.com` |
| Privacy Policy URL | [Mikansei Privacy Policy](https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/PRIVACY_POLICY.md) |
| Support URL | [Mikansei Support](https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/SUPPORT.md) |

应用支持 iPhone 和 iPad。日历、通知、AlarmKit 闹钟和实时活动都是可选的系统集成；拒绝授权不影响本地清单和笔记。应用无需登录，没有自有后端、广告 SDK、分析 SDK、付费功能或 App 内购买。数据默认保存在本机；只有用户选择文件夹后才开始 iCloud Drive 文件夹同步。

## 发布者账号侧字段

这些信息只能由实际发布者从自己的 Apple 账号获取或填写，不得代造，也不要把账号凭据放进交接包：

- **Team ID：**使用实际签名团队的 Team ID。
- **App Store Connect Apple ID (App Record ID)：**创建 App 记录后由 Apple 分配；记录在发布者自己的构建/发布记录中。
- **Beta App Review Contact：**填写发布者本人的真实名、姓、电话号码和邮箱。
- **App Bundle ID / Widget Extension Bundle ID：**先按 `README.md` 中的 `BUILD_GUIDE.md`，使用发布者自己的 Team ID 运行构建助手；将助手输出的 `PREPARED_APP.json` 里主 App 与 Widget extension 的准确标识符抄入记录和构建设置。助手默认主标识为 `com.personal.mikansei.beta.<team-id-lowercase>`，Widget 标识为主标识加 `.widgets`。请在自己的团队中确认这两个生成标识可用。
- 如果准备记录或签名时发现冲突，使用构建助手的自定义 Bundle ID 选项生成独立标识，并按新的 `PREPARED_APP.json` 更新记录；不要直接修改原工程中的 Bundle ID。
- 使用发布者自己的团队、签名证书/描述文件与 App Store Connect 账号完成归档和上传。不要在文档中放入密码、API 密钥或签名私钥。

App Store Connect 只为主应用创建一条 App 记录，并在其 Bundle ID 字段选择 `bundle_id`。`widget_bundle_id` 用于开发者团队中的扩展标识和签名，不需要再为 Widgets 创建第二条 App Store Connect 记录。

## TestFlight 文案

- **Beta App Description：**从 `BETA_DESCRIPTION.txt` 复制简体中文正文；如添加英文语言版本，使用 `BETA_DESCRIPTION_EN.txt`。
- **What to Test：**为 `0.4.2 (10)` 从 `WHAT_TO_TEST.txt` 复制简体中文正文；如需英文版本，使用 `WHAT_TO_TEST_EN.txt`。每份文件均可单独粘贴。
- **Feedback Email：**`kikuchiheinr@qq.com`。
- **Beta App Review Information → Sign-in required：**No。无需测试账号或密码。
- **Beta App Review Information → Contact：**填写本文件前述发布者真实审核联系人。
- **Beta App Review Information → Notes：**按审核语言使用 `REVIEW_NOTES_EN.txt` 或 `REVIEW_NOTES_ZH.txt`。
- **External Testing Group：**创建 `Friends Beta`。构建处理完成且所需 TestFlight Beta Review 完成后，再邀请外部测试者。
- **Privacy Policy URL / Support URL：**使用上方公开链接。

## 构建与 TestFlight 范围

截至 2026 年 10 月 28 日，Apple 上传构建要求 Xcode 26 或更新版本，并使用 iOS 26 SDK 或更新版本。项目所有者本机为 Xcode 26.5；归档前仍须确认发布者构建环境选择的 Xcode 和 SDK。

本资料不包含已签名的归档或 IPA，也不表示签名、上传、处理或 Beta Review 已成功。目标工程版本为 `0.4.2 (10)`；上传前以实际归档中的版本和构建号为准。

正式提交 App Store 时再准备商店截图即可。本 TestFlight 交接不要求先准备正式商店截图、定价或 App 内购买。

## Apple 官方说明

- [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)
- [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
