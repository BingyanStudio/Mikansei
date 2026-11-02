# Mikanseta iOS TestFlight 准备情况

更新日期：2026-11-02。本文只记录 Mikanseta Flutter iOS App 的签名与 TestFlight 准备状态，不把它与原生 Mikansei 的版本或 App Store Connect 记录混为一谈。

## 结论

Mikanseta `0.7.0 (18)` 有 iOS App + Widget 的 unsigned Release 构建记录，但尚无签名归档、上传或 TestFlight 分发证据；Mikanseta 尚未上传 TestFlight。因此目前不能称它已可通过 TestFlight 安装。原生 Mikansei 的 Xcode Cloud 流程只覆盖原生工程；它的成功记录不能证明 Mikanseta 已构建或上传。

## 两个 iOS App 的身份

| App | Bundle ID | 工程中的 Team | 版本 / 构建号 | 当前证据 |
| --- | --- | --- | --- | --- |
| 原生 Mikansei | `net.bingyan.KikuchiHeinrich.mikansei` | `6PVAPR495F`（原生发布资料记录） | 源码 `0.7.0 (14)`；用户确认 TestFlight 安装 `0.7.0 (8)` | Xcode Cloud 对提交 `cfe17a1d1cb04fff7de86106f469362a338a966d` 的 `Mikansei | Internal TestFlight Build | Archive - iOS` check 为 `SUCCESS`。这只确认归档 check 成功，不能单独证明它与 Build 8 一一对应。 [查看归档记录](https://appstoreconnect.apple.com/teams/69a6de96-390e-47e3-e053-5b8c7c11a4d1/apps/6827965680/ci/builds/512d9cb8-3cd6-490e-b206-5bd0ff5378f1/action/47b42543-8bda-46f8-a1d8-1c6465bc0b95) |
| Mikanseta（Flutter） | `com.personal.mikanseta` | `7JMRL8X34C`（当前 Xcode 工程设置） | `0.7.0 (18)` | unsigned App + Widget Release 已构建；没有签名、上传或 TestFlight 成品记录。 |
| Mikanseta Widget 扩展 | `com.personal.mikanseta.Widgets` | `7JMRL8X34C`（当前 Xcode 工程设置） | `0.7.0 (18)` | 随 Mikanseta App 一起构建；采用共享 Keychain entitlement。 |

工程中的 Team ID 只是配置值，不证明该团队当前可签名或具有 App Store Connect 分发权限。Mikanseta 配置的 Team `7JMRL8X34C` 与原生发布资料中的 Team `6PVAPR495F` 不同；本说明没有核实任一团队的账户权限。

## 工程与现有 Cloud 流程

- Mikanseta 主 App 与 Widget 都设为 Automatic Signing；共享 Keychain entitlement 在 `Mikanseta/ios/Runner/Mikanseta.entitlements`。主 App 已声明 `NSSupportsLiveActivities=true`。
- `Documentation/TestFlight/XCODE_CLOUD.md` 中的现有 Cloud 交接绑定原生 `Mikansei.xcodeproj` / `Mikansei` scheme、原生 Bundle ID 及 App Store Connect App ID `6827965680`。根目录 Cloud 脚本也会生成原生工程并只检查 `Mikansei` 与 `MikanseiWidgets`。这不能作为 Flutter `Mikanseta.xcodeproj` 已接入该 Cloud 流程的证据。
- Mikanseta 的 0.7.0+18 iOS 记录是 unsigned 编译成功，不代表签名成功。签名归档、上传、Apple 处理及 TestFlight 安装是后续独立结果。
- Mikanseta 当前有番茄主屏幕 Widget、截止事项 Live Activity 和提醒 Live Activity；0.7.0+18 没有番茄专注 Live Activity。原生专注实时活动的源码改动与本次 `0.7.0 (18)` 发布包分开验证，不能据此声称已进入用户安装的原生 `0.7.0 (8)`。

## 发布前需要确认

1. 决定为 Mikanseta 使用哪个开发者团队，并由团队持有人确认该 Team 有权为 `com.personal.mikanseta` 签名与分发。可以使用与原生 Mikansei 相同的 Bingyan 团队，但仍须为 Mikanseta 使用单独的 App Store Connect App 记录；现有原生记录 `6827965680` 的 Bundle ID 不匹配，不能直接用它上传 Mikanseta。
2. 在该团队下确认或建立 Bundle ID 为 `com.personal.mikanseta` 的独立 App Store Connect 记录，并确认 Widget 扩展标识可在同一团队下签名。不要仅凭项目中的 Team 字段推断注册或访问权限。
3. 使用 `Mikanseta/ios/Mikanseta.xcworkspace` 与 `Mikanseta` scheme 做 Team 下的 Release 签名归档，再上传。上传前核对主 App、Widget 的 Bundle ID、版本、构建号与签名；按实际上传结果确认 Apple 处理完成，并在 Mikanseta 自己的 TestFlight 页面核对构建和测试组。
4. 原生 Mikansei 与 Mikanseta 的本机安装身份和数据目录分开。迁移前保留原生 App 与备份；优先在非重要副本上通过 JSON 备份导入或已配置的共享账号同步验证数据，再对照条目和设置。确认数据完整后再决定是否继续使用两款 App。

Apple 说明：上传前需在 App Store Connect 添加 App；上传的 Bundle ID 与版本号用于关联 App 记录，且必须与 Xcode 工程匹配。首次上传后还需等待 Apple 处理，构建才会出现在后台。[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) · [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
