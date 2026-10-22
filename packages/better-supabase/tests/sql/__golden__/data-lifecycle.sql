-- ==== alone: schema supabase/schemas/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module data-lifecycle@6 managed
-- Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Exports of a user's or an organization's data, written by the app's
-- export job as one NDJSON file per table under {id}/ in the data-exports bucket.
create table if not exists "better_supabase"."data_exports" (
  "id" uuid primary key default gen_random_uuid(),
  "subject" text not null check ("subject" in ('user', 'organization')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'running', 'ready', 'failed')),
  "bucket" text not null default 'data-exports',
  "files" text[] not null default '{}',
  "error" text,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "expires_at" timestamptz,
  check (("subject" = 'user') = ("user_id" is not null)),
  check (("subject" = 'organization') = ("organization_id" is not null))
);
create unique index if not exists data_exports_open_user_idx on "better_supabase"."data_exports" ("user_id") where "status" in ('pending', 'running') and "subject" = 'user';
create unique index if not exists data_exports_open_tenant_idx on "better_supabase"."data_exports" ("organization_id") where "status" in ('pending', 'running') and "subject" = 'organization';
create index if not exists data_exports_requested_by_idx on "better_supabase"."data_exports" ("requested_by");
create index if not exists data_exports_user_idx on "better_supabase"."data_exports" ("user_id") where "user_id" is not null;
alter table "better_supabase"."data_exports" enable row level security;
revoke all on "better_supabase"."data_exports" from anon, authenticated;
grant select on "better_supabase"."data_exports" to authenticated;
grant all on "better_supabase"."data_exports" to service_role;
drop policy if exists "data_exports_read" on "better_supabase"."data_exports";
create policy "data_exports_read" on "better_supabase"."data_exports" for select to authenticated
  using ("requested_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('organization.export')));

-- Organizations waiting for their purge. Requesting disables the tenant
-- through the access contract; cancelling enables it again unless it was
-- disabled before.
create table if not exists "better_supabase"."organization_deletions" (
  "organization_id" uuid primary key,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "purge_after" timestamptz not null,
  "cancelled_at" timestamptz,
  "purged_at" timestamptz,
  "previously_disabled" boolean not null default false
);
create index if not exists organization_deletions_due_idx on "better_supabase"."organization_deletions" ("purge_after") where "cancelled_at" is null and "purged_at" is null;
create index if not exists organization_deletions_requested_by_idx on "better_supabase"."organization_deletions" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."organization_deletions" enable row level security;
revoke all on "better_supabase"."organization_deletions" from anon, authenticated;
grant all on "better_supabase"."organization_deletions" to service_role;

-- How long each kind of record is kept: for one tenant, for the tenants
-- on a plan, or for every tenant (both null). A purge keeps a row while
-- retention_for says so, whatever its own older_than argument.
create table if not exists "better_supabase"."retention_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "plan" text,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "keep" interval not null check ("keep" > interval '0'),
  "updated_at" timestamptz not null default now(),
  check ("organization_id" is null or "plan" is null),
  unique nulls not distinct ("kind", "organization_id", "plan")
);
create index if not exists retention_policies_tenant_idx on "better_supabase"."retention_policies" ("organization_id") where "organization_id" is not null;
alter table "better_supabase"."retention_policies" enable row level security;
revoke all on "better_supabase"."retention_policies" from anon, authenticated;
grant all on "better_supabase"."retention_policies" to service_role;

-- Legal holds: while one is active (released_at null), no purge deletes
-- the records it covers. A null tenant holds every tenant, a null kind
-- every kind.
create table if not exists "better_supabase"."legal_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "reason" text not null check (length("reason") between 1 and 1000),
  "placed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "placed_at" timestamptz not null default now(),
  "released_by" uuid references auth.users (id) on delete set null,
  "released_at" timestamptz
);
create index if not exists legal_holds_active_idx on "better_supabase"."legal_holds" ("organization_id", "kind") where "released_at" is null;
create index if not exists legal_holds_placed_by_idx on "better_supabase"."legal_holds" ("placed_by") where "placed_by" is not null;
create index if not exists legal_holds_released_by_idx on "better_supabase"."legal_holds" ("released_by") where "released_by" is not null;
alter table "better_supabase"."legal_holds" enable row level security;
revoke all on "better_supabase"."legal_holds" from anon, authenticated;
grant all on "better_supabase"."legal_holds" to service_role;

-- The tenant's policy for a kind, else its plan's (the shortest when it has
-- several plans), else the policy for every tenant; null without one.
create or replace function "better_supabase"."retention_for"(kind text, tenant text default null)
returns interval
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_keep interval;
begin
  if retention_for.tenant is not null then
    select x."keep" into v_keep from "better_supabase"."retention_policies" x
    where x."kind" = retention_for.kind and x."organization_id"::text = retention_for.tenant;
    if v_keep is not null then
      return v_keep;
    end if;
    
  end if;
  select x."keep" into v_keep from "better_supabase"."retention_policies" x
  where x."kind" = retention_for.kind and x."organization_id" is null and x."plan" is null;
  return v_keep;
end;
$$;

-- The shortest time any policy keeps a kind, so a purge can bound its scan
-- on the timestamp index before it asks retention_for per row.
create or replace function "better_supabase"."retention_floor"(kind text)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select min(x."keep") from "better_supabase"."retention_policies" x where x."kind" = retention_floor.kind
$$;

-- Whether an active hold covers the kind for the tenant. A null tenant (a
-- row that belongs to no tenant) is covered only by a hold on every tenant.
create or replace function "better_supabase"."is_held"(kind text, tenant text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = is_held.kind)
      and (x."organization_id" is null or x."organization_id"::text = is_held.tenant)
  )
$$;

-- Before when every tenant's rows of a kind may go, so a purge can drop a
-- whole partition: null while any hold covers the kind, else the longest
-- policy or the fallback, whichever keeps more.
create or replace function "better_supabase"."retention_cutoff"(kind text, fallback interval)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = retention_cutoff.kind)
  ) then null else now() - greatest(
    fallback,
    (select max(x."keep") from "better_supabase"."retention_policies" x where x."kind" = retention_cutoff.kind)
  ) end
$$;

create or replace function "better_supabase"."set_retention_policy"(kind text, keep interval, tenant uuid default null, plan text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."retention_policies";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role sets retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."retention_policies" as x ("kind", "keep", "organization_id", "plan")
  values (set_retention_policy.kind, set_retention_policy.keep, set_retention_policy.tenant, set_retention_policy.plan)
  on conflict ("kind", "organization_id", "plan") do update set
    "keep" = excluded."keep",
    "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."remove_retention_policy"(kind text, tenant uuid default null, plan text default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role removes retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  delete from "better_supabase"."retention_policies" x
  where x."kind" = remove_retention_policy.kind
    and x."organization_id" is not distinct from remove_retention_policy.tenant
    and x."plan" is not distinct from remove_retention_policy.plan;
  return found;
end;
$$;

create or replace function "better_supabase"."list_retention_policies"(kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."kind", x."organization_id" nulls first, x."plan" nulls first), '[]'::jsonb)
  from "better_supabase"."retention_policies" x
  where list_retention_policies.kind is null or x."kind" = list_retention_policies.kind
$$;

create or replace function "better_supabase"."place_legal_hold"(reason text, tenant uuid default null, kind text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role places legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  insert into "better_supabase"."legal_holds" ("reason", "organization_id", "kind", "placed_by")
  values (place_legal_hold.reason, place_legal_hold.tenant, place_legal_hold.kind, auth.uid())
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Releasing keeps the row, so the holds stay on record.
create or replace function "better_supabase"."release_legal_hold"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role releases legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  update "better_supabase"."legal_holds" x set "released_at" = now(), "released_by" = auth.uid()
  where x."id" = release_legal_hold.id and x."released_at" is null
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_legal_holds"(include_released boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."placed_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."legal_holds" x
  where list_legal_holds.include_released or x."released_at" is null
$$;

revoke execute on function "better_supabase"."retention_for"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."retention_floor"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."is_held"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."retention_cutoff"(text, interval) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_retention_policy"(text, interval, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."remove_retention_policy"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_retention_policies"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."place_legal_hold"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."release_legal_hold"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_legal_holds"(boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."retention_for"(text, text) to service_role;
grant execute on function "better_supabase"."retention_floor"(text) to service_role;
grant execute on function "better_supabase"."is_held"(text, text) to service_role;
grant execute on function "better_supabase"."retention_cutoff"(text, interval) to service_role;
grant execute on function "better_supabase"."set_retention_policy"(text, interval, uuid, text) to service_role;
grant execute on function "better_supabase"."remove_retention_policy"(text, uuid, text) to service_role;
grant execute on function "better_supabase"."list_retention_policies"(text) to service_role;
grant execute on function "better_supabase"."place_legal_hold"(text, uuid, text) to service_role;
grant execute on function "better_supabase"."release_legal_hold"(uuid) to service_role;
grant execute on function "better_supabase"."list_legal_holds"(boolean) to service_role;

-- What an export reads and the purge clears: subject, display name,
-- quoted table, column and whether the purge deletes it.
drop function if exists "better_supabase"."data_lifecycle_tables"();
create or replace function "better_supabase"."data_lifecycle_tables"()
returns table (subject text, name text, tbl text, col text, purge boolean, omit text[], exported boolean)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('user', 'better_supabase.memberships', '"better_supabase"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memberships', '"better_supabase"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$$;

-- The credential_ref columns of module tables: display name, quoted table,
-- column and the user column a ref is revoked for (null for the app).
drop function if exists "better_supabase"."data_lifecycle_credentials"();
create or replace function "better_supabase"."data_lifecycle_credentials"()
returns table (name text, tbl text, col text, user_col text)
language sql
immutable
set search_path = ''
as $$
  select null::text, null::text, null::text, null::text where false
$$;

-- The credential_refs in the rows a due purge deletes (service role), for
-- the purger to revoke through its CredentialProvider first. in_tenant is
-- false for a ref that doesn't carry the organization; those stay unrevoked.
create or replace function "better_supabase"."organization_credential_refs"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_entry record;
  v_type text;
  v_refs jsonb;
  v_all jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."organization_deletions" x
    where x."organization_id" = organization_credential_refs.tenant and x."cancelled_at" is null
      and x."purged_at" is null and x."purge_after" <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = organization_credential_refs.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  for v_entry in
    select c.name, c.tbl, c.col, c.user_col, t.col as tenant_col
    from "better_supabase"."data_lifecycle_credentials"() c
    join "better_supabase"."data_lifecycle_tables"() t on t.subject = 'organization' and t.name = c.name and t.purge
    where to_regclass(c.tbl) is not null
    order by c.name, c.col
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
    from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(v_entry.tbl) and a.attname = v_entry.tenant_col and not a.attisdropped;
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''table'', $2, ''column'', $3, ''ref'', r.ref, ''user_id'', r.user_id, ''in_tenant'', not (jsonb_typeof(r.ref -> ''tenant'') is distinct from ''string'' or (r.ref ->> ''tenant'') is distinct from ($1)::text))), ''[]''::jsonb)
       from (select t.%I as ref, %s as user_id from %s t where t.%I = $1::%s) r
       where jsonb_typeof(r.ref) = ''object''',
      v_entry.col,
      case when v_entry.user_col is null then 'null::text' else format('t.%I::text', v_entry.user_col) end,
      v_entry.tbl, v_entry.tenant_col, v_type
    ) into v_refs
    using organization_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$$;
revoke execute on function "better_supabase"."data_lifecycle_credentials"() from public, anon, authenticated;
revoke execute on function "better_supabase"."organization_credential_refs"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_credentials"() to service_role;
grant execute on function "better_supabase"."organization_credential_refs"(uuid) to service_role;

create or replace function "better_supabase"."data_export_object_allowed"(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Files sit under <export id>/, so the primary key finds the one export.
  select exists (
    select 1 from "better_supabase"."data_exports" x
    where x."id" = case when split_part(path, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then split_part(path, '/', 1)::uuid end
      and x."bucket" = 'data-exports'
      and x."status" = 'ready'
      and (x."expires_at" is null or x."expires_at" > now())
      and path = any (x."files")
      and (x."requested_by" = auth.uid() or (x."organization_id" is not null and coalesce(better_supabase.can('tenant', x."organization_id", 'organization.export'), false)))
  )
$$;
revoke execute on function "better_supabase"."data_export_object_allowed"(text) from public, anon;
grant execute on function "better_supabase"."data_export_object_allowed"(text) to authenticated, service_role;

drop policy if exists "bs_data_exports_select" on storage.objects;
create policy "bs_data_exports_select" on storage.objects for select to authenticated
  using (bucket_id = 'data-exports' and "better_supabase"."data_export_object_allowed"(name));

-- The caller's own data (subject 'user') or a tenant's (needs the export
-- permission). An open export for the same subject is returned instead
-- of a second one.
create or replace function "better_supabase"."request_data_export"(subject text default 'user', tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_data_export.subject = 'organization' then
    if request_data_export.tenant is null or not coalesce(better_supabase.can('tenant', request_data_export.tenant, 'organization.export'), false) then
      raise exception 'You may not export this organization''s data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
    end if;
    select * into v_row from "better_supabase"."data_exports" x where x."organization_id" = request_data_export.tenant and x."subject" = 'organization' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "organization_id") values ('organization', request_data_export.tenant) returning * into v_row;
      null;
    end if;
  elsif request_data_export.subject = 'user' then
    select * into v_row from "better_supabase"."data_exports" x where x."user_id" = auth.uid() and x."subject" = 'user' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "user_id") values ('user', auth.uid()) returning * into v_row;
      null;
    end if;
  else
    raise exception 'subject must be user or organization' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_data_exports"(tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."requested_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."data_exports" x
  where case when list_data_exports.tenant is null
    then x."subject" = 'user' and x."user_id" = auth.uid()
    else x."organization_id" = list_data_exports.tenant
  end
$$;

create or replace function "better_supabase"."get_data_export"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."data_exports" x where x."id" = get_data_export.id
$$;

-- Starts a pending (or failed) export and returns it with the tables to
-- read (service role).
create or replace function "better_supabase"."claim_data_export"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'running', "error" = null
  where x."id" = claim_data_export.id and x."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  return to_jsonb(v_row) || jsonb_build_object('tables', (
    select coalesce(jsonb_agg(t.name order by t.name), '[]'::jsonb)
    from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = v_row."subject" and t.exported and to_regclass(t.tbl) is not null
  ));
end;
$$;

-- A page of the subject's rows in one table, after the ctid `after`
-- (service role): { rows, after }, with after null on the last page.
create or replace function "better_supabase"."data_export_rows"(id uuid, table_name text, after text default null, page_size integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
  v_table record;
  v_type text;
  v_rows jsonb;
  v_after text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x where x."id" = data_export_rows.id and x."status" = 'running';
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  select * into v_table from "better_supabase"."data_lifecycle_tables"() t
  where t.subject = v_row."subject" and t.name = data_export_rows.table_name and t.exported;
  if v_table.tbl is null or to_regclass(v_table.tbl) is null then
    raise exception 'The export has no table %', data_export_rows.table_name using errcode = '22023', hint = 'DATA_EXPORT_TABLE';
  end if;
  select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
  from pg_catalog.pg_attribute a
  where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
  execute format(
    'select coalesce(jsonb_agg((to_jsonb(p.*) - ''_ctid'') - $4::text[] order by p._ctid), ''[]''::jsonb), max(p._ctid)::text, count(*)
     from (select t.ctid as _ctid, t.* from %s t where t.%I = $1::%s and ($2::tid is null or t.ctid > $2::tid) order by t.ctid limit $3) p',
    v_table.tbl, v_table.col, v_type
  ) into v_rows, v_after
  using case when v_row."subject" = 'user' then v_row."user_id"::text else v_row."organization_id"::text end,
    data_export_rows.after, greatest(1, least(data_export_rows.page_size, 10000)), coalesce(v_table.omit, '{}');
  return jsonb_build_object(
    'rows', v_rows,
    'after', case when jsonb_array_length(v_rows) < greatest(1, least(data_export_rows.page_size, 10000)) then null else v_after end
  );
end;
$$;

create or replace function "better_supabase"."complete_data_export"(id uuid, files text[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'ready', "files" = complete_data_export.files,
    "completed_at" = now(), "expires_at" = now() + '7 days'::interval
  where x."id" = complete_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."fail_data_export"(id uuid, error text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'failed', "error" = fail_data_export.error, "completed_at" = now()
  where x."id" = fail_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Schedules the purge after the grace period and disables the tenant.
-- Needs the delete permission; requesting again moves the purge date.
create or replace function "better_supabase"."request_organization_deletion"(tenant uuid, grace interval default '30 days'::interval)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
  v_disabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', request_organization_deletion.tenant, 'organization.delete'), false) then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_organization_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from "better_supabase"."organization_deletions" x where x."organization_id" = request_organization_deletion.tenant and x."purged_at" is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  v_disabled := false;
  insert into "better_supabase"."organization_deletions" as x ("organization_id", "requested_by", "purge_after", "previously_disabled")
  values (request_organization_deletion.tenant, auth.uid(), now() + request_organization_deletion.grace, coalesce(v_disabled, false))
  on conflict ("organization_id") do update set
    "requested_by" = excluded."requested_by",
    "requested_at" = now(),
    "purge_after" = excluded."purge_after",
    "previously_disabled" = case when x."cancelled_at" is null then x."previously_disabled" else excluded."previously_disabled" end,
    "cancelled_at" = null
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The requester, a member holding the cancelDelete permission or the service
-- role cancels a pending purge. The tenant is disabled meanwhile, so this
-- asks member_can_while_deleting, which skips the disabled-tenant check.
create or replace function "better_supabase"."cancel_organization_deletion"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = cancel_organization_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."requested_by" = auth.uid() or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_organization_deletion.tenant, 'organization.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "better_supabase"."organization_deletions" x set "cancelled_at" = now()
  where x."organization_id" = v_row."organization_id"
  returning * into v_row;
  
  null;
  return to_jsonb(v_row);
end;
$$;

-- The pending deletion, for the organization's members.
create or replace function "better_supabase"."organization_deletion"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."organization_deletions" x
  where x."organization_id" = organization_deletion.tenant
    and x."cancelled_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = organization_deletion.tenant and mm."user_id" = auth.uid()))
$$;

create or replace function "better_supabase"."due_organization_deletions"(max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."purge_after"), '[]'::jsonb)
  from (
    select * from "better_supabase"."organization_deletions" y
    where y."purge_after" <= now() and y."cancelled_at" is null and y."purged_at" is null
    order by y."purge_after"
    limit greatest(1, least(due_organization_deletions.max_rows, 1000))
  ) x
$$;

-- Deletes a due organization's rows (service role): the app's
-- on_organization_purge(tenant) hook first, then each purged table, then
-- the organization. Returns { organizationId, deleted: { table: rows } }.
create or replace function "better_supabase"."purge_organization"(tenant uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = purge_organization.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null or v_row."purge_after" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = purge_organization.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_organization.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"better_supabase"."organization_deletions"')
    order by (row_number() over ()) desc
  );
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from "better_supabase"."data_lifecycle_tables"() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  update "better_supabase"."organization_deletions" x set "purged_at" = now() where x."organization_id" = v_row."organization_id" returning * into v_row;
  
  null;
  return jsonb_build_object('organizationId', v_row."organization_id"::text, 'deleted', v_deleted);
end;
$$;

-- Exports past expires_at, oldest first, with their files, for the purger to
-- remove from Storage before forget_data_exports drops the rows.
create or replace function "better_supabase"."expired_data_exports"(max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'bucket', x."bucket", 'files', to_jsonb(x."files")) order by x."expires_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."data_exports" y
    where y."expires_at" < now()
    order by y."expires_at"
    limit greatest(1, least(coalesce(max_rows, 100), 1000))
  ) x
$$;

-- Deletes the export rows (their files are already gone); returns how many.
create or replace function "better_supabase"."forget_data_exports"(ids uuid[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."data_exports" x where x."id" = any (forget_data_exports.ids) and x."expires_at" < now() returning 1
  )
  select count(*)::integer from removed
$$;

revoke execute on function "better_supabase"."expired_data_exports"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."forget_data_exports"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."expired_data_exports"(integer) to service_role;

-- Anonymizes the rows blocks.data-lifecycle.options.anonymize names once
-- their time is up (service role): at most max_rows per rule, each row once,
-- marked with the time. Returns { table: rows }.
create or replace function "better_supabase"."anonymize_due"(max_rows integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_done jsonb := '{}'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role anonymizes rows' using errcode = '42501', hint = 'DATA_ANONYMIZE_FORBIDDEN';
  end if;
  return v_done;
end;
$$;
revoke execute on function "better_supabase"."anonymize_due"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."anonymize_due"(integer) to service_role;

grant execute on function "better_supabase"."forget_data_exports"(uuid[]) to service_role;
revoke execute on function "better_supabase"."data_lifecycle_tables"() from public, anon, authenticated;
revoke execute on function "better_supabase"."request_data_export"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."list_data_exports"(uuid) from public, anon;
revoke execute on function "better_supabase"."get_data_export"(uuid) from public, anon;
revoke execute on function "better_supabase"."claim_data_export"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."complete_data_export"(uuid, text[]) from public, anon, authenticated;
revoke execute on function "better_supabase"."fail_data_export"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."request_organization_deletion"(uuid, interval) from public, anon;
revoke execute on function "better_supabase"."cancel_organization_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."organization_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."due_organization_deletions"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."purge_organization"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_tables"() to service_role;
grant execute on function "better_supabase"."request_data_export"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_data_exports"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."get_data_export"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."claim_data_export"(uuid) to service_role;
grant execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) to service_role;
grant execute on function "better_supabase"."complete_data_export"(uuid, text[]) to service_role;
grant execute on function "better_supabase"."fail_data_export"(uuid, text) to service_role;
grant execute on function "better_supabase"."request_organization_deletion"(uuid, interval) to authenticated, service_role;
grant execute on function "better_supabase"."cancel_organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."due_organization_deletions"(integer) to service_role;
grant execute on function "better_supabase"."purge_organization"(uuid) to service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module-data data-lifecycle
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.modules (name, version, mode)
values ('data-lifecycle', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module data-lifecycle@6 managed
-- Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Exports of a user's or an organization's data, written by the app's
-- export job as one NDJSON file per table under {id}/ in the data-exports bucket.
create table if not exists "better_supabase"."data_exports" (
  "id" uuid primary key default gen_random_uuid(),
  "subject" text not null check ("subject" in ('user', 'organization')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'running', 'ready', 'failed')),
  "bucket" text not null default 'data-exports',
  "files" text[] not null default '{}',
  "error" text,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "expires_at" timestamptz,
  check (("subject" = 'user') = ("user_id" is not null)),
  check (("subject" = 'organization') = ("organization_id" is not null))
);
create unique index if not exists data_exports_open_user_idx on "better_supabase"."data_exports" ("user_id") where "status" in ('pending', 'running') and "subject" = 'user';
create unique index if not exists data_exports_open_tenant_idx on "better_supabase"."data_exports" ("organization_id") where "status" in ('pending', 'running') and "subject" = 'organization';
create index if not exists data_exports_requested_by_idx on "better_supabase"."data_exports" ("requested_by");
create index if not exists data_exports_user_idx on "better_supabase"."data_exports" ("user_id") where "user_id" is not null;
alter table "better_supabase"."data_exports" enable row level security;
revoke all on "better_supabase"."data_exports" from anon, authenticated;
grant select on "better_supabase"."data_exports" to authenticated;
grant all on "better_supabase"."data_exports" to service_role;
drop policy if exists "data_exports_read" on "better_supabase"."data_exports";
create policy "data_exports_read" on "better_supabase"."data_exports" for select to authenticated
  using ("requested_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('organization.export')));

-- Organizations waiting for their purge. Requesting disables the tenant
-- through the access contract; cancelling enables it again unless it was
-- disabled before.
create table if not exists "better_supabase"."organization_deletions" (
  "organization_id" uuid primary key,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "purge_after" timestamptz not null,
  "cancelled_at" timestamptz,
  "purged_at" timestamptz,
  "previously_disabled" boolean not null default false
);
create index if not exists organization_deletions_due_idx on "better_supabase"."organization_deletions" ("purge_after") where "cancelled_at" is null and "purged_at" is null;
create index if not exists organization_deletions_requested_by_idx on "better_supabase"."organization_deletions" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."organization_deletions" enable row level security;
revoke all on "better_supabase"."organization_deletions" from anon, authenticated;
grant all on "better_supabase"."organization_deletions" to service_role;

-- How long each kind of record is kept: for one tenant, for the tenants
-- on a plan, or for every tenant (both null). A purge keeps a row while
-- retention_for says so, whatever its own older_than argument.
create table if not exists "better_supabase"."retention_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "plan" text,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "keep" interval not null check ("keep" > interval '0'),
  "updated_at" timestamptz not null default now(),
  check ("organization_id" is null or "plan" is null),
  unique nulls not distinct ("kind", "organization_id", "plan")
);
create index if not exists retention_policies_tenant_idx on "better_supabase"."retention_policies" ("organization_id") where "organization_id" is not null;
alter table "better_supabase"."retention_policies" enable row level security;
revoke all on "better_supabase"."retention_policies" from anon, authenticated;
grant all on "better_supabase"."retention_policies" to service_role;

-- Legal holds: while one is active (released_at null), no purge deletes
-- the records it covers. A null tenant holds every tenant, a null kind
-- every kind.
create table if not exists "better_supabase"."legal_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "reason" text not null check (length("reason") between 1 and 1000),
  "placed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "placed_at" timestamptz not null default now(),
  "released_by" uuid references auth.users (id) on delete set null,
  "released_at" timestamptz
);
create index if not exists legal_holds_active_idx on "better_supabase"."legal_holds" ("organization_id", "kind") where "released_at" is null;
create index if not exists legal_holds_placed_by_idx on "better_supabase"."legal_holds" ("placed_by") where "placed_by" is not null;
create index if not exists legal_holds_released_by_idx on "better_supabase"."legal_holds" ("released_by") where "released_by" is not null;
alter table "better_supabase"."legal_holds" enable row level security;
revoke all on "better_supabase"."legal_holds" from anon, authenticated;
grant all on "better_supabase"."legal_holds" to service_role;

-- The tenant's policy for a kind, else its plan's (the shortest when it has
-- several plans), else the policy for every tenant; null without one.
create or replace function "better_supabase"."retention_for"(kind text, tenant text default null)
returns interval
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_keep interval;
begin
  if retention_for.tenant is not null then
    select x."keep" into v_keep from "better_supabase"."retention_policies" x
    where x."kind" = retention_for.kind and x."organization_id"::text = retention_for.tenant;
    if v_keep is not null then
      return v_keep;
    end if;
    if pg_input_is_valid(retention_for.tenant, 'uuid') then
      select min(x."keep") into v_keep from "better_supabase"."retention_policies" x
      where x."kind" = retention_for.kind and x."organization_id" is null
        and x."plan" = any (better_supabase.tenant_plans(retention_for.tenant::uuid));
      if v_keep is not null then
        return v_keep;
      end if;
    end if;
  end if;
  select x."keep" into v_keep from "better_supabase"."retention_policies" x
  where x."kind" = retention_for.kind and x."organization_id" is null and x."plan" is null;
  return v_keep;
end;
$$;

-- The shortest time any policy keeps a kind, so a purge can bound its scan
-- on the timestamp index before it asks retention_for per row.
create or replace function "better_supabase"."retention_floor"(kind text)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select min(x."keep") from "better_supabase"."retention_policies" x where x."kind" = retention_floor.kind
$$;

-- Whether an active hold covers the kind for the tenant. A null tenant (a
-- row that belongs to no tenant) is covered only by a hold on every tenant.
create or replace function "better_supabase"."is_held"(kind text, tenant text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = is_held.kind)
      and (x."organization_id" is null or x."organization_id"::text = is_held.tenant)
  )
$$;

-- Before when every tenant's rows of a kind may go, so a purge can drop a
-- whole partition: null while any hold covers the kind, else the longest
-- policy or the fallback, whichever keeps more.
create or replace function "better_supabase"."retention_cutoff"(kind text, fallback interval)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = retention_cutoff.kind)
  ) then null else now() - greatest(
    fallback,
    (select max(x."keep") from "better_supabase"."retention_policies" x where x."kind" = retention_cutoff.kind)
  ) end
$$;

create or replace function "better_supabase"."set_retention_policy"(kind text, keep interval, tenant uuid default null, plan text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."retention_policies";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role sets retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."retention_policies" as x ("kind", "keep", "organization_id", "plan")
  values (set_retention_policy.kind, set_retention_policy.keep, set_retention_policy.tenant, set_retention_policy.plan)
  on conflict ("kind", "organization_id", "plan") do update set
    "keep" = excluded."keep",
    "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."remove_retention_policy"(kind text, tenant uuid default null, plan text default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role removes retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  delete from "better_supabase"."retention_policies" x
  where x."kind" = remove_retention_policy.kind
    and x."organization_id" is not distinct from remove_retention_policy.tenant
    and x."plan" is not distinct from remove_retention_policy.plan;
  return found;
end;
$$;

create or replace function "better_supabase"."list_retention_policies"(kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."kind", x."organization_id" nulls first, x."plan" nulls first), '[]'::jsonb)
  from "better_supabase"."retention_policies" x
  where list_retention_policies.kind is null or x."kind" = list_retention_policies.kind
$$;

create or replace function "better_supabase"."place_legal_hold"(reason text, tenant uuid default null, kind text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role places legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  insert into "better_supabase"."legal_holds" ("reason", "organization_id", "kind", "placed_by")
  values (place_legal_hold.reason, place_legal_hold.tenant, place_legal_hold.kind, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('legal_hold.placed', jsonb_build_object('holdId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind", 'reason', v_row."reason"), 'legal-holds/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'legal_hold.placed',
    category => 'data',
    target_type => 'legal_hold',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('holdId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind", 'reason', v_row."reason")
  );
  return to_jsonb(v_row);
end;
$$;

-- Releasing keeps the row, so the holds stay on record.
create or replace function "better_supabase"."release_legal_hold"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role releases legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  update "better_supabase"."legal_holds" x set "released_at" = now(), "released_by" = auth.uid()
  where x."id" = release_legal_hold.id and x."released_at" is null
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  perform "better_supabase".emit_event('legal_hold.released', jsonb_build_object('holdId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind", 'reason', v_row."reason"), 'legal-holds/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'legal_hold.released',
    category => 'data',
    target_type => 'legal_hold',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('holdId', v_row."id", 'organizationId', v_row."organization_id"::text, 'kind', v_row."kind", 'reason', v_row."reason")
  );
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_legal_holds"(include_released boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."placed_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."legal_holds" x
  where list_legal_holds.include_released or x."released_at" is null
$$;

revoke execute on function "better_supabase"."retention_for"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."retention_floor"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."is_held"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."retention_cutoff"(text, interval) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_retention_policy"(text, interval, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."remove_retention_policy"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_retention_policies"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."place_legal_hold"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."release_legal_hold"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_legal_holds"(boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."retention_for"(text, text) to service_role;
grant execute on function "better_supabase"."retention_floor"(text) to service_role;
grant execute on function "better_supabase"."is_held"(text, text) to service_role;
grant execute on function "better_supabase"."retention_cutoff"(text, interval) to service_role;
grant execute on function "better_supabase"."set_retention_policy"(text, interval, uuid, text) to service_role;
grant execute on function "better_supabase"."remove_retention_policy"(text, uuid, text) to service_role;
grant execute on function "better_supabase"."list_retention_policies"(text) to service_role;
grant execute on function "better_supabase"."place_legal_hold"(text, uuid, text) to service_role;
grant execute on function "better_supabase"."release_legal_hold"(uuid) to service_role;
grant execute on function "better_supabase"."list_legal_holds"(boolean) to service_role;

-- What an export reads and the purge clears: subject, display name,
-- quoted table, column and whether the purge deletes it.
drop function if exists "better_supabase"."data_lifecycle_tables"();
create or replace function "better_supabase"."data_lifecycle_tables"()
returns table (subject text, name text, tbl text, col text, purge boolean, omit text[], exported boolean)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'better_supabase.memberships', '"better_supabase"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', false, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.identity_links', '"better_supabase"."identity_links"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.identity_link_codes', '"better_supabase"."identity_link_codes"', 'user_id', true, '{}'::text[], false),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_collections', '"better_supabase"."subject_collections"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.favorites', '"better_supabase"."favorites"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.reviews', '"better_supabase"."reviews"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leave_requests', '"better_supabase"."leave_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leave_ledger', '"better_supabase"."leave_ledger"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'better_supabase.memberships', '"better_supabase"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.support_sessions', '"better_supabase"."support_sessions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.support_requests', '"better_supabase"."support_requests"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incoming_webhooks', '"better_supabase"."incoming_webhooks"', 'tenant', true, array['token_hash', 'secret', 'secret_id', 'previous_secret', 'previous_secret_id']::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_customers', '"better_supabase"."billing_customers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_subscriptions', '"better_supabase"."billing_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_views', '"better_supabase"."saved_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collections', '"better_supabase"."collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_movements', '"better_supabase"."stock_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.projects', '"better_supabase"."projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.jobs', '"better_supabase"."jobs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_payments', '"better_supabase"."invoice_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_collections', '"better_supabase"."subject_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_collection_entries', '"better_supabase"."subject_collection_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.favorites', '"better_supabase"."favorites"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_hostnames', '"better_supabase"."organization_hostnames"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reviews', '"better_supabase"."reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.review_stats', '"better_supabase"."review_stats"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_types', '"better_supabase"."leave_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_requests', '"better_supabase"."leave_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_ledger', '"better_supabase"."leave_ledger"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$$;

-- The credential_ref columns of module tables: display name, quoted table,
-- column and the user column a ref is revoked for (null for the app).
drop function if exists "better_supabase"."data_lifecycle_credentials"();
create or replace function "better_supabase"."data_lifecycle_credentials"()
returns table (name text, tbl text, col text, user_col text)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'credential_ref', null::text),
    ('better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'credential_ref', null::text),
    ('better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'credential_ref', null::text),
    ('better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'credential_ref', null::text),
    ('better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'credential_ref', 'user_id'),
    ('better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'credential_ref', null::text)
  ) as c(name, tbl, col, user_col)
$$;

-- The credential_refs in the rows a due purge deletes (service role), for
-- the purger to revoke through its CredentialProvider first. in_tenant is
-- false for a ref that doesn't carry the organization; those stay unrevoked.
create or replace function "better_supabase"."organization_credential_refs"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_entry record;
  v_type text;
  v_refs jsonb;
  v_all jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."organization_deletions" x
    where x."organization_id" = organization_credential_refs.tenant and x."cancelled_at" is null
      and x."purged_at" is null and x."purge_after" <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = organization_credential_refs.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  for v_entry in
    select c.name, c.tbl, c.col, c.user_col, t.col as tenant_col
    from "better_supabase"."data_lifecycle_credentials"() c
    join "better_supabase"."data_lifecycle_tables"() t on t.subject = 'organization' and t.name = c.name and t.purge
    where to_regclass(c.tbl) is not null
    order by c.name, c.col
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
    from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(v_entry.tbl) and a.attname = v_entry.tenant_col and not a.attisdropped;
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''table'', $2, ''column'', $3, ''ref'', r.ref, ''user_id'', r.user_id, ''in_tenant'', not (jsonb_typeof(r.ref -> ''tenant'') is distinct from ''string'' or (r.ref ->> ''tenant'') is distinct from ($1)::text))), ''[]''::jsonb)
       from (select t.%I as ref, %s as user_id from %s t where t.%I = $1::%s) r
       where jsonb_typeof(r.ref) = ''object''',
      v_entry.col,
      case when v_entry.user_col is null then 'null::text' else format('t.%I::text', v_entry.user_col) end,
      v_entry.tbl, v_entry.tenant_col, v_type
    ) into v_refs
    using organization_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$$;
revoke execute on function "better_supabase"."data_lifecycle_credentials"() from public, anon, authenticated;
revoke execute on function "better_supabase"."organization_credential_refs"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_credentials"() to service_role;
grant execute on function "better_supabase"."organization_credential_refs"(uuid) to service_role;

create or replace function "better_supabase"."data_export_object_allowed"(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Files sit under <export id>/, so the primary key finds the one export.
  select exists (
    select 1 from "better_supabase"."data_exports" x
    where x."id" = case when split_part(path, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then split_part(path, '/', 1)::uuid end
      and x."bucket" = 'data-exports'
      and x."status" = 'ready'
      and (x."expires_at" is null or x."expires_at" > now())
      and path = any (x."files")
      and (x."requested_by" = auth.uid() or (x."organization_id" is not null and coalesce(better_supabase.can('tenant', x."organization_id", 'organization.export'), false)))
  )
$$;
revoke execute on function "better_supabase"."data_export_object_allowed"(text) from public, anon;
grant execute on function "better_supabase"."data_export_object_allowed"(text) to authenticated, service_role;

drop policy if exists "bs_data_exports_select" on storage.objects;
create policy "bs_data_exports_select" on storage.objects for select to authenticated
  using (bucket_id = 'data-exports' and "better_supabase"."data_export_object_allowed"(name));

-- The caller's own data (subject 'user') or a tenant's (needs the export
-- permission). An open export for the same subject is returned instead
-- of a second one.
create or replace function "better_supabase"."request_data_export"(subject text default 'user', tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_data_export.subject = 'organization' then
    if request_data_export.tenant is null or not coalesce(better_supabase.can('tenant', request_data_export.tenant, 'organization.export'), false) then
      raise exception 'You may not export this organization''s data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
    end if;
    select * into v_row from "better_supabase"."data_exports" x where x."organization_id" = request_data_export.tenant and x."subject" = 'organization' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "organization_id") values ('organization', request_data_export.tenant) returning * into v_row;
      perform "better_supabase".emit_event('data_export.requested', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.requested',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by")
  );
    end if;
  elsif request_data_export.subject = 'user' then
    select * into v_row from "better_supabase"."data_exports" x where x."user_id" = auth.uid() and x."subject" = 'user' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "user_id") values ('user', auth.uid()) returning * into v_row;
      perform "better_supabase".emit_event('data_export.requested', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.requested',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by")
  );
    end if;
  else
    raise exception 'subject must be user or organization' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_data_exports"(tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."requested_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."data_exports" x
  where case when list_data_exports.tenant is null
    then x."subject" = 'user' and x."user_id" = auth.uid()
    else x."organization_id" = list_data_exports.tenant
  end
$$;

create or replace function "better_supabase"."get_data_export"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."data_exports" x where x."id" = get_data_export.id
$$;

-- Starts a pending (or failed) export and returns it with the tables to
-- read (service role).
create or replace function "better_supabase"."claim_data_export"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'running', "error" = null
  where x."id" = claim_data_export.id and x."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  return to_jsonb(v_row) || jsonb_build_object('tables', (
    select coalesce(jsonb_agg(t.name order by t.name), '[]'::jsonb)
    from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = v_row."subject" and t.exported and to_regclass(t.tbl) is not null
  ));
end;
$$;

-- A page of the subject's rows in one table, after the ctid `after`
-- (service role): { rows, after }, with after null on the last page.
create or replace function "better_supabase"."data_export_rows"(id uuid, table_name text, after text default null, page_size integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
  v_table record;
  v_type text;
  v_rows jsonb;
  v_after text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x where x."id" = data_export_rows.id and x."status" = 'running';
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  select * into v_table from "better_supabase"."data_lifecycle_tables"() t
  where t.subject = v_row."subject" and t.name = data_export_rows.table_name and t.exported;
  if v_table.tbl is null or to_regclass(v_table.tbl) is null then
    raise exception 'The export has no table %', data_export_rows.table_name using errcode = '22023', hint = 'DATA_EXPORT_TABLE';
  end if;
  select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
  from pg_catalog.pg_attribute a
  where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
  execute format(
    'select coalesce(jsonb_agg((to_jsonb(p.*) - ''_ctid'') - $4::text[] order by p._ctid), ''[]''::jsonb), max(p._ctid)::text, count(*)
     from (select t.ctid as _ctid, t.* from %s t where t.%I = $1::%s and ($2::tid is null or t.ctid > $2::tid) order by t.ctid limit $3) p',
    v_table.tbl, v_table.col, v_type
  ) into v_rows, v_after
  using case when v_row."subject" = 'user' then v_row."user_id"::text else v_row."organization_id"::text end,
    data_export_rows.after, greatest(1, least(data_export_rows.page_size, 10000)), coalesce(v_table.omit, '{}');
  return jsonb_build_object(
    'rows', v_rows,
    'after', case when jsonb_array_length(v_rows) < greatest(1, least(data_export_rows.page_size, 10000)) then null else v_after end
  );
end;
$$;

create or replace function "better_supabase"."complete_data_export"(id uuid, files text[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'ready', "files" = complete_data_export.files,
    "completed_at" = now(), "expires_at" = now() + '7 days'::interval
  where x."id" = complete_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('data_export.completed', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'files', to_jsonb(v_row."files"), 'expiresAt', v_row."expires_at"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, 'data_export.completed:' || v_row."id"::text || ':' || v_row."completed_at"::text, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.completed',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'files', to_jsonb(v_row."files"), 'expiresAt', v_row."expires_at"),
    idempotency_key => 'data_export.completed:' || v_row."id"::text || ':' || v_row."completed_at"::text
  );
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."fail_data_export"(id uuid, error text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'failed', "error" = fail_data_export.error, "completed_at" = now()
  where x."id" = fail_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  perform "better_supabase".emit_event('data_export.failed', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'error', v_row."error"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, 'data_export.failed:' || v_row."id"::text || ':' || v_row."completed_at"::text, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.failed',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'error', v_row."error"),
    idempotency_key => 'data_export.failed:' || v_row."id"::text || ':' || v_row."completed_at"::text
  );
  return to_jsonb(v_row);
end;
$$;

-- Schedules the purge after the grace period and disables the tenant.
-- Needs the delete permission; requesting again moves the purge date.
create or replace function "better_supabase"."request_organization_deletion"(tenant uuid, grace interval default '30 days'::interval)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
  v_disabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', request_organization_deletion.tenant, 'organization.delete'), false) then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_organization_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from "better_supabase"."organization_deletions" x where x."organization_id" = request_organization_deletion.tenant and x."purged_at" is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  select "disabled_at" is not null into v_disabled from "better_supabase"."organizations" where "id" = request_organization_deletion.tenant;
  update "better_supabase"."organizations" set "disabled_at" = coalesce("disabled_at", now()) where "id" = request_organization_deletion.tenant;
  insert into "better_supabase"."organization_deletions" as x ("organization_id", "requested_by", "purge_after", "previously_disabled")
  values (request_organization_deletion.tenant, auth.uid(), now() + request_organization_deletion.grace, coalesce(v_disabled, false))
  on conflict ("organization_id") do update set
    "requested_by" = excluded."requested_by",
    "requested_at" = now(),
    "purge_after" = excluded."purge_after",
    "previously_disabled" = case when x."cancelled_at" is null then x."previously_disabled" else excluded."previously_disabled" end,
    "cancelled_at" = null
  returning * into v_row;
  perform "better_supabase".emit_event('organization.deletion_requested', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_after"), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.deletion_requested',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_after")
  );
  return to_jsonb(v_row);
end;
$$;

-- The requester, a member holding the cancelDelete permission or the service
-- role cancels a pending purge. The tenant is disabled meanwhile, so this
-- asks member_can_while_deleting, which skips the disabled-tenant check.
create or replace function "better_supabase"."cancel_organization_deletion"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = cancel_organization_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."requested_by" = auth.uid() or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_organization_deletion.tenant, 'organization.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "better_supabase"."organization_deletions" x set "cancelled_at" = now()
  where x."organization_id" = v_row."organization_id"
  returning * into v_row;
  if not v_row."previously_disabled" then
    update "better_supabase"."organizations" set "disabled_at" = null where "id" = cancel_organization_deletion.tenant;
  end if;
  perform "better_supabase".emit_event('organization.deletion_cancelled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_after"), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.deletion_cancelled',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', auth.uid(), 'purgeAfter', v_row."purge_after")
  );
  return to_jsonb(v_row);
end;
$$;

-- The pending deletion, for the organization's members.
create or replace function "better_supabase"."organization_deletion"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."organization_deletions" x
  where x."organization_id" = organization_deletion.tenant
    and x."cancelled_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = organization_deletion.tenant and mm."user_id" = auth.uid()))
$$;

create or replace function "better_supabase"."due_organization_deletions"(max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."purge_after"), '[]'::jsonb)
  from (
    select * from "better_supabase"."organization_deletions" y
    where y."purge_after" <= now() and y."cancelled_at" is null and y."purged_at" is null
    order by y."purge_after"
    limit greatest(1, least(due_organization_deletions.max_rows, 1000))
  ) x
$$;

-- Deletes a due organization's rows (service role): the app's
-- on_organization_purge(tenant) hook first, then each purged table, then
-- the organization. Returns { organizationId, deleted: { table: rows } }.
create or replace function "better_supabase"."purge_organization"(tenant uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = purge_organization.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null or v_row."purge_after" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = purge_organization.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_organization.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"better_supabase"."organization_deletions"') and to_regclass(t.tbl) is distinct from to_regclass('"better_supabase"."organizations"')
    order by (row_number() over ()) desc
  );
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from "better_supabase"."data_lifecycle_tables"() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  update "better_supabase"."organization_deletions" x set "purged_at" = now() where x."organization_id" = v_row."organization_id" returning * into v_row;
  begin
    delete from "better_supabase"."organizations" where "id" = purge_organization.tenant;
  exception when foreign_key_violation or restrict_violation then
    raise exception 'Rows still reference the organization: %', sqlerrm
      using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
  end;
  perform "better_supabase".emit_event('organization.purged', jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', null::uuid, 'purgeAfter', v_row."purge_after"), 'organizations/' || v_row."organization_id"::text, (null)::text, 'organization.purged:' || v_row."organization_id"::text, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'organization.purged',
    category => 'data',
    target_type => 'organization',
    record_id => v_row."organization_id"::text,
    tenant => (null)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'userId', null::uuid, 'purgeAfter', v_row."purge_after"),
    idempotency_key => 'organization.purged:' || v_row."organization_id"::text
  );
  return jsonb_build_object('organizationId', v_row."organization_id"::text, 'deleted', v_deleted);
end;
$$;

-- Exports past expires_at, oldest first, with their files, for the purger to
-- remove from Storage before forget_data_exports drops the rows.
create or replace function "better_supabase"."expired_data_exports"(max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'bucket', x."bucket", 'files', to_jsonb(x."files")) order by x."expires_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."data_exports" y
    where y."expires_at" < now()
    order by y."expires_at"
    limit greatest(1, least(coalesce(max_rows, 100), 1000))
  ) x
$$;

-- Deletes the export rows (their files are already gone); returns how many.
create or replace function "better_supabase"."forget_data_exports"(ids uuid[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."data_exports" x where x."id" = any (forget_data_exports.ids) and x."expires_at" < now() returning 1
  )
  select count(*)::integer from removed
$$;

revoke execute on function "better_supabase"."expired_data_exports"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."forget_data_exports"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."expired_data_exports"(integer) to service_role;

-- Anonymizes the rows blocks.data-lifecycle.options.anonymize names once
-- their time is up (service role): at most max_rows per rule, each row once,
-- marked with the time. Returns { table: rows }.
create or replace function "better_supabase"."anonymize_due"(max_rows integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_done jsonb := '{}'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role anonymizes rows' using errcode = '42501', hint = 'DATA_ANONYMIZE_FORBIDDEN';
  end if;
  return v_done;
end;
$$;
revoke execute on function "better_supabase"."anonymize_due"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."anonymize_due"(integer) to service_role;

grant execute on function "better_supabase"."forget_data_exports"(uuid[]) to service_role;
revoke execute on function "better_supabase"."data_lifecycle_tables"() from public, anon, authenticated;
revoke execute on function "better_supabase"."request_data_export"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."list_data_exports"(uuid) from public, anon;
revoke execute on function "better_supabase"."get_data_export"(uuid) from public, anon;
revoke execute on function "better_supabase"."claim_data_export"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."complete_data_export"(uuid, text[]) from public, anon, authenticated;
revoke execute on function "better_supabase"."fail_data_export"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."request_organization_deletion"(uuid, interval) from public, anon;
revoke execute on function "better_supabase"."cancel_organization_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."organization_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."due_organization_deletions"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."purge_organization"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_tables"() to service_role;
grant execute on function "better_supabase"."request_data_export"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_data_exports"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."get_data_export"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."claim_data_export"(uuid) to service_role;
grant execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) to service_role;
grant execute on function "better_supabase"."complete_data_export"(uuid, text[]) to service_role;
grant execute on function "better_supabase"."fail_data_export"(uuid, text) to service_role;
grant execute on function "better_supabase"."request_organization_deletion"(uuid, interval) to authenticated, service_role;
grant execute on function "better_supabase"."cancel_organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."due_organization_deletions"(integer) to service_role;
grant execute on function "better_supabase"."purge_organization"(uuid) to service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module-data data-lifecycle
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.modules (name, version, mode)
values ('data-lifecycle', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module data-lifecycle@6 managed
-- Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Exports of a user's or an organization's data, written by the app's
-- export job as one NDJSON file per table under {id}/ in the data-exports bucket.
create table if not exists "app_private"."data_exports" (
  "id" uuid primary key default gen_random_uuid(),
  "subject" text not null check ("subject" in ('user', 'organization')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'running', 'ready', 'failed')),
  "bucket" text not null default 'data-exports',
  "files" text[] not null default '{}',
  "error" text,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "expires_at" timestamptz,
  check (("subject" = 'user') = ("user_id" is not null)),
  check (("subject" = 'organization') = ("organization_id" is not null))
);
create unique index if not exists data_exports_open_user_idx on "app_private"."data_exports" ("user_id") where "status" in ('pending', 'running') and "subject" = 'user';
create unique index if not exists data_exports_open_tenant_idx on "app_private"."data_exports" ("organization_id") where "status" in ('pending', 'running') and "subject" = 'organization';
create index if not exists data_exports_requested_by_idx on "app_private"."data_exports" ("requested_by");
create index if not exists data_exports_user_idx on "app_private"."data_exports" ("user_id") where "user_id" is not null;
alter table "app_private"."data_exports" enable row level security;
revoke all on "app_private"."data_exports" from anon, authenticated;
grant select on "app_private"."data_exports" to authenticated;
grant all on "app_private"."data_exports" to service_role;
drop policy if exists "data_exports_read" on "app_private"."data_exports";
create policy "data_exports_read" on "app_private"."data_exports" for select to authenticated
  using ("requested_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('organization.export')));

-- Organizations waiting for their purge. Requesting disables the tenant
-- through the access contract; cancelling enables it again unless it was
-- disabled before.
create table if not exists "app_private"."organization_deletions" (
  "organization_id" uuid primary key,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "purge_after" timestamptz not null,
  "cancelled_at" timestamptz,
  "purged_at" timestamptz,
  "previously_disabled" boolean not null default false
);
create index if not exists organization_deletions_due_idx on "app_private"."organization_deletions" ("purge_after") where "cancelled_at" is null and "purged_at" is null;
create index if not exists organization_deletions_requested_by_idx on "app_private"."organization_deletions" ("requested_by") where "requested_by" is not null;
alter table "app_private"."organization_deletions" enable row level security;
revoke all on "app_private"."organization_deletions" from anon, authenticated;
grant all on "app_private"."organization_deletions" to service_role;

-- How long each kind of record is kept: for one tenant, for the tenants
-- on a plan, or for every tenant (both null). A purge keeps a row while
-- retention_for says so, whatever its own older_than argument.
create table if not exists "app_private"."retention_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "plan" text,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "keep" interval not null check ("keep" > interval '0'),
  "updated_at" timestamptz not null default now(),
  check ("organization_id" is null or "plan" is null),
  unique nulls not distinct ("kind", "organization_id", "plan")
);
create index if not exists retention_policies_tenant_idx on "app_private"."retention_policies" ("organization_id") where "organization_id" is not null;
alter table "app_private"."retention_policies" enable row level security;
revoke all on "app_private"."retention_policies" from anon, authenticated;
grant all on "app_private"."retention_policies" to service_role;

-- Legal holds: while one is active (released_at null), no purge deletes
-- the records it covers. A null tenant holds every tenant, a null kind
-- every kind.
create table if not exists "app_private"."legal_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "reason" text not null check (length("reason") between 1 and 1000),
  "placed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "placed_at" timestamptz not null default now(),
  "released_by" uuid references auth.users (id) on delete set null,
  "released_at" timestamptz
);
create index if not exists legal_holds_active_idx on "app_private"."legal_holds" ("organization_id", "kind") where "released_at" is null;
create index if not exists legal_holds_placed_by_idx on "app_private"."legal_holds" ("placed_by") where "placed_by" is not null;
create index if not exists legal_holds_released_by_idx on "app_private"."legal_holds" ("released_by") where "released_by" is not null;
alter table "app_private"."legal_holds" enable row level security;
revoke all on "app_private"."legal_holds" from anon, authenticated;
grant all on "app_private"."legal_holds" to service_role;

-- The tenant's policy for a kind, else its plan's (the shortest when it has
-- several plans), else the policy for every tenant; null without one.
create or replace function "app_private"."retention_for"(kind text, tenant text default null)
returns interval
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_keep interval;
begin
  if retention_for.tenant is not null then
    select x."keep" into v_keep from "app_private"."retention_policies" x
    where x."kind" = retention_for.kind and x."organization_id"::text = retention_for.tenant;
    if v_keep is not null then
      return v_keep;
    end if;
    
  end if;
  select x."keep" into v_keep from "app_private"."retention_policies" x
  where x."kind" = retention_for.kind and x."organization_id" is null and x."plan" is null;
  return v_keep;
end;
$$;

-- The shortest time any policy keeps a kind, so a purge can bound its scan
-- on the timestamp index before it asks retention_for per row.
create or replace function "app_private"."retention_floor"(kind text)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select min(x."keep") from "app_private"."retention_policies" x where x."kind" = retention_floor.kind
$$;

-- Whether an active hold covers the kind for the tenant. A null tenant (a
-- row that belongs to no tenant) is covered only by a hold on every tenant.
create or replace function "app_private"."is_held"(kind text, tenant text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "app_private"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = is_held.kind)
      and (x."organization_id" is null or x."organization_id"::text = is_held.tenant)
  )
$$;

-- Before when every tenant's rows of a kind may go, so a purge can drop a
-- whole partition: null while any hold covers the kind, else the longest
-- policy or the fallback, whichever keeps more.
create or replace function "app_private"."retention_cutoff"(kind text, fallback interval)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from "app_private"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = retention_cutoff.kind)
  ) then null else now() - greatest(
    fallback,
    (select max(x."keep") from "app_private"."retention_policies" x where x."kind" = retention_cutoff.kind)
  ) end
$$;

create or replace function "app_private"."set_retention_policy"(kind text, keep interval, tenant uuid default null, plan text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."retention_policies";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role sets retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  insert into "app_private"."retention_policies" as x ("kind", "keep", "organization_id", "plan")
  values (set_retention_policy.kind, set_retention_policy.keep, set_retention_policy.tenant, set_retention_policy.plan)
  on conflict ("kind", "organization_id", "plan") do update set
    "keep" = excluded."keep",
    "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function "app_private"."remove_retention_policy"(kind text, tenant uuid default null, plan text default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role removes retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  delete from "app_private"."retention_policies" x
  where x."kind" = remove_retention_policy.kind
    and x."organization_id" is not distinct from remove_retention_policy.tenant
    and x."plan" is not distinct from remove_retention_policy.plan;
  return found;
end;
$$;

create or replace function "app_private"."list_retention_policies"(kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."kind", x."organization_id" nulls first, x."plan" nulls first), '[]'::jsonb)
  from "app_private"."retention_policies" x
  where list_retention_policies.kind is null or x."kind" = list_retention_policies.kind
$$;

create or replace function "app_private"."place_legal_hold"(reason text, tenant uuid default null, kind text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role places legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  insert into "app_private"."legal_holds" ("reason", "organization_id", "kind", "placed_by")
  values (place_legal_hold.reason, place_legal_hold.tenant, place_legal_hold.kind, auth.uid())
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Releasing keeps the row, so the holds stay on record.
create or replace function "app_private"."release_legal_hold"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role releases legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  update "app_private"."legal_holds" x set "released_at" = now(), "released_by" = auth.uid()
  where x."id" = release_legal_hold.id and x."released_at" is null
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "app_private"."list_legal_holds"(include_released boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."placed_at" desc, x."id"), '[]'::jsonb)
  from "app_private"."legal_holds" x
  where list_legal_holds.include_released or x."released_at" is null
$$;

revoke execute on function "app_private"."retention_for"(text, text) from public, anon, authenticated;
revoke execute on function "app_private"."retention_floor"(text) from public, anon, authenticated;
revoke execute on function "app_private"."is_held"(text, text) from public, anon, authenticated;
revoke execute on function "app_private"."retention_cutoff"(text, interval) from public, anon, authenticated;
revoke execute on function "app_private"."set_retention_policy"(text, interval, uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."remove_retention_policy"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."list_retention_policies"(text) from public, anon, authenticated;
revoke execute on function "app_private"."place_legal_hold"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."release_legal_hold"(uuid) from public, anon, authenticated;
revoke execute on function "app_private"."list_legal_holds"(boolean) from public, anon, authenticated;
grant execute on function "app_private"."retention_for"(text, text) to service_role;
grant execute on function "app_private"."retention_floor"(text) to service_role;
grant execute on function "app_private"."is_held"(text, text) to service_role;
grant execute on function "app_private"."retention_cutoff"(text, interval) to service_role;
grant execute on function "app_private"."set_retention_policy"(text, interval, uuid, text) to service_role;
grant execute on function "app_private"."remove_retention_policy"(text, uuid, text) to service_role;
grant execute on function "app_private"."list_retention_policies"(text) to service_role;
grant execute on function "app_private"."place_legal_hold"(text, uuid, text) to service_role;
grant execute on function "app_private"."release_legal_hold"(uuid) to service_role;
grant execute on function "app_private"."list_legal_holds"(boolean) to service_role;

-- What an export reads and the purge clears: subject, display name,
-- quoted table, column and whether the purge deletes it.
drop function if exists "app_private"."data_lifecycle_tables"();
create or replace function "app_private"."data_lifecycle_tables"()
returns table (subject text, name text, tbl text, col text, purge boolean, omit text[], exported boolean)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('user', 'better_supabase.memberships', '"better_supabase"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memberships', '"better_supabase"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'app_private.retention_policies', '"app_private"."retention_policies"', 'organization_id', true, '{}'::text[], false)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$$;

-- The credential_ref columns of module tables: display name, quoted table,
-- column and the user column a ref is revoked for (null for the app).
drop function if exists "app_private"."data_lifecycle_credentials"();
create or replace function "app_private"."data_lifecycle_credentials"()
returns table (name text, tbl text, col text, user_col text)
language sql
immutable
set search_path = ''
as $$
  select null::text, null::text, null::text, null::text where false
$$;

-- The credential_refs in the rows a due purge deletes (service role), for
-- the purger to revoke through its CredentialProvider first. in_tenant is
-- false for a ref that doesn't carry the organization; those stay unrevoked.
create or replace function "app_private"."organization_credential_refs"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_entry record;
  v_type text;
  v_refs jsonb;
  v_all jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "app_private"."organization_deletions" x
    where x."organization_id" = organization_credential_refs.tenant and x."cancelled_at" is null
      and x."purged_at" is null and x."purge_after" <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "app_private"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = organization_credential_refs.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  for v_entry in
    select c.name, c.tbl, c.col, c.user_col, t.col as tenant_col
    from "app_private"."data_lifecycle_credentials"() c
    join "app_private"."data_lifecycle_tables"() t on t.subject = 'organization' and t.name = c.name and t.purge
    where to_regclass(c.tbl) is not null
    order by c.name, c.col
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
    from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(v_entry.tbl) and a.attname = v_entry.tenant_col and not a.attisdropped;
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''table'', $2, ''column'', $3, ''ref'', r.ref, ''user_id'', r.user_id, ''in_tenant'', not (jsonb_typeof(r.ref -> ''tenant'') is distinct from ''string'' or (r.ref ->> ''tenant'') is distinct from ($1)::text))), ''[]''::jsonb)
       from (select t.%I as ref, %s as user_id from %s t where t.%I = $1::%s) r
       where jsonb_typeof(r.ref) = ''object''',
      v_entry.col,
      case when v_entry.user_col is null then 'null::text' else format('t.%I::text', v_entry.user_col) end,
      v_entry.tbl, v_entry.tenant_col, v_type
    ) into v_refs
    using organization_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$$;
revoke execute on function "app_private"."data_lifecycle_credentials"() from public, anon, authenticated;
revoke execute on function "app_private"."organization_credential_refs"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."data_lifecycle_credentials"() to service_role;
grant execute on function "app_private"."organization_credential_refs"(uuid) to service_role;

create or replace function "app_private"."data_export_object_allowed"(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Files sit under <export id>/, so the primary key finds the one export.
  select exists (
    select 1 from "app_private"."data_exports" x
    where x."id" = case when split_part(path, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then split_part(path, '/', 1)::uuid end
      and x."bucket" = 'data-exports'
      and x."status" = 'ready'
      and (x."expires_at" is null or x."expires_at" > now())
      and path = any (x."files")
      and (x."requested_by" = auth.uid() or (x."organization_id" is not null and coalesce(better_supabase.can('tenant', x."organization_id", 'organization.export'), false)))
  )
$$;
revoke execute on function "app_private"."data_export_object_allowed"(text) from public, anon;
grant execute on function "app_private"."data_export_object_allowed"(text) to authenticated, service_role;

drop policy if exists "bs_data_exports_select" on storage.objects;
create policy "bs_data_exports_select" on storage.objects for select to authenticated
  using (bucket_id = 'data-exports' and "app_private"."data_export_object_allowed"(name));

-- The caller's own data (subject 'user') or a tenant's (needs the export
-- permission). An open export for the same subject is returned instead
-- of a second one.
create or replace function "app_private"."request_data_export"(subject text default 'user', tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."data_exports";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_data_export.subject = 'organization' then
    if request_data_export.tenant is null or not coalesce(better_supabase.can('tenant', request_data_export.tenant, 'organization.export'), false) then
      raise exception 'You may not export this organization''s data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
    end if;
    select * into v_row from "app_private"."data_exports" x where x."organization_id" = request_data_export.tenant and x."subject" = 'organization' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "app_private"."data_exports" ("subject", "organization_id") values ('organization', request_data_export.tenant) returning * into v_row;
      null;
    end if;
  elsif request_data_export.subject = 'user' then
    select * into v_row from "app_private"."data_exports" x where x."user_id" = auth.uid() and x."subject" = 'user' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "app_private"."data_exports" ("subject", "user_id") values ('user', auth.uid()) returning * into v_row;
      null;
    end if;
  else
    raise exception 'subject must be user or organization' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function "app_private"."list_data_exports"(tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."requested_at" desc, x."id"), '[]'::jsonb)
  from "app_private"."data_exports" x
  where case when list_data_exports.tenant is null
    then x."subject" = 'user' and x."user_id" = auth.uid()
    else x."organization_id" = list_data_exports.tenant
  end
$$;

create or replace function "app_private"."get_data_export"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x.*) from "app_private"."data_exports" x where x."id" = get_data_export.id
$$;

-- Starts a pending (or failed) export and returns it with the tables to
-- read (service role).
create or replace function "app_private"."claim_data_export"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "app_private"."data_exports" x set "status" = 'running', "error" = null
  where x."id" = claim_data_export.id and x."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  return to_jsonb(v_row) || jsonb_build_object('tables', (
    select coalesce(jsonb_agg(t.name order by t.name), '[]'::jsonb)
    from "app_private"."data_lifecycle_tables"() t
    where t.subject = v_row."subject" and t.exported and to_regclass(t.tbl) is not null
  ));
end;
$$;

-- A page of the subject's rows in one table, after the ctid `after`
-- (service role): { rows, after }, with after null on the last page.
create or replace function "app_private"."data_export_rows"(id uuid, table_name text, after text default null, page_size integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."data_exports";
  v_table record;
  v_type text;
  v_rows jsonb;
  v_after text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."data_exports" x where x."id" = data_export_rows.id and x."status" = 'running';
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  select * into v_table from "app_private"."data_lifecycle_tables"() t
  where t.subject = v_row."subject" and t.name = data_export_rows.table_name and t.exported;
  if v_table.tbl is null or to_regclass(v_table.tbl) is null then
    raise exception 'The export has no table %', data_export_rows.table_name using errcode = '22023', hint = 'DATA_EXPORT_TABLE';
  end if;
  select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
  from pg_catalog.pg_attribute a
  where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
  execute format(
    'select coalesce(jsonb_agg((to_jsonb(p.*) - ''_ctid'') - $4::text[] order by p._ctid), ''[]''::jsonb), max(p._ctid)::text, count(*)
     from (select t.ctid as _ctid, t.* from %s t where t.%I = $1::%s and ($2::tid is null or t.ctid > $2::tid) order by t.ctid limit $3) p',
    v_table.tbl, v_table.col, v_type
  ) into v_rows, v_after
  using case when v_row."subject" = 'user' then v_row."user_id"::text else v_row."organization_id"::text end,
    data_export_rows.after, greatest(1, least(data_export_rows.page_size, 10000)), coalesce(v_table.omit, '{}');
  return jsonb_build_object(
    'rows', v_rows,
    'after', case when jsonb_array_length(v_rows) < greatest(1, least(data_export_rows.page_size, 10000)) then null else v_after end
  );
end;
$$;

create or replace function "app_private"."complete_data_export"(id uuid, files text[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "app_private"."data_exports" x set "status" = 'ready', "files" = complete_data_export.files,
    "completed_at" = now(), "expires_at" = now() + '7 days'::interval
  where x."id" = complete_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "app_private"."fail_data_export"(id uuid, error text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "app_private"."data_exports" x set "status" = 'failed', "error" = fail_data_export.error, "completed_at" = now()
  where x."id" = fail_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Schedules the purge after the grace period and disables the tenant.
-- Needs the delete permission; requesting again moves the purge date.
create or replace function "app_private"."request_organization_deletion"(tenant uuid, grace interval default '30 days'::interval)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."organization_deletions";
  v_disabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', request_organization_deletion.tenant, 'organization.delete'), false) then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_organization_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from "app_private"."organization_deletions" x where x."organization_id" = request_organization_deletion.tenant and x."purged_at" is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  v_disabled := false;
  insert into "app_private"."organization_deletions" as x ("organization_id", "requested_by", "purge_after", "previously_disabled")
  values (request_organization_deletion.tenant, auth.uid(), now() + request_organization_deletion.grace, coalesce(v_disabled, false))
  on conflict ("organization_id") do update set
    "requested_by" = excluded."requested_by",
    "requested_at" = now(),
    "purge_after" = excluded."purge_after",
    "previously_disabled" = case when x."cancelled_at" is null then x."previously_disabled" else excluded."previously_disabled" end,
    "cancelled_at" = null
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The requester, a member holding the cancelDelete permission or the service
-- role cancels a pending purge. The tenant is disabled meanwhile, so this
-- asks member_can_while_deleting, which skips the disabled-tenant check.
create or replace function "app_private"."cancel_organization_deletion"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."organization_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."organization_deletions" x
  where x."organization_id" = cancel_organization_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."requested_by" = auth.uid() or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_organization_deletion.tenant, 'organization.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "app_private"."organization_deletions" x set "cancelled_at" = now()
  where x."organization_id" = v_row."organization_id"
  returning * into v_row;
  
  null;
  return to_jsonb(v_row);
end;
$$;

-- The pending deletion, for the organization's members.
create or replace function "app_private"."organization_deletion"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x.*) from "app_private"."organization_deletions" x
  where x."organization_id" = organization_deletion.tenant
    and x."cancelled_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = organization_deletion.tenant and mm."user_id" = auth.uid()))
$$;

create or replace function "app_private"."due_organization_deletions"(max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."purge_after"), '[]'::jsonb)
  from (
    select * from "app_private"."organization_deletions" y
    where y."purge_after" <= now() and y."cancelled_at" is null and y."purged_at" is null
    order by y."purge_after"
    limit greatest(1, least(due_organization_deletions.max_rows, 1000))
  ) x
$$;

-- Deletes a due organization's rows (service role): the app's
-- on_organization_purge(tenant) hook first, then each purged table, then
-- the organization. Returns { organizationId, deleted: { table: rows } }.
create or replace function "app_private"."purge_organization"(tenant uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."organization_deletions";
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."organization_deletions" x
  where x."organization_id" = purge_organization.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null or v_row."purge_after" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "app_private"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = purge_organization.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_organization.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "app_private"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"app_private"."organization_deletions"')
    order by (row_number() over ()) desc
  );
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from "app_private"."data_lifecycle_tables"() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  update "app_private"."organization_deletions" x set "purged_at" = now() where x."organization_id" = v_row."organization_id" returning * into v_row;
  
  null;
  return jsonb_build_object('organizationId', v_row."organization_id"::text, 'deleted', v_deleted);
end;
$$;

-- Exports past expires_at, oldest first, with their files, for the purger to
-- remove from Storage before forget_data_exports drops the rows.
create or replace function "app_private"."expired_data_exports"(max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'bucket', x."bucket", 'files', to_jsonb(x."files")) order by x."expires_at"), '[]'::jsonb)
  from (
    select * from "app_private"."data_exports" y
    where y."expires_at" < now()
    order by y."expires_at"
    limit greatest(1, least(coalesce(max_rows, 100), 1000))
  ) x
$$;

-- Deletes the export rows (their files are already gone); returns how many.
create or replace function "app_private"."forget_data_exports"(ids uuid[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from "app_private"."data_exports" x where x."id" = any (forget_data_exports.ids) and x."expires_at" < now() returning 1
  )
  select count(*)::integer from removed
$$;

revoke execute on function "app_private"."expired_data_exports"(integer) from public, anon, authenticated;
revoke execute on function "app_private"."forget_data_exports"(uuid[]) from public, anon, authenticated;
grant execute on function "app_private"."expired_data_exports"(integer) to service_role;

-- Anonymizes the rows blocks.data-lifecycle.options.anonymize names once
-- their time is up (service role): at most max_rows per rule, each row once,
-- marked with the time. Returns { table: rows }.
create or replace function "app_private"."anonymize_due"(max_rows integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_done jsonb := '{}'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role anonymizes rows' using errcode = '42501', hint = 'DATA_ANONYMIZE_FORBIDDEN';
  end if;
  return v_done;
end;
$$;
revoke execute on function "app_private"."anonymize_due"(integer) from public, anon, authenticated;
grant execute on function "app_private"."anonymize_due"(integer) to service_role;

grant execute on function "app_private"."forget_data_exports"(uuid[]) to service_role;
revoke execute on function "app_private"."data_lifecycle_tables"() from public, anon, authenticated;
revoke execute on function "app_private"."request_data_export"(text, uuid) from public, anon;
revoke execute on function "app_private"."list_data_exports"(uuid) from public, anon;
revoke execute on function "app_private"."get_data_export"(uuid) from public, anon;
revoke execute on function "app_private"."claim_data_export"(uuid) from public, anon, authenticated;
revoke execute on function "app_private"."data_export_rows"(uuid, text, text, integer) from public, anon, authenticated;
revoke execute on function "app_private"."complete_data_export"(uuid, text[]) from public, anon, authenticated;
revoke execute on function "app_private"."fail_data_export"(uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."request_organization_deletion"(uuid, interval) from public, anon;
revoke execute on function "app_private"."cancel_organization_deletion"(uuid) from public, anon;
revoke execute on function "app_private"."organization_deletion"(uuid) from public, anon;
revoke execute on function "app_private"."due_organization_deletions"(integer) from public, anon, authenticated;
revoke execute on function "app_private"."purge_organization"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."data_lifecycle_tables"() to service_role;
grant execute on function "app_private"."request_data_export"(text, uuid) to authenticated, service_role;
grant execute on function "app_private"."list_data_exports"(uuid) to authenticated, service_role;
grant execute on function "app_private"."get_data_export"(uuid) to authenticated, service_role;
grant execute on function "app_private"."claim_data_export"(uuid) to service_role;
grant execute on function "app_private"."data_export_rows"(uuid, text, text, integer) to service_role;
grant execute on function "app_private"."complete_data_export"(uuid, text[]) to service_role;
grant execute on function "app_private"."fail_data_export"(uuid, text) to service_role;
grant execute on function "app_private"."request_organization_deletion"(uuid, interval) to authenticated, service_role;
grant execute on function "app_private"."cancel_organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "app_private"."organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "app_private"."due_organization_deletions"(integer) to service_role;
grant execute on function "app_private"."purge_organization"(uuid) to service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module-data data-lifecycle
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.modules (name, version, mode)
values ('data-lifecycle', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module data-lifecycle@6 managed
-- Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Exports of a user's or an organization's data, written by the app's
-- export job as one NDJSON file per table under {id}/ in the data-exports bucket.
create table if not exists "better_supabase"."data_exports" (
  "id" uuid primary key default gen_random_uuid(),
  "subject" text not null check ("subject" in ('user', 'organization')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "organization_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'running', 'ready', 'failed')),
  "bucket" text not null default 'data-exports',
  "files" text[] not null default '{}',
  "error" text,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "expires_at" timestamptz,
  check (("subject" = 'user') = ("user_id" is not null)),
  check (("subject" = 'organization') = ("organization_id" is not null))
);
create unique index if not exists data_exports_open_user_idx on "better_supabase"."data_exports" ("user_id") where "status" in ('pending', 'running') and "subject" = 'user';
create unique index if not exists data_exports_open_tenant_idx on "better_supabase"."data_exports" ("organization_id") where "status" in ('pending', 'running') and "subject" = 'organization';
create index if not exists data_exports_requested_by_idx on "better_supabase"."data_exports" ("requested_by");
create index if not exists data_exports_user_idx on "better_supabase"."data_exports" ("user_id") where "user_id" is not null;
alter table "better_supabase"."data_exports" enable row level security;
revoke all on "better_supabase"."data_exports" from anon, authenticated;
grant select on "better_supabase"."data_exports" to authenticated;
grant all on "better_supabase"."data_exports" to service_role;
drop policy if exists "data_exports_read" on "better_supabase"."data_exports";
create policy "data_exports_read" on "better_supabase"."data_exports" for select to authenticated
  using ("requested_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('organization.export')));

-- Organizations waiting for their purge. Requesting disables the tenant
-- through the access contract; cancelling enables it again unless it was
-- disabled before.
create table if not exists "better_supabase"."organization_deletions" (
  "organization_id" uuid primary key,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "purge_after" timestamptz not null,
  "cancelled_at" timestamptz,
  "purged_at" timestamptz,
  "previously_disabled" boolean not null default false
);
create index if not exists organization_deletions_due_idx on "better_supabase"."organization_deletions" ("purge_after") where "cancelled_at" is null and "purged_at" is null;
create index if not exists organization_deletions_requested_by_idx on "better_supabase"."organization_deletions" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."organization_deletions" enable row level security;
revoke all on "better_supabase"."organization_deletions" from anon, authenticated;
grant all on "better_supabase"."organization_deletions" to service_role;

-- How long each kind of record is kept: for one tenant, for the tenants
-- on a plan, or for every tenant (both null). A purge keeps a row while
-- retention_for says so, whatever its own older_than argument.
create table if not exists "better_supabase"."retention_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "plan" text,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "keep" interval not null check ("keep" > interval '0'),
  "updated_at" timestamptz not null default now(),
  check ("organization_id" is null or "plan" is null),
  unique nulls not distinct ("kind", "organization_id", "plan")
);
create index if not exists retention_policies_tenant_idx on "better_supabase"."retention_policies" ("organization_id") where "organization_id" is not null;
alter table "better_supabase"."retention_policies" enable row level security;
revoke all on "better_supabase"."retention_policies" from anon, authenticated;
grant all on "better_supabase"."retention_policies" to service_role;

-- Legal holds: while one is active (released_at null), no purge deletes
-- the records it covers. A null tenant holds every tenant, a null kind
-- every kind.
create table if not exists "better_supabase"."legal_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "reason" text not null check (length("reason") between 1 and 1000),
  "placed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "placed_at" timestamptz not null default now(),
  "released_by" uuid references auth.users (id) on delete set null,
  "released_at" timestamptz
);
create index if not exists legal_holds_active_idx on "better_supabase"."legal_holds" ("organization_id", "kind") where "released_at" is null;
create index if not exists legal_holds_placed_by_idx on "better_supabase"."legal_holds" ("placed_by") where "placed_by" is not null;
create index if not exists legal_holds_released_by_idx on "better_supabase"."legal_holds" ("released_by") where "released_by" is not null;
alter table "better_supabase"."legal_holds" enable row level security;
revoke all on "better_supabase"."legal_holds" from anon, authenticated;
grant all on "better_supabase"."legal_holds" to service_role;

-- The tenant's policy for a kind, else its plan's (the shortest when it has
-- several plans), else the policy for every tenant; null without one.
create or replace function "better_supabase"."retention_for"(kind text, tenant text default null)
returns interval
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_keep interval;
begin
  if retention_for.tenant is not null then
    select x."keep" into v_keep from "better_supabase"."retention_policies" x
    where x."kind" = retention_for.kind and x."organization_id"::text = retention_for.tenant;
    if v_keep is not null then
      return v_keep;
    end if;
    
  end if;
  select x."keep" into v_keep from "better_supabase"."retention_policies" x
  where x."kind" = retention_for.kind and x."organization_id" is null and x."plan" is null;
  return v_keep;
end;
$$;

-- The shortest time any policy keeps a kind, so a purge can bound its scan
-- on the timestamp index before it asks retention_for per row.
create or replace function "better_supabase"."retention_floor"(kind text)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select min(x."keep") from "better_supabase"."retention_policies" x where x."kind" = retention_floor.kind
$$;

-- Whether an active hold covers the kind for the tenant. A null tenant (a
-- row that belongs to no tenant) is covered only by a hold on every tenant.
create or replace function "better_supabase"."is_held"(kind text, tenant text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = is_held.kind)
      and (x."organization_id" is null or x."organization_id"::text = is_held.tenant)
  )
$$;

-- Before when every tenant's rows of a kind may go, so a purge can drop a
-- whole partition: null while any hold covers the kind, else the longest
-- policy or the fallback, whichever keeps more.
create or replace function "better_supabase"."retention_cutoff"(kind text, fallback interval)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."kind" is null or x."kind" = retention_cutoff.kind)
  ) then null else now() - greatest(
    fallback,
    (select max(x."keep") from "better_supabase"."retention_policies" x where x."kind" = retention_cutoff.kind)
  ) end
$$;

create or replace function "better_supabase"."set_retention_policy"(kind text, keep interval, tenant uuid default null, plan text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."retention_policies";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role sets retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."retention_policies" as x ("kind", "keep", "organization_id", "plan")
  values (set_retention_policy.kind, set_retention_policy.keep, set_retention_policy.tenant, set_retention_policy.plan)
  on conflict ("kind", "organization_id", "plan") do update set
    "keep" = excluded."keep",
    "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."remove_retention_policy"(kind text, tenant uuid default null, plan text default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role removes retention policies' using errcode = '42501', hint = 'RETENTION_FORBIDDEN';
  end if;
  delete from "better_supabase"."retention_policies" x
  where x."kind" = remove_retention_policy.kind
    and x."organization_id" is not distinct from remove_retention_policy.tenant
    and x."plan" is not distinct from remove_retention_policy.plan;
  return found;
end;
$$;

create or replace function "better_supabase"."list_retention_policies"(kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."kind", x."organization_id" nulls first, x."plan" nulls first), '[]'::jsonb)
  from "better_supabase"."retention_policies" x
  where list_retention_policies.kind is null or x."kind" = list_retention_policies.kind
$$;

create or replace function "better_supabase"."place_legal_hold"(reason text, tenant uuid default null, kind text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role places legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  insert into "better_supabase"."legal_holds" ("reason", "organization_id", "kind", "placed_by")
  values (place_legal_hold.reason, place_legal_hold.tenant, place_legal_hold.kind, auth.uid())
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Releasing keeps the row, so the holds stay on record.
create or replace function "better_supabase"."release_legal_hold"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."legal_holds";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role releases legal holds' using errcode = '42501', hint = 'LEGAL_HOLD_FORBIDDEN';
  end if;
  update "better_supabase"."legal_holds" x set "released_at" = now(), "released_by" = auth.uid()
  where x."id" = release_legal_hold.id and x."released_at" is null
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_legal_holds"(include_released boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."placed_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."legal_holds" x
  where list_legal_holds.include_released or x."released_at" is null
$$;

revoke execute on function "better_supabase"."retention_for"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."retention_floor"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."is_held"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."retention_cutoff"(text, interval) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_retention_policy"(text, interval, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."remove_retention_policy"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_retention_policies"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."place_legal_hold"(text, uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."release_legal_hold"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_legal_holds"(boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."retention_for"(text, text) to service_role;
grant execute on function "better_supabase"."retention_floor"(text) to service_role;
grant execute on function "better_supabase"."is_held"(text, text) to service_role;
grant execute on function "better_supabase"."retention_cutoff"(text, interval) to service_role;
grant execute on function "better_supabase"."set_retention_policy"(text, interval, uuid, text) to service_role;
grant execute on function "better_supabase"."remove_retention_policy"(text, uuid, text) to service_role;
grant execute on function "better_supabase"."list_retention_policies"(text) to service_role;
grant execute on function "better_supabase"."place_legal_hold"(text, uuid, text) to service_role;
grant execute on function "better_supabase"."release_legal_hold"(uuid) to service_role;
grant execute on function "better_supabase"."list_legal_holds"(boolean) to service_role;

-- What an export reads and the purge clears: subject, display name,
-- quoted table, column and whether the purge deletes it.
drop function if exists "better_supabase"."data_lifecycle_tables"();
create or replace function "better_supabase"."data_lifecycle_tables"()
returns table (subject text, name text, tbl text, col text, purge boolean, omit text[], exported boolean)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('user', 'better_supabase.memberships', '"better_supabase"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memberships', '"better_supabase"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$$;

-- The credential_ref columns of module tables: display name, quoted table,
-- column and the user column a ref is revoked for (null for the app).
drop function if exists "better_supabase"."data_lifecycle_credentials"();
create or replace function "better_supabase"."data_lifecycle_credentials"()
returns table (name text, tbl text, col text, user_col text)
language sql
immutable
set search_path = ''
as $$
  select null::text, null::text, null::text, null::text where false
$$;

-- The credential_refs in the rows a due purge deletes (service role), for
-- the purger to revoke through its CredentialProvider first. in_tenant is
-- false for a ref that doesn't carry the organization; those stay unrevoked.
create or replace function "better_supabase"."organization_credential_refs"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_entry record;
  v_type text;
  v_refs jsonb;
  v_all jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."organization_deletions" x
    where x."organization_id" = organization_credential_refs.tenant and x."cancelled_at" is null
      and x."purged_at" is null and x."purge_after" <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = organization_credential_refs.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  for v_entry in
    select c.name, c.tbl, c.col, c.user_col, t.col as tenant_col
    from "better_supabase"."data_lifecycle_credentials"() c
    join "better_supabase"."data_lifecycle_tables"() t on t.subject = 'organization' and t.name = c.name and t.purge
    where to_regclass(c.tbl) is not null
    order by c.name, c.col
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
    from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(v_entry.tbl) and a.attname = v_entry.tenant_col and not a.attisdropped;
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''table'', $2, ''column'', $3, ''ref'', r.ref, ''user_id'', r.user_id, ''in_tenant'', not (jsonb_typeof(r.ref -> ''tenant'') is distinct from ''string'' or (r.ref ->> ''tenant'') is distinct from ($1)::text))), ''[]''::jsonb)
       from (select t.%I as ref, %s as user_id from %s t where t.%I = $1::%s) r
       where jsonb_typeof(r.ref) = ''object''',
      v_entry.col,
      case when v_entry.user_col is null then 'null::text' else format('t.%I::text', v_entry.user_col) end,
      v_entry.tbl, v_entry.tenant_col, v_type
    ) into v_refs
    using organization_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$$;
revoke execute on function "better_supabase"."data_lifecycle_credentials"() from public, anon, authenticated;
revoke execute on function "better_supabase"."organization_credential_refs"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_credentials"() to service_role;
grant execute on function "better_supabase"."organization_credential_refs"(uuid) to service_role;

create or replace function "better_supabase"."data_export_object_allowed"(path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Files sit under <export id>/, so the primary key finds the one export.
  select exists (
    select 1 from "better_supabase"."data_exports" x
    where x."id" = case when split_part(path, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then split_part(path, '/', 1)::uuid end
      and x."bucket" = 'data-exports'
      and x."status" = 'ready'
      and (x."expires_at" is null or x."expires_at" > now())
      and path = any (x."files")
      and (x."requested_by" = auth.uid() or (x."organization_id" is not null and coalesce(better_supabase.can('tenant', x."organization_id", 'organization.export'), false)))
  )
$$;
revoke execute on function "better_supabase"."data_export_object_allowed"(text) from public, anon;
grant execute on function "better_supabase"."data_export_object_allowed"(text) to authenticated, service_role;

drop policy if exists "bs_data_exports_select" on storage.objects;
create policy "bs_data_exports_select" on storage.objects for select to authenticated
  using (bucket_id = 'data-exports' and "better_supabase"."data_export_object_allowed"(name));

-- The caller's own data (subject 'user') or a tenant's (needs the export
-- permission). An open export for the same subject is returned instead
-- of a second one.
create or replace function "better_supabase"."request_data_export"(subject text default 'user', tenant uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_data_export.subject = 'organization' then
    if request_data_export.tenant is null or not coalesce(better_supabase.can('tenant', request_data_export.tenant, 'organization.export'), false) then
      raise exception 'You may not export this organization''s data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
    end if;
    select * into v_row from "better_supabase"."data_exports" x where x."organization_id" = request_data_export.tenant and x."subject" = 'organization' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "organization_id") values ('organization', request_data_export.tenant) returning * into v_row;
      null;
    end if;
  elsif request_data_export.subject = 'user' then
    select * into v_row from "better_supabase"."data_exports" x where x."user_id" = auth.uid() and x."subject" = 'user' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "user_id") values ('user', auth.uid()) returning * into v_row;
      null;
    end if;
  else
    raise exception 'subject must be user or organization' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_data_exports"(tenant uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."requested_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."data_exports" x
  where case when list_data_exports.tenant is null
    then x."subject" = 'user' and x."user_id" = auth.uid()
    else x."organization_id" = list_data_exports.tenant
  end
$$;

create or replace function "better_supabase"."get_data_export"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."data_exports" x where x."id" = get_data_export.id
$$;

-- Starts a pending (or failed) export and returns it with the tables to
-- read (service role).
create or replace function "better_supabase"."claim_data_export"(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'running', "error" = null
  where x."id" = claim_data_export.id and x."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  return to_jsonb(v_row) || jsonb_build_object('tables', (
    select coalesce(jsonb_agg(t.name order by t.name), '[]'::jsonb)
    from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = v_row."subject" and t.exported and to_regclass(t.tbl) is not null
  ));
end;
$$;

-- A page of the subject's rows in one table, after the ctid `after`
-- (service role): { rows, after }, with after null on the last page.
create or replace function "better_supabase"."data_export_rows"(id uuid, table_name text, after text default null, page_size integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
  v_table record;
  v_type text;
  v_rows jsonb;
  v_after text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x where x."id" = data_export_rows.id and x."status" = 'running';
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  select * into v_table from "better_supabase"."data_lifecycle_tables"() t
  where t.subject = v_row."subject" and t.name = data_export_rows.table_name and t.exported;
  if v_table.tbl is null or to_regclass(v_table.tbl) is null then
    raise exception 'The export has no table %', data_export_rows.table_name using errcode = '22023', hint = 'DATA_EXPORT_TABLE';
  end if;
  select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
  from pg_catalog.pg_attribute a
  where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
  execute format(
    'select coalesce(jsonb_agg((to_jsonb(p.*) - ''_ctid'') - $4::text[] order by p._ctid), ''[]''::jsonb), max(p._ctid)::text, count(*)
     from (select t.ctid as _ctid, t.* from %s t where t.%I = $1::%s and ($2::tid is null or t.ctid > $2::tid) order by t.ctid limit $3) p',
    v_table.tbl, v_table.col, v_type
  ) into v_rows, v_after
  using case when v_row."subject" = 'user' then v_row."user_id"::text else v_row."organization_id"::text end,
    data_export_rows.after, greatest(1, least(data_export_rows.page_size, 10000)), coalesce(v_table.omit, '{}');
  return jsonb_build_object(
    'rows', v_rows,
    'after', case when jsonb_array_length(v_rows) < greatest(1, least(data_export_rows.page_size, 10000)) then null else v_after end
  );
end;
$$;

create or replace function "better_supabase"."complete_data_export"(id uuid, files text[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'ready', "files" = complete_data_export.files,
    "completed_at" = now(), "expires_at" = now() + '7 days'::interval
  where x."id" = complete_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No running export has this id' using errcode = 'P0002', hint = 'DATA_EXPORT_NOT_FOUND';
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."fail_data_export"(id uuid, error text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."data_exports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs exports' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  update "better_supabase"."data_exports" x set "status" = 'failed', "error" = fail_data_export.error, "completed_at" = now()
  where x."id" = fail_data_export.id and x."status" = 'running'
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Schedules the purge after the grace period and disables the tenant.
-- Needs the delete permission; requesting again moves the purge date.
create or replace function "better_supabase"."request_organization_deletion"(tenant uuid, grace interval default '30 days'::interval)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
  v_disabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', request_organization_deletion.tenant, 'organization.delete'), false) then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_organization_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from "better_supabase"."organization_deletions" x where x."organization_id" = request_organization_deletion.tenant and x."purged_at" is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  v_disabled := false;
  insert into "better_supabase"."organization_deletions" as x ("organization_id", "requested_by", "purge_after", "previously_disabled")
  values (request_organization_deletion.tenant, auth.uid(), now() + request_organization_deletion.grace, coalesce(v_disabled, false))
  on conflict ("organization_id") do update set
    "requested_by" = excluded."requested_by",
    "requested_at" = now(),
    "purge_after" = excluded."purge_after",
    "previously_disabled" = case when x."cancelled_at" is null then x."previously_disabled" else excluded."previously_disabled" end,
    "cancelled_at" = null
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The requester, a member holding the cancelDelete permission or the service
-- role cancels a pending purge. The tenant is disabled meanwhile, so this
-- asks member_can_while_deleting, which skips the disabled-tenant check.
create or replace function "better_supabase"."cancel_organization_deletion"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = cancel_organization_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."requested_by" = auth.uid() or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_organization_deletion.tenant, 'organization.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "better_supabase"."organization_deletions" x set "cancelled_at" = now()
  where x."organization_id" = v_row."organization_id"
  returning * into v_row;
  
  null;
  return to_jsonb(v_row);
end;
$$;

-- The pending deletion, for the organization's members.
create or replace function "better_supabase"."organization_deletion"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."organization_deletions" x
  where x."organization_id" = organization_deletion.tenant
    and x."cancelled_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = organization_deletion.tenant and mm."user_id" = auth.uid()))
$$;

create or replace function "better_supabase"."due_organization_deletions"(max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."purge_after"), '[]'::jsonb)
  from (
    select * from "better_supabase"."organization_deletions" y
    where y."purge_after" <= now() and y."cancelled_at" is null and y."purged_at" is null
    order by y."purge_after"
    limit greatest(1, least(due_organization_deletions.max_rows, 1000))
  ) x
$$;

-- Deletes a due organization's rows (service role): the app's
-- on_organization_purge(tenant) hook first, then each purged table, then
-- the organization. Returns { organizationId, deleted: { table: rows } }.
create or replace function "better_supabase"."purge_organization"(tenant uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_deletions";
  v_table record;
  v_type text;
  v_count bigint;
  v_deleted jsonb := '{}'::jsonb;
  v_pending text[];
  v_left text[];
  v_name text;
  v_pass integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_deletions" x
  where x."organization_id" = purge_organization.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."organization_id" is null or v_row."purge_after" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."organization_id" is null or x."organization_id" = purge_organization.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_organization.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"better_supabase"."organization_deletions"')
    order by (row_number() over ()) desc
  );
  for v_pass in 1..10 loop
    exit when cardinality(v_pending) = 0;
    v_left := '{}';
    foreach v_name in array v_pending loop
      select * into v_table from "better_supabase"."data_lifecycle_tables"() t
      where t.subject = 'organization' and t.name = v_name;
      select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_table.tbl) and a.attname = v_table.col and not a.attisdropped;
      begin
        execute format('delete from %s t where t.%I = $1::%s', v_table.tbl, v_table.col, v_type)
          using purge_organization.tenant::text;
        get diagnostics v_count = row_count;
        v_deleted := v_deleted || jsonb_build_object(v_name, coalesce((v_deleted ->> v_name)::bigint, 0) + v_count);
      exception when foreign_key_violation or restrict_violation or check_violation then
        -- Another table's rows still point here (or a set null action breaks
        -- a check on them): try again after the other tables.
        v_left := v_left || v_name;
      end;
    end loop;
    if v_left = v_pending then
      raise exception 'Rows in % still have references the purge does not delete', array_to_string(v_left, ', ')
        using errcode = '23503', hint = 'ORGANIZATION_PURGE_BLOCKED';
    end if;
    v_pending := v_left;
  end loop;
  update "better_supabase"."organization_deletions" x set "purged_at" = now() where x."organization_id" = v_row."organization_id" returning * into v_row;
  
  null;
  return jsonb_build_object('organizationId', v_row."organization_id"::text, 'deleted', v_deleted);
end;
$$;

-- Exports past expires_at, oldest first, with their files, for the purger to
-- remove from Storage before forget_data_exports drops the rows.
create or replace function "better_supabase"."expired_data_exports"(max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'bucket', x."bucket", 'files', to_jsonb(x."files")) order by x."expires_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."data_exports" y
    where y."expires_at" < now()
    order by y."expires_at"
    limit greatest(1, least(coalesce(max_rows, 100), 1000))
  ) x
$$;

-- Deletes the export rows (their files are already gone); returns how many.
create or replace function "better_supabase"."forget_data_exports"(ids uuid[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."data_exports" x where x."id" = any (forget_data_exports.ids) and x."expires_at" < now() returning 1
  )
  select count(*)::integer from removed
$$;

revoke execute on function "better_supabase"."expired_data_exports"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."forget_data_exports"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."expired_data_exports"(integer) to service_role;

-- Anonymizes the rows blocks.data-lifecycle.options.anonymize names once
-- their time is up (service role): at most max_rows per rule, each row once,
-- marked with the time. Returns { table: rows }.
create or replace function "better_supabase"."anonymize_due"(max_rows integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_done jsonb := '{}'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role anonymizes rows' using errcode = '42501', hint = 'DATA_ANONYMIZE_FORBIDDEN';
  end if;
  return v_done;
end;
$$;
revoke execute on function "better_supabase"."anonymize_due"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."anonymize_due"(integer) to service_role;

grant execute on function "better_supabase"."forget_data_exports"(uuid[]) to service_role;
revoke execute on function "better_supabase"."data_lifecycle_tables"() from public, anon, authenticated;
revoke execute on function "better_supabase"."request_data_export"(text, uuid) from public, anon;
revoke execute on function "better_supabase"."list_data_exports"(uuid) from public, anon;
revoke execute on function "better_supabase"."get_data_export"(uuid) from public, anon;
revoke execute on function "better_supabase"."claim_data_export"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."complete_data_export"(uuid, text[]) from public, anon, authenticated;
revoke execute on function "better_supabase"."fail_data_export"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."request_organization_deletion"(uuid, interval) from public, anon;
revoke execute on function "better_supabase"."cancel_organization_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."organization_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."due_organization_deletions"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."purge_organization"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_tables"() to service_role;
grant execute on function "better_supabase"."request_data_export"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_data_exports"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."get_data_export"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."claim_data_export"(uuid) to service_role;
grant execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) to service_role;
grant execute on function "better_supabase"."complete_data_export"(uuid, text[]) to service_role;
grant execute on function "better_supabase"."fail_data_export"(uuid, text) to service_role;
grant execute on function "better_supabase"."request_organization_deletion"(uuid, interval) to authenticated, service_role;
grant execute on function "better_supabase"."cancel_organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."organization_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."due_organization_deletions"(integer) to service_role;
grant execute on function "better_supabase"."purge_organization"(uuid) to service_role;

-- blocks.data-lifecycle.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."data_export_object_allowed"(text);

drop function if exists "api"."data_lifecycle_tables"();
drop function if exists "api"."data_lifecycle_credentials"();

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

create or replace function "api"."retention_for"(kind text, tenant text default null)
returns interval
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."retention_for"($1, $2) $$;
revoke execute on function "api"."retention_for"(text, text) from public, anon, authenticated;
grant execute on function "api"."retention_for"(text, text) to service_role;

create or replace function "api"."retention_floor"(kind text)
returns interval
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."retention_floor"($1) $$;
revoke execute on function "api"."retention_floor"(text) from public, anon, authenticated;
grant execute on function "api"."retention_floor"(text) to service_role;

create or replace function "api"."is_held"(kind text, tenant text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."is_held"($1, $2) $$;
revoke execute on function "api"."is_held"(text, text) from public, anon, authenticated;
grant execute on function "api"."is_held"(text, text) to service_role;

create or replace function "api"."retention_cutoff"(kind text, fallback interval)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."retention_cutoff"($1, $2) $$;
revoke execute on function "api"."retention_cutoff"(text, interval) from public, anon, authenticated;
grant execute on function "api"."retention_cutoff"(text, interval) to service_role;

create or replace function "api"."set_retention_policy"(kind text, keep interval, tenant uuid default null, plan text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_retention_policy"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_retention_policy"(text, interval, uuid, text) from public, anon, authenticated;
grant execute on function "api"."set_retention_policy"(text, interval, uuid, text) to service_role;

create or replace function "api"."remove_retention_policy"(kind text, tenant uuid default null, plan text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_retention_policy"($1, $2, $3) $$;
revoke execute on function "api"."remove_retention_policy"(text, uuid, text) from public, anon, authenticated;
grant execute on function "api"."remove_retention_policy"(text, uuid, text) to service_role;

create or replace function "api"."list_retention_policies"(kind text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_retention_policies"($1) $$;
revoke execute on function "api"."list_retention_policies"(text) from public, anon, authenticated;
grant execute on function "api"."list_retention_policies"(text) to service_role;

create or replace function "api"."place_legal_hold"(reason text, tenant uuid default null, kind text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."place_legal_hold"($1, $2, $3) $$;
revoke execute on function "api"."place_legal_hold"(text, uuid, text) from public, anon, authenticated;
grant execute on function "api"."place_legal_hold"(text, uuid, text) to service_role;

create or replace function "api"."release_legal_hold"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_legal_hold"($1) $$;
revoke execute on function "api"."release_legal_hold"(uuid) from public, anon, authenticated;
grant execute on function "api"."release_legal_hold"(uuid) to service_role;

create or replace function "api"."list_legal_holds"(include_released boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_legal_holds"($1) $$;
revoke execute on function "api"."list_legal_holds"(boolean) from public, anon, authenticated;
grant execute on function "api"."list_legal_holds"(boolean) to service_role;

create or replace function "api"."data_lifecycle_credentials"()
returns table (name text, tbl text, col text, user_col text)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."data_lifecycle_credentials"() $$;
revoke execute on function "api"."data_lifecycle_credentials"() from public, anon, authenticated;
grant execute on function "api"."data_lifecycle_credentials"() to service_role;

create or replace function "api"."organization_credential_refs"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_credential_refs"($1) $$;
revoke execute on function "api"."organization_credential_refs"(uuid) from public, anon, authenticated;
grant execute on function "api"."organization_credential_refs"(uuid) to service_role;

create or replace function "api"."expired_data_exports"(max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expired_data_exports"($1) $$;
revoke execute on function "api"."expired_data_exports"(integer) from public, anon, authenticated;
grant execute on function "api"."expired_data_exports"(integer) to service_role;

create or replace function "api"."anonymize_due"(max_rows integer default 1000)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."anonymize_due"($1) $$;
revoke execute on function "api"."anonymize_due"(integer) from public, anon, authenticated;
grant execute on function "api"."anonymize_due"(integer) to service_role;

create or replace function "api"."forget_data_exports"(ids uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."forget_data_exports"($1) $$;
revoke execute on function "api"."forget_data_exports"(uuid[]) from public, anon, authenticated;
grant execute on function "api"."forget_data_exports"(uuid[]) to service_role;

create or replace function "api"."data_lifecycle_tables"()
returns table (subject text, name text, tbl text, col text, purge boolean, omit text[], exported boolean)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."data_lifecycle_tables"() $$;
revoke execute on function "api"."data_lifecycle_tables"() from public, anon, authenticated;
grant execute on function "api"."data_lifecycle_tables"() to service_role;

create or replace function "api"."request_data_export"(subject text default 'user', tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_data_export"($1, $2) $$;
revoke execute on function "api"."request_data_export"(text, uuid) from public, anon;
grant execute on function "api"."request_data_export"(text, uuid) to authenticated, service_role;

create or replace function "api"."list_data_exports"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_data_exports"($1) $$;
revoke execute on function "api"."list_data_exports"(uuid) from public, anon;
grant execute on function "api"."list_data_exports"(uuid) to authenticated, service_role;

create or replace function "api"."get_data_export"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_data_export"($1) $$;
revoke execute on function "api"."get_data_export"(uuid) from public, anon;
grant execute on function "api"."get_data_export"(uuid) to authenticated, service_role;

create or replace function "api"."claim_data_export"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_data_export"($1) $$;
revoke execute on function "api"."claim_data_export"(uuid) from public, anon, authenticated;
grant execute on function "api"."claim_data_export"(uuid) to service_role;

create or replace function "api"."data_export_rows"(id uuid, table_name text, after text default null, page_size integer default 1000)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."data_export_rows"($1, $2, $3, $4) $$;
revoke execute on function "api"."data_export_rows"(uuid, text, text, integer) from public, anon, authenticated;
grant execute on function "api"."data_export_rows"(uuid, text, text, integer) to service_role;

create or replace function "api"."complete_data_export"(id uuid, files text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_data_export"($1, $2) $$;
revoke execute on function "api"."complete_data_export"(uuid, text[]) from public, anon, authenticated;
grant execute on function "api"."complete_data_export"(uuid, text[]) to service_role;

create or replace function "api"."fail_data_export"(id uuid, error text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."fail_data_export"($1, $2) $$;
revoke execute on function "api"."fail_data_export"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."fail_data_export"(uuid, text) to service_role;

create or replace function "api"."request_organization_deletion"(tenant uuid, grace interval default '30 days'::interval)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_organization_deletion"($1, $2) $$;
revoke execute on function "api"."request_organization_deletion"(uuid, interval) from public, anon;
grant execute on function "api"."request_organization_deletion"(uuid, interval) to authenticated, service_role;

create or replace function "api"."cancel_organization_deletion"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_organization_deletion"($1) $$;
revoke execute on function "api"."cancel_organization_deletion"(uuid) from public, anon;
grant execute on function "api"."cancel_organization_deletion"(uuid) to authenticated, service_role;

create or replace function "api"."organization_deletion"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_deletion"($1) $$;
revoke execute on function "api"."organization_deletion"(uuid) from public, anon;
grant execute on function "api"."organization_deletion"(uuid) to authenticated, service_role;

create or replace function "api"."due_organization_deletions"(max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."due_organization_deletions"($1) $$;
revoke execute on function "api"."due_organization_deletions"(integer) from public, anon, authenticated;
grant execute on function "api"."due_organization_deletions"(integer) to service_role;

create or replace function "api"."purge_organization"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_organization"($1) $$;
revoke execute on function "api"."purge_organization"(uuid) from public, anon, authenticated;
grant execute on function "api"."purge_organization"(uuid) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_35_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bs-module-data data-lifecycle
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.modules (name, version, mode)
values ('data-lifecycle', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
