# Supabase 客户端配置

原生 Mikansei 与 Mikanseta 使用同一 Supabase 项目、邮箱验证码登录和 `mikanseta_archives` 表。

仓库中的 **`SupabaseClient.public.plist`** 是经校验的公开客户端配置，随源码版本保存，供 Xcode Cloud 和全新检出直接使用。它只包含项目 HTTPS 地址和 publishable 客户端密钥，不含后台管理权限。

生成器按顺序读取本机 `SupabaseClient.plist`、原生 `LocalInstall/supabase.env`、`Mikanseta/LocalInstall/supabase.env`，最后使用上述公开配置。本机覆盖文件及生成的 `SupabaseClient.plist` 继续被 Git 忽略；公开配置文件已纳入 Git。不要把管理员密钥填写到任何客户端文件。

生成器把通过校验的配置写为 `SupabaseClient.plist`，作为 App 资源接入 iOS / macOS。Xcode Cloud 的 `ci_scripts/ci_post_clone.sh` 会自动执行此步骤，并检查工程资源、图标和主应用 / Widget 的版本及发布身份；归档后再核对实际产物。无需 Paul 额外填写 Supabase 环境变量或手工上传本机文件，详见 [云构建说明](../Documentation/TestFlight/XCODE_CLOUD.md)。

客户端值会随 App 分发，可以从安装包中读取；账户隔离依赖 Supabase Auth 与表的 RLS。不能填写 `service_role`、`sb_secret_`、数据库密码或管理令牌。构建脚本会拒绝管理密钥。

提供给发布者的源码交接包同时包含公开配置、生成资源及 CI 脚本。客户端配置完整不代表验证码投递、真实登录、同步或账号删除接口已经在线验收。
