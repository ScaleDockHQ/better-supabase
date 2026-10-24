-- ==== alone: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:1dbaf23dd1071894fbbcb32e7771539c05ad0ece94c50eb94d0f0f3984d1a390
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table if not exists "better_supabase"."field_changes" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index if not exists field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index if not exists field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index if not exists field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
drop policy if exists field_changes_read on "better_supabase"."field_changes";
create policy field_changes_read on "better_supabase"."field_changes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function "better_supabase"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z."id"::text,
    'organizationId', z."tenant_id",
    'subjectType', z."subject_type",
    'subjectId', z."subject_id",
    'field', z."field",
    'before', z."old_value",
    'after', z."new_value",
    'changedBy', z."changed_by",
    'changedAt', z."changed_at"
  ) order by z."id" desc), '[]'::jsonb)
  from (
    select x.* from "better_supabase"."field_changes" x
    where x."subject_type" = field_history.subject_type
      and x."subject_id" = field_history.subject_id
      and (field_history.field is null or x."field" = field_history.field)
      and (field_history.before is null or x."id" < field_history.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block-data field-history
-- @bsb-hash sha256:563bb02e577a82d70031527590e31e445260155bc6212649c68e4e88083c124f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('field-history', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:1dbaf23dd1071894fbbcb32e7771539c05ad0ece94c50eb94d0f0f3984d1a390
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table if not exists "better_supabase"."field_changes" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index if not exists field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index if not exists field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index if not exists field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
drop policy if exists field_changes_read on "better_supabase"."field_changes";
create policy field_changes_read on "better_supabase"."field_changes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function "better_supabase"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z."id"::text,
    'organizationId', z."tenant_id",
    'subjectType', z."subject_type",
    'subjectId', z."subject_id",
    'field', z."field",
    'before', z."old_value",
    'after', z."new_value",
    'changedBy', z."changed_by",
    'changedAt', z."changed_at"
  ) order by z."id" desc), '[]'::jsonb)
  from (
    select x.* from "better_supabase"."field_changes" x
    where x."subject_type" = field_history.subject_type
      and x."subject_id" = field_history.subject_id
      and (field_history.field is null or x."field" = field_history.field)
      and (field_history.before is null or x."id" < field_history.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block-data field-history
-- @bsb-hash sha256:563bb02e577a82d70031527590e31e445260155bc6212649c68e4e88083c124f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('field-history', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:c7b31cc0d89c11862ac8b43703294ccf5d312690448ffd7de4d080a8292eba66
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table if not exists "app_private"."field_changes" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index if not exists field_changes_subject_idx on "app_private"."field_changes" ("subject_type", "subject_id", "id" desc);
create index if not exists field_changes_tenant_idx on "app_private"."field_changes" ("tenant_id", "changed_at");
create index if not exists field_changes_changed_by_idx on "app_private"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "app_private"."field_changes" enable row level security;
revoke all on "app_private"."field_changes" from anon, authenticated;
grant select on "app_private"."field_changes" to authenticated;
grant all on "app_private"."field_changes" to service_role;
drop policy if exists field_changes_read on "app_private"."field_changes";
create policy field_changes_read on "app_private"."field_changes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function "app_private"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z."id"::text,
    'organizationId', z."tenant_id",
    'subjectType', z."subject_type",
    'subjectId', z."subject_id",
    'field', z."field",
    'before', z."old_value",
    'after', z."new_value",
    'changedBy', z."changed_by",
    'changedAt', z."changed_at"
  ) order by z."id" desc), '[]'::jsonb)
  from (
    select x.* from "app_private"."field_changes" x
    where x."subject_type" = field_history.subject_type
      and x."subject_id" = field_history.subject_id
      and (field_history.field is null or x."field" = field_history.field)
      and (field_history.before is null or x."id" < field_history.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "app_private"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "app_private"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block-data field-history
-- @bsb-hash sha256:563bb02e577a82d70031527590e31e445260155bc6212649c68e4e88083c124f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('field-history', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:0214c624bf5b9937a8ae3514bbb1274a13a77f83d5c9a3f7caa2c7859d6e1965
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table if not exists "better_supabase"."field_changes" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index if not exists field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index if not exists field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index if not exists field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
drop policy if exists field_changes_read on "better_supabase"."field_changes";
create policy field_changes_read on "better_supabase"."field_changes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function "better_supabase"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z."id"::text,
    'organizationId', z."tenant_id",
    'subjectType', z."subject_type",
    'subjectId', z."subject_id",
    'field', z."field",
    'before', z."old_value",
    'after', z."new_value",
    'changedBy', z."changed_by",
    'changedAt', z."changed_at"
  ) order by z."id" desc), '[]'::jsonb)
  from (
    select x.* from "better_supabase"."field_changes" x
    where x."subject_type" = field_history.subject_type
      and x."subject_id" = field_history.subject_id
      and (field_history.field is null or x."field" = field_history.field)
      and (field_history.before is null or x."id" < field_history.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- blocks.field-history.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."field_history"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "api"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block-data field-history
-- @bsb-hash sha256:563bb02e577a82d70031527590e31e445260155bc6212649c68e4e88083c124f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('field-history', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
