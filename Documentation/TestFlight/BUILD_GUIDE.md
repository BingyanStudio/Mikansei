# Mikansei iOS TestFlight 交接指南

本指南用于发布者使用自己的 Apple Developer 账号，为原生 iOS App 生成并上传 TestFlight build。项目要求 Xcode 26+（含 iOS 26 SDK 或更新版本），本次维护环境为 26.5；macOS 需满足所选 Xcode 版本的官方系统要求。脚本使用 Python 3.9+ 标准库。请先确认 Xcode 已安装 iOS 平台组件，并核对随版本更新的 [Xcode SDK 与系统要求](https://developer.apple.com/xcode/system-requirements/)。

## 1. 解压源码并准备归档

解压交接 ZIP，进入其中包含 `App/`、`Shared/`、`Widgets/` 和 `Scripts/` 的 **`Source/`** 目录；如果直接使用 Git 仓库，则进入仓库根目录。先在 Xcode 中登录发布者自己的 Apple Account，并确认该账号已加入 Apple Developer Program，且有权访问用于分发的 App Store Connect 团队。账号登录及签名凭据请自行保管，交接过程无需提供这些信息。

从 Apple Developer 账号页面复制发布者团队的真实 10 位 Team ID。此处请使用账号页面显示的 Team ID，以便正确配置签名。然后在上述源码根目录执行：

```sh
python3 Scripts/prepare_testflight.py \
  --team '替换为发布者真实的10位Team ID' \
  --output ../Prepared-Mikansei \
  --archive
```

把 Team ID 占位文字替换成实际值再运行。工具会在源码旁新建 `Prepared-Mikansei/`，复制最小原生源码、共享 scheme、生成器和本指南；排除隐藏文件、个人 Xcode 状态及本机配置。目标路径必须不存在或为空，且不能与输入目录重叠。工具只在复制品中写入 Team ID、Bundle ID 和版本信息，不改原工程。

签名归档会从原工程 `Mikansei` App target 的 Release 配置读取版本与 build；当前源码值为 `0.4.2` 和 `10`。如需覆盖 build，可加 `--build-number 11`，App 与 Widget 会同步更新。主 App Bundle ID 默认是 `com.personal.mikansei.beta.<TeamID小写>`，Widget 为主 ID 加 `.widgets`。如需自选主 Bundle ID，可加 `--bundle-id com.example.mikansei.beta`。

发布者也可以省略 `--archive`，只生成准备包和可复制的 `xcodebuild` 命令；随后在自己的 Mac 上运行打印的命令。签名归档使用 Xcode Automatic Signing 和 `-allowProvisioningUpdates`，由发布者的 Xcode 账号创建或更新所需的 provisioning profile。工具不登录 Apple 账号、不上传、不导出 `.p12`、证书私钥或 API key。归档命令、过程输出和失败退出码记录在 `Prepared-Mikansei/build.log`；包内 `PREPARED_APP.json` 列出可复制到 App Store Connect 的 Team、App Bundle ID、Widget Bundle ID、版本和 build number。

## 2. 在 App Store Connect 创建 App 记录

首次上传前，发布者先登录 App Store Connect，在 **Apps** 页面点 **+ > New App** 创建记录，选择 iOS 平台，并将 Bundle ID 设为 `PREPARED_APP.json` 中的 `bundle_id`。填写名称、主要语言和 SKU 后创建记录。不要使用原开发版的 Bundle ID；Beta 使用独立 ID。Apple 的操作说明：[创建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)。

## 3. 在 Xcode Organizer 上传

归档成功后，若 Xcode Organizer 未自动显示该 archive，可在终端打开包内归档：

```sh
open ../Prepared-Mikansei/Mikansei.xcarchive
```

也可以在 Xcode 选择 **Window > Organizer**，选中 `Mikansei.xcarchive`，点 **Distribute App**，选择 **App Store Connect**，再按向导上传。Xcode 显示上传成功后，到 App Store Connect 的 **Apps** 中选择对应 App，打开 **TestFlight**，等待 build 处理完成，再添加内部或外部测试者并发送邀请。Apple 的操作说明：[上传 build](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) · [TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。

如果上传列表里找不到发布者的 App，先确认 App Store Connect 团队、App 记录和 `PREPARED_APP.json` 的 Bundle ID 一致。Beta Bundle ID 是按 Team ID 单独生成的；如果该 App ID 尚未注册，Xcode Automatic Signing 会尝试在发布者授权的团队内注册。

## 4. 团队成员权限

个人会员由本人拥有开发团队。此流程应由账户持有人本人在自己的 Xcode 和 App Store Connect 会话中完成签名、上传和 TestFlight 操作。组织会员可以由 Account Holder 或有相应权限的管理员邀请成员，并按工作需要分配团队角色；具体权限以 Apple 页面和当前团队设置为准：[邀请团队成员](https://developer.apple.com/help/account/access/invite-team-members/) · [App Store Connect 用户与角色](https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users/)。

## 5. 数据迁移与 App 能力

Beta 使用独立 Bundle ID，旧开发版与 Beta 会被系统视为两个 App，Beta 不会自动接管旧 App 的本地数据库。安装前请在旧版 **我的 > 数据与备份 > 导出 JSON 备份**；安装 Beta 后用同一页面的 **导入 JSON 备份** 手动合并。

工程的共享 capability 是 **Keychain Sharing**：App 与 Widget 用同一团队下的共享 Keychain access group。生成器会按新的主 Bundle ID 同步 host 和 keychain suffix。Keychain Sharing 不等于 App Groups；无需为此启用 App Groups。Mikansei 的 iCloud Drive 同步由用户在 App 内选择文件夹，通过系统文件选择器访问；这不要求伪造 CloudKit container 或推送服务配置，也不要为本次 TestFlight 额外开启这些 capabilities。可查阅 Apple 文档：[Keychain Sharing](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps) · [配置 App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) · [SwiftUI 文件导入器](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:))。

## 6. 无签名编译检查（仅维护者）

在没有发布者 Team ID 的情况下，维护者可以从原生源码根目录执行：

```sh
python3 Scripts/prepare_testflight.py \
  --output ../Prepared-Mikansei-Unsigned \
  --unsigned-check
```

这会在复制品中清空 App 与 Widget 的 Team，执行 `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` 的 iOS Release archive，并将完整输出写入 `build.log`。它只能帮助检查编译；无签名归档不能安装到设备，也不能上传或分发到 TestFlight，不能代替发布者 Team 下的签名归档验证。
