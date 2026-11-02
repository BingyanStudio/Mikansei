# Mikanseta iOS TestFlight 准备情况

更新日期：2026-11-02。候选源码版本：**0.7.0（18）**。本文记录 Mikanseta Flutter iOS App 的签名与 TestFlight 准备状态，不把它与原生 Mikansei 的版本或 App Store Connect 记录混为一谈。

## 结论

用户已确认 App Store Connect 中没有 Mikanseta 记录，并决定暂缓 Mikanseta 发布。已完成的本机 Flutter 配置、`0.7.0 (18)` unsigned archive、归档检查器与 Cloud 准备脚本留作后续准备；本机归档未签名，本轮没有上传或分发。

## 两个 iOS App 的身份

| App | Bundle ID | 工程中的 Team | 版本 / 构建号 | 当前证据 |
| --- | --- | --- | --- | --- |
| 原生 Mikansei | `net.bingyan.KikuchiHeinrich.mikansei` | `6PVAPR495F`（原生发布资料记录） | 当前原生发布状态见其独立 TestFlight 记录 | 原生工作流与 Mikanseta 分开；原生成功不能替代 Flutter App 的构建或上传证据。 |
| Mikanseta（Flutter） | `com.personal.mikanseta` | `7JMRL8X34C`（当前 Xcode 工程设置） | `0.7.0 (18)` | 本机 `iphoneos` Release unsigned archive 已生成，归档检查通过；没有签名、上传或 TestFlight 成品证据。 |
| Mikanseta Widget 扩展 | `com.personal.mikanseta.Widgets` | `7JMRL8X34C`（当前 Xcode 工程设置） | `0.7.0 (18)` | 已包含在通过检查的 App archive 中；采用共享 Keychain entitlement。 |

工程中的 Team ID 只是配置值，不证明该团队当前可签名或具有 App Store Connect 分发权限。用户提供的 Apple App 记录、Team 和 Bundle ID 仍需发布者在实际 Apple 帐户中核对；当前源码值没有被本轮修改，也不代表 Apple 侧记录已经创建或可用。

## 工程与 Xcode Cloud 准备

- Mikanseta 主 App 与 Widget 都设为 Automatic Signing；共享 Keychain entitlement 在 `Mikanseta/ios/Runner/Mikanseta.entitlements`。主 App 已声明 `NSSupportsLiveActivities=true`。
- 工程已有 Flutter Swift Package Manager 集成且当前没有 Podfile。准备脚本使用固定的 Flutter SDK、`pub get --enforce-lockfile` 与 iOS `config-only`；只有当前工程实际存在 Podfile 时才运行 `pod install`。
- 根目录 `ci_scripts/ci_post_clone.sh` 与 `ci_post_xcodebuild.sh` 按 Xcode Cloud 的 `CI_PROJECT_FILE_PATH`、`CI_XCODE_PROJECT` 和 `CI_XCODE_SCHEME` 识别 `Mikanseta`；项目路径会先归一化。其他工程继续使用原生 Mikansei 的既有准备与归档检查。
- Flutter iOS 准备从仓库跟踪的 `Configuration/SupabaseClient.public.plist` 读取公开客户端配置，经 publishable / `anon` 校验后生成 Dart defines；不会读取个人覆盖文件或 Cloud secret。此公开客户端配置是构建输入，不证明 Supabase 后端工作流已部署或在线验收。
- 本机分别从仓库 root 与 `Mikanseta` 目录运行准备脚本均成功，完成固定版本依赖解析、iOS 配置生成及公开 Dart defines 检查。之后以 `CODE_SIGNING_ALLOWED=NO` 对 `generic/platform=iOS` 做 Release archive，Xcode 输出 `ARCHIVE SUCCEEDED`；检查器读取 `/private/tmp/Mikanseta-0.7.0-18-TestFlight-LunaMax-20261102-01.xcarchive` 并通过。App 与 Widget bundle ID、版本 `0.7.0`、构建号 `18` 一致；App 的 iPhone `AppIcon` 含 `120×120` PNG，iPad `AppIcon` 含 `152×152` PNG；隐私清单、Live Activities 与公开 Dart defines 均通过检查。此本机 archive 未签名、未上传，临时路径不是长期归档存储。
- 当前 Flutter scheme 使用通用 `Release` build configuration。`config-only` 输出说明没有独立的 `Release-Mikanseta` 配置名，并回退到 `Release`；配置生成成功。若之后新增 flavor 配置，需同步更新工程配置。
- App 和 Widget 隐私清单已作为各自 target 资源加入。声明依据现有共享云账号能力：Email、Supabase User ID、同步的用户内容、云归档中可能包含的日历设备标识，以及既有 Supabase 安全日志披露；App 源码访问仅供自身使用的 `UserDefaults`。Widgets 不访问云账号网络，直接代码不使用 required-reason API。App Store Connect 隐私表单仍需发布者对照服务方日志、最终归档与最新 Apple 字段核对。

## 暂缓状态

用户决定暂缓发布；恢复发布前再确认 App Store Connect 记录、团队身份与 Mikanseta 专属 Cloud 工作流。现有 Cloud 脚本只保留准备能力，不能作为 Cloud 已绑定或 TestFlight 已发布的证据。

## 脚本入口与边界

- 本机准备：[`Mikanseta/Scripts/prepare-testflight.sh`](../../Mikanseta/Scripts/prepare-testflight.sh)
- Cloud 克隆后准备：根目录 [`ci_scripts/ci_post_clone.sh`](../../ci_scripts/ci_post_clone.sh)
- Cloud 归档检查：根目录 [`ci_scripts/ci_post_xcodebuild.sh`](../../ci_scripts/ci_post_xcodebuild.sh) 调用 [`Mikanseta/Scripts/check-testflight-archive.py`](../../Mikanseta/Scripts/check-testflight-archive.py)
- 这些脚本不会登录 Apple、创建 App 记录、签名、上传、分配测试组或部署 Supabase 后端。Cloud 准备步骤和归档检查通过，只代表源码与构建输入已就绪；不代表工作流已绑定、签名可用、成功上传或已发布 TestFlight。
