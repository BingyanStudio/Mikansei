# 原生 Mikansei 0.7.1 TestFlight 准备记录

日期：2026-11-02
目标分支：`experimental/sync`
准备时基线提交：`d07e93d7d20e7fa2e3f95f0126e9b6ff055a4d18`

## 版本与功能

- 原生 iOS 源码目标：`0.7.1`，build `15`。云端或 TestFlight 可重新编号；实际分发 build 以 App Store Connect / TestFlight 显示为准。
- 保留 Team `6PVAPR495F`、主 Bundle ID `net.bingyan.KikuchiHeinrich.mikansei`、Widget Bundle ID `net.bingyan.KikuchiHeinrich.mikansei.widgets` 以及现有数据路径。
- 新增专注计时 Live Activity，在锁屏与灵动岛显示主题和醒目计时，并提供暂停 / 继续及结束保存入口；手动收起后可从 App 重新显示。现有 DDL Live Activity 维持独立。
- 倒计时、正计时、倒计时到期提示与 ActivityKit 八小时显示边界均列入 TestFlight 检查范围。测试文案见 [中文测试说明](TestFlight/WHAT_TO_TEST.txt) 和 [英文测试说明](TestFlight/WHAT_TO_TEST_EN.txt)。

## 构建与核对

Xcode 26.5 / iOS SDK 26.5，scheme `Mikansei`，`Release`，`generic/platform=iOS`，`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`。`xcodebuild archive` 结果为 `ARCHIVE SUCCEEDED`；无签名 archive 大小约 32 MB。

- 归档：`/private/tmp/Mikansei-0.7.1-TestFlight-LunaMax-20261102-archive.xcarchive`
- 完整构建日志：`/private/tmp/Mikansei-0.7.1-TestFlight-LunaMax-20261102-archive.log`
- Xcode result bundle：`/private/tmp/Mikansei-0.7.1-TestFlight-LunaMax-20261102-archive.xcresult`
- `python3 Scripts/check_xcode_cloud_release.py` source check 通过；归档检查报告 App / Widget 均为 `0.7.1 / 15`，Bundle ID 分别为 `net.bingyan.KikuchiHeinrich.mikansei` 与 `net.bingyan.KikuchiHeinrich.mikansei.widgets`。App 图标、隐私清单及仅 App 内的公开客户端配置检查通过。
- `plutil -lint Mikansei.xcodeproj/project.pbxproj` 与 `git diff --check` 通过。未运行自动化测试。

无签名 archive 只用于构建核对，不可安装或上传 TestFlight。

## 分发状态

此准备记录不代表已完成真机验收、Apple 签名、TestFlight 上传或处理。当前用户确认的既有 TestFlight 版本为 `0.7.0 (8)`；它与本轮源码 `0.7.1 (15)` 是不同记录。分发后应在 TestFlight → Mikansei 更新现有 App，并以 TestFlight 页面显示的版本和 build 为准。
