-- ==== alone: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:85b9a01de3c64c46febfbccbe80ae442534a68a10052b0c3b652bf055b2a2358
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "better_supabase"."field_changes" (
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
create index field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from public, anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
create policy bsb_field_changes_read on "better_supabase"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:85b9a01de3c64c46febfbccbe80ae442534a68a10052b0c3b652bf055b2a2358
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "better_supabase"."field_changes" (
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
create index field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from public, anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
create policy bsb_field_changes_read on "better_supabase"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:869c112307e5b19e1e992f0a03786547bc253def3a72b07df66abd72038b7299
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "app_private"."field_changes" (
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
create index field_changes_subject_idx on "app_private"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "app_private"."field_changes" ("tenant_id", "changed_at");
create index field_changes_changed_by_idx on "app_private"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "app_private"."field_changes" enable row level security;
revoke all on "app_private"."field_changes" from public, anon, authenticated;
grant select on "app_private"."field_changes" to authenticated;
grant all on "app_private"."field_changes" to service_role;
create policy bsb_field_changes_read on "app_private"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "app_private"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "app_private"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "app_private"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:f0e9da9cf313422320f7b6eb867a4d82d6d0abca662b7ed193e106d538d4cb8e
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "better_supabase"."field_changes" (
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
create index field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from public, anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
create policy bsb_field_changes_read on "better_supabase"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.field-history.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."field_history"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "api"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:13ad1a62321baedf3c876d93f8d10b4358285eca4335cb7d1ae493983bd3e55e
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
-- better_supabase.field_changes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."field_changes" add column if not exists "id" bigint generated always as identity;
alter table "better_supabase"."field_changes" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."field_changes" add column if not exists "subject_type" text;
alter table "better_supabase"."field_changes" add column if not exists "subject_id" text;
alter table "better_supabase"."field_changes" add column if not exists "field" text;
alter table "better_supabase"."field_changes" add column if not exists "old_value" jsonb;
alter table "better_supabase"."field_changes" add column if not exists "new_value" jsonb;
alter table "better_supabase"."field_changes" add column if not exists "changed_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."field_changes" add column if not exists "changed_at" timestamptz not null default now();
create index if not exists field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index if not exists field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index if not exists field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
create policy bsb_field_changes_select on "better_supabase"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_137_field_history.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_137_field_history.sql
-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:8cf9053f5efc71cd19bd0f90e0aa9e21abb647eaa772e37cdacd23ee699a585f
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "better_supabase"."field_changes" (
  "id" bigint generated always as identity primary key,
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "better_supabase"."field_changes" ("org_id", "changed_at");
create index field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from public, anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
create policy bsb_field_changes_read on "better_supabase"."field_changes"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));


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
    'organizationId', z."org_id",
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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."org_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_137_field_history.sql
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
