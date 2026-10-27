-- ==== schema supabase/schemas/900_better_supabase_075_trash.sql
-- better-supabase module: trash
-- @bsb-block trash@3 managed
-- @bsb-hash sha256:07c5ff3ba818b93541239b83b56c57110bdba58891507a680003c5897502fe55
-- Soft delete through each subject's deletedAt column: trash with children in one batch, restore with unique checks, a list per organization, and purge after a retention period, skipped for subjects under a legal hold.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."trash_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."trash_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."trash_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."trash_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."trash_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."trash_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "title" text,
  "batch_id" uuid not null,
  "depth" integer not null default 0 check ("depth" >= 0),
  "trashed_by" uuid,
  "trashed_at" timestamptz not null default now(),
  "purge_after" timestamptz,
  unique ("subject_type", "subject_id")
);
create index if not exists "trash_items_tenant_idx" on "better_supabase"."trash_items" ("tenant_id", "trashed_at" desc);
create index if not exists "trash_items_batch_idx" on "better_supabase"."trash_items" ("batch_id");
alter table "better_supabase"."trash_items" enable row level security;
revoke all on "better_supabase"."trash_items" from public, anon, authenticated;
grant select on "better_supabase"."trash_items" to authenticated;
grant all on "better_supabase"."trash_items" to service_role;
drop policy if exists trash_items_read on "better_supabase"."trash_items";
create policy trash_items_read on "better_supabase"."trash_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('trash.read')));

-- Marks one subject row trashed, records it, then trashes the rows the
-- subject's children options point at, in the same batch.
create or replace function "better_supabase"."trash_cascade"(tenant uuid, subject_type text, subject_id text, batch uuid, depth integer, actor uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_count integer := 1;
  v_child text;
  v_item "better_supabase"."trash_items"%rowtype;
begin
  raise exception 'this subject type has no deletedAt column' using errcode = '22023', hint = 'TRASH_UNSUPPORTED';
  delete from "better_supabase"."trash_items" i
    where i."subject_type" = trash_cascade.subject_type and i."subject_id" = trash_cascade.subject_id;
  insert into "better_supabase"."trash_items" ("tenant_id", "subject_type", "subject_id", "title", "batch_id", "depth", "trashed_by", "trashed_at", "purge_after")
  values (trash_cascade.tenant, trash_cascade.subject_type, trash_cascade.subject_id, v_title, trash_cascade.batch, trash_cascade.depth, trash_cascade.actor, now(), now() + make_interval(days => 30))
  returning * into v_item;
  null;
  
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."trash_cascade"(uuid, text, text, uuid, integer, uuid) from public, anon, authenticated;

-- fields: the extra columns (blocks.trash.options.extraColumns) of the
-- subject's trash item.
drop function if exists "better_supabase"."trash"(uuid, text, text, jsonb);
create or replace function "better_supabase"."trash"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_count integer;
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', trash.tenant, 'trash.create'), false) and true and true)) then
    raise exception 'not allowed to trash this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_trash"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using trash.tenant, trash.subject_type, trash.subject_id;
    end if;
  end;
  v_count := "better_supabase"."trash_cascade"(trash.tenant, trash.subject_type, trash.subject_id, v_batch, 0, auth.uid());
  if v_count = 0 then
    raise exception 'no live record to trash' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  select i."id" into v_id from "better_supabase"."trash_items" i
    where i."subject_type" = trash.subject_type and i."subject_id" = trash.subject_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_trash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, v_batch;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$$;
revoke execute on function "better_supabase"."trash"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."trash"(uuid, text, text) to authenticated, service_role;

-- Restores every row of a batch, after checking the unique columns. The
-- caller deletes the batch's items, so the read-only guard sees its write.
create or replace function "better_supabase"."trash_restore_batch"(batch uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_restore_batch.batch order by "depth" loop
    null;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."trash_restore_batch"(uuid) from public, anon, authenticated;

create or replace function "better_supabase"."restore_trash"(item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_root "better_supabase"."trash_items"%rowtype;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r.* into v_root from "better_supabase"."trash_items" i
    join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
    where i."id" = restore_trash.item_id;
  if not found then
    raise exception 'trash item not found' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_root."tenant_id", 'trash.restore'), false) and true)) then
    raise exception 'not allowed to restore this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_untrash"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_root."id";
    end if;
  end;
  v_count := "better_supabase"."trash_restore_batch"(v_root."batch_id");
  delete from "better_supabase"."trash_items" where "batch_id" = v_root."batch_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_untrash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_root."id", v_root."batch_id";
    end if;
  end;
  return jsonb_build_object('id', v_root."id", 'batchId', v_root."batch_id", 'subjectType', v_root."subject_type", 'subjectId', v_root."subject_id", 'count', v_count);
end;
$$;
revoke execute on function "better_supabase"."restore_trash"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_trash"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_trash"(tenant uuid, subject_type text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_trash.tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'subjectType', t."subject_type", 'subjectId', t."subject_id", 'title', t."title", 'batchId', t."batch_id", 'count', t.n, 'trashedBy', t."trashed_by", 'trashedAt', t."trashed_at", 'purgeAfter', t."purge_after") order by t."trashed_at" desc, t."id"), '[]'::jsonb)
    into v_rows
  from (
    select x.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = x."batch_id")::integer as n
    from "better_supabase"."trash_items" x
    where x."tenant_id" = list_trash.tenant
      and x."depth" = 0
      and (list_trash.subject_type is null or x."subject_type" = list_trash.subject_type)
      and (list_trash.before is null or x."trashed_at" < list_trash.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true)
    order by x."trashed_at" desc, x."id"
    limit least(greatest(coalesce(list_trash.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_trash"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_trash"(uuid, text, integer, timestamptz) to authenticated, service_role;

-- Deletes a batch's rows for good, children first.
create or replace function "better_supabase"."trash_purge_batch"(batch uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_purge_batch.batch order by "depth" desc loop
    if (false) then
      raise exception 'a record in this batch is under a legal hold' using errcode = '42501', hint = 'TRASH_HELD';
    end if;
    null;
    null;
    v_count := v_count + 1;
  end loop;
  delete from "better_supabase"."trash_items" where "batch_id" = trash_purge_batch.batch;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."trash_purge_batch"(uuid) from public, anon, authenticated;

create or replace function "better_supabase"."purge_trash"(item_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_batch uuid;
begin
  select "tenant_id", "batch_id" into v_tenant, v_batch from "better_supabase"."trash_items" where "id" = purge_trash.item_id;
  if v_batch is null then
    raise exception 'trash item not found' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'trash.manage'), false)) then
    raise exception 'not allowed to empty the trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  return "better_supabase"."trash_purge_batch"(v_batch);
end;
$$;
revoke execute on function "better_supabase"."purge_trash"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_trash"(uuid) to authenticated, service_role;

-- Purges batches past their retention. Run it nightly, e.g. from pg_cron:
--   select cron.schedule('purge-trash', '15 3 * * *', 'select "better_supabase"."purge_expired_trash"()');
create or replace function "better_supabase"."purge_expired_trash"(max_batches integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch uuid;
  v_count integer := 0;
begin
  for v_batch in
    select t."batch_id" from "better_supabase"."trash_items" t
    where t."depth" = 0 and t."purge_after" <= now()
      and not false
    order by t."purge_after"
    limit greatest(coalesce(purge_expired_trash.max_batches, 100), 1)
  loop
    v_count := v_count + "better_supabase"."trash_purge_batch"(v_batch);
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_expired_trash"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_expired_trash"(integer) to service_role;

-- For policies: `using (not "better_supabase"."is_trashed"('doc', id::text))` hides
-- trashed rows where the table's own deletedAt column isn't checked.
create or replace function "better_supabase"."is_trashed"(subject_type text, subject_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."trash_items"
    where "subject_type" = is_trashed.subject_type and "subject_id" = is_trashed.subject_id
  )
$$;
revoke execute on function "better_supabase"."is_trashed"(text, text) from public, anon;
grant execute on function "better_supabase"."is_trashed"(text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."trash_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."trash_items";
create policy bsb_tenant_scope_select on "better_supabase"."trash_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('trash.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."trash_items";
create policy bsb_tenant_scope_insert on "better_supabase"."trash_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."trash_items";
create policy bsb_tenant_scope_update on "better_supabase"."trash_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."trash_items";
create policy bsb_tenant_scope_delete on "better_supabase"."trash_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_075_trash.sql
-- better-supabase module: trash
-- @bsb-block-data trash
-- @bsb-hash sha256:24d0f2ecaf819874fb898f6b205c5f6c365b78955412bee3ada0390cce9376c4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('trash', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
