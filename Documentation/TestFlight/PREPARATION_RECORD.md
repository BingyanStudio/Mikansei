# Mikansei TestFlight 交接准备记录

记录日期：2026-10-29

当前资料目标：原生 Mikansei **0.5.0（11）**，iPhone / iPad；云账号服务也供原生 Mac 版使用。

源码提交：以最终交接 ZIP 根目录的 `SOURCE_COMMIT.txt` 为准。

## 2026-10-29：Bingyan 交接包

- 最新原生源码保留 `0.5.0 (11)`，将 Paul 在 `origin/main` 提交 `1c968a009b5b862ae145a9efe43f7666a21364c8` 中的 iOS 发布设置接入 `experimental/sync`。沿用 Team `6PVAPR495F`、主标识 `net.bingyan.KikuchiHeinrich.mikansei`、扩展标识 `.widgets` 和现有 Xcode Cloud manifest；其他平台的本地安装身份未改。
- 对最终交接包 `Source/` 使用 Xcode 26.5 执行 Release 无签名归档，退出码 0，`ARCHIVE SUCCEEDED`。两份产物均为 `0.5.0 (11)` 和上述 Bingyan 标识。
- 独立图标检查通过：`Assets.car` 存在，iPhone / iPad 的 `CFBundlePrimaryIcon.CFBundleIconName` 均为 `AppIcon`，对应 PNG 的真实像素包含 120 × 120 和 152 × 152。
- 主 App 的公开 Supabase 配置与交接源码一致，Widget 无该配置；交接副本的 49 份 Swift 文件与仓库逐字节一致。Python 脚本通过 3.9 语法检查，归档入口通过 `bash -n` 检查。本轮未运行自动化测试。
- 归档仍有 `EntryStore.swift:297` 和 `NotificationManager.swift:182` 两处既有 Swift 并发捕获警告；使用 Swift 5 语言模式，不阻断本次编译。
- 本机另尝试过 Bingyan 自动签名归档，但主应用与 Widget 均返回 `No Account for Team "6PVAPR495F"` 及缺少描述文件。用户提供的 Xcode 团队截图显示 Developer 角色，但 `Certificates, Identifiers & Profiles` 为红叉。没有取得签名归档或完成上传。
- 交接包包含签名归档入口、图标检查工具、1024 图标、实际产物元数据、来源提交与文件校验清单。由 Paul 使用有签名权限的团队账号继续部署；本轮未创建发布标签。
- 云账号删除 RPC 仍未部署，邮箱登录与同步仍未在线验收；本轮源码和图标归档检查不代替这些操作。

归档位置（相对 `Mikansei_Project/`）：`Archives/Builds/TestFlightPreparation/2026-10-29-Bingyan-handoff-unsigned/Mikansei.xcarchive`。完整本机日志：`/private/tmp/mikansei-bingyan-handoff-unsigned-20261029.log`。交接包：`Releases/Mikansei/TestFlight/0.5.0+11/Mikansei-TestFlight-Handoff-0.5.0+11-2026-10-29.zip`。

## 2026-10-28：0.5.0（11）资料更新与待确认项

| 项目 | 当前状态 |
| --- | --- |
| TestFlight 文案、审核说明、隐私政策、支持页和分发说明 | 已按可选邮箱云账号及目标版本更新；需发布者复核实际归档和后台字段 |
| 隐私披露 | 文档列出 Email Address、User ID、Other User Content、Device ID、Other Data Types；主 App 隐私清单与之对应，Widgets 不连接云服务且维持无云数据收集声明 |
| 账号服务 | Mikansei 与 Mikanseta 共用 Supabase 项目及 `mikanseta_archives`，每个 Auth 用户一条归档；未登录仍离线使用，首次登录须经用户确认后合并 |
| Supabase Auth 设置 | 只读检查接口返回 HTTP 200，`external.email=true`、`disable_signup=false`；这不是实际登录或邮件投递验收 |
| 邮箱验证码、真实登录、云同步、账号删除 | 本轮未真实发信、登录、同步、调用删除 RPC 或进行设备验收 |
| 删除 SQL | `Documentation/supabase-native-account.sql` 中的 `mikansei_delete_account` 尚未部署；待项目管理员授权配置并完成在线检查。未部署前不应声称 App 内删除可用 |
| iOS 0.5.0（11）编译 | 使用 Xcode 26.5 执行最终源码的无签名 Release 归档，退出码 0，`ARCHIVE SUCCEEDED`；App 与 Widgets 均为 0.5.0（11） |
| macOS 0.5.0（11）编译 | 无签名 Release 通用构建退出码 0，`BUILD SUCCEEDED`；二进制包含 x86_64 / arm64 |
| 客户端资源 | 两端 App 均包含与现有 Mikanseta 相同且经验证的公开客户端配置；Widget 不含此配置；准备副本的 Swift 文件与最终工作区逐字节一致 |
| 签名、安装、上传、审核 | 本轮未执行；无签名检查不能用于安装或 TestFlight 分发 |
| 自动化测试 | 本轮未运行 |

客户端设计的自动同步策略为本机修改后约 2 秒上传、Realtime 变化触发、前台每 30 秒兜底及回到前台立即同步。由于没有真实邮箱登录、网络同步或设备验收，该策略未在本轮在线验证；实际表现还取决于网络、服务端配置及系统调度。

最终 iOS 准备目录：`Archives/Builds/TestFlightPreparation/2026-10-28-cloud-final-unsigned/`（相对 `Mikansei_Project/`），含 `build.log`、`PREPARED_APP.json` 和无签名 `Mikansei.xcarchive`。Mac 日志为维护者本机 `/private/tmp/mikansei-cloud-mac-final.log`。源码工程保留既有 Team 和 Bundle ID；无签名 iOS 检查副本使用独立的 `com.personal.mikansei.beta.unsigned` 标识。

归档仍有既有 `EntryStore` 的 WidgetSnapshot 捕获及 `NotificationManager` 字典捕获并发警告；工程使用 Swift 5 语言模式。Mac 有既有的冗余 `_ =` 及 AppIntents 元数据提取提示。编译成功不表示真实登录、合并、断线恢复或删除功能已通过设备验收。

现有 Supabase Auth、共享归档表及 RLS 用于云账号登录和同步；当前仅账号删除 RPC 的 SQL 尚未部署。开放云账号审核前，发布者仍需确认 OTP 邮件投递，并安排审核者可访问的测试邮箱和验证码流程；如需测试删除功能，项目管理员须先授权并部署该 SQL。不要使用发布者私人邮箱，也不要声称 OTP 对审核者一定可达。交接包将附经验证的公开客户端配置和 `Source/Documentation/supabase-native-account.sql`，但不得包含管理密钥、service-role key、数据库密码或签名私钥。

## 历史记录：0.4.2（10）无签名归档检查

以下结果来自此前对 0.4.2（10）的检查，只记录历史，不代表当前 0.5.0（11）已经构建或验证。

| 检查 | 历史结果 |
| --- | --- |
| 工具环境 | Xcode 26.5，iOS SDK 26.5；原工程最低运行系统 iOS 17 |
| Python 语法 | 当时生成器和准备助手通过 Python 3.9 语法解析 |
| 配置文件 | 当时 App Info.plist 和两份 PrivacyInfo.xcprivacy 可解析；生成的 Xcode 工程可被 plutil 读取 |
| 无签名 Release 归档 | 当时运行交接助手 `--unsigned-check`，退出码 0，Xcode 输出 `ARCHIVE SUCCEEDED` |
| 主应用产物 | 检查专用 Bundle ID `com.personal.mikansei.beta.unsigned`；版本 0.4.2、build 10 |
| 小组件产物 | 检查专用主 ID 加 `.widgets`；版本 0.4.2、build 10 |
| 原工程身份 | 当时 App / Widgets 的 Team、Bundle ID、版本和共享钥匙串身份保留 |
| Swift 并发警告 | 当时归档有 `NotificationManager.swift` 字典捕获及 `EntryStore.swift` WidgetSnapshot 捕获警告；使用 Swift 5 语言模式 |

## 发布者仍需完成

1. 使用自己的 Apple Developer Program 团队、真实审核联系人和 App Store Connect 账号。
2. 以实际 Team ID 生成签名准备包；确认最终二进制为目标版本 `0.5.0 (11)` 及预期 Bundle ID。
3. 核对本轮 App Privacy 分类、隐私政策和隐私清单与最终提交构建及 Supabase 实际日志、字段一致。
4. 如需开放云账号功能，先取得管理员授权、部署并验证 SQL / RLS / OTP 邮件流程；若要审核云功能，配置审核可访问的邮箱与验证码方式。
5. 上传构建、等待 Apple 处理，完成外部测试审核并设置测试组。

此前 0.4.2（10）和本轮 0.5.0（11）的无签名检查均不能安装到设备，也不能上传或分发到 TestFlight。发布者仍需补录签名分发及在线服务验收结果。
