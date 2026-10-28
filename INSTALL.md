# Mikansei · 最简 iPhone 安装

**首次配置一次，以后双击“安装到iPhone.command”。** 需要 Mac、完整 Xcode 和 iOS 17+ iPhone。

## 第一次：三件事

1. **连接手机**：数据线连接 Mac，解锁 iPhone，点击“信任此电脑”；在 Xcode 中完成设备配对。
2. **选择账号**：打开 `Mikansei.xcodeproj`；Xcode → Settings → Accounts 登录 Apple 账号。选 Mikansei target → Signing & Capabilities，勾选 **Automatically manage signing**，选择你的 **Team**。如 Bundle Identifier 被占用，改为自己的唯一标识，例如 `com.kikuchiheinrich.mikansei`。
3. **手机确认**：设置 → 隐私与安全性 → 开发者模式，开启、重启并确认。若尚未出现开发者模式，先完成 Xcode 配对；Xcode 提示缺少 iOS 平台时，在 Settings → Components 安装对应组件。

Xcode 可自动创建签名资源，但 Apple 账号登录、电脑信任和手机开发者模式确认需要你本人操作。[Apple 真机运行说明](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)、[开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/)。

## 后续：双击安装

保持 iPhone 连接并解锁，在 Mac 上双击项目根目录的 **安装到iPhone.command**。

自动完成：检查配置 → 选择已连接的 iPhone → 编译与签名 → 安装 → 尝试启动。连接多台手机时让你选一个，不会自动猜测目标。签名使用 Xcode 中已有账号，不需要在脚本输入密码。

安装后首次打开 App，请允许通知。若系统提示“未信任开发者”，按提示在手机“设置 → 通用 → VPN 与设备管理”中信任自己的开发签名。

首次更新到日历导入版时，允许系统弹窗中的日历读取权限（iOS 称为“完全访问”）。随后在设置中手动勾选需要同步的日历来源；首次不会自动导入所有日历。之后打开 App 自动导入所选来源未来 30 天（含今天）的事件，默认作为日程保留执行时段。在 **设置 → 日历自动导入** 选择日历、关闭自动同步或手动同步；拒绝后可从该页进入系统设置开启。

## 添加小组件

1. 更新安装后，先打开 Mikansei 一次。
2. 长按 iPhone 主屏幕空白处 → **编辑 → 添加小组件**，搜索 **Mikansei**。
3. 选择 **今日清单**、**快速添加**、**今日进度**或**正在做 · 计时**。进度与计时也支持锁屏的小组件区域。

今日清单显示超时、今天截止、无日期事项和今天完成的事项；点清单打开今日聚焦，点事项打开详情，点 `+` 或快速添加按钮直接录入。

在 App 清单中点击一件事项的“开始做”，计时小组件会显示它的名称与累计用时。暂停保留用时，继续累加，完成后停止；开始另一件事自动暂停上一件。小组件里的“暂停 / 继续”会打开 App 并执行操作，点击标题或计时区域打开详情。

免费 Personal Team 版本通过共享钥匙串传递小组件摘要，工程已经配置，无需开启 App Groups。`MikanseiWidgets` 扩展需和主 App 使用同一 Team；当前工程已继承你的设置。若更改主 App 的 Bundle Identifier，运行 `python3 Scripts/generate_project.py` 同步扩展配置，再重新打开 Xcode。

小组件刷新由 iOS 调度；保存后 App 会请求更新。如提示“打开 App 同步清单”，先解锁并打开 App，再查看设置里的同步提示。共享读取与真实小组件布局仍需在 iPhone 上验证。

**如尚未配置 Team，脚本会打开 Xcode 并说明如何配置，不会继续安装。** Apple 可能还会显示钥匙串或账号确认，请按系统提示完成。

## 常见问题

- **签名或平台报错**：先在 Xcode 选择手机并按 `⌘R` 一次，通常会给出具体的账号、签名或组件提示。签名失败时脚本不会尝试安装旧产物。
- **免费账号过几天打不开**：Personal Team 的安装描述文件有效期为 7 天，届时重新双击安装。无需卸载 App。[Apple 免费账号限制](https://developer.apple.com/help/account/basics/about-your-developer-account)
- **双击没执行**：在源码仓库根目录打开终端，运行 `bash ./安装到iPhone.command`。不要移走入口文件和 `Scripts/` 文件夹。
- **查看报错**：项目内 `LocalInstall/install.log` 保存编译与安装日志，Git 已忽略这个目录。

只检查前置条件，不安装：

```sh
python3 Scripts/install_iphone.py --check
```

脚本保留现有 Bundle Identifier；更改 Identifier 会让 iOS 将其视为另一个 App。如果已有数据，请先导出备份。脚本不会卸载 App、擦除手机或导出证书。

## 如果想在手机上点链接安装

后续可走 **TestFlight**：完成开发者会员、App Store Connect 上传与测试配置后，手机安装 TestFlight，打开邀请并点击安装。开发构建通过 Xcode 安装需开发者模式，TestFlight 安装不需要。[TestFlight 说明](https://developer.apple.com/testflight/)、[开发者模式适用范围](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/)。

Mikansei 目前没有上传到 TestFlight，没有可用邀请链接。App 与小组件已通过本机 Personal Team 签名编译验证；完整自动安装与启动已在 iPhone 17 上跑通，小组件的真实读取与布局仍需在手机上确认。

## 本次更新的使用方式

- 只记待办或 DDL：直接保存，不必创建日历事件。
- 确定执行时段：事项详情 → “保存并安排到苹果日历” → 在系统日历编辑页选时段并保存。以后可从同一事项编辑日程。勾选清单不会删除日历事件。
- 提醒：事项详情 → 提醒我 → 弹窗 / 闹钟 → 铃声（点选试听）与稍后提醒间隔。闹钟需要 iOS 26+ 和系统闹钟授权；免费 Personal Team 签名构建已通过。锁屏实际响铃和真实账号回写仍需在你的 iPhone 验证。

## 切换日历式视图

更新后打开 **日程 → 日历 → 月历 / 日视图**。上方可返回今日聚焦或列表；所选模式会自动记住。月历点日期浏览，日时间轴点事件进入原事项，长按月历日期或日时间轴空白处添加日程，开始时间按位置预填。输入持续时间即可，结束时间自动计算；默认闹钟提醒，iOS 26 以下可改用弹窗。DDL 在单独的截止区域展示。

## 日历来源与常态

- **设置 → 日历自动导入 → 自动同步的日历标签 / 来源**：按日历的名称、颜色和账号勾选。旧版误导入的节假日来源升级后会取消选择；如仍有未经修改的旧导入事项，可以点“清理未选日历的导入事项”并确认。
- **事项详情 → 标签 → 常态（Routine）**：待办和日程都可以开启；支持每天、每周多选星期、每月与自定义间隔，或在“日历选日”中跨月点选不规则日期。
- 勾选立即更新界面，保存与小组件刷新在后台执行。若出现“更改尚未写入手机”，点击“重试保存”，成功前保留 App 并导出备份。

核心逻辑与 Swift 语法已在 Linux 验证；iOS 签名构建与真机安装已在 Mac + iPhone 17 跑通。界面测试与真机交互（长按、重复规则、闹钟与连续勾选）仍按 VALIDATION.md 的检查项在手机上确认。
