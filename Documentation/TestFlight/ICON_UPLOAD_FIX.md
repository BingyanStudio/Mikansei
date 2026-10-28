# App Store 上传图标错误处理

记录日期：2026-10-28。

## 本次问题

上传邮件显示原生 Mikansei **0.3.1（4）**，Bundle ID 为 `net.bingyan.KikuchiHeinrich.mikansei`：

| 错误 | 邮件说明 |
| --- | --- |
| ITMS-90022 | 缺少 iPhone 120 × 120 PNG 图标 |
| ITMS-90023 | 缺少 iPad 152 × 152 PNG 图标 |
| ITMS-90713 | 缺少 `CFBundleIconName` |

核对远端 `main` 提交 `1c968a009b5b862ae145a9efe43f7666a21364c8` 时，工程已是 **0.3.1（5）**，其 App target 仍未把 `App/Assets.xcassets` 纳入资源构建，也未指定 `ASSETCATALOG_COMPILER_APPICON_NAME`。旧 Info.plist 使用手写散图声明；这是图标打包配置问题。

`experimental/sync` 中的 0.4.2（10）和 0.5.0（11）已使用图标资产目录。维护者检查实际无签名归档，均可找到 120 × 120、152 × 152 PNG，且 iPhone / iPad 的 `CFBundlePrimaryIcon` 含 `CFBundleIconName=AppIcon`。不能仅凭截图认定较新的交接 ZIP 也缺少图标。

## 沿用已建立的上架工程

发布者已经设置的 Team 和 Bundle ID 应继续沿用，不需要为了修复图标重建 App Store Connect 应用记录。

在含有本轮脚本的源码根目录运行：

```sh
python3 Scripts/repair_ios_icons.py --root /实际路径/Mikansei
```

脚本修复主 App 的图标资产目录引用与主图标集设置，并备份修改前的工程配置。它保留 Team、Bundle ID、版本和构建号。对只有旧源码的目录，可使用修补包中的同一脚本，并将 `--root` 指向旧工程根目录。

修补包中的 0.3.1（6）基于上述 `main`，已保留其签名设置与分发标识。发布者可打开包内 `Source/Mikansei.xcodeproj`，选择 `Mikansei` scheme，在自己的 Xcode 会话中重新归档并上传。最终上传构建号应高于 App Store Connect 中已使用的值；如已使用 6，请同步提高 App 和 Widgets 的 build number。

如果重新运行旧版本的工程生成器，请再次执行修复脚本，避免生成器恢复旧的散图配置。也可直接使用本轮已经修好的工程副本。

维护者已经用 Xcode 26.5 对该修补工程完成无签名 Release 归档，`ARCHIVE SUCCEEDED`。实际产物中 App 与 Widgets 均为 0.3.1（6），主 ID 与扩展 ID 保持原值；图标检查通过。源码工程的 Team 保留为 `6PVAPR495F`。未签名、安装、上传或取得 Apple 处理结果。

## 检查最终归档

```sh
python3 Scripts/check_ios_archive_icons.py /实际路径/Mikansei.xcarchive
```

该工具只检查文件：资产编译产物、iPhone / iPad 图标声明、声明所引用 PNG 的真实像素尺寸。它不会签名、上传，也不会访问 Apple 账号。新的 TestFlight 准备助手会在归档成功后自动运行此检查。

图标检查通过仅代表本次缺失项已在本地归档中补齐；发布者仍需在 Xcode Organizer 中验证并重新上传，以 Apple 的实际处理结果为准。
