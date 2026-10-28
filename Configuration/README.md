# Supabase 客户端配置

原生 Mikansei 与 Mikanseta 使用同一 Supabase 项目、邮箱验证码登录和 `mikanseta_archives` 表。

本机可把示例复制为 `SupabaseClient.plist`，填写 HTTPS 项目地址以及 **publishable / anon 客户端密钥**。实际文件被 Git 忽略。若没有该文件，项目生成器会依次读取原生 `LocalInstall/supabase.env` 或现有 `Mikanseta/LocalInstall/supabase.env`，只提取上述两个客户端值。

生成器把通过校验的 `SupabaseClient.plist` 作为 App 资源接入 iOS / macOS。没有配置时仍可编译并离线使用，账户区域会提示服务未配置。

客户端值会随 App 分发，可以从安装包中读取；账户隔离依赖 Supabase Auth 与表的 RLS。不能填写 `service_role`、`sb_secret_`、数据库密码或管理令牌。构建脚本会拒绝管理密钥。

提供给发布者的源码交接包可以附带已校验的这份公开客户端配置，从而无需对方重新配置项目；它不包含后台管理凭据。
