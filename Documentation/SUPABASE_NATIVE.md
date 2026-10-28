# 原生 Mikansei 云账号配置

适用：Mikansei iOS / macOS 0.5.0 (11)。复用 Mikanseta 现有 Supabase 项目、邮箱验证码、`public.mikanseta_archives` 表及其用户隔离 RLS，无需复制一份云数据。

## 客户端配置

将 `Configuration/SupabaseClient.example.plist` 复制为同目录下的 `SupabaseClient.plist`，填写项目 HTTPS 根地址与 publishable / anon 客户端密钥。实际文件被 Git 忽略。也可沿用本机 `Mikanseta/LocalInstall/supabase.env`；生成器只读取项目地址与公开客户端密钥。

在源码根目录执行：

```sh
python3 Scripts/generate_project.py
python3 Scripts/generate_macos_project.py
```

生成器会校验并接入 App 资源。缺少配置时会生成离线工程；清洁检出后需先运行生成器再打开 Xcode。iPhone Widget 不包含客户端配置或账户会话。实际配置随 App 分发，不应包含管理凭据、`service_role`、数据库密码或私钥。

现有 Mikanseta 服务的基础表、RLS 和 Realtime 配置见 [现有配置说明](../Mikanseta/Documentation/SUPABASE_SETUP.md) 与 [基础 schema](../Mikanseta/Documentation/supabase-schema.sql)。已有表的项目不要重复初始化或清空数据。邮箱模板需要提供数字验证码；收不到邮件时由管理员检查邮箱服务、发送额度及 Auth 日志。

## 部署账户删除接口

管理员在同一项目的 SQL Editor 审阅并执行 [supabase-native-account.sql](supabase-native-account.sql)。它只创建 `mikansei_delete_account()`；部署时不删除数据。

接口没有目标用户参数，通过 `auth.uid()` 确定调用者，只允许 `authenticated` 执行。用户在 App 两次确认后调用，删除本人 `auth.users` 记录，现有表的外键级联删除其云归档。不要使用管理员密钥代替客户端调用。

当前仓库包含 SQL 与客户端调用；是否已部署以项目管理记录为准。不要通过删除真实用户来验证部署。发布 TestFlight 前，管理员应确认接口和权限，并用专用审核账号完成登录、同步及删除流程。

删除不会清除设备本地副本或导出的备份；已有访问令牌可能在过期前仍有效，后续刷新会失败。此行为在 App 确认文案和隐私资料中说明。

## 数据与同步边界

- 原生本机 JSON 仍是 `EntryArchive` v1；新增可选 `cloudArchiveState`，旧文件仍可读取。
- 云协议沿用 Flutter v1 的事项时间戳与 `tombstones` / `courseTombstones`，与文件夹同步的 Lamport replica 分开。云端的 `replica` 不会作为当前设备副本重放。
- 未识别的顶层、事项和课程字段会保留在本机兼容缓存中，回传时覆盖原生已知字段。日历授权和来源选择仍保持本机设置。
- 云合并先落盘，成功后才上传；坏归档或保存失败会暂停本次同步。归档条件更新发生冲突时重新获取、合并，最多尝试三轮。
- 每个设备的本机事项会在确认后与当前账号合并；换账号不会自动清空本机事项。云兼容缓存按 Supabase 项目和用户隔离。

## 发布与验证

`Scripts/prepare_testflight.py` 会把经过验证的公开客户端配置复制到准备目录。不要直接打包 `LocalInstall/`。隐私、审核与交接文案见 [TestFlight 资料](TestFlight/README.md)，实际构建证据见 [验证记录](../VALIDATION.md)。
