-- ==== alone: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:d72b8e82046d5e865366fcca6be91c72f121a289da7d78597f6c0207ebd54e2c
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
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
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table if not exists "better_supabase"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null check (length("title") between 1 and 200),
  "body" text not null default '' check (length("body") <= 10000),
  "severity" text not null default 'info' check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" is null or "ends_at" > "starts_at"),
  check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
alter table "better_supabase"."announcements" drop constraint if exists bsb_announcements_audience;
alter table "better_supabase"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role'));
create index if not exists announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index if not exists announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
revoke all on "better_supabase"."announcements" from anon, authenticated;
grant all on "better_supabase"."announcements" to service_role;

create table if not exists "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid not null references "better_supabase"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index if not exists announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
revoke all on "better_supabase"."announcement_dismissals" from anon, authenticated;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform).
create or replace function "better_supabase"."list_announcements"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."delete_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
drop trigger if exists "bsb_announcements_broadcast" on "better_supabase"."announcements";
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_announcements_receive" on realtime.messages;
    create policy "bsb_announcements_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');
  end if;
end;
$$;

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"() from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"() to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_announcement"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:1d20e9548ead2c8b7b94fe4b912eb1a8785b5a92676f0c5f0c8c854ef432ed78
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
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
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table if not exists "better_supabase"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null check (length("title") between 1 and 200),
  "body" text not null default '' check (length("body") <= 10000),
  "severity" text not null default 'info' check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" is null or "ends_at" > "starts_at"),
  check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
alter table "better_supabase"."announcements" drop constraint if exists bsb_announcements_audience;
alter table "better_supabase"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role', 'plan'));
create index if not exists announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index if not exists announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
revoke all on "better_supabase"."announcements" from anon, authenticated;
grant all on "better_supabase"."announcements" to service_role;

create table if not exists "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid not null references "better_supabase"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index if not exists announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
revoke all on "better_supabase"."announcement_dismissals" from anon, authenticated;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        when 'plan' then v_tenant is not null and x."targets" && better_supabase.tenant_entitlements(v_tenant)
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform).
create or replace function "better_supabase"."list_announcements"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('announcement.saved', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.saved',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."delete_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform "better_supabase".emit_event('announcement.deleted', jsonb_build_object('announcementId', delete_announcement.id), 'announcements/' || delete_announcement.id::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.deleted',
    category => 'configuration',
    target_type => 'announcement',
    record_id => delete_announcement.id::text,
    metadata => jsonb_build_object('announcementId', delete_announcement.id)
  );
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
drop trigger if exists "bsb_announcements_broadcast" on "better_supabase"."announcements";
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_announcements_receive" on realtime.messages;
    create policy "bsb_announcements_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');
  end if;
end;
$$;

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"() from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"() to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_announcement"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:d55f6df5e12b8b0d6f46e3c393336cf2ec61078d2740bd9dfa72a5ecc7ea1c25
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
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
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table if not exists "app_private"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null check (length("title") between 1 and 200),
  "body" text not null default '' check (length("body") <= 10000),
  "severity" text not null default 'info' check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" is null or "ends_at" > "starts_at"),
  check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
alter table "app_private"."announcements" drop constraint if exists bsb_announcements_audience;
alter table "app_private"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role'));
create index if not exists announcements_window_idx on "app_private"."announcements" ("starts_at", "ends_at");
create index if not exists announcements_created_by_idx on "app_private"."announcements" ("created_by");
alter table "app_private"."announcements" enable row level security;
revoke all on "app_private"."announcements" from anon, authenticated;
grant all on "app_private"."announcements" to service_role;

create table if not exists "app_private"."announcement_dismissals" (
  "announcement_id" uuid not null references "app_private"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index if not exists announcement_dismissals_user_idx on "app_private"."announcement_dismissals" ("user_id");
alter table "app_private"."announcement_dismissals" enable row level security;
revoke all on "app_private"."announcement_dismissals" from anon, authenticated;
grant all on "app_private"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "app_private"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "app_private"."announcements" x
    where x."starts_at" <= now()
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "app_private"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "app_private"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "app_private"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "app_private"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform).
create or replace function "app_private"."list_announcements"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "app_private"."announcements" x
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "app_private"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"app_private"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "app_private"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "app_private"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "app_private"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "app_private"."delete_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "app_private"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "app_private"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."broadcast_announcement"() from public, anon, authenticated;
drop trigger if exists "bsb_announcements_broadcast" on "app_private"."announcements";
create trigger "bsb_announcements_broadcast" after insert or update or delete on "app_private"."announcements"
  for each row execute function "app_private"."broadcast_announcement"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_announcements_receive" on realtime.messages;
    create policy "bsb_announcements_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');
  end if;
end;
$$;

revoke execute on function "app_private"."active_announcements"(uuid) from public, anon;
revoke execute on function "app_private"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "app_private"."list_announcements"() from public, anon;
revoke execute on function "app_private"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "app_private"."delete_announcement"(uuid) from public, anon;
grant execute on function "app_private"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "app_private"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "app_private"."list_announcements"() to authenticated, service_role;
grant execute on function "app_private"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "app_private"."delete_announcement"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:86291466420729a4ec627dc02433c765df4164100ed90c976ef01d895021f474
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
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
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table if not exists "better_supabase"."announcements" (
  "id" uuid primary key default gen_random_uuid(),
  "title" text not null check (length("title") between 1 and 200),
  "body" text not null default '' check (length("body") <= 10000),
  "severity" text not null default 'info' check ("severity" in ('info', 'success', 'warning', 'critical')),
  "href" text check ("href" ~ '^(https://|/)'),
  "audience" text not null default 'all',
  "targets" text[] not null default '{}',
  "starts_at" timestamptz not null default now(),
  "ends_at" timestamptz,
  "dismissible" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" is null or "ends_at" > "starts_at"),
  check (("audience" = 'all') = (cardinality("targets") = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
alter table "better_supabase"."announcements" drop constraint if exists bsb_announcements_audience;
alter table "better_supabase"."announcements" add constraint bsb_announcements_audience check ("audience" in ('all', 'tenant', 'role'));
create index if not exists announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index if not exists announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
revoke all on "better_supabase"."announcements" from anon, authenticated;
grant all on "better_supabase"."announcements" to service_role;

create table if not exists "better_supabase"."announcement_dismissals" (
  "announcement_id" uuid not null references "better_supabase"."announcements" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "dismissed_at" timestamptz not null default now(),
  primary key ("announcement_id", "user_id")
);
create index if not exists announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
revoke all on "better_supabase"."announcement_dismissals" from anon, authenticated;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform).
create or replace function "better_supabase"."list_announcements"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."delete_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
drop trigger if exists "bsb_announcements_broadcast" on "better_supabase"."announcements";
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_announcements_receive" on realtime.messages;
    create policy "bsb_announcements_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');
  end if;
end;
$$;

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"() from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"() to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_announcement"(uuid) to authenticated, service_role;

-- blocks.announcements.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."active_announcements"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."active_announcements"($1) $$;
revoke execute on function "api"."active_announcements"(uuid) from public, anon;
grant execute on function "api"."active_announcements"(uuid) to authenticated, service_role;

create or replace function "api"."dismiss_announcement"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dismiss_announcement"($1) $$;
revoke execute on function "api"."dismiss_announcement"(uuid) from public, anon;
grant execute on function "api"."dismiss_announcement"(uuid) to authenticated, service_role;

create or replace function "api"."list_announcements"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_announcements"() $$;
revoke execute on function "api"."list_announcements"() from public, anon;
grant execute on function "api"."list_announcements"() to authenticated, service_role;

create or replace function "api"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_announcement"($1, $2) $$;
revoke execute on function "api"."save_announcement"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_announcement"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_announcement"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_announcement"($1) $$;
revoke execute on function "api"."delete_announcement"(uuid) from public, anon;
grant execute on function "api"."delete_announcement"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block announcements@1 managed
-- @bsb-hash sha256:72a8e54be1bd8ceec77b7882234062c2569f3f53c483a5cf99cf2e95591d78e0
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
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
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
-- better_supabase.announcements is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."announcements" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."announcements" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."announcements" add column if not exists "body" text not null default '' check (length("body") <= 10000);
alter table "better_supabase"."announcements" add column if not exists "severity" text not null default 'info' check ("severity" in ('info', 'success', 'warning', 'critical'));
alter table "better_supabase"."announcements" add column if not exists "href" text check ("href" ~ '^(https://|/)');
alter table "better_supabase"."announcements" add column if not exists "audience" text not null default 'all';
alter table "better_supabase"."announcements" add column if not exists "targets" text[] not null default '{}';
alter table "better_supabase"."announcements" add column if not exists "starts_at" timestamptz not null default now();
alter table "better_supabase"."announcements" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."announcements" add column if not exists "dismissible" boolean not null default true;
alter table "better_supabase"."announcements" add column if not exists "created_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."announcements" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."announcements" add column if not exists "updated_at" timestamptz not null default now();
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
create index if not exists announcements_window_idx on "better_supabase"."announcements" ("starts_at", "ends_at");
create index if not exists announcements_created_by_idx on "better_supabase"."announcements" ("created_by");
alter table "better_supabase"."announcements" enable row level security;
grant all on "better_supabase"."announcements" to service_role;

-- better_supabase.announcement_dismissals is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."announcement_dismissals" add column if not exists "announcement_id" uuid references "better_supabase"."announcements" ("id") on delete cascade;
alter table "better_supabase"."announcement_dismissals" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."announcement_dismissals" add column if not exists "dismissed_at" timestamptz not null default now();
create index if not exists announcement_dismissals_user_idx on "better_supabase"."announcement_dismissals" ("user_id");
create unique index if not exists "bsb_announcement_dismissals_key" on "better_supabase"."announcement_dismissals" ("announcement_id", "user_id");
alter table "better_supabase"."announcement_dismissals" enable row level security;
grant all on "better_supabase"."announcement_dismissals" to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function "better_supabase"."active_announcements"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'targets' order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
    where x."starts_at" <= now()
      and (x."ends_at" is null or x."ends_at" > now())
      and case x."audience"
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x."targets")
        when 'role' then v_role is not null and v_role = any (x."targets")
        
        else false
      end
      and not exists (
        select 1 from "better_supabase"."announcement_dismissals" s
        where s."announcement_id" = x."id" and s."user_id" = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function "better_supabase"."dismiss_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform).
create or replace function "better_supabase"."list_announcements"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."starts_at" desc), '[]'::jsonb)
    from "better_supabase"."announcements" x
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function "better_supabase"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" ("id", "title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "created_by", "created_at", "updated_at") select v_row."id", v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."created_by", v_row."created_at", v_row."updated_at" returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."delete_announcement"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    null;
  end if;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the announcements topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function "better_supabase"."broadcast_announcement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new."id", old."id"), 'operation', lower(tg_op)),
      'announcement_changed',
      'announcements',
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."broadcast_announcement"() from public, anon, authenticated;
drop trigger if exists "bsb_announcements_broadcast" on "better_supabase"."announcements";
create trigger "bsb_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_announcements_receive" on realtime.messages;
    create policy "bsb_announcements_receive" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'announcements');
  end if;
end;
$$;

revoke execute on function "better_supabase"."active_announcements"(uuid) from public, anon;
revoke execute on function "better_supabase"."dismiss_announcement"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_announcements"() from public, anon;
revoke execute on function "better_supabase"."save_announcement"(uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."delete_announcement"(uuid) from public, anon;
grant execute on function "better_supabase"."active_announcements"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."dismiss_announcement"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_announcements"() to authenticated, service_role;
grant execute on function "better_supabase"."save_announcement"(uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."delete_announcement"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_039_announcements.sql
-- better-supabase module: announcements
-- @bsb-block-data announcements
-- @bsb-hash sha256:60ebe88a3adfda6790a201adc72f29be4d50593ece2281d013078f8e48a2dc8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('announcements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
