# Mikanseta Windows 测试版

目标系统：**Windows 10 / 11，x64（64 位）**。源码版本 **0.4.3 (9)**。

## 下载与安装

在仓库的 [Releases](https://github.com/KikuchiHeinrich/Mikansei/releases) 中选择包含 Windows 附件的版本：

- **Mikanseta-Windows-x64-Setup.exe**：运行并按提示安装到当前用户的程序目录，提供开始菜单快捷方式，可选择创建桌面快捷方式。
- **Mikanseta-Windows-x64.zip**：完整解压后打开 Mikanseta.exe。保留旁边的 DLL 和 data 文件夹。

安装包包含所需的 Visual C++ 运行库文件，无需安装 Flutter 或 Visual Studio。测试包尚未做 Windows 代码签名，系统可能显示发布者未知。

## 功能范围

Windows 版提供清单、Checklist、日历视图、循环、专注计时、课表文本导入、JSON 备份和共享文件夹同步。使用与其他 Mikanseta / 原生 Mikansei 兼容的数据格式。处理平台的 HTTP(S) 链接可打开系统浏览器。

在设置中选择共享文件夹后，使用原版 Mikansei-sync 协议交换数据；各设备须能访问同一个文件夹。文件夹不可用时提示重新选择，保留本机清单。

账号同步取决于构建时是否配置服务连接。Windows 系统日历、后台提醒、闹钟、小组件和实时活动尚未接入；提醒配置可随数据交给支持这些功能的设备。

数据保存在 AppData 的应用支持目录，独立于安装目录。更新或卸载程序不主动删除清单。建议定期在设置中导出 JSON 备份。

## 本机打包

需要 Windows、Visual Studio 2022 的 C++ 桌面开发组件、Flutter **3.47.7** 和 Inno Setup 6。在 Mikanseta 目录的 PowerShell 运行：

```powershell
./Scripts/build-windows.ps1
```

脚本从 pubspec.yaml 读取版本，构建 Release、复制运行库、生成 ZIP 与安装程序及 SHA-256。输出位于 build/windows-delivery/，可用 -OutputDirectory 指定位置。

同时提供 SUPABASE_URL 和 SUPABASE_ANON_KEY 环境变量时，构建会加入账号服务连接。构建不读取开发者的个人会话、任务文件或签名私钥。

## 自动构建与验证

.github/workflows/mikanseta-windows.yml 在 Windows 2022 上运行静态检查、Flutter 回归、Windows 应用集成、Release 构建和安装验证。工作流上传构建产物，由发布流程核对后发布。

实际验证结果见 [VALIDATION.md](VALIDATION.md)。源码工程已接入不等于 Windows 安装包已构建或所有实机行为均已验收。
