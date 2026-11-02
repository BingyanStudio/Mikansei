# 原生 Mikansei 0.7.1 内部 TestFlight 发布记录

日期：2026-11-02
目标分支：`experimental/sync`
源码提交：`49bd08c7ce592b1a0df37355aefdb269dd70f00d`；tag `v0.7.1` 指向同一提交。

## 版本与功能

- 原生 iOS 源码目标：`0.7.1`，build `15`；App Store Connect / TestFlight 实际分发为 `0.7.1 (9)`。云端 build number 可与源码目标不同。
- 保留 Team `6PVAPR495F`、主 Bundle ID `net.bingyan.KikuchiHeinrich.mikansei`、Widget Bundle ID `net.bingyan.KikuchiHeinrich.mikansei.widgets` 以及现有数据路径。
- 新增专注计时 Live Activity，在锁屏与灵动岛显示主题和醒目计时，并提供暂停 / 继续及结束保存入口；手动收起后可从 App 重新显示。现有 DDL Live Activity 维持独立。
- 倒计时、正计时、倒计时到期提示与 ActivityKit 八小时显示边界均列入 TestFlight 检查范围。测试文案见 [中文测试说明](TestFlight/WHAT_TO_TEST.txt) 和 [英文测试说明](TestFlight/WHAT_TO_TEST_EN.txt)。

## 本地无签名构建与核对

Xcode 26.5 / iOS SDK 26.5，scheme `Mikansei`，`Release`，`generic/platform=iOS`，`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`。`xcodebuild archive` 结果为 `ARCHIVE SUCCEEDED`；无签名 archive 大小约 32 MB。

- 归档：`/private/tmp/Mikansei-0.7.1-TestFlight-LunaMax-20261102-archive.xcarchive`
- 完整构建日志：`/private/tmp/Mikansei-0.7.1-TestFlight-LunaMax-20261102-archive.log`
- Xcode result bundle：`/private/tmp/Mikansei-0.7.1-TestFlight-LunaMax-20261102-archive.xcresult`
- `python3 Scripts/check_xcode_cloud_release.py` source check 通过；归档检查报告 App / Widget 均为 `0.7.1 / 15`，Bundle ID 分别为 `net.bingyan.KikuchiHeinrich.mikansei` 与 `net.bingyan.KikuchiHeinrich.mikansei.widgets`。App 图标、隐私清单及仅 App 内的公开客户端配置检查通过。
- `plutil -lint Mikansei.xcodeproj/project.pbxproj` 与 `git diff --check` 通过。未运行自动化测试。

此无签名 archive 只作为本地构建核对证据，不可安装或上传 TestFlight；它与下方由 Xcode Cloud 管理签名的分发归档是两份独立产物。

## Xcode Cloud 与 TestFlight 内部发布

- Xcode Cloud Build `a48a5822-75bd-44a5-aec8-11f381332e4e` 的正式 check `125276357665` 为成功：0 errors、0 test failures、0 analysis findings、4 warnings。正式 check 替代临时 check `125273877479`。
- TestFlight build：`0.7.1 (9)`，状态“正在测试”，已加入内部测试组 `Mikansei`（2 位受邀测试者）；上传时间为 2026-11-02 20:27（上海时间）。[App Store Connect build 详情](https://appstoreconnect.apple.com/teams/69a6de96-390e-47e3-e053-5b8c7c11a4d1/apps/6827965680/testflight/ios/86b69993-c5ef-44e1-84b6-2fd5cd669ae5)。
- 本次仅完成内部 TestFlight 分发；未确认用户已安装 Build 9，未做真机目视验收，未完成外部测试审核，也没有公测邀请链接。
- App Store Connect 当前显示一条需 Account Holder 处理的新许可协议提示；已确认该提示没有阻挡本次内部 TestFlight 分发。

此前用户确认已安装的原生 Mikansei 为 `0.7.0 (8)`；这与源码 `0.7.1 (15)` 及当前 TestFlight `0.7.1 (9)` 是不同记录。后续更新应沿用 TestFlight 中的 Mikansei App，并以其页面显示的版本和 build 为准。
