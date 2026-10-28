# Mikansei iOS · TestFlight 发布交接包

准备日期：2026-10-28  
产品：**原生 Mikansei**，SwiftUI，iPhone / iPad；账号服务也供原生 Mac 版使用

资料目标版本：**0.5.0（11）**

反馈邮箱：**kikuchiheinr@qq.com**

## 给发布者

本交接包包含 TestFlight 文案、审核说明、隐私与支持资料及构建指南。0.5.0（11）已通过 iOS 无签名 Release 归档及 Mac 通用构建，尚未签名、安装、上传或完成云端在线验收。无签名结果不能代替发布者团队的分发归档。

Mikansei 可在不登录时离线使用。本机数据只有在用户主动使用邮箱验证码登录并确认合并后，才会进入与 Mikanseta 共用的 Supabase 云归档。Supabase Auth 与共享归档表已存在；本轮未在线验收邮件投递、登录或同步。当前仅 `mikansei_delete_account` SQL/RPC 尚未部署，App 内删除账号功能暂不可用。

发布者烦请使用自己的 Apple Developer 与 App Store Connect 账号完成签名、分发和审核资料。交接源码将附带经验证的公开 Supabase 客户端配置（项目地址和 public/anon key）；公开 key 可嵌入客户端，访问隔离由 RLS 等策略负责。交接包不包含 Supabase 管理凭据、service-role key、数据库密码、证书私钥或可直接安装的 IPA。

## 操作顺序

1. 阅读 [BUILD_GUIDE.md](BUILD_GUIDE.md)，用自己的 Team ID 生成独立的发布工程副本并归档。原项目的签名和 Bundle ID 不会被覆盖。
2. 按准备助手输出的 `PREPARED_APP.json` 确认主应用和 Widgets 的标识；在自己的团队中注册或确认可用性。
3. 按 [APP_STORE_CONNECT_FIELDS.md](APP_STORE_CONNECT_FIELDS.md) 创建 App 记录并填写 TestFlight 资料。审核联系人的姓名、电话请填发布者本人的真实资料。
4. 如要开放云账号测试，请确认现有归档表的 RLS、OTP 邮件投递和审核者可访问的邮箱与验证码流程。若要测试 App 内删除账号，再与项目管理员协商部署 [原生云账号 SQL](../supabase-native-account.sql)；该 SQL/RPC 当前尚未部署。不要使用发布者的私人邮箱作为审核账号。
5. 在 Xcode Organizer 中分发归档到 App Store Connect / TestFlight。处理完成后，按表中说明提交外部测试审核。
6. 审核通过后为 `Friends Beta` 测试组开启公开邀请链接，分享该链接即可。

## 资料索引

| 文件 | 用途 |
| --- | --- |
| [BUILD_GUIDE.md](BUILD_GUIDE.md) | 准备工程、签名、归档、上传和云账号上线前条件 |
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

## 发布边界

本包不代替发布者接受协议、签名、上传或取得审核通过。0.5.0（11）的无签名构建检查已经完成，尚未安装或在线验收。Supabase Auth 与共享归档表已存在；仅删除账号的 SQL/RPC 尚待管理员授权和部署。准备开放云功能审核前，须确认 OTP 邮箱可由审核者访问。

默认生成不同于旧开发安装版的独立 Beta Bundle ID。旧版数据请先通过 JSON 备份导出，再在 Beta 中导入。TestFlight App 记录归发布者账号管理；后续长期维护和账号迁移应由双方事先约定。
