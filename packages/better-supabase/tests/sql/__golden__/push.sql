-- ==== alone: schema supabase/schemas/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block push@2 managed
-- @bsb-hash sha256:00a4bb4825baaa0b8102a08c2435806a26126ce58ede8a7c0282185dbc5bf445
-- The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
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
revoke all on "better_supabase"."push_devices" from public, anon, authenticated;
grant select, delete on "better_supabase"."push_devices" to authenticated;
grant all on "better_supabase"."push_devices" to service_role;
drop policy if exists "push_devices_own_read" on "better_supabase"."push_devices";
create policy "push_devices_own_read" on "better_supabase"."push_devices" for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists "push_devices_own_delete" on "better_supabase"."push_devices";
create policy "push_devices_own_delete" on "better_supabase"."push_devices" for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- Registers the caller's device, or refreshes it; returns the device id.
drop function if exists "better_supabase"."register_push_device"(text, text, text, text, text, jsonb);
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block-data push
-- @bsb-hash sha256:7b7d164757126320c261094b3bca9cb4cccefb671267b0edf6726ff5cdcc5e76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('push', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block push@2 managed
-- @bsb-hash sha256:606dcc831370a904d384628d593e99c29a4cb3a5506b9174bad8cd6aa9db7465
-- The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
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
revoke all on "better_supabase"."push_devices" from public, anon, authenticated;
grant select, delete on "better_supabase"."push_devices" to authenticated;
grant all on "better_supabase"."push_devices" to service_role;
drop policy if exists "push_devices_own_read" on "better_supabase"."push_devices";
create policy "push_devices_own_read" on "better_supabase"."push_devices" for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists "push_devices_own_delete" on "better_supabase"."push_devices";
create policy "push_devices_own_delete" on "better_supabase"."push_devices" for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- Registers the caller's device, or refreshes it; returns the device id.
drop function if exists "better_supabase"."register_push_device"(text, text, text, text, text, jsonb);
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    perform "better_supabase".emit_event('push.device_registered', jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text, 'platform', register_push_device.platform, 'provider', register_push_device.provider), 'push-devices/' || v_id::text, null, null, 'better-supabase/push');
  perform better_supabase.audit_event(
    event_type => 'push.device_registered',
    category => 'security',
    target_type => 'push_device',
    record_id => v_id::text,
    metadata => jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text, 'platform', register_push_device.platform, 'provider', register_push_device.provider)
  );
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  perform "better_supabase".emit_event('push.device_unregistered', jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text), 'push-devices/' || v_id::text, null, null, 'better-supabase/push');
  perform better_supabase.audit_event(
    event_type => 'push.device_unregistered',
    category => 'security',
    target_type => 'push_device',
    record_id => v_id::text,
    metadata => jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text)
  );
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

-- One row per delivery and device: the Expo ticket id, or the error Expo
-- answered. A retried delivery skips the devices that already have a ticket.
create table if not exists "better_supabase"."push_tickets" (
  "id" uuid primary key default gen_random_uuid(),
  "delivery_id" uuid not null references "better_supabase"."notification_deliveries" ("id") on delete cascade,
  "token" text not null,
  "ticket_id" text,
  "status" text not null default 'pending' check ("status" in ('pending', 'ok', 'error')),
  "error" text,
  "created_at" timestamptz not null default now(),
  "checked_at" timestamptz,
  unique ("delivery_id", "token")
);
create index if not exists push_tickets_unchecked_idx on "better_supabase"."push_tickets" ("created_at") where "checked_at" is null and "ticket_id" is not null;
alter table "better_supabase"."push_tickets" enable row level security;
revoke all on "better_supabase"."push_tickets" from public, anon, authenticated;
grant all on "better_supabase"."push_tickets" to service_role;

-- Stores the tickets of one delivery: [{ token, id } | { token, error }].
-- A ticket with an id replaces an earlier error for the same device and is
-- never replaced itself.
create or replace function "better_supabase"."record_push_tickets"(delivery uuid, tickets jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if jsonb_typeof(record_push_tickets.tickets) <> 'array' or jsonb_array_length(record_push_tickets.tickets) > 1000 then
    raise exception 'pass at most 1000 tickets' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  insert into "better_supabase"."push_tickets" as x ("delivery_id", "token", "ticket_id", "status", "error")
  select record_push_tickets.delivery, e ->> 'token', e ->> 'id',
    case when e ->> 'id' is null then 'error' else 'pending' end,
    e ->> 'error'
  from jsonb_array_elements(record_push_tickets.tickets) e
  where e ->> 'token' is not null
  on conflict ("delivery_id", "token") do update set
    "ticket_id" = coalesce(excluded."ticket_id", x."ticket_id"),
    "status" = case when x."ticket_id" is not null then x."status" else excluded."status" end,
    "error" = case
      when x."ticket_id" is not null then x."error"
      when excluded."ticket_id" is not null then null
      else excluded."error"
    end;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- [{ token, id, error }] already stored for a delivery, in insert order.
create or replace function "better_supabase"."push_tickets_for"(delivery uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'token', x."token",
      'id', x."ticket_id",
      'error', x."error"
    )) order by x."created_at", x."token"), '[]'::jsonb)
    from "better_supabase"."push_tickets" x
    where x."delivery_id" = push_tickets_for.delivery
  );
end;
$$;

-- [{ id, token, deliveryId }] for tickets older than older_than whose
-- receipt nobody read yet, oldest first.
create or replace function "better_supabase"."unchecked_push_tickets"(max_items integer default 1000, older_than interval default '15 minutes')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."ticket_id",
      'token', x."token",
      'deliveryId', x."delivery_id"
    ) order by x."created_at"), '[]'::jsonb)
    from (
      select * from "better_supabase"."push_tickets" y
      where y."checked_at" is null
        and y."ticket_id" is not null
        and y."created_at" <= now() - unchecked_push_tickets.older_than
      order by y."created_at"
      limit least(greatest(coalesce(unchecked_push_tickets.max_items, 1000), 1), 1000)
    ) x
  );
end;
$$;

-- Stores what Expo answered for each ticket, [{ id, status: ok | error,
-- error, message }], and records notification.delivered or bounced on the
-- delivery when the notifications block tracks provider events. A ticket
-- Expo has no receipt for yet stays unchecked. Returns how many it stored.
create or replace function "better_supabase"."complete_push_receipts"(receipts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if jsonb_typeof(complete_push_receipts.receipts) <> 'array' or jsonb_array_length(complete_push_receipts.receipts) > 1000 then
    raise exception 'pass at most 1000 receipts' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  -- The delivery's provider message id is Expo's first ticket id, so every
  -- receipt of the delivery records its event on that message, once per
  -- ticket.
  perform "better_supabase"."record_delivery_event"(
    'expo',
    d."provider_message_id",
    case when r ->> 'status' = 'ok' then 'delivered' else 'bounced' end,
    'expo-receipt:' || (r ->> 'id'),
    now(),
    jsonb_strip_nulls(jsonb_build_object('token', x."token", 'error', r ->> 'error', 'message', r ->> 'message')),
    false
  )
  from "better_supabase"."push_tickets" x
  join "better_supabase"."notification_deliveries" d on d."id" = x."delivery_id"
  cross join jsonb_array_elements(complete_push_receipts.receipts) r
  where x."ticket_id" = r ->> 'id'
    and x."checked_at" is null
    and d."provider_message_id" is not null;
  update "better_supabase"."push_tickets" x set
    "status" = case when r ->> 'status' = 'ok' then 'ok' else 'error' end,
    "error" = case when r ->> 'status' = 'ok' then null else coalesce(r ->> 'error', 'Unknown') end,
    "checked_at" = now()
  from jsonb_array_elements(complete_push_receipts.receipts) r
  where x."ticket_id" = r ->> 'id'
    and x."checked_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."record_push_tickets"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."record_push_tickets"(uuid, jsonb) to service_role;
revoke execute on function "better_supabase"."push_tickets_for"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."push_tickets_for"(uuid) to service_role;
revoke execute on function "better_supabase"."unchecked_push_tickets"(integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."unchecked_push_tickets"(integer, interval) to service_role;
revoke execute on function "better_supabase"."complete_push_receipts"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_push_receipts"(jsonb) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block-data push
-- @bsb-hash sha256:7b7d164757126320c261094b3bca9cb4cccefb671267b0edf6726ff5cdcc5e76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('push', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block push@2 managed
-- @bsb-hash sha256:bc133f9da24ea1d9529919b7d2331d5b15a039dc77bcaaa0cd6a4d648b225c1d
-- The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- The push tokens of each user's devices. A token belongs to one user: a
-- device that signs in as someone else moves its token to them. Apps write
-- through register_push_device and unregister_push_device; the sender reads
-- tokens with push_tokens_for and drops the ones the provider rejects with
-- prune_push_tokens, both service role only.
create table if not exists "app_private"."push_devices" (
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
create index if not exists push_devices_user_idx on "app_private"."push_devices" ("user_id");
alter table "app_private"."push_devices" enable row level security;
revoke all on "app_private"."push_devices" from public, anon, authenticated;
grant select, delete on "app_private"."push_devices" to authenticated;
grant all on "app_private"."push_devices" to service_role;
drop policy if exists "push_devices_own_read" on "app_private"."push_devices";
create policy "push_devices_own_read" on "app_private"."push_devices" for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists "push_devices_own_delete" on "app_private"."push_devices";
create policy "push_devices_own_delete" on "app_private"."push_devices" for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- Registers the caller's device, or refreshes it; returns the device id.
drop function if exists "app_private"."register_push_device"(text, text, text, text, text, jsonb);
create or replace function "app_private"."register_push_device"(
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  insert into "app_private"."push_devices" as x ("user_id", "token", "platform", "provider", "device_name", "app_version")
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
create or replace function "app_private"."unregister_push_device"(token text)
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  delete from "app_private"."push_devices" x
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
create or replace function "app_private"."push_tokens_for"(users uuid[])
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
    from "app_private"."push_devices" x
    where x."user_id" = any (push_tokens_for.users)
  );
end;
$$;

-- Deletes the devices with tokens the provider rejected; returns how many.
create or replace function "app_private"."prune_push_tokens"(tokens text[])
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
  delete from "app_private"."push_devices" x where x."token" = any (prune_push_tokens.tokens);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function "app_private"."register_push_device"(text, text, text, text, text) from public, anon;
revoke execute on function "app_private"."unregister_push_device"(text) from public, anon;
revoke execute on function "app_private"."push_tokens_for"(uuid[]) from public, anon, authenticated;
revoke execute on function "app_private"."prune_push_tokens"(text[]) from public, anon, authenticated;
grant execute on function "app_private"."register_push_device"(text, text, text, text, text) to authenticated, service_role;
grant execute on function "app_private"."unregister_push_device"(text) to authenticated, service_role;
grant execute on function "app_private"."push_tokens_for"(uuid[]) to service_role;
grant execute on function "app_private"."prune_push_tokens"(text[]) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block-data push
-- @bsb-hash sha256:7b7d164757126320c261094b3bca9cb4cccefb671267b0edf6726ff5cdcc5e76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('push', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block push@2 managed
-- @bsb-hash sha256:aa76f8cb58be53afa974fa021e48f7783b8c0ab7319581fa3d4cd8e05d2bf69c
-- The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
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
revoke all on "better_supabase"."push_devices" from public, anon, authenticated;
grant select, delete on "better_supabase"."push_devices" to authenticated;
grant all on "better_supabase"."push_devices" to service_role;
drop policy if exists "push_devices_own_read" on "better_supabase"."push_devices";
create policy "push_devices_own_read" on "better_supabase"."push_devices" for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists "push_devices_own_delete" on "better_supabase"."push_devices";
create policy "push_devices_own_delete" on "better_supabase"."push_devices" for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- Registers the caller's device, or refreshes it; returns the device id.
drop function if exists "better_supabase"."register_push_device"(text, text, text, text, text, jsonb);
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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

-- blocks.push.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."register_push_device"(text, text, text, text, text, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

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
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block-data push
-- @bsb-hash sha256:7b7d164757126320c261094b3bca9cb4cccefb671267b0edf6726ff5cdcc5e76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('push', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block push@2 managed
-- @bsb-hash sha256:0f1e8f4479862f72962fab27f97286528c6ec4e42bac34e3369217348c07d677
-- The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
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
-- The push tokens of each user's devices. A token belongs to one user: a
-- device that signs in as someone else moves its token to them. Apps write
-- through register_push_device and unregister_push_device; the sender reads
-- tokens with push_tokens_for and drops the ones the provider rejects with
-- prune_push_tokens, both service role only.
-- better_supabase.push_devices is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."push_devices" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."push_devices" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."push_devices" add column if not exists "token" text check (length("token") between 1 and 4096);
alter table "better_supabase"."push_devices" add column if not exists "platform" text check ("platform" in ('ios', 'android', 'web'));
alter table "better_supabase"."push_devices" add column if not exists "provider" text not null default 'expo' check ("provider" in ('expo', 'fcm', 'apns', 'webpush'));
alter table "better_supabase"."push_devices" add column if not exists "device_name" text check (length("device_name") <= 200);
alter table "better_supabase"."push_devices" add column if not exists "app_version" text check (length("app_version") <= 50);
alter table "better_supabase"."push_devices" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."push_devices" add column if not exists "last_seen_at" timestamptz not null default now();
create index if not exists push_devices_user_idx on "better_supabase"."push_devices" ("user_id");
create unique index if not exists "bsb_push_devices_token_key" on "better_supabase"."push_devices" ("token");
alter table "better_supabase"."push_devices" enable row level security;
grant select, delete on "better_supabase"."push_devices" to authenticated;
grant all on "better_supabase"."push_devices" to service_role;
drop policy if exists bsb_push_devices_select on "better_supabase"."push_devices";
create policy bsb_push_devices_select on "better_supabase"."push_devices" for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists bsb_push_devices_delete on "better_supabase"."push_devices";
create policy bsb_push_devices_delete on "better_supabase"."push_devices" for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- Registers the caller's device, or refreshes it; returns the device id.
drop function if exists "better_supabase"."register_push_device"(text, text, text, text, text, jsonb);
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    better_supabase.as_column_type(register_push_device.platform, (null::"better_supabase"."push_devices")."platform"),
    better_supabase.as_column_type(register_push_device.provider, (null::"better_supabase"."push_devices")."provider"),
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_054_push.sql
-- better-supabase module: push
-- @bsb-block-data push
-- @bsb-hash sha256:7b7d164757126320c261094b3bca9cb4cccefb671267b0edf6726ff5cdcc5e76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('push', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
