# Mikanseta 0.7.0 (18) 发布准备说明

**状态：准备中，尚未发布。** 本文记录计划中的同一 GitHub Release；不要将下列版本页或资产名当作可下载链接，直到发布流程完成并核对产物。

## 版本与发布计划

- Mikanseta Flutter 版：`0.7.0+18`（界面显示 `0.7.0 (18)`）。
- 原生 Mikansei：`0.7.0 (14)`，本轮不改版本。
- 计划 tag：`mikanseta-v0.7.0`。Tag 和 Release 均尚未创建。
- 计划的 GitHub Release：[BingyanStudio/Mikansei · mikanseta-v0.7.0](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0)。本仓库已重定向到 `BingyanStudio/Mikansei`；发布资料统一使用该 owner。
- Android 与 Windows 0.4.2 / 0.4.3 旧下载仍作为历史包保留，不删除、不作为 0.7.0 下载。

计划在同一个 GitHub Release 上传以下文件：

| 平台 | 计划资产名 | 当前状态 |
| --- | --- | --- |
| Android | `Mikanseta-Android.apk` | APK 签名连续性待核实，尚未上传 |
| macOS | `Mikanseta-macOS.zip` | universal Release 构建通过；ZIP 分发打包及公证待确认 |
| Windows | `Mikanseta-Windows-x64-Setup.exe` | Windows CI 尚未完成，安装器尚未构建 |
| Windows | `Mikanseta-Windows-x64.zip` | Windows CI 尚未完成，ZIP 尚未构建 |

## 本轮产品变化

Mikanseta 是 Mikansei 的 Flutter 版，沿用相同的事项、染色与数据语义。本轮把手机主入口统一为「待办、日程、笔记」，默认进入待办；日程提供「今日聚焦、列表、日历」和规划入口。待办可按类型、分类、当前清单与历史筛选；卡片点击进入编辑，完成、重开、计时、Checklist、移入规划与恢复等操作沿用对应事项语义。DDL 和执行时间分别显示。桌面按窗口宽度采用侧栏、列表和详情布局，并保留课表、专注、账户同步、本机同步、备份及系统权限相关入口。

颜色按语义区分：待办和日程使用绿色，作业使用蓝紫色，笔记使用暖橙色；DDL / 逾期使用提示色，完成项为中性色，正在做的事项使用浅强调色。详细映射与平台能力范围见 [Mikanseta 原生操作对应说明](MIKANSETA_PARITY.md)。

## 验证记录

- Mikanseta iOS `0.7.0 (18)` unsigned Release：主 App 与 Widget 构建通过。日志：`/private/tmp/Mikanseta-parity-ios-final.log`。
- macOS universal Release：构建通过，产物 56.9 MB。日志：`/private/tmp/parity-macos-final.log`。当前 App 未公证；ZIP 分发产物及可公开安装状态尚未确认。
- `domain_test.dart` 34 项通过；Swift → Dart → Swift 备份往返通过。
- 8 张合成内存数据预览覆盖手机浅 / 深色、320 点宽且文字放大 1.5 倍、桌面、日程、编辑器和笔记，未发现布局溢出。截图保存在 `/private/tmp/Mikanseta-Parity-Preview/`，临时预览测试文件已删除。
- 本轮修改的三份 UI 文件通过 `dart analyze`。完整 Flutter 测试套件、全库分析和 Windows CI 尚未确认；以 [Mikanseta 验证记录](../Mikanseta/VALIDATION.md) 后续更新为准。

## 安装与数据保留

- **Android**：确认 application ID 与发布证书后，使用现有 APK 安装方式直接覆盖更新，不要先卸载。Android 只允许兼容签名的 APK 覆盖同一 application ID；兼容更新会保留本机数据。本轮 0.7.0 APK 的签名与已发布 0.4.2 APK 是否一致仍待核实，核实前不要把新 APK 当作可安全覆盖更新的包。建议先导出 JSON 备份。细节见 [Android 安装说明](../Mikanseta/INSTALL_ANDROID.md)。
- **macOS**：计划通过 ZIP 提供 universal App。使用原有方式替换 Applications 中的 Mikanseta.app，不要先删除用户数据目录；App bundle ID 保持 `com.personal.mikanseta.macOS`。当前构建未公证，ZIP 分发与首次启动体验仍待确认。不要使用绕过 Gatekeeper 的命令或将当前构建表述为已公证。
- **Windows**：计划提供 Setup 与 ZIP。Setup 应通过原有安装方式覆盖更新；JSON 数据位于 AppData 应用支持目录，独立于安装目录。Windows CI 和 0.7.0 更新流程待验证。细节见 [Windows 安装说明](../Mikanseta/INSTALL_WINDOWS.md)。
- **iOS**：unsigned Release 不是可直接安装到普通设备的通用 IPA。本轮未更新 TestFlight；安装需由用户签名部署，或在后续实际上传 TestFlight 后通过 TestFlight 获取。

本说明将在 tag、CI、签名、分发文件和 GitHub Release 均完成核对后更新为最终发布记录。当前不创建 tag、不上传资产，也不发布 GitHub Release。
