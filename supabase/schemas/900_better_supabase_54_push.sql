-- better-supabase module: push (0.5.1)
-- @bs-module push@1 managed
-- The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The push tokens of each user's devices. A token belongs to one user: a
-- device that signs in as someone else moves its token to them. Apps write
-- through register_push_device and unregister_push_device; the sender reads
-- tokens with push_tokens_for and drops the ones the provider rejects with
-- prune_push_tokens, both service role only.
create table if not exists "better_supabase"."push_devices" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "token" text not null unique check (length("token") between 1 and 4096),
  "platform" text not null check ("platform" in ('ios', 'android', 'web')),
  "provider" text not null default 'expo' check ("provider" in ('expo', 'fcm', 'apns', 'webpush')),
  "device_name" text check (length("device_name") <= 200),
  "app_version" text check (length("app_version") <= 50),
  "created_at" timestamptz not null default now(),
  "last_seen_at" timestamptz not null default now()
);
create index if not exists push_devices_user_idx on "better_supabase"."push_devices" ("user_id");
alter table "better_supabase"."push_devices" enable row level security;
revoke all on "better_supabase"."push_devices" from anon, authenticated;
grant select, delete on "better_supabase"."push_devices" to authenticated;
grant all on "better_supabase"."push_devices" to service_role;
drop policy if exists "push_devices_own_read" on "better_supabase"."push_devices";
create policy "push_devices_own_read" on "better_supabase"."push_devices" for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists "push_devices_own_delete" on "better_supabase"."push_devices";
create policy "push_devices_own_delete" on "better_supabase"."push_devices" for delete to authenticated
  using ("user_id" = (select auth.uid()));

-- Registers the caller's device, or refreshes it; returns the device id.
create or replace function "better_supabase"."register_push_device"(
  token text,
  platform text,
  provider text default 'expo',
  device_name text default null,
  app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_new boolean;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if register_push_device.platform is null or register_push_device.platform not in ('ios', 'android', 'web') then
    raise exception 'Unknown push platform %', register_push_device.platform using errcode = '22023', hint = 'PUSH_PLATFORM';
  end if;
  if register_push_device.provider is null or register_push_device.provider not in ('expo', 'fcm', 'apns', 'webpush') then
    raise exception 'Unknown push provider %', register_push_device.provider using errcode = '22023', hint = 'PUSH_PROVIDER';
  end if;
  if register_push_device.token is null or length(register_push_device.token) not between 1 and 4096 then
    raise exception 'A push token is 1 to 4096 characters' using errcode = '22023', hint = 'PUSH_TOKEN';
  end if;
  insert into "better_supabase"."push_devices" as x ("user_id", "token", "platform", "provider", "device_name", "app_version")
  values (
    v_user,
    register_push_device.token,
    register_push_device.platform,
    register_push_device.provider,
    left(register_push_device.device_name, 200),
    left(register_push_device.app_version, 50)
  )
  on conflict ("token") do update set
    "user_id" = excluded."user_id",
    "platform" = excluded."platform",
    "provider" = excluded."provider",
    "device_name" = coalesce(excluded."device_name", x."device_name"),
    "app_version" = coalesce(excluded."app_version", x."app_version"),
    "last_seen_at" = now()
  returning x."id", (x.xmax = 0) into v_id, v_new;
  if v_new then
    null;
  end if;
  return v_id;
end;
$$;

-- Removes the caller's device with token, e.g. on sign-out; false when the
-- caller had none.
create or replace function "better_supabase"."unregister_push_device"(token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  delete from "better_supabase"."push_devices" x
  where x."token" = unregister_push_device.token
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."user_id" = v_user)
  returning x."id", x."user_id" into v_id, v_user;
  if v_id is null then
    return false;
  end if;
  null;
  return true;
end;
$$;

-- [{ userId, token, platform, provider }] for every device of users.
create or replace function "better_supabase"."push_tokens_for"(users uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tokens' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if push_tokens_for.users is null or cardinality(push_tokens_for.users) > 1000 then
    raise exception 'pass at most 1000 values' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', x."user_id",
      'token', x."token",
      'platform', x."platform",
      'provider', x."provider"
    ) order by x."user_id", x."last_seen_at" desc), '[]'::jsonb)
    from "better_supabase"."push_devices" x
    where x."user_id" = any (push_tokens_for.users)
  );
end;
$$;

-- Deletes the devices with tokens the provider rejected; returns how many.
create or replace function "better_supabase"."prune_push_tokens"(tokens text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tokens' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if prune_push_tokens.tokens is null or cardinality(prune_push_tokens.tokens) > 1000 then
    raise exception 'pass at most 1000 values' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  delete from "better_supabase"."push_devices" x where x."token" = any (prune_push_tokens.tokens);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function "better_supabase"."register_push_device"(text, text, text, text, text) from public, anon;
revoke execute on function "better_supabase"."unregister_push_device"(text) from public, anon;
revoke execute on function "better_supabase"."push_tokens_for"(uuid[]) from public, anon, authenticated;
revoke execute on function "better_supabase"."prune_push_tokens"(text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."register_push_device"(text, text, text, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."unregister_push_device"(text) to authenticated, service_role;
grant execute on function "better_supabase"."push_tokens_for"(uuid[]) to service_role;
grant execute on function "better_supabase"."prune_push_tokens"(text[]) to service_role;

-- sql.modules.push.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."register_push_device"(token text, platform text, provider text default 'expo', device_name text default null, app_version text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_push_device"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."register_push_device"(text, text, text, text, text) from public, anon;
grant execute on function "api"."register_push_device"(text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."unregister_push_device"(token text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unregister_push_device"($1) $$;
revoke execute on function "api"."unregister_push_device"(text) from public, anon;
grant execute on function "api"."unregister_push_device"(text) to authenticated, service_role;

create or replace function "api"."push_tokens_for"(users uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."push_tokens_for"($1) $$;
revoke execute on function "api"."push_tokens_for"(uuid[]) from public, anon, authenticated;
grant execute on function "api"."push_tokens_for"(uuid[]) to service_role;

create or replace function "api"."prune_push_tokens"(tokens text[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."prune_push_tokens"($1) $$;
revoke execute on function "api"."prune_push_tokens"(text[]) from public, anon, authenticated;
grant execute on function "api"."prune_push_tokens"(text[]) to service_role;

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
