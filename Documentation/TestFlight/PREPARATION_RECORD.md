# Mikansei TestFlight 交接准备记录

日期：2026-10-28  
适用：原生 Mikansei iOS **0.4.2（10）**，iPhone / iPad  
源码提交：以交接 ZIP 根目录的 `SOURCE_COMMIT.txt` 为准。

## 已完成

- 产品简介、反馈邮箱、测试重点、英文与中文审核说明、App Store Connect 填写表和发布操作指南。
- 隐私政策、支持页和 App 内“隐私与支持”入口。
- 主应用及小组件的隐私清单；主应用声明 UserDefaults 用途 `CA92.1`。
- 1024 × 1024、无 Alpha 通道的 AppIcon 原图核对；资产目录接入 iOS App target。
- 当前版本的系统加密使用说明及 `ITSAppUsesNonExemptEncryption=false`。
- 使用发布者 Team ID 生成独立发布工程副本的助手；默认生成独立 Beta Bundle ID，不覆盖原工程。

## 实际检查结果

| 检查 | 结果 |
| --- | --- |
| 工具环境 | Xcode 26.5，iOS SDK 26.5；原工程最低运行系统 iOS 17 |
| Python 语法 | 生成器和准备助手均通过 Python 3.9 语法解析 |
| 配置文件 | App Info.plist 和两份 PrivacyInfo.xcprivacy 均可解析；生成后的 Xcode 工程可被 plutil 读取 |
| 无签名 Release 归档 | 实际运行交接助手 `--unsigned-check`，退出码 0，Xcode 输出 `ARCHIVE SUCCEEDED` |
| 主应用产物 | Bundle ID 为检查专用的 `com.personal.mikansei.beta.unsigned`；版本 0.4.2、build 10；包含 Assets.car、生成的 AppIcon 信息和 App 隐私清单 |
| 小组件产物 | Bundle ID 为检查专用主 ID 加 `.widgets`；版本 0.4.2、build 10；包含扩展隐私清单 |
| 原工程身份 | App / Widgets 的原 Team、Bundle ID、版本和共享钥匙串身份保留 |
| 测试 | 本轮未新增或运行自动化测试，也未做设备交互验收 |

编译仍有两条现有 Swift 并发警告：`NotificationManager.swift` 中非 Sendable 字典捕获，以及 `EntryStore.swift` 中 WidgetSnapshot 捕获。当前工程使用 Swift 5 语言模式，本次归档成功；尚未在本轮迁移到 Swift 6 语言模式。

## 发布者仍需完成的步骤

1. 使用自己的有效 Apple Developer Program 团队和真实审核联系人。
2. 以实际 Team ID 运行签名准备 / 归档，确认 Bundle ID 可用并创建对应 App Store Connect 主应用记录。
3. 上传构建、完成 Apple 处理与外部测试审核、开启测试组邀请链接。

本次没有使用朋友的账号或证书，没有执行分发签名、上传、安装或取得 Apple 审核通过。无签名检查归档不包含在交接 ZIP 中，也不能当作可安装的 IPA 使用。
