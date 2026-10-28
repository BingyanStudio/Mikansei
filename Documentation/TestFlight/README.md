# Mikansei iOS · TestFlight 发布交接包

准备日期：2026-10-28  
产品：**原生 Mikansei**，SwiftUI，iPhone / iPad  
源码版本：**0.4.2（10）**  
反馈邮箱：**kikuchiheinr@qq.com**

## 给发布者

这是一次 TestFlight 外部测试交接。产品介绍、测试重点、双语审核说明、隐私政策、支持页、图标和原生源码均随包提供。请先看下方操作顺序。

涉及 Apple Developer Program Team ID、开发者账号登录、会员协议、真实审核联系人和分发签名的部分，烦请发布者使用自己的账号完成。包内不包含账号密码、证书私钥、API 密钥或可直接安装的 IPA。

## 操作顺序

1. 阅读 [BUILD_GUIDE.md](BUILD_GUIDE.md)，用自己的 Team ID 生成独立的发布工程副本并归档。原项目的签名和 Bundle ID 不会被覆盖。
2. 按准备助手输出的 `PREPARED_APP.json` 确认主应用和 Widgets 的标识；在自己的团队中注册或确认可用性。
3. 按 [APP_STORE_CONNECT_FIELDS.md](APP_STORE_CONNECT_FIELDS.md) 创建 App 记录并填写 TestFlight 资料。产品字段已经写好；审核联系人的姓名、电话请填发布者本人的真实资料。
4. 在 Xcode Organizer 中分发归档到 App Store Connect / TestFlight。处理完成后，按表中说明提交外部测试审核。
5. 审核通过后为 `Friends Beta` 测试组开启公开邀请链接，分享该链接即可。

## 资料索引

| 文件 | 用途 |
| --- | --- |
| [BUILD_GUIDE.md](BUILD_GUIDE.md) | 准备工程、签名、归档、上传 |
| [APP_STORE_CONNECT_FIELDS.md](APP_STORE_CONNECT_FIELDS.md) | 后台字段逐项填写 |
| [BETA_DESCRIPTION.txt](BETA_DESCRIPTION.txt) | 可直接粘贴的测试版简介 |
| [BETA_DESCRIPTION_EN.txt](BETA_DESCRIPTION_EN.txt) | 英文版简介，独立粘贴 |
| [WHAT_TO_TEST.txt](WHAT_TO_TEST.txt) | 可直接粘贴的本轮测试重点 |
| [WHAT_TO_TEST_EN.txt](WHAT_TO_TEST_EN.txt) | 英文版测试重点，独立粘贴 |
| [REVIEW_NOTES_EN.txt](REVIEW_NOTES_EN.txt) | 英文审核操作说明 |
| [REVIEW_NOTES_ZH.txt](REVIEW_NOTES_ZH.txt) | 中文审核操作说明 |
| [PRIVACY_POLICY.md](PRIVACY_POLICY.md) | 已按原生源码整理的隐私政策 |
| [SUPPORT.md](SUPPORT.md) | 支持页与反馈方式 |
| [PRIVACY_AND_COMPLIANCE.md](PRIVACY_AND_COMPLIANCE.md) | App Privacy、加密和隐私清单填写依据 |
| [PREPARATION_RECORD.md](PREPARATION_RECORD.md) | 本次实际完成的准备与归档检查结果 |
| [FORWARD_TO_PUBLISHER.txt](FORWARD_TO_PUBLISHER.txt) | 可转发给发布者的简短说明 |

交接 ZIP 根目录另含原生 `Source/`、1024 图标和文件校验清单。源码仓库的 `Documentation/TestFlight/` 是这些资料的维护位置。

## 已准备的公开地址

- 隐私政策：<https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/PRIVACY_POLICY.md>
- 支持页：<https://github.com/KikuchiHeinrich/Mikansei/blob/experimental/sync/Documentation/TestFlight/SUPPORT.md>
- 反馈邮箱：`kikuchiheinr@qq.com`

## 发布边界

本包准备的是 TestFlight 测试分发资料，没有代替发布者接受协议、签名、上传或取得审核通过。实际结果见交接 ZIP 中的准备记录。

默认生成不同于旧开发安装版的独立 Beta Bundle ID。旧版数据请先通过 JSON 备份导出，再在 Beta 中导入。

TestFlight 下发的 App 记录归发布者账号管理。后续长期维护和账号迁移应由双方事先约定；不要把 TestFlight 测试包等同于已经正式上架 App Store。
