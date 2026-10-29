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

## 请 Paul 执行的发布步骤

1. 从包根目录 `SOURCE_COMMIT.txt` 取得这次完整源码的提交编号，并确认该提交已存在于 `experimental/sync`。
2. 沿用现有 `Internal TestFlight Build` 工作流，将符合该工作流匹配规则的发布标签指向上述提交。**不要直接给旧 `main` 提交打标签**。本包没有替发布者更改服务器端工作流、创建标签或开启外部测试。
3. 在 Xcode Cloud 日志确认 post-clone 输出 `Xcode Cloud source check passed`；归档阶段应输出 `Xcode Cloud archive check passed`。
4. 查看现有 App 的 TestFlight，确认上传、处理和实际构建号。源码归档成功或检查脚本成功都不代表 Apple 接收和处理已成功。

工作流需要使用具备本项目 SDK 的 Xcode（本地检查环境为 Xcode 26.5 / iOS SDK 26.5），并保持原有签名与 TestFlight 分发动作。标签匹配规则、签名权限、协议和分发动作存放在 Apple 服务器端，需由有权限的发布者核对。

## 自动检查范围

- 构建前：App / Widgets 的 Team、Bundle ID、版本和构建号一致；图标资产目录、隐私清单、Swift 源文件和客户端配置资源存在；无旧散图冲突。
- 归档后：120 × 120、152 × 152 PNG 与 `CFBundleIconName=AppIcon` 完整；主应用和 Widgets 的 Bundle ID、版本与实际构建号匹配；两端均有隐私清单；主应用确实包含预期公开客户端配置，Widget 不含该配置。
- 不调用用户数据接口，不发送验证码，不创建或删除用户。

## 云服务仍需完成

客户端配置已接通。只读 Auth 设置请求返回 HTTP 200、邮箱认证已开启，这不代替真实邮箱投递、登录和双端同步验收。

`mikansei_delete_account` RPC 仍待 Supabase 管理员部署，SQL 位于 `Documentation/supabase-native-account.sql`；未部署前应用内删除账号暂不可用。请先核对内部构建，再安排外部云功能测试和审核。

## 官方依据

- Apple：Writing custom build scripts，`https://developer.apple.com/documentation/xcode/writing-custom-build-scripts`
- Apple：Environment variable reference，`https://developer.apple.com/documentation/xcode/environment-variable-reference`
- Supabase：API keys，`https://supabase.com/docs/guides/api/api-keys`
