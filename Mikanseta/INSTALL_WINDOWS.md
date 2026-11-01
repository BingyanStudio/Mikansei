# Mikanseta Windows 安装与更新

目标系统：**Windows 10 / 11，x64（64 位）**。

## 0.7.0 (18) 发布状态

Mikanseta 0.7.0 (18) 目前处于发布准备中。Git tag `mikanseta-v0.7.0` 和 GitHub Release 尚未创建，Windows CI 仍待完成；本版 Windows 安装包尚未构建、核验或发布。计划在 [BingyanStudio/Mikansei 的同一版本页](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0) 提供：

- `Mikanseta-Windows-x64-Setup.exe`：安装版
- `Mikanseta-Windows-x64.zip`：免安装版

旧版 Windows 0.4.3 (9) 安装包仍作为历史版本保留：[安装版](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-windows-v0.4.3/Mikanseta-Windows-x64-Setup.exe) · [免安装版](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-windows-v0.4.3/Mikanseta-Windows-x64.zip)。这两个旧包不代表本轮版本。

## 安装与覆盖更新

本版安装包发布并完成 Windows CI 核验后，可从上方版本页下载。安装版下载后运行 Setup 并按提示安装；已有安装可使用同一安装方式覆盖更新，无需先卸载。免安装版需完整解压并运行 `Mikanseta.exe`，同时保留 DLL 与 `data` 文件夹。

Windows 本机归档保存在 AppData 的应用支持目录，独立于安装目录；因此替换程序文件不会清除清单数据。升级前仍建议从设置导出 JSON 备份。0.7.0 安装包和更新流程尚未完成验收，Windows CI 通过后再补充最终验证结果。

## 历史版本功能说明

公开的 Windows 0.4.3 (9) 测试包提供待办、Checklist、日历、循环、专注计时、课表文本导入、JSON 备份和共享文件夹同步。该版本尚未接入 Windows 系统日历、后台提醒、系统闹钟、小组件和实时活动。0.4.3 的账号同步服务连接已加入包中，但真实登录和跨设备同步仍未完成端到端验收。

## 本机打包

需要 Windows、Visual Studio 2022 的 C++ 桌面开发组件、Flutter **3.47.7** 和 Inno Setup 6。在 Mikanseta 目录的 PowerShell 中运行：

```powershell
./Scripts/build-windows.ps1
```

脚本从 `pubspec.yaml` 读取版本，构建 Release、复制运行库，并生成 ZIP、安装程序和 SHA-256。默认输出到仓库旁的 `../Releases/Mikanseta/Windows/<version+build>/`；可用 `-OutputDirectory` 或 `MIKANSETA_OUTPUT_DIR` 指定输出目录，`MIKANSEI_RELEASES_DIR` 可更换 `Releases/` 根目录。计划上传到 0.7.0 (18) GitHub Release 的资产名见上方；实际产物尚待 CI 生成。

同时提供 `SUPABASE_URL` 与 `SUPABASE_ANON_KEY` 环境变量时，构建会加入账号服务连接。构建脚本不读取开发者个人会话、任务文件或签名私钥。

## 自动构建与验证

`.github/workflows/mikanseta-windows.yml` 运行静态检查、Flutter 回归、Windows 集成、Release 构建和安装检查。当前 Windows CI 尚未完成；本版 Windows 是否构建成功、安装器启动及产物校验均待确认。源码工程已接入不等于 Windows 安装包已发布或所有设备行为已验收。

更多发布状态见 [Mikanseta 0.7.0 发布说明](../Documentation/RELEASE_MIKANSETA_0.7.0.md) 和 [Mikanseta 验证记录](VALIDATION.md)。
