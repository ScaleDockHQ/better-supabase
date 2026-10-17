-- ==== schema supabase/schemas/900_better_supabase_29_settings.sql
-- better-supabase module: settings
-- @bs-module settings@1 managed
-- Per-user, per-organization and platform-wide settings as key-value jsonb rows. Users read and write their own; organization settings check settings.read and settings.update; platform settings check a platform permission per key. Keys with a JSON Schema in options.schemas get a pg_jsonschema check.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Settings as key-value rows. The app validates values with defineSettings();
-- keys with a JSON Schema also get a pg_jsonschema check below.
create table if not exists "better_supabase"."user_settings" (
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "key" text not null check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "value" jsonb not null,
  "updated_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "updated_at" timestamptz not null default now(),
  primary key ("user_id", "key")
);
create index if not exists user_settings_updated_by_idx on "better_supabase"."user_settings" ("updated_by");
alter table "better_supabase"."user_settings" enable row level security;
revoke all on "better_supabase"."user_settings" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."user_settings" to authenticated;
grant all on "better_supabase"."user_settings" to service_role;
drop policy if exists "user_settings_own" on "better_supabase"."user_settings";
drop policy if exists "user_settings_own_read" on "better_supabase"."user_settings";
create policy "user_settings_own_read" on "better_supabase"."user_settings" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "user_settings_own_insert" on "better_supabase"."user_settings";
create policy "user_settings_own_insert" on "better_supabase"."user_settings" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "user_settings_own_update" on "better_supabase"."user_settings";
create policy "user_settings_own_update" on "better_supabase"."user_settings" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists "user_settings_own_delete" on "better_supabase"."user_settings";
create policy "user_settings_own_delete" on "better_supabase"."user_settings" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create table if not exists "better_supabase"."workspace_settings" (
  "workspace_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "value" jsonb not null,
  "updated_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "updated_at" timestamptz not null default now(),
  primary key ("workspace_id", "key")
);
create index if not exists workspace_settings_updated_by_idx on "better_supabase"."workspace_settings" ("updated_by");
alter table "better_supabase"."workspace_settings" enable row level security;
revoke all on "better_supabase"."workspace_settings" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."workspace_settings" to authenticated;
grant all on "better_supabase"."workspace_settings" to service_role;
drop policy if exists "workspace_settings_read" on "better_supabase"."workspace_settings";
create policy "workspace_settings_read" on "better_supabase"."workspace_settings" for select to authenticated
  using ("workspace_id" in (select better_supabase.tenant_ids_with('settings.read')));
drop policy if exists "workspace_settings_insert" on "better_supabase"."workspace_settings";
create policy "workspace_settings_insert" on "better_supabase"."workspace_settings" for insert to authenticated
  with check ((coalesce(better_supabase.can('tenant', "workspace_id", 'settings.update'), false)) and (select better_supabase.actor_may_write()));
drop policy if exists "workspace_settings_update" on "better_supabase"."workspace_settings";
create policy "workspace_settings_update" on "better_supabase"."workspace_settings" for update to authenticated
  using (("workspace_id" in (select better_supabase.tenant_ids_with('settings.update'))) and (select better_supabase.actor_may_write()))
  with check (("workspace_id" in (select better_supabase.tenant_ids_with('settings.update'))) and (select better_supabase.actor_may_write()));
drop policy if exists "workspace_settings_delete" on "better_supabase"."workspace_settings";
create policy "workspace_settings_delete" on "better_supabase"."workspace_settings" for delete to authenticated
  using (("workspace_id" in (select better_supabase.tenant_ids_with('settings.update'))) and (select better_supabase.actor_may_write()));

-- Platform settings: one row per key for the whole product, such as fee
-- rates or feature switches an admin console edits. Each key's permission
-- (is_platform) guards writes, and its read rule decides who sees it.
create table if not exists "better_supabase"."platform_settings" (
  "key" text primary key check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "value" jsonb not null,
  "updated_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "updated_at" timestamptz not null default now()
);
create index if not exists platform_settings_updated_by_idx on "better_supabase"."platform_settings" ("updated_by");
alter table "better_supabase"."platform_settings" enable row level security;
revoke all on "better_supabase"."platform_settings" from anon, authenticated;
grant select on "better_supabase"."platform_settings" to anon;
grant select, insert, update, delete on "better_supabase"."platform_settings" to authenticated;
grant all on "better_supabase"."platform_settings" to service_role;
drop policy if exists "platform_settings_read" on "better_supabase"."platform_settings";
create policy "platform_settings_read" on "better_supabase"."platform_settings" for select to authenticated
  using (true);
drop policy if exists "platform_settings_read_public" on "better_supabase"."platform_settings";
create policy "platform_settings_read_public" on "better_supabase"."platform_settings" for select to anon
  using (false);
drop policy if exists "platform_settings_insert" on "better_supabase"."platform_settings";
create policy "platform_settings_insert" on "better_supabase"."platform_settings" for insert to authenticated
  with check ((coalesce(better_supabase.is_platform('settings.manage'), false)) and (select better_supabase.actor_may_write()));
drop policy if exists "platform_settings_update" on "better_supabase"."platform_settings";
create policy "platform_settings_update" on "better_supabase"."platform_settings" for update to authenticated
  using ((coalesce(better_supabase.is_platform('settings.manage'), false)) and (select better_supabase.actor_may_write()))
  with check ((coalesce(better_supabase.is_platform('settings.manage'), false)) and (select better_supabase.actor_may_write()));
drop policy if exists "platform_settings_delete" on "better_supabase"."platform_settings";
create policy "platform_settings_delete" on "better_supabase"."platform_settings" for delete to authenticated
  using ((coalesce(better_supabase.is_platform('settings.manage'), false)) and (select better_supabase.actor_may_write()));

-- The functions run as the caller, so the policies above decide. set_*
-- takes the value inside an envelope, { "value": ... }, so strings and
-- numbers reach jsonb the same way over Postgres and the Data API.
create or replace function "better_supabase"."get_user_settings"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."user_settings" s
  where s."user_id" = auth.uid()
$$;

create or replace function "better_supabase"."set_user_setting"(key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."user_settings" ("user_id", "key", "value", "updated_by", "updated_at")
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict ("user_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$$;

create or replace function "better_supabase"."reset_user_setting"(key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."user_settings" s where s."user_id" = auth.uid() and s."key" = reset_user_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

create or replace function "better_supabase"."get_workspace_settings"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."workspace_settings" s
  where s."workspace_id" = get_workspace_settings.tenant
$$;

create or replace function "better_supabase"."set_workspace_setting"(tenant uuid, key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."workspace_settings" ("workspace_id", "key", "value", "updated_by", "updated_at")
  values (set_workspace_setting.tenant, set_workspace_setting.key, coalesce(set_workspace_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict ("workspace_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$$;

create or replace function "better_supabase"."reset_workspace_setting"(tenant uuid, key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."workspace_settings" s
    where s."workspace_id" = reset_workspace_setting.tenant and s."key" = reset_workspace_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

create or replace function "better_supabase"."get_platform_settings"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."platform_settings" s
$$;

create or replace function "better_supabase"."set_platform_setting"(key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."platform_settings" ("key", "value", "updated_by", "updated_at")
  values (set_platform_setting.key, coalesce(set_platform_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict ("key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$$;

create or replace function "better_supabase"."reset_platform_setting"(key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."platform_settings" s where s."key" = reset_platform_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

revoke execute on function "better_supabase"."get_platform_settings"() from public;
revoke execute on function "better_supabase"."set_platform_setting"(text, jsonb) from public, anon;
revoke execute on function "better_supabase"."reset_platform_setting"(text) from public, anon;
grant execute on function "better_supabase"."get_platform_settings"() to anon, authenticated, service_role;
grant execute on function "better_supabase"."set_platform_setting"(text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."reset_platform_setting"(text) to authenticated, service_role;
revoke execute on function "better_supabase"."get_user_settings"() from public, anon;
revoke execute on function "better_supabase"."set_user_setting"(text, jsonb) from public, anon;
revoke execute on function "better_supabase"."reset_user_setting"(text) from public, anon;
revoke execute on function "better_supabase"."get_workspace_settings"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_workspace_setting"(uuid, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."reset_workspace_setting"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_user_settings"() to authenticated, service_role;
grant execute on function "better_supabase"."set_user_setting"(text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."reset_user_setting"(text) to authenticated, service_role;
grant execute on function "better_supabase"."get_workspace_settings"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_workspace_setting"(uuid, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."reset_workspace_setting"(uuid, text) to authenticated, service_role;

-- Records organization and platform setting changes; user settings are not
-- recorded.
drop trigger if exists "bs_record_workspace_setting" on "better_supabase"."workspace_settings";
drop function if exists "better_supabase"."record_workspace_setting"();
drop trigger if exists "bs_record_platform_setting" on "better_supabase"."platform_settings";
drop function if exists "better_supabase"."record_platform_setting"();

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_29_settings.sql
-- better-supabase module: settings
-- @bs-module-data settings
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('settings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
