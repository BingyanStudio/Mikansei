-- Mikanseta 账户同步的 Supabase 表结构。
-- 在 Supabase 控制台 → SQL Editor → New query 粘贴并执行一次即可。
-- 用法与配置见 Documentation/SUPABASE_SETUP.md。

create table if not exists public.mikanseta_archives (
  user_id uuid primary key references auth.users (id) on delete cascade,
  revision bigint not null,
  updated_at timestamptz not null default now(),
  content text not null
);

-- 行级安全：每个登录用户只能读写自己那一行（每账号一行完整 Archive JSON）。
alter table public.mikanseta_archives enable row level security;

-- Realtime 需要完整行才能按 RLS 过滤推送。
alter table public.mikanseta_archives replica identity full;

drop policy if exists "mikanseta_own_row" on public.mikanseta_archives;
create policy "mikanseta_own_row" on public.mikanseta_archives
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 把表加入实时推送，客户端按 user_id 订阅自己那一行的变更。
alter publication supabase_realtime add table public.mikanseta_archives;
