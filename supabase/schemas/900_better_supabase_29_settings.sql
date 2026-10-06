-- better-supabase module: settings (0.5.1)
-- @bs-module settings@1 managed
-- Per-user and per-organization settings as key-value jsonb rows. Users read and write their own; organization settings check settings.read and settings.update. Keys with a JSON Schema in options.schemas get a pg_jsonschema check.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
create policy "user_settings_own" on "better_supabase"."user_settings" for all to authenticated
  using ("user_id" = (select auth.uid()))
  with check ("user_id" = (select auth.uid()));

create table if not exists "better_supabase"."organization_settings" (
  "organization_id" uuid not null,
  "key" text not null check ("key" ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'),
  "value" jsonb not null,
  "updated_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "updated_at" timestamptz not null default now(),
  primary key ("organization_id", "key")
);
create index if not exists organization_settings_updated_by_idx on "better_supabase"."organization_settings" ("updated_by");
alter table "better_supabase"."organization_settings" enable row level security;
revoke all on "better_supabase"."organization_settings" from anon, authenticated;
grant select, insert, update, delete on "better_supabase"."organization_settings" to authenticated;
grant all on "better_supabase"."organization_settings" to service_role;
drop policy if exists "organization_settings_read" on "better_supabase"."organization_settings";
create policy "organization_settings_read" on "better_supabase"."organization_settings" for select to authenticated
  using (coalesce(better_supabase.can('tenant', "organization_id", 'settings.read'), false));
drop policy if exists "organization_settings_insert" on "better_supabase"."organization_settings";
create policy "organization_settings_insert" on "better_supabase"."organization_settings" for insert to authenticated
  with check (coalesce(better_supabase.can('tenant', "organization_id", 'settings.update'), false));
drop policy if exists "organization_settings_update" on "better_supabase"."organization_settings";
create policy "organization_settings_update" on "better_supabase"."organization_settings" for update to authenticated
  using (coalesce(better_supabase.can('tenant', "organization_id", 'settings.update'), false))
  with check (coalesce(better_supabase.can('tenant', "organization_id", 'settings.update'), false));
drop policy if exists "organization_settings_delete" on "better_supabase"."organization_settings";
create policy "organization_settings_delete" on "better_supabase"."organization_settings" for delete to authenticated
  using (coalesce(better_supabase.can('tenant', "organization_id", 'settings.update'), false));

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
  insert into "better_supabase"."user_settings" ("user_id", "key", "value")
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb))
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

create or replace function "better_supabase"."get_organization_settings"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."organization_settings" s
  where s."organization_id" = get_organization_settings.tenant
$$;

create or replace function "better_supabase"."set_organization_setting"(tenant uuid, key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."organization_settings" ("organization_id", "key", "value")
  values (set_organization_setting.tenant, set_organization_setting.key, coalesce(set_organization_setting.value -> 'value', 'null'::jsonb))
  on conflict ("organization_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$$;

create or replace function "better_supabase"."reset_organization_setting"(tenant uuid, key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."organization_settings" s
    where s."organization_id" = reset_organization_setting.tenant and s."key" = reset_organization_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$$;

revoke execute on function "better_supabase"."get_user_settings"() from public, anon;
revoke execute on function "better_supabase"."set_user_setting"(text, jsonb) from public, anon;
revoke execute on function "better_supabase"."reset_user_setting"(text) from public, anon;
revoke execute on function "better_supabase"."get_organization_settings"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_organization_setting"(uuid, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."reset_organization_setting"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_user_settings"() to authenticated, service_role;
grant execute on function "better_supabase"."set_user_setting"(text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."reset_user_setting"(text) to authenticated, service_role;
grant execute on function "better_supabase"."get_organization_settings"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_organization_setting"(uuid, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."reset_organization_setting"(uuid, text) to authenticated, service_role;

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
