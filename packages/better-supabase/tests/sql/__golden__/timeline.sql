-- ==== alone: schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:2f4f0028e3fd2d8ebd0b3651b4fb05c1e55f875d5a0a4f8101d354b247d55540
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists activity_entries_read on "better_supabase"."activity_entries";
create policy activity_entries_read on "better_supabase"."activity_entries" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')));
drop function if exists "better_supabase"."activity_subject_readable"(text, text);
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
create policy bsb_tenant_scope on "better_supabase"."activity_entries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:2f4f0028e3fd2d8ebd0b3651b4fb05c1e55f875d5a0a4f8101d354b247d55540
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists activity_entries_read on "better_supabase"."activity_entries";
create policy activity_entries_read on "better_supabase"."activity_entries" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')));
drop function if exists "better_supabase"."activity_subject_readable"(text, text);
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
create policy bsb_tenant_scope on "better_supabase"."activity_entries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:48dd3f9dafacc4ccc3825830a04838116850a025f594982fda7605dfb66c243d
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "app_private"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "app_private"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "app_private"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "app_private"."activity_entries" ("actor_id");
alter table "app_private"."activity_entries" enable row level security;
revoke all on "app_private"."activity_entries" from anon, authenticated;
grant select on "app_private"."activity_entries" to authenticated;
grant all on "app_private"."activity_entries" to service_role;
drop policy if exists activity_entries_read on "app_private"."activity_entries";
create policy activity_entries_read on "app_private"."activity_entries" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')));
drop function if exists "app_private"."activity_subject_readable"(text, text);
drop function if exists "app_private"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "app_private"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "app_private"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "app_private"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "app_private"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "app_private"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "app_private"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."activity_entries";
create policy bsb_tenant_scope on "app_private"."activity_entries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:848dd5c2d8370af1519a6c31f2bd9ba2c87ec26611a52d6bef3bf90c5146a9d2
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists activity_entries_read on "better_supabase"."activity_entries";
create policy activity_entries_read on "better_supabase"."activity_entries" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')));
drop function if exists "better_supabase"."activity_subject_readable"(text, text);
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
create policy bsb_tenant_scope on "better_supabase"."activity_entries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.timeline.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."list_activity"(tenant uuid, subject_type text default null, subject_id text default null, before timestamptz default null, max_rows integer default 50, sources text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_activity"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
grant execute on function "api"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;

create or replace function "api"."record_activity"(batch jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_activity"($1) $$;
revoke execute on function "api"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "api"."record_activity"(jsonb) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:ff2852ded19ad7687dbd37c16c36c389ac514085831f213aaa4e4b1e77a896a2
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
-- better_supabase.activity_entries is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."activity_entries" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."activity_entries" add column if not exists "organization_id" uuid;
alter table "better_supabase"."activity_entries" add column if not exists "event_id" text;
alter table "better_supabase"."activity_entries" add column if not exists "type" text;
alter table "better_supabase"."activity_entries" add column if not exists "actor_id" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."activity_entries" add column if not exists "subject_type" text;
alter table "better_supabase"."activity_entries" add column if not exists "subject_id" text;
alter table "better_supabase"."activity_entries" add column if not exists "summary" text;
alter table "better_supabase"."activity_entries" add column if not exists "data" jsonb not null default '{}'::jsonb;
alter table "better_supabase"."activity_entries" add column if not exists "occurred_at" timestamptz not null default now();
create unique index if not exists "activity_entries_event_id_key" on "better_supabase"."activity_entries" ("event_id");
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists bsb_activity_entries_select on "better_supabase"."activity_entries";
create policy bsb_activity_entries_select on "better_supabase"."activity_entries" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')));
drop function if exists "better_supabase"."activity_subject_readable"(text, text);
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
create policy bsb_tenant_scope on "better_supabase"."activity_entries" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block timeline@1 managed
-- @bsb-hash sha256:21323422e67ef1d8eeead981dcf99e6350f9a3c0fe28d50178f5a114404fce3e
-- An activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("org_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("org_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists activity_entries_read on "better_supabase"."activity_entries";
create policy activity_entries_read on "better_supabase"."activity_entries" for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('activity.read')));
drop function if exists "better_supabase"."activity_subject_readable"(text, text);
drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "org_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: event for an activity entry.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."org_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."activity_entries";
create policy bsb_tenant_scope on "better_supabase"."activity_entries" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('activity.read')))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_131_timeline.sql
-- better-supabase module: timeline
-- @bsb-block-data timeline
-- @bsb-hash sha256:bb23b7cd67670a73cbec8ff09f4097d1e4368fe94954344993bab88288bc8070
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('timeline', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
