-- 原生 Mikansei 账户删除接口。与 Mikanseta 使用同一 Supabase 项目。
-- 只创建接口，不会在执行本文件时删除任何账户或归档。
-- 在已有 mikanseta_archives 表及 RLS 的项目中，由项目管理员执行一次。
-- 不需要把 service_role、数据库密码或管理令牌放入 App。

begin;

create or replace function public.mikansei_delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requesting_user uuid := auth.uid();
begin
  -- 角色权限由下方 EXECUTE 授权限制；身份来自已验证 JWT 的 auth.uid()。
  if requesting_user is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  -- 调用者没有传入目标用户的参数；只能删除自己。
  -- mikanseta_archives.user_id 的 ON DELETE CASCADE 同时清除该账户云归档。
  delete from auth.users where id = requesting_user;
  if not found then
    raise exception 'Account no longer exists' using errcode = 'P0002';
  end if;
end;
$function$;

revoke all on function public.mikansei_delete_account()
  from public, anon, authenticated, service_role;
grant execute on function public.mikansei_delete_account() to authenticated;

comment on function public.mikansei_delete_account() is
  'Deletes only the authenticated caller and its cascading account data. No target user argument.';

commit;
