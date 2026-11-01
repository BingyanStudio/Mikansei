# Mikanseta Windows 安装与更新

目标系统：**Windows 10 / 11，x64（64 位）**。

## 0.7.0 (18) 发布状态

Mikanseta 0.7.0 (18) 已在 [BingyanStudio/Mikansei GitHub Release](https://github.com/BingyanStudio/Mikansei/releases/tag/mikanseta-v0.7.0) 公开预发布（`draft=false`、`prerelease=true`，tag 指向 `cfe17a1d1cb04fff7de86106f469362a338a966d`）。Windows CI [run 41305090339](https://github.com/BingyanStudio/Mikansei/actions/runs/41305090339) 成功，来源提交 `cfe17a1`。已发布：

- [`Mikanseta-Windows-x64-Setup.exe`](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-Windows-x64-Setup.exe)：安装版
- [`Mikanseta-Windows-x64.zip`](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/Mikanseta-Windows-x64.zip)：免安装版
- [`SHA256SUMS.txt`](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/SHA256SUMS.txt) 与 [`build-info.json`](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-v0.7.0/build-info.json)：校验和构建信息

旧版 Windows 0.4.3 (9) 安装包仍作为历史版本保留：[安装版](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-windows-v0.4.3/Mikanseta-Windows-x64-Setup.exe) · [免安装版](https://github.com/BingyanStudio/Mikansei/releases/download/mikanseta-windows-v0.4.3/Mikanseta-Windows-x64.zip)。这两个旧包不代表本轮版本。

## 安装与覆盖更新

本版安装包发布并完成 Windows CI 核验后，可从上方版本页下载。安装版下载后运行 Setup 并按提示安装；已有安装可使用同一安装方式覆盖更新，无需先卸载。免安装版需完整解压并运行 `Mikanseta.exe`，同时保留 DLL 与 `data` 文件夹。

Windows 本机归档保存在 AppData 的应用支持目录，独立于安装目录；因此使用安装版覆盖更新不会清除清单数据。升级前仍建议从设置导出 JSON 备份。CI 已完成构建、安装与启动检查，但没有在个人 Windows 设备上逐项验收界面和升级流程。

## 历史版本功能说明

公开的 Windows 0.4.3 (9) 测试包提供待办、Checklist、日历、循环、专注计时、课表文本导入、JSON 备份和共享文件夹同步。该版本尚未接入 Windows 系统日历、后台提醒、系统闹钟、小组件和实时活动。0.4.3 的账号同步服务连接已加入包中，但真实登录和跨设备同步仍未完成端到端验收。

## 本机打包

需要 Windows、Visual Studio 2022 的 C++ 桌面开发组件、Flutter **3.47.7** 和 Inno Setup 6。在 Mikanseta 目录的 PowerShell 中运行：

```powershell
./Scripts/build-windows.ps1
```

脚本从 `pubspec.yaml` 读取版本，构建 Release、复制运行库，并生成 ZIP、安装程序和 SHA-256。默认输出到仓库旁的 `../Releases/Mikanseta/Windows/<version+build>/`；可用 `-OutputDirectory` 或 `MIKANSETA_OUTPUT_DIR` 指定输出目录，`MIKANSEI_RELEASES_DIR` 可更换 `Releases/` 根目录。本版已上传至上方 GitHub Release，校验文件可直接下载。

同时提供 `SUPABASE_URL` 与 `SUPABASE_ANON_KEY` 环境变量时，构建会加入账号服务连接。构建脚本不读取开发者个人会话、任务文件或签名私钥。

## 自动构建与验证

`.github/workflows/mikanseta-windows.yml` 运行静态检查、Flutter 回归、Windows 集成、Release 构建和安装检查。0.7.0 的最终 Windows CI 已成功，Release 资产的大小和摘要与本地产物匹配。CI 安装检查不等于所有 Windows 设备行为均已验收。

更多发布状态见 [Mikanseta 0.7.0 发布说明](../Documentation/RELEASE_MIKANSETA_0.7.0.md) 和 [Mikanseta 验证记录](VALIDATION.md)。
