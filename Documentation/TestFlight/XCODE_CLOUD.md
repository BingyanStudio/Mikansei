# Mikansei · Xcode Cloud 发布

适用：2026-10-29 的 Xcode Cloud 专用交接包，原生 Mikansei 0.5.0。

## 已在源码中准备

| 项目 | 配置 |
| --- | --- |
| 原生工程 / scheme | `Mikansei.xcodeproj` / `Mikansei` |
| Team | `6PVAPR495F` |
| 主应用 Bundle ID | `net.bingyan.KikuchiHeinrich.mikansei` |
| Widgets Bundle ID | `net.bingyan.KikuchiHeinrich.mikansei.widgets` |
| App Store Connect App ID | `6827965680`，继续使用既有应用 |
| 源码版本 / 构建号 | 主应用与 Widgets 均为 `0.5.0 (11)`；实际云构建号以 Xcode Cloud 管理结果为准 |
| Xcode Cloud product manifest | 保留 Paul 已建立的绑定 |
| Supabase 客户端配置 | `Configuration/SupabaseClient.public.plist` 已纳入 Git，只含公开客户端值 |
| 构建准备 | `ci_scripts/ci_post_clone.sh`，自动生成工程和客户端资源 |
| 归档检查 | `ci_scripts/ci_post_xcodebuild.sh`，检查实际 App / Widgets 产物 |

生成的 `Configuration/SupabaseClient.plist` 仍被 Git 忽略，这是构建中间文件；它的输入 `SupabaseClient.public.plist` 已有版本记录。Xcode Cloud 全新拉取源码后会自动恢复中间文件，**无需再向 Paul 索取或让他手工配置 Supabase secrets**。代码拒绝 `service_role` 和 `sb_secret_` 管理密钥，脚本不打印客户端密钥。

## 后续自行发布

本次 `v0.5.0` → `ba2ecf1` 已触发 `Internal TestFlight Build`，云归档和工作流成功；用户已下载实际 **0.5.0（Build 5）**。无需每次请 Paul 代构建。

1. 确认待发布提交已推送到 `experimental/sync`，为下一版使用新标签；不要让标签指向旧 `main`，也不要移动已发布标签。
2. 沿用现有工作流，推送匹配规则的标签，核对云任务对应的提交。
3. 日志中应有 `Xcode Cloud source check passed` 和 `Xcode Cloud archive check passed`。
4. 查看工作流整体结果和正式归档检查，再到 TestFlight 确认实际版本、构建号与分配的测试组。

本次 Xcode Cloud build ID 为 `0179c066-1198-4db1-8f01-d592b2ab4f3b`。旧临时 Check Run 曾残留运行中；正式成功记录为 `123274415418`。详见 [执行记录](PREPARATION_RECORD.md) 和 [新手教程](RELEASE_WALKTHROUGH_ZH.md)。

工作流应使用支持本项目 SDK 的 Xcode，保持既有签名与 TestFlight 分发动作。服务器端工作流权限或协议发生变化时再由团队管理员处理。

## 自动检查范围

- 构建前：App / Widgets 的 Team、Bundle ID、版本和构建号一致；图标资产目录、隐私清单、Swift 源文件和客户端配置资源存在；无旧散图冲突。
- 归档后：120 × 120、152 × 152 PNG 与 `CFBundleIconName=AppIcon` 完整；主应用和 Widgets 的 Bundle ID、版本与实际构建号匹配；两端均有隐私清单；主应用确实包含预期公开客户端配置，Widget 不含该配置。
- 不调用用户数据接口，不发送验证码，不创建或删除用户。

## 云服务仍需完成

客户端配置已接通。只读 Auth 设置请求返回 HTTP 200、邮箱认证已开启，这不代替真实邮箱投递、登录和双端同步验收。

`mikansei_delete_account` RPC 已于 2026-10-29 部署，目录和权限检查通过；SQL 位于 `Documentation/supabase-native-account.sql`。未执行真实账号删除，也未验收真实邮箱登录和同步。完成这些核对后再安排外部云功能审核。

## 官方依据

- Apple：Writing custom build scripts，`https://developer.apple.com/documentation/xcode/writing-custom-build-scripts`
- Apple：Environment variable reference，`https://developer.apple.com/documentation/xcode/environment-variable-reference`
- Supabase：API keys，`https://supabase.com/docs/guides/api/api-keys`
