# Mikanseta 账户同步 · Supabase 配置指南

Mikanseta 0.3.0 (5) 起支持登录 Supabase 账号，同一账号的 iPhone、安卓与 Mac 之间基本实时同步全部数据：待办、作业、日程、笔记、Checklist、完成状态、专注计时与课表。服务器端是你自己的 Supabase 免费项目，成本 ¥0。

## 一、一次性配置（约 5 分钟）

1. **建表**：打开 Supabase 项目 → 左侧 **SQL Editor** → New query → 粘贴 [`supabase-schema.sql`](supabase-schema.sql) 的内容并 Run。它创建 `mikanseta_archives` 表（每账号一行）、行级安全策略，并把表加入实时推送。
2. **取两个值**：**Project Settings → API**（新界面在 Settings → API Keys）里复制：
   - **Project URL**：形如 `https://xxxxxxxxxxxx.supabase.co`
   - **anon key**（新界面可能叫 publishable key）：一长串 `eyJ...` 的 JWT
3. **写入本地配置**（不入 Git）：
   ```sh
   cd Mikanseta
   cp Scripts/supabase.env.example LocalInstall/supabase.env
   # 编辑 LocalInstall/supabase.env，填入上面两个值
   ```
   `LocalInstall/` 已被 .gitignore 忽略，密钥不会进入仓库。
4. **重新构建安装**：双击 `安装到iPhone.command`、`生成安卓安装包.command` 或 `打开Mac测试版.command`。脚本会自动读取 env 文件并通过 `--dart-define` 注入；没配置时照常构建，只是设置里显示"未配置"。
5. **登录**：App → 设置 → 账户同步 → 输入邮箱 → 发送验证码 → 填入邮件里的 6 位验证码登录。在每台设备上用**同一邮箱**登录。

登录方式是邮箱验证码（OTP），没有密码。Supabase 默认的 Email provider 已开启，无需改动；Authentication → Providers 里不要关闭它。

### 让验证码出现在邮件里（必做一次）

Supabase 默认的邮件模板只有链接、没有数字码，而 App 登录需要 6 位数字码。请在控制台 **Authentication → Emails**（旧界面为 Authentication → Email Templates）里，把 **Confirm signup** 和 **Magic Link** 两个模板的正文都替换为：

```html
<h2>Mikanseta 登录验证码</h2>
<p>在 App 的“账户同步”里填入下面的 6 位验证码：</p>
<p style="font-size:32px;font-weight:700;letter-spacing:10px;margin:16px 0">{{ .Token }}</p>
<p>验证码 1 小时内有效。也可以直接点击链接：<br /><a href="{{ .ConfirmationURL }}">登录</a></p>
```

保存即可。邮件里的链接仍会跳到 Site URL（新项目默认 `http://localhost:3000`，显示“拒绝连接”是正常现象），忽略链接、只用数字码。

**首次用某个邮箱登录分两步**（未改模板时的旧流程）：第一次收到的是标题 **Confirm your email address** 的邮件，只有链接；点一次确认邮箱后再回 App 重新发送验证码。改好模板后首封邮件也带数字码，可直接登录；该邮箱在之后所有设备上都只需输入验证码。

## 二、同步行为

- 每次本机保存成功后约 2 秒上传；其他设备通过实时频道秒级收到变更、拉取合并。手动入口是设置 → 账户同步 → **立即同步**；回到前台时也会自动同步一次。
- 首次在新设备登录会把本机数据与账户数据**合并**，不会清空任何一端。之后两端同时修改不同事项会各自保留；同一事项按更新时间保留较新版本。
- **删除会同步**：删除带墓碑标记，另一台设备的旧副本不会把已删事项复活。删除后又编辑的事项视为重新创建，会保留。
- 系统日历来源、日历权限是按设备的设置，不随账户同步；外观等偏好随账户同步。
- 两台设备同时专注计时会保留较新的一台，另一台自动暂停并保留累计用时。
- 退出登录只断开本机连接，本机数据保留，账户与其它设备不受影响。

## 三、免费额度与限制（2026-10 查证，以 Supabase 官网为准）

| 项目 | 免费档 | 影响 |
| --- | --- | --- |
| 数据库 | 500 MB | 一份 Archive 约几十至几百 KB，个人多年用量远低于上限 |
| 认证 | 50,000 月活用户 | 个人设备远低于上限 |
| Realtime | 200 并发连接、每月 200 万条消息 | 几台设备常驻在线远低于上限 |
| 内置验证码邮件 | 每小时 2 封 | 登录不频繁即可；登录状态保存在本机，无需反复登录 |
| 项目暂停 | 一周无 API 活动会暂停 | 日常使用即算活动；暂停后在控制台一键恢复 |

## 四、隐私与边界须知

- 同步数据**明文**存放在你自己的 Supabase 项目中，行级安全保证只有登录者本人可读写；这不是端到端加密。介意的话不要同步敏感内容。
- 旧版 Mikanseta（0.2.0 及以前，无墓碑逻辑）不要与 0.3.0+ 混用同一账号，否则删除可能复活。
- 两台安卓手机同时导入同一个系统日历来源时，可能产生跨设备重复日程；当前单安卓设备场景不受影响。
- anon key 本身按设计可放在客户端，真正的访问控制由行级安全策略承担；但仍建议仓库不提交它（本项目通过 git 忽略的 env 文件注入）。

## 五、常见问题

- **收不到验证码**：内置发件人 `noreply@mail.app.supabase.co` 常进垃圾箱；一小时内超过 2 封会被限流，稍后再试。
- **邮件里没有验证码，只有链接**：邮件模板还没改。按上文"让验证码出现在邮件里（必做一次）"把 `{{ .Token }}` 加进 Confirm signup 与 Magic Link 模板；在此之前首次登录只能靠邮件里的确认链接。
- **设置里显示"未配置"**：构建时没读到 `LocalInstall/supabase.env`。确认文件存在且两行都以 `SUPABASE_URL=` / `SUPABASE_ANON_KEY=` 开头，再重新构建。
- **同步提示错误**：本机数据始终保留，回到前台或点"立即同步"重试；若持续失败，检查设备联网与项目是否被暂停（控制台恢复）。
- **换了 Supabase 项目**：把新值写进 env 重新构建即可；旧项目数据不会自动迁移，可先在一台设备导出 JSON 备份再导入。
