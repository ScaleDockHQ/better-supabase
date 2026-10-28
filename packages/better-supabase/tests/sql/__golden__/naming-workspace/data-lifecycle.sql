-- ==== schema supabase/schemas/900_better_supabase_035_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bsb-block data-lifecycle@6 managed
-- @bsb-hash sha256:41a9d73c7325a239788e4a37bb5c8e33f5f3177653c4ae6ce5ab84a6f68da20c
-- Data exports per user or organization from every installed module's tables and the app's, written to a private bucket by the app's export job, and organization deletion with a grace period that disables the tenant before a purge job deletes its rows.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."retention_policies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."retention_policies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."retention_policies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."retention_policies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."retention_policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Exports of a user's or an organization's data, written by the app's
-- export job as one NDJSON file per table under {id}/ in the data-exports bucket.
create table if not exists "better_supabase"."data_exports" (
  "id" uuid primary key default gen_random_uuid(),
  "subject" text not null check ("subject" in ('user', 'organization')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "workspace_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'running', 'ready', 'failed')),
  "bucket" text not null default 'data-exports',
  "files" text[] not null default '{}',
  "error" text,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "expires_at" timestamptz,
  check (("subject" = 'user') = ("user_id" is not null)),
  check (("subject" = 'organization') = ("workspace_id" is not null))
);
create unique index if not exists data_exports_open_user_idx on "better_supabase"."data_exports" ("user_id") where "status" in ('pending', 'running') and "subject" = 'user';
create unique index if not exists data_exports_open_tenant_idx on "better_supabase"."data_exports" ("workspace_id") where "status" in ('pending', 'running') and "subject" = 'organization';
create index if not exists data_exports_requested_by_idx on "better_supabase"."data_exports" ("requested_by");
create index if not exists data_exports_user_idx on "better_supabase"."data_exports" ("user_id") where "user_id" is not null;
alter table "better_supabase"."data_exports" enable row level security;
revoke all on "better_supabase"."data_exports" from public, anon, authenticated;
grant select on "better_supabase"."data_exports" to authenticated;
grant all on "better_supabase"."data_exports" to service_role;
drop policy if exists data_exports_read on "better_supabase"."data_exports";
create policy data_exports_read on "better_supabase"."data_exports"
  for select to authenticated
  using ("requested_by" = (select auth.uid()) or "workspace_id" in (select better_supabase.tenant_ids_with('data_lifecycle.export')));

-- Organizations waiting for their purge. Requesting disables the tenant
-- through the access contract; cancelling enables it again unless it was
-- disabled before.
create table if not exists "better_supabase"."workspace_deletions" (
  "workspace_id" uuid primary key,
  "requested_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "requested_at" timestamptz not null default now(),
  "purge_after" timestamptz not null,
  "cancelled_at" timestamptz,
  "purged_at" timestamptz,
  "previously_disabled" boolean not null default false
);
create index if not exists workspace_deletions_due_idx on "better_supabase"."workspace_deletions" ("purge_after") where "cancelled_at" is null and "purged_at" is null;
create index if not exists workspace_deletions_requested_by_idx on "better_supabase"."workspace_deletions" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."workspace_deletions" enable row level security;
revoke all on "better_supabase"."workspace_deletions" from public, anon, authenticated;
grant all on "better_supabase"."workspace_deletions" to service_role;

-- How long each kind of record is kept: for one tenant, for the tenants
-- on a plan, or for every tenant (both null). A purge keeps a row while
-- retention_for says so, whatever its own older_than argument.
create table if not exists "better_supabase"."retention_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "workspace_id" uuid,
  "plan" text,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "keep" interval not null check ("keep" > interval '0'),
  "updated_at" timestamptz not null default now(),
  check ("workspace_id" is null or "plan" is null),
  unique nulls not distinct ("kind", "workspace_id", "plan")
);
create index if not exists retention_policies_tenant_idx on "better_supabase"."retention_policies" ("workspace_id") where "workspace_id" is not null;
alter table "better_supabase"."retention_policies" enable row level security;
revoke all on "better_supabase"."retention_policies" from public, anon, authenticated;
grant all on "better_supabase"."retention_policies" to service_role;

-- Legal holds: while one is active (released_at null), no purge deletes
-- the records it covers. A null tenant holds every tenant, a null kind
-- every kind.
create table if not exists "better_supabase"."legal_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "workspace_id" uuid,
  "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "reason" text not null check (length("reason") between 1 and 1000),
  "placed_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "placed_at" timestamptz not null default now(),
  "released_by" uuid references auth.users (id) on delete set null,
  "released_at" timestamptz
);
create index if not exists legal_holds_active_idx on "better_supabase"."legal_holds" ("workspace_id", "kind") where "released_at" is null;
create index if not exists legal_holds_placed_by_idx on "better_supabase"."legal_holds" ("placed_by") where "placed_by" is not null;
create index if not exists legal_holds_released_by_idx on "better_supabase"."legal_holds" ("released_by") where "released_by" is not null;
alter table "better_supabase"."legal_holds" enable row level security;
revoke all on "better_supabase"."legal_holds" from public, anon, authenticated;
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
    where x."kind" = retention_for.kind and x."workspace_id"::text = retention_for.tenant;
    if v_keep is not null then
      return v_keep;
    end if;
    
  end if;
  select x."keep" into v_keep from "better_supabase"."retention_policies" x
  where x."kind" = retention_for.kind and x."workspace_id" is null and x."plan" is null;
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
      and (x."workspace_id" is null or x."workspace_id"::text = is_held.tenant)
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
  insert into "better_supabase"."retention_policies" as x ("kind", "keep", "workspace_id", "plan")
  values (set_retention_policy.kind, set_retention_policy.keep, set_retention_policy.tenant, set_retention_policy.plan)
  on conflict ("kind", "workspace_id", "plan") do update set
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
    and x."workspace_id" is not distinct from remove_retention_policy.tenant
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
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."kind", x."workspace_id" nulls first, x."plan" nulls first), '[]'::jsonb)
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
  insert into "better_supabase"."legal_holds" ("reason", "workspace_id", "kind", "placed_by")
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
    ('organization', 'better_supabase.memberships', '"better_supabase"."memberships"', 'workspace_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'workspace_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'workspace_id', true, '{}'::text[], false)
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
create or replace function "better_supabase"."workspace_credential_refs"(tenant uuid)
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
    select 1 from "better_supabase"."workspace_deletions" x
    where x."workspace_id" = workspace_credential_refs.tenant and x."cancelled_at" is null
      and x."purged_at" is null and x."purge_after" <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."workspace_id" is null or x."workspace_id" = workspace_credential_refs.tenant)
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
    using workspace_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$$;
revoke execute on function "better_supabase"."data_lifecycle_credentials"() from public, anon, authenticated;
revoke execute on function "better_supabase"."workspace_credential_refs"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_credentials"() to service_role;
grant execute on function "better_supabase"."workspace_credential_refs"(uuid) to service_role;

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
      and (x."requested_by" = auth.uid() or (x."workspace_id" is not null and coalesce(better_supabase.can('tenant', x."workspace_id", 'data_lifecycle.export'), false)))
  )
$$;
revoke execute on function "better_supabase"."data_export_object_allowed"(text) from public, anon;
grant execute on function "better_supabase"."data_export_object_allowed"(text) to authenticated, service_role;

drop policy if exists bsb_data_exports_select on storage.objects;
create policy bsb_data_exports_select on storage.objects
  for select to authenticated
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
    if request_data_export.tenant is null or not coalesce(better_supabase.can('tenant', request_data_export.tenant, 'data_lifecycle.export'), false) then
      raise exception 'You may not export this organization''s data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
    end if;
    select * into v_row from "better_supabase"."data_exports" x where x."workspace_id" = request_data_export.tenant and x."subject" = 'organization' and x."status" in ('pending', 'running');
    if v_row."id" is null then
      insert into "better_supabase"."data_exports" ("subject", "workspace_id") values ('organization', request_data_export.tenant) returning * into v_row;
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
    else x."workspace_id" = list_data_exports.tenant
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
  using case when v_row."subject" = 'user' then v_row."user_id"::text else v_row."workspace_id"::text end,
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
create or replace function "better_supabase"."request_workspace_deletion"(tenant uuid, grace interval default '30 days'::interval)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."workspace_deletions";
  v_disabled boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', request_workspace_deletion.tenant, 'data_lifecycle.delete'), false) then
    raise exception 'You may not delete this organization' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if request_workspace_deletion.grace < interval '0' then
    raise exception 'grace must not be negative' using errcode = '22023', hint = 'ORGANIZATION_DELETION_GRACE';
  end if;
  if exists (select 1 from "better_supabase"."workspace_deletions" x where x."workspace_id" = request_workspace_deletion.tenant and x."purged_at" is not null) then
    raise exception 'The organization was already purged' using errcode = 'P0002', hint = 'ORGANIZATION_PURGED';
  end if;
  v_disabled := false;
  insert into "better_supabase"."workspace_deletions" as x ("workspace_id", "requested_by", "purge_after", "previously_disabled")
  values (request_workspace_deletion.tenant, auth.uid(), now() + request_workspace_deletion.grace, coalesce(v_disabled, false))
  on conflict ("workspace_id") do update set
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
create or replace function "better_supabase"."cancel_workspace_deletion"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."workspace_deletions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workspace_deletions" x
  where x."workspace_id" = cancel_workspace_deletion.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."workspace_id" is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."requested_by" = auth.uid(), false) or coalesce(better_supabase.member_can_while_deleting(auth.uid(), cancel_workspace_deletion.tenant, 'data_lifecycle.delete'), false)) then
    raise exception 'You may not cancel this deletion' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  update "better_supabase"."workspace_deletions" x set "cancelled_at" = now()
  where x."workspace_id" = v_row."workspace_id"
  returning * into v_row;
  
  null;
  return to_jsonb(v_row);
end;
$$;

-- The pending deletion, for the organization's members.
create or replace function "better_supabase"."workspace_deletion"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x.*) from "better_supabase"."workspace_deletions" x
  where x."workspace_id" = workspace_deletion.tenant
    and x."cancelled_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (select 1 from "better_supabase"."memberships" mm where mm."workspace_id" = workspace_deletion.tenant and mm."user_id" = auth.uid()))
$$;

create or replace function "better_supabase"."due_workspace_deletions"(max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."purge_after"), '[]'::jsonb)
  from (
    select * from "better_supabase"."workspace_deletions" y
    where y."purge_after" <= now() and y."cancelled_at" is null and y."purged_at" is null
    order by y."purge_after"
    limit greatest(1, least(due_workspace_deletions.max_rows, 1000))
  ) x
$$;

-- Deletes a due organization's rows (service role): the app's
-- on_organization_purge(tenant) hook first, then each purged table, then
-- the organization. Returns { organizationId, deleted: { table: rows } }.
create or replace function "better_supabase"."purge_workspace"(tenant uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."workspace_deletions";
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
  select * into v_row from "better_supabase"."workspace_deletions" x
  where x."workspace_id" = purge_workspace.tenant and x."cancelled_at" is null and x."purged_at" is null
  for update;
  if v_row."workspace_id" is null or v_row."purge_after" > now() then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_holds" x
    where x."released_at" is null
      and (x."workspace_id" is null or x."workspace_id" = purge_workspace.tenant)
  ) then
    raise exception 'A legal hold covers this organization, so it can''t be purged' using errcode = 'P0001', hint = 'ORGANIZATION_LEGAL_HOLD';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."on_organization_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using purge_workspace.tenant;
    end if;
  end;
  -- Tables go in reverse order; a table whose rows another table still
  -- references (a restricting foreign key) waits for a later pass.
  v_pending := array(
    select t.name from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null
      and to_regclass(t.tbl) <> to_regclass('"better_supabase"."workspace_deletions"')
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
          using purge_workspace.tenant::text;
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
  update "better_supabase"."workspace_deletions" x set "purged_at" = now() where x."workspace_id" = v_row."workspace_id" returning * into v_row;
  
  null;
  return jsonb_build_object('organizationId', v_row."workspace_id"::text, 'deleted', v_deleted);
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
revoke execute on function "better_supabase"."request_workspace_deletion"(uuid, interval) from public, anon;
revoke execute on function "better_supabase"."cancel_workspace_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."workspace_deletion"(uuid) from public, anon;
revoke execute on function "better_supabase"."due_workspace_deletions"(integer) from public, anon, authenticated;
revoke execute on function "better_supabase"."purge_workspace"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."data_lifecycle_tables"() to service_role;
grant execute on function "better_supabase"."request_data_export"(text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_data_exports"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."get_data_export"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."claim_data_export"(uuid) to service_role;
grant execute on function "better_supabase"."data_export_rows"(uuid, text, text, integer) to service_role;
grant execute on function "better_supabase"."complete_data_export"(uuid, text[]) to service_role;
grant execute on function "better_supabase"."fail_data_export"(uuid, text) to service_role;
grant execute on function "better_supabase"."request_workspace_deletion"(uuid, interval) to authenticated, service_role;
grant execute on function "better_supabase"."cancel_workspace_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."workspace_deletion"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."due_workspace_deletions"(integer) to service_role;
grant execute on function "better_supabase"."purge_workspace"(uuid) to service_role;

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

-- ==== data supabase/better-supabase-data/900_better_supabase_035_data_lifecycle.sql
-- better-supabase module: data-lifecycle
-- @bsb-block-data data-lifecycle
-- @bsb-hash sha256:f5b3e1b63eb0f0eee30fc84a1ce265c8fa794402a5f303dbb3ab73aa65c4df57
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('data-lifecycle', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
