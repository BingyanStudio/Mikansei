# Mikansei iOS · TestFlight 发布资料

更新日期：2026-10-30。上次核实的已分发版本：**0.5.0（Build 5）**。反馈邮箱：**kikuchiheinr@qq.com**。

## 当前结果

- Paul 已配置 Bingyan 的 Xcode Cloud 流程；本次自行推送 `v0.5.0`，指向提交 `ba2ecf1`，云工作流成功。
- 用户已通过 TestFlight 下载，截图显示“打开”、冰岩科技、`0.5.0 (5)`。源码中填写的构建号是 11，云端分发的实际构建号是 5。
- 公开 Supabase 客户端配置已纳入 Git；Cloud 自动准备资源并检查成品图标、版本、配置与隐私清单。
- `mikansei_delete_account()` 已部署并通过目录及权限检查。真实邮箱投递、登录、同步和注销流程尚未端到端验收。
- 本次完成 TestFlight 测试版发布；外部测试公开链接和正式 App Store 上架状态未确认。

## 0.6.0（12）源码候选状态

0.6.0（12）是当前源码目标，已重新生成 iOS 与 Mac 工程，并完成 iOS App + Widgets Release 和 Mac Release universal 的无签名构建。它尚未上传 TestFlight、尚未发布，也未做真实设备 / 系统日历交互验收；完整范围和构建日志位置见 [0.6.0 发布记录](../RELEASE_0.6.0.md)。上次核实的 TestFlight 安装截图为 0.5.0（Build 5）；提交 `9bb9c94` 没有后续 Xcode Cloud 构建记录。

新版出现在 TestFlight 后，在 iPhone 的 TestFlight App 中打开现有 **Mikansei** 页面并点“更新”，更新已安装应用；无需安装另一份 Beta App。上传前后仍应核对 TestFlight 显示的版本号、构建号和实际处理状态。

新手先读 **[上线全流程详解](RELEASE_WALKTHROUGH_ZH.md)**；技术记录见 [PREPARATION_RECORD.md](PREPARATION_RECORD.md)。

## 本项目后续发布方式

1. 在 `experimental/sync` 完成修改，并确认要发布的提交；当前 `main` 保留旧版本，不能只按分支名称判断内容。
2. 推送源码，使用新版本标签指向已准备好的提交，再推送标签。不要移动已经发布的 `v0.5.0`。
3. 查看 `Internal TestFlight Build` 的整体结果与正式归档检查。
4. 到现有 App 的 TestFlight 页面确认实际版本、构建号和测试组；安装后核对启动与关键功能。

沿用 Team `6PVAPR495F`、主 Bundle ID `net.bingyan.KikuchiHeinrich.mikansei`、Widgets ID 加 `.widgets`、App Store Connect App ID `6827965680`。无需新建 App，也无需每次再把 ZIP 交给 Paul。详见 [XCODE_CLOUD.md](XCODE_CLOUD.md)。

## 交接助手的适用范围

通用构建指南和准备助手仍可用于其他团队或手工归档。其他团队采用独立身份时，要确认数据迁移；Bingyan 当前流程保持上述既有身份。历史 ZIP 保存了当时资料，不随当前文档更新，也不代表另一份已安装的 IPA。

Mikansei 未登录时可离线使用；主动登录并确认合并后，才上传与 Mikanseta 共用的云归档。公开客户端 key 可以嵌入 App；管理 key、数据库密码、用户会话令牌和签名私钥不能随源码或交接包分发。

## 资料索引

| 文件 | 用途 |
| --- | --- |
| [RELEASE_WALKTHROUGH_ZH.md](RELEASE_WALKTHROUGH_ZH.md) | 面向小白的本次上线复盘与下次发布步骤 |
| [BUILD_GUIDE.md](BUILD_GUIDE.md) | 准备工程、签名、归档、上传和云账号上线前条件 |
| [ICON_UPLOAD_FIX.md](ICON_UPLOAD_FIX.md) | ITMS-90022 / 90023 / 90713 图标问题、旧上架工程修补与归档检查 |
| [XCODE_CLOUD.md](XCODE_CLOUD.md) | 公开配置、云构建自动准备、归档检查与标签发布注意事项 |
| [SUPABASE_NATIVE.md](../SUPABASE_NATIVE.md) | 原生客户端云账号配置、同步行为与管理员上线步骤 |
| [APP_STORE_CONNECT_FIELDS.md](APP_STORE_CONNECT_FIELDS.md) | 后台字段逐项填写 |
| [BETA_DESCRIPTION.txt](BETA_DESCRIPTION.txt) | 可直接粘贴的测试版简介 |
| [BETA_DESCRIPTION_EN.txt](BETA_DESCRIPTION_EN.txt) | 英文版简介，独立粘贴 |
| [WHAT_TO_TEST.txt](WHAT_TO_TEST.txt) | 可直接粘贴的本轮测试重点 |
| [WHAT_TO_TEST_EN.txt](WHAT_TO_TEST_EN.txt) | 英文版测试重点，独立粘贴 |
| [REVIEW_NOTES_EN.txt](REVIEW_NOTES_EN.txt) | 英文审核操作说明 |
| [REVIEW_NOTES_ZH.txt](REVIEW_NOTES_ZH.txt) | 中文审核操作说明 |
| [PRIVACY_POLICY.md](PRIVACY_POLICY.md) | 原生应用与可选云账号隐私政策 |
| [SUPPORT.md](SUPPORT.md) | 支持页与反馈方式 |
| [PRIVACY_AND_COMPLIANCE.md](PRIVACY_AND_COMPLIANCE.md) | App Privacy、隐私清单和加密填写依据 |
| [PREPARATION_RECORD.md](PREPARATION_RECORD.md) | 0.5.0（11）构建证据、在线验收边界及历史记录 |
| [FORWARD_TO_PUBLISHER.txt](FORWARD_TO_PUBLISHER.txt) | 可转发给发布者的简短说明 |

交接包会包含原生 `Source/`、1024 图标和文件校验清单；账号 SQL 的包内路径为 `Source/Documentation/supabase-native-account.sql`。源码仓库的维护位置为 `Documentation/supabase-native-account.sql`。

## 已准备的公开地址

- 隐私政策：<https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/PRIVACY_POLICY.md>
- 支持页：<https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/SUPPORT.md>
- 反馈邮箱：`kikuchiheinr@qq.com`

## 验证边界

构建、上传和 TestFlight 安装已有相应证据。真实启动、邮箱验证码、双端同步及删除账号仍需在专用测试账号上核对。外部测试还需要审核者可访问的邮箱及验证码接收方式；不要使用发布者私人邮箱作为审核账号。
