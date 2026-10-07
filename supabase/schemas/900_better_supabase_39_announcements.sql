-- better-supabase module: announcements (0.5.1)
-- @bs-module announcements@1 managed
-- In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
alter table "better_supabase"."announcements" drop constraint if exists bs_announcements_audience;
alter table "better_supabase"."announcements" add constraint bs_announcements_audience check ("audience" in ('all', 'tenant', 'role', 'plan'));
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
    if v_role is null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
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
drop trigger if exists "bs_announcements_broadcast" on "better_supabase"."announcements";
create trigger "bs_announcements_broadcast" after insert or update or delete on "better_supabase"."announcements"
  for each row execute function "better_supabase"."broadcast_announcement"();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_announcements_receive" on realtime.messages;
    create policy "bs_announcements_receive" on realtime.messages for select to authenticated
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

-- sql.modules.announcements.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."active_announcements"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."active_announcements"($1) $$;
revoke execute on function "api"."active_announcements"(uuid) from public;
grant execute on function "api"."active_announcements"(uuid) to authenticated, service_role;

create or replace function "api"."dismiss_announcement"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dismiss_announcement"($1) $$;
revoke execute on function "api"."dismiss_announcement"(uuid) from public;
grant execute on function "api"."dismiss_announcement"(uuid) to authenticated, service_role;

create or replace function "api"."list_announcements"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_announcements"() $$;
revoke execute on function "api"."list_announcements"() from public;
grant execute on function "api"."list_announcements"() to authenticated, service_role;

create or replace function "api"."save_announcement"(id uuid, fields jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_announcement"($1, $2) $$;
revoke execute on function "api"."save_announcement"(uuid, jsonb) from public;
grant execute on function "api"."save_announcement"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_announcement"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_announcement"($1) $$;
revoke execute on function "api"."delete_announcement"(uuid) from public;
grant execute on function "api"."delete_announcement"(uuid) to authenticated, service_role;

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
