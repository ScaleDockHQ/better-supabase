-- ==== schema supabase/schemas/900_better_supabase_032_drive.sql
-- better-supabase module: drive
-- @bsb-block drive@1 managed
-- @bsb-hash sha256:1e223f5163a5f315e8ccd34d0fa074c7e2285e463bc85580cf0d6f53aa6a0a1e
-- Folders and files on the attachments module: access granted to users, teams or roles and inherited down the tree, enforced by storage policies too; moves and renames with a name-conflict policy; revisions through versions, a bin through trash, starred and recent items through share-links' user state, and folder share links.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."drive_nodes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."drive_nodes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."drive_nodes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."drive_nodes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."drive_nodes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."drive_grants";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."drive_grants";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."drive_grants";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."drive_grants";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."drive_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."drive_nodes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  
  "parent_id" uuid references "better_supabase"."drive_nodes" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('folder', 'file')),
  "name" text not null check (length(btrim("name")) between 1 and 255 and "name" !~ '[/[:cntrl:]]'),
  "attachment_id" uuid,
  "path" text not null default '',
  "rank" text collate "C" not null default 'V' check ("rank" ~ '^[0-9A-Za-z]*[1-9A-Za-z]$'),
  "deleted_at" timestamptz,
  "source" text not null default 'internal' check ("source" = any (array['internal', 'google-drive', 'onedrive']::text[])),
  "external_id" text,
  "external_metadata" jsonb not null default '{}'::jsonb,
  "legal_hold_until" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("external_id" is null or "source" <> 'internal')
);
alter table "better_supabase"."drive_nodes" add column if not exists "app_note" text;
create unique index if not exists "drive_nodes_sibling_name_idx" on "better_supabase"."drive_nodes" ("tenant_id", coalesce("parent_id", '00000000-0000-0000-0000-000000000000'::uuid), lower("name")) where "deleted_at" is null and "source" = 'internal';
create index if not exists "drive_nodes_parent_idx" on "better_supabase"."drive_nodes" ("tenant_id", "parent_id", "rank");
create index if not exists "drive_nodes_parent_fk_idx" on "better_supabase"."drive_nodes" ("parent_id") where "parent_id" is not null;
create index if not exists "drive_nodes_path_idx" on "better_supabase"."drive_nodes" ("path" text_pattern_ops);
create index if not exists "drive_nodes_attachment_idx" on "better_supabase"."drive_nodes" ("attachment_id");
create unique index if not exists "drive_nodes_external_idx" on "better_supabase"."drive_nodes" ("tenant_id", "source", "external_id") where "external_id" is not null and "deleted_at" is null;
alter table "better_supabase"."drive_nodes" enable row level security;
revoke all on "better_supabase"."drive_nodes" from public, anon, authenticated;
grant select on "better_supabase"."drive_nodes" to authenticated;
grant all on "better_supabase"."drive_nodes" to service_role;
create table if not exists "better_supabase"."drive_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "node_id" uuid not null references "better_supabase"."drive_nodes" ("id") on delete cascade,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null,
  "role" text not null,
  "expires_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("node_id", "principal_type", "principal_id")
);
create index if not exists "drive_grants_principal_idx" on "better_supabase"."drive_grants" ("principal_type", "principal_id");
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."drive_grants"'::regclass and c.conname = 'bsb_drive_grants_role'
  ), 'pg_constraint'), '') <> 'better-supabase check d20245e0' then
    alter table "better_supabase"."drive_grants" drop constraint if exists "bsb_drive_grants_role";
    alter table "better_supabase"."drive_grants" add constraint "bsb_drive_grants_role" check ("role" = any (array['viewer', 'editor', 'owner']::text[]));
    comment on constraint "bsb_drive_grants_role" on "better_supabase"."drive_grants" is 'better-supabase check d20245e0';
  end if;
end;
$$;
alter table "better_supabase"."drive_grants" enable row level security;
revoke all on "better_supabase"."drive_grants" from public, anon, authenticated;
grant all on "better_supabase"."drive_grants" to service_role;

-- The node's ancestors and itself, root first.
create or replace function "better_supabase"."drive_ancestors"(node uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select string_to_array(btrim(x."path", '/'), '/')::uuid[] from "better_supabase"."drive_nodes" x where x."id" = drive_ancestors.node
$$;
revoke execute on function "better_supabase"."drive_ancestors"(uuid) from public, anon, authenticated;

-- The node and everything under it, with depth 0 for the node.
create or replace function "better_supabase"."drive_subtree"(node uuid)
returns table (node_id uuid, depth integer)
language sql
stable
security definer
set search_path = ''
as $$
  select x."id", (length(x."path") - length(replace(x."path", '/', ''))) - (length(r."path") - length(replace(r."path", '/', '')))
  from "better_supabase"."drive_nodes" r join "better_supabase"."drive_nodes" x on x."path" like r."path" || '%'
  where r."id" = drive_subtree.node
$$;
revoke execute on function "better_supabase"."drive_subtree"(uuid) from public, anon, authenticated;

-- Whether the node, a folder above it or anything under it is under a legal
-- hold, which purge has to respect.
create or replace function "better_supabase"."drive_node_held"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."drive_nodes" h
    where (h."id" in (select s.node_id from "better_supabase"."drive_subtree"(drive_node_held.node) s)
        or h."id" = any ("better_supabase"."drive_ancestors"(drive_node_held.node)))
      and h."legal_hold_until" is not null and h."legal_hold_until" > now()
  )
$$;
revoke execute on function "better_supabase"."drive_node_held"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_node_held"(uuid) to authenticated, service_role;


-- The caller's role on a node: the highest of the grants on it and its ancestors that name them, one of their teams or their organization role. drive.manage is owner everywhere. Grants
-- need drive.read in the node's organization too.
create or replace function "better_supabase"."drive_role"(node uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  
  v_rank integer;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return 'owner';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."drive_nodes" x where x."id" = drive_role.node;
  if v_tenant is null or v_uid is null or not coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) then
    return null;
  end if;
  if coalesce(better_supabase.can('tenant', v_tenant, 'drive.manage'), false) then
    return 'owner';
  end if;
  
  select greatest(coalesce(v_rank, 0), coalesce(max(coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"), 0)), 0)) into v_rank from "better_supabase"."drive_grants" dg
  where dg."node_id" = any ("better_supabase"."drive_ancestors"(drive_role.node)) and (dg."expires_at" is null or dg."expires_at" > now())
    and ((dg."principal_type" = 'user' and dg."principal_id" = v_uid::text)
      or (dg."principal_type" = 'team' and false)
      or (dg."principal_type" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = v_uid and mr."role"::text = dg."principal_id" and mr."disabled_at" is null)));
  
  if coalesce(v_rank, 0) = 0 then
    return null;
  end if;
  return (array['viewer', 'editor', 'owner']::text[])[v_rank];
end;
$$;
revoke execute on function "better_supabase"."drive_role"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_role"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."drive_can"(node uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(coalesce(array_position(array['viewer', 'editor', 'owner']::text[], "better_supabase"."drive_role"(drive_can.node)), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_can.role), 0) and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_can.role), 0) > 0, false)
$$;
revoke execute on function "better_supabase"."drive_can"(uuid, text) from public, anon;
grant execute on function "better_supabase"."drive_can"(uuid, text) to authenticated, service_role;

-- Whether the caller may change the node: the write role, and not a read-only
-- mirror of an external account.
create or replace function "better_supabase"."drive_node_writable"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select "better_supabase"."drive_can"(x."id", 'editor') and not (coalesce(x."source", 'internal') <> 'internal' or false)
    from "better_supabase"."drive_nodes" x where x."id" = drive_node_writable.node
  ), false)
$$;
revoke execute on function "better_supabase"."drive_node_writable"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_node_writable"(uuid) to authenticated, service_role;

-- The nodes drive_can(node, 'viewer') is true for, as one set, so the read policy
-- runs it once per statement instead of once per row: every node in an organization
-- the caller manages, and the subtree of each grant that names them.
create or replace function "better_supabase"."drive_readable_ids"()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x."id" from "better_supabase"."drive_nodes" x
  where coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or (auth.uid() is not null
      and x."tenant_id" in (select better_supabase.tenant_ids_with('drive.read'))
      and (x."tenant_id" in (select better_supabase.tenant_ids_with('drive.manage'))))
  union
  select s.node_id from "better_supabase"."drive_grants" dg
  cross join lateral "better_supabase"."drive_subtree"(dg."node_id") s
  join "better_supabase"."drive_nodes" x on x."id" = s.node_id
  where auth.uid() is not null and (dg."expires_at" is null or dg."expires_at" > now())
    and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'viewer'), 0)
    and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'viewer'), 0) > 0
    and x."tenant_id" in (select better_supabase.tenant_ids_with('drive.read'))
    and ((dg."principal_type" = 'user' and dg."principal_id" = auth.uid()::text)
      or (dg."principal_type" = 'team' and false)
      or (dg."principal_type" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = dg."principal_id" and mr."disabled_at" is null)))
$$;
revoke execute on function "better_supabase"."drive_readable_ids"() from public, anon;
grant execute on function "better_supabase"."drive_readable_ids"() to authenticated, service_role;

create or replace function "better_supabase"."drive_node_json"(node "better_supabase"."drive_nodes")
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."tenant_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', ($1)."rank", 'source', ($1)."source", 'externalId', ($1)."external_id", 'externalMetadata', ($1)."external_metadata", 'legalHoldUntil', ($1)."legal_hold_until", 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', ($1)."deleted_at", 'fields', jsonb_build_object('app_note', ($1)."app_note"))
$$;
revoke execute on function "better_supabase"."drive_node_json"("better_supabase"."drive_nodes") from public, anon, authenticated;

drop policy if exists drive_nodes_read on "better_supabase"."drive_nodes";
create policy drive_nodes_read on "better_supabase"."drive_nodes"
  for select to authenticated
  using ("deleted_at" is null and "id" in (select "better_supabase"."drive_readable_ids"()));

-- Keeps path, the ids from the root to the node, in step with parent, so
-- any writer (a function, the service role, a migration) stays consistent.
create or replace function "better_supabase"."drive_node_path"()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_path text;
  v_parent_tenant text;
  v_parent_kind text;
begin
  if new."parent_id" is null then
    new."path" := '/' || new."id"::text || '/';
    return new;
  end if;
  select x."path", x."tenant_id"::text, x."kind" into v_parent_path, v_parent_tenant, v_parent_kind
  from "better_supabase"."drive_nodes" x where x."id" = new."parent_id";
  if v_parent_path is null or v_parent_tenant is distinct from new."tenant_id"::text then
    raise exception 'the parent folder does not exist in this organization' using errcode = '23503', hint = 'DRIVE_PARENT_NOT_FOUND';
  end if;
  if v_parent_kind <> 'folder' then
    raise exception 'a file can''t hold other items' using errcode = '22023', hint = 'DRIVE_PARENT_NOT_FOLDER';
  end if;
  if v_parent_path like '%/' || new."id"::text || '/%' then
    raise exception 'a folder can''t move into itself or its own subfolder' using errcode = '22023', hint = 'DRIVE_MOVE_CYCLE';
  end if;
  new."path" := v_parent_path || new."id"::text || '/';
  return new;
end;
$$;
drop trigger if exists "bsb_drive_node_path" on "better_supabase"."drive_nodes";
create trigger "bsb_drive_node_path"
  before insert or update of "parent_id" on "better_supabase"."drive_nodes"
  for each row execute function "better_supabase"."drive_node_path"();

create or replace function "better_supabase"."drive_node_moved"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update "better_supabase"."drive_nodes" x set "path" = new."path" || substr(x."path", length(old."path") + 1)
  where x."path" like old."path" || '_%';
  return null;
end;
$$;
drop trigger if exists "bsb_drive_node_moved" on "better_supabase"."drive_nodes";
create trigger "bsb_drive_node_moved"
  after update of "parent_id" on "better_supabase"."drive_nodes"
  for each row when (old."parent_id" is distinct from new."parent_id")
  execute function "better_supabase"."drive_node_moved"();

create or replace function "better_supabase"."drive_clean_name"(name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text := btrim(drive_clean_name.name);
begin
  if v_name is null or v_name = '' or length(v_name) > 255 or v_name ~ '[/[:cntrl:]]' or v_name in ('.', '..') then
    raise exception 'a name needs 1 to 255 characters without / or control characters' using errcode = '22023', hint = 'DRIVE_NAME_INVALID';
  end if;
  return v_name;
end;
$$;
revoke execute on function "better_supabase"."drive_clean_name"(text) from public, anon, authenticated;

create or replace function "better_supabase"."drive_conflict"(conflict text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if coalesce(drive_conflict.conflict, 'fail') not in ('fail', 'rename', 'replace') then
    raise exception 'conflict must be fail, rename, replace' using errcode = '22023', hint = 'DRIVE_CONFLICT_INVALID';
  end if;
  return coalesce(drive_conflict.conflict, 'fail');
end;
$$;
revoke execute on function "better_supabase"."drive_conflict"(text) from public, anon, authenticated;

-- Serializes name checks in one folder.
create or replace function "better_supabase"."drive_lock_siblings"(tenant uuid, drive uuid, parent uuid)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('better-supabase:drive:' || coalesce(drive_lock_siblings.parent::text, drive_lock_siblings.tenant::text) || ':' || coalesce(drive_lock_siblings.drive::text, ''), 0))
$$;
revoke execute on function "better_supabase"."drive_lock_siblings"(uuid, uuid, uuid) from public, anon, authenticated;

-- name when no other live item in the folder has it (case-insensitively);
-- with conflict 'rename' the first free "name (2).ext"; otherwise
-- DRIVE_NAME_CONFLICT.
create or replace function "better_supabase"."drive_free_name"(tenant uuid, drive uuid, parent uuid, name text, exclude uuid, conflict text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ext text;
  v_base text;
  v_try text := drive_free_name.name;
  v_n integer := 1;
begin
  perform "better_supabase"."drive_lock_siblings"(drive_free_name.tenant, drive_free_name.drive, drive_free_name.parent);
  loop
    exit when not exists (
      select 1 from "better_supabase"."drive_nodes" x
      where x."tenant_id" = drive_free_name.tenant and x."parent_id" is not distinct from drive_free_name.parent and x."deleted_at" is null
        and lower(x."name") = lower(v_try) and x."id" is distinct from drive_free_name.exclude
    );
    if drive_free_name.conflict <> 'rename' then
      raise exception 'another item in this folder has this name' using errcode = '23505', hint = 'DRIVE_NAME_CONFLICT';
    end if;
    if v_n = 1 then
      v_ext := coalesce(substring(drive_free_name.name from '.(\.[^.]+)$'), '');
      v_base := left(drive_free_name.name, length(drive_free_name.name) - length(v_ext));
    end if;
    v_n := v_n + 1;
    v_try := v_base || ' (' || v_n::text || ')' || v_ext;
  end loop;
  return v_try;
end;
$$;
revoke execute on function "better_supabase"."drive_free_name"(uuid, uuid, uuid, text, uuid, text) from public, anon, authenticated;

-- Whether the caller may create an item in parent: drive.create and the
-- drive's write role at the root, the write role in a folder. External
-- mirrors are read-only.
create or replace function "better_supabase"."drive_check_parent"(tenant uuid, parent uuid, drive uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_parent "better_supabase"."drive_nodes"%rowtype;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return;
  end if;
  if drive_check_parent.parent is null then
    if not coalesce(better_supabase.can('tenant', drive_check_parent.tenant, 'drive.create'), false) then
      raise exception 'not allowed to create items in this drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
    return;
  end if;
  select * into v_parent from "better_supabase"."drive_nodes" x
  where x."id" = drive_check_parent.parent and x."tenant_id" = drive_check_parent.tenant and x."deleted_at" is null;
  if not found or not "better_supabase"."drive_can"(v_parent."id", 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not "better_supabase"."drive_can"(v_parent."id", 'editor') then
    raise exception 'not allowed to add items to this folder' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_parent."kind" <> 'folder' then
    raise exception 'a file can''t hold other items' using errcode = '22023', hint = 'DRIVE_PARENT_NOT_FOLDER';
  end if;
  if (coalesce(v_parent."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
end;
$$;
revoke execute on function "better_supabase"."drive_check_parent"(uuid, uuid, uuid) from public, anon, authenticated;

-- It returns the node table's row type, which differs between managed and
-- adopted tables.
drop function if exists "better_supabase"."drive_insert_node"(uuid, uuid, uuid, text, text, text, jsonb);
drop function if exists "better_supabase"."drive_insert_node"(uuid, uuid, text, text, text, jsonb);
-- Inserts a node after its siblings. Extra columns come from fields, or
-- from the parent. At the root, the creator gets owner.
create or replace function "better_supabase"."drive_insert_node"(tenant uuid, drive uuid, parent uuid, kind text, name text, conflict text, fields jsonb)
returns "better_supabase"."drive_nodes"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_parent "better_supabase"."drive_nodes"%rowtype;
  v_fields "better_supabase"."drive_nodes"%rowtype;
  v_drive uuid := drive_insert_node.drive;
  v_name text;
  v_last text;
begin
  select * into v_parent from "better_supabase"."drive_nodes" x where x."id" = drive_insert_node.parent;
  v_name := "better_supabase"."drive_free_name"(drive_insert_node.tenant, v_drive, drive_insert_node.parent, drive_insert_node.name, null, drive_insert_node.conflict);
  v_fields := jsonb_populate_record(null::"better_supabase"."drive_nodes", coalesce(drive_insert_node.fields, '{}'::jsonb));
  select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
  where x."tenant_id" = drive_insert_node.tenant and x."parent_id" is not distinct from drive_insert_node.parent and x."deleted_at" is null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_create"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name;
    end if;
  end;
  insert into "better_supabase"."drive_nodes" ("tenant_id", "parent_id", "kind", "name", "rank", "source", "created_by", "app_note")
  values (drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end, 'internal', auth.uid(), coalesce(v_fields."app_note", v_parent."app_note"))
  returning * into v_node;
  if drive_insert_node.parent is null and auth.uid() is not null then
    insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, 'owner')
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role";
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return v_node;
end;
$$;
revoke execute on function "better_supabase"."drive_insert_node"(uuid, uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."drive_create_folder"(tenant uuid, parent uuid, name text, conflict text default null, fields jsonb default null, drive uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := "better_supabase"."drive_clean_name"(drive_create_folder.name);
  v_conflict text := "better_supabase"."drive_conflict"(drive_create_folder.conflict);
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  perform "better_supabase"."drive_check_parent"(drive_create_folder.tenant, drive_create_folder.parent, drive_create_folder.drive);
  v_node := "better_supabase"."drive_insert_node"(drive_create_folder.tenant, drive_create_folder.drive, drive_create_folder.parent, 'folder', v_name,
    case when v_conflict = 'replace' then 'fail' else v_conflict end, drive_create_folder.fields);
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_create_folder"(uuid, uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."drive_create_folder"(uuid, uuid, text, text, jsonb, uuid) to authenticated, service_role;
create or replace function "better_supabase"."drive_get"(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_get.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_get"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_get"(uuid) to authenticated, service_role;

-- A folder's children, folders first, then in rank order. Without parent, the
-- root items of drive, or of every drive the caller can read.
create or replace function "better_supabase"."drive_list"(tenant uuid, parent uuid default null, page_size integer default 100, skip integer default 0, drive uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_list.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_list.parent is not null and not exists (
    select 1 from "better_supabase"."drive_nodes" p where p."id" = drive_list.parent and p."tenant_id" = drive_list.tenant and p."deleted_at" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(p."id", 'viewer'))
  ) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"))) order by ((c.r)."kind" = 'folder') desc, (c.r)."rank", lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
    from (
      select x as r from "better_supabase"."drive_nodes" x
      where x."tenant_id" = drive_list.tenant and x."parent_id" is not distinct from drive_list.parent and x."deleted_at" is null
        and (drive_list.parent is not null or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
      order by (x."kind" = 'folder') desc, x."rank", lower(x."name"), x."id"
      limit least(greatest(coalesce(drive_list.page_size, 100), 1), 500)
      offset greatest(coalesce(drive_list.skip, 0), 0)
    ) c
  );
end;
$$;
revoke execute on function "better_supabase"."drive_list"(uuid, uuid, integer, integer, uuid) from public, anon;
grant execute on function "better_supabase"."drive_list"(uuid, uuid, integer, integer, uuid) to authenticated, service_role;

-- Items shared with the caller directly, whose folder they can't open.
create or replace function "better_supabase"."drive_shared"(tenant uuid, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
  select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"))) order by (c.r)."name", (c.r)."id"), '[]'::jsonb)
  from (
    select x as r from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_shared.tenant and x."deleted_at" is null
      and auth.uid() is not null
      and exists (
        select 1 from "better_supabase"."drive_grants" dg
        where dg."node_id" = x."id" and (dg."expires_at" is null or dg."expires_at" > now())
          and ((dg."principal_type" = 'user' and dg."principal_id" = auth.uid()::text)
      or (dg."principal_type" = 'team' and false)
      or (dg."principal_type" = 'role' and exists (select 1 from "better_supabase"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = dg."principal_id" and mr."disabled_at" is null)))
      )
      and (x."parent_id" is null or not "better_supabase"."drive_can"(x."parent_id", 'viewer'))
      and "better_supabase"."drive_can"(x."id", 'viewer')
    order by x."name", x."id"
    limit least(greatest(coalesce(drive_shared.page_size, 100), 1), 500)
  ) c
  );
end;
$$;
revoke execute on function "better_supabase"."drive_shared"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."drive_shared"(uuid, integer) to authenticated, service_role;

-- The breadcrumb: the node's ancestors the caller can open, root first.
create or replace function "better_supabase"."drive_path"(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(drive_path.node, 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'name', x."name", 'kind', x."kind") order by p.ord), '[]'::jsonb)
    from unnest("better_supabase"."drive_ancestors"(drive_path.node)) with ordinality p (id, ord)
    join "better_supabase"."drive_nodes" x on x."id" = p.id
    where coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer')
  );
end;
$$;
revoke execute on function "better_supabase"."drive_path"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_path"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."drive_rename"(node uuid, name text, conflict text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous text;
  v_name text := "better_supabase"."drive_clean_name"(drive_rename.name);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_rename.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to rename this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if v_name = v_node."name" then
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", null, v_node."parent_id", v_name, v_node."id",
    case when "better_supabase"."drive_conflict"(drive_rename.conflict) = 'rename' then 'rename' else 'fail' end);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_rename"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_node."id", v_name;
    end if;
  end;
  v_previous := v_node."name";
  update "better_supabase"."drive_nodes" x set "name" = v_name, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_rename"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_rename"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."drive_rename"(uuid, text, text) to authenticated, service_role;

-- Moves a node into parent (null for the root) at rank, after the last
-- item by default. Moving to the root needs the share role and
-- drive.create, and keeps the mover's role as a grant.
create or replace function "better_supabase"."drive_move"(node uuid, parent uuid, rank text default null, conflict text default null, drive uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous uuid;
  v_target uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_move.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if drive_move.rank is not null and drive_move.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a key from rankBetween' using errcode = '22023', hint = 'DRIVE_RANK_INVALID';
  end if;
  v_previous := v_node."parent_id";
  if drive_move.parent is null then
    if v_previous is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(better_supabase.can('tenant', v_node."tenant_id", 'drive.create'), false))) then
      raise exception 'not allowed to move this item to the top of the drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
  else
    perform "better_supabase"."drive_check_parent"(v_node."tenant_id", drive_move.parent, drive_move.drive);
    if v_node."id" = any ("better_supabase"."drive_ancestors"(drive_move.parent)) then
      raise exception 'a folder can''t move into itself or its own subfolder' using errcode = '22023', hint = 'DRIVE_MOVE_CYCLE';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_move"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", drive_move.parent;
    end if;
  end;
  if v_previous is distinct from drive_move.parent then
    v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", v_target, drive_move.parent, v_node."name", v_node."id",
      case when "better_supabase"."drive_conflict"(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := "better_supabase"."drive_role"(v_node."id");
      insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, v_role)
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role";
    end if;
    if drive_move.rank is null then
      select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
      where x."tenant_id" = v_node."tenant_id" and x."parent_id" is not distinct from drive_move.parent and x."deleted_at" is null;
    end if;
    update "better_supabase"."drive_nodes" x set "parent_id" = drive_move.parent, "name" = v_name, "rank" = coalesce(drive_move.rank, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    null;
  elsif drive_move.rank is not null then
    update "better_supabase"."drive_nodes" x set "rank" = drive_move.rank, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_move"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_move"(uuid, uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."drive_move"(uuid, uuid, text, text, uuid) to authenticated, service_role;

-- Deletes a node and everything under it for good (the share role).
create or replace function "better_supabase"."drive_delete"(node uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_delete.node;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to delete this item for good' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  delete from "better_supabase"."drive_nodes" x where x."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s);
  return true;
end;
$$;
revoke execute on function "better_supabase"."drive_delete"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_delete"(uuid) to authenticated, service_role;


-- Grants role on a node (and what is under it) to a user, a team or an
-- organization role. Needs the share role, and no more than the caller's.
create or replace function "better_supabase"."drive_share"(node uuid, principal_type text, principal_id text, role text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_type text := lower(drive_share.principal_type);
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_share.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role), 0) <= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], "better_supabase"."drive_role"(v_node."id")), 0))) then
    raise exception 'not allowed to share this item with that role' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role), 0) = 0 then
    raise exception 'role must be one of viewer, editor, owner' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if v_type not in ('user', 'team', 'role') or drive_share.principal_id is null then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'DRIVE_PRINCIPAL_INVALID';
  end if;
  if (v_type = 'user' and (drive_share.principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or not exists (
      select 1 from "better_supabase"."memberships" mu
      where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_share.principal_id::uuid and mu."disabled_at" is null
    )))
    or (v_type = 'team' and not false) then
    raise exception 'no member or team of this organization has that id' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_share"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using v_node."id", v_type, drive_share.principal_id, drive_share.role;
    end if;
  end;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = v_type and dg."principal_id" = drive_share.principal_id;
  insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role", "expires_at", "created_by")
  values (v_node."tenant_id", v_node."id", v_type, drive_share.principal_id, drive_share.role, drive_share.expires_at, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_share"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'nodeId', v_node."id", 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role, 'expiresAt', drive_share.expires_at, 'inherited', false);
end;
$$;
revoke execute on function "better_supabase"."drive_share"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."drive_share"(uuid, text, text, text, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."drive_unshare"(node uuid, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_type text := lower(drive_unshare.principal_type);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unshare.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to change who this item is shared with' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id"
    and dg."principal_type" = v_type and dg."principal_id" = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drive_unshare"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."drive_unshare"(uuid, text, text) to authenticated, service_role;

-- Who has access: the grants on the node and, marked inherited, on its
-- ancestors.
create or replace function "better_supabase"."drive_grants"(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(drive_grants.node, 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', dg."id", 'nodeId', dg."node_id", 'principalType', dg."principal_type", 'principalId', dg."principal_id", 'role', dg."role", 'expiresAt', dg."expires_at", 'inherited', dg."node_id" <> drive_grants.node) order by dg."node_id" = drive_grants.node, coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"), 0) desc, dg."id"), '[]'::jsonb)
    from "better_supabase"."drive_grants" dg
    where dg."node_id" = any ("better_supabase"."drive_ancestors"(drive_grants.node)) and (dg."expires_at" is null or dg."expires_at" > now())
  );
end;
$$;
revoke execute on function "better_supabase"."drive_grants"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_grants"(uuid) to authenticated, service_role;


-- Places a legal hold on a node and everything under it: purge skips held
-- nodes until the hold ends or is released.
create or replace function "better_supabase"."drive_hold"(node uuid, until timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_hold.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to place a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if drive_hold.until is null or drive_hold.until <= now() then
    raise exception 'a legal hold needs an end in the future' using errcode = '22023', hint = 'DRIVE_HOLD_INVALID';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_until" = drive_hold.until, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  null;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_hold"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."drive_hold"(uuid, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."drive_release_hold"(node uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_release_hold.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to release a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source", 'internal') <> 'internal' or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_until" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  null;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source", 'internal') <> 'internal' or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_release_hold"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_release_hold"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."drive_nodes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."drive_nodes";
create policy bsb_tenant_scope_select on "better_supabase"."drive_nodes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("deleted_at" is null and "id" in (select "better_supabase"."drive_readable_ids"()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."drive_nodes";
create policy bsb_tenant_scope_insert on "better_supabase"."drive_nodes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."drive_nodes";
create policy bsb_tenant_scope_update on "better_supabase"."drive_nodes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."drive_nodes";
create policy bsb_tenant_scope_delete on "better_supabase"."drive_nodes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_032_drive.sql
-- better-supabase module: drive
-- @bsb-block-data drive
-- @bsb-hash sha256:da363416284271105f5b8aca2cba8f5f804764f6211202b435b16becfca2d334
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('drive', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
