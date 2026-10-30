-- better-supabase module: drive
-- @bsb-block drive@2 managed
-- @bsb-hash sha256:9f83d85dc47d543139ac9934ecdf5431481abfcdac06227dac018eaa29b65f6b
-- Folders and files on the attachments module: access granted to users, teams or roles and inherited down the tree, enforced by storage policies too; moves and renames with a name-conflict policy; revisions through versions, a bin through trash, starred and recent items through share-links' user state, and folder share links.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "centrakit"."file_node";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."file_node";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."file_node";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."file_node";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."file_node";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "centrakit"."file_node_grant";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."file_node_grant";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."file_node_grant";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."file_node_grant";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."file_node_grant";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- The node's ancestors and itself, root first.
create or replace function "better_supabase"."drive_ancestors"(node uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with recursive up (id, parent, depth) as (
    select x."id", x."parent_id", 0 from "centrakit"."file_node" x where x."id" = drive_ancestors.node
    union all
    select x."id", x."parent_id", up.depth + 1 from "centrakit"."file_node" x join up on x."id" = up.parent where up.depth < 256
  )
  select array_agg(up.id order by up.depth desc) from up
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
  with recursive down (id, depth) as (
    select x."id", 0 from "centrakit"."file_node" x where x."id" = drive_subtree.node
    union all
    select x."id", down.depth + 1 from "centrakit"."file_node" x join down on x."parent_id" = down.id where down.depth < 256
  )
  select down.id, down.depth from down
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
    select 1 from "centrakit"."file_node" h
    where (h."id" in (select s.node_id from "better_supabase"."drive_subtree"(drive_node_held.node) s)
        or h."id" = any ("better_supabase"."drive_ancestors"(drive_node_held.node)))
      and false
  )
$$;
revoke execute on function "better_supabase"."drive_node_held"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_node_held"(uuid) to authenticated, service_role;


-- The caller's role on a node: the highest of the grants on it and its ancestors that name them, one of their teams or their organization role. drive.manage is editor everywhere. Grants
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
    return 'editor';
  end if;
  select x."organization_id" into v_tenant from "centrakit"."file_node" x where x."id" = drive_role.node;
  if v_tenant is null or v_uid is null or not coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) then
    return null;
  end if;
  if coalesce(better_supabase.can('tenant', v_tenant, 'drive.manage'), false) then
    return 'editor';
  end if;
  
  select greatest(coalesce(v_rank, 0), coalesce(max(coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], dg."role"::text), 0)), 0)) into v_rank from "centrakit"."file_node_grant" dg
  where dg."file_node_id" = any ("better_supabase"."drive_ancestors"(drive_role.node))
    and (dg."user_id" = v_uid or (dg."team_id" is not null and exists (select 1 from "centrakit"."team_members" tm where tm."team_id"::text = dg."team_id"::text and tm."user_id" = v_uid)));
  
  if coalesce(v_rank, 0) = 0 then
    return null;
  end if;
  return (array['viewer', 'commenter', 'editor']::text[])[v_rank];
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
  select coalesce(coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], "better_supabase"."drive_role"(drive_can.node)::text), 0) >= coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], drive_can.role::text), 0) and coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], drive_can.role::text), 0) > 0, false)
$$;
revoke execute on function "better_supabase"."drive_can"(uuid, text) from public, anon;
grant execute on function "better_supabase"."drive_can"(uuid, text) to authenticated, service_role;

-- Whether the caller may read the node: the read role on it, so a check
-- function in config.subjects can follow drive grants.
create or replace function "better_supabase"."drive_node_readable"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select "better_supabase"."drive_can"(drive_node_readable.node, 'viewer')
$$;
revoke execute on function "better_supabase"."drive_node_readable"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_node_readable"(uuid) to authenticated, service_role;

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
    select "better_supabase"."drive_can"(x."id", 'editor') and not (false or false)
    from "centrakit"."file_node" x where x."id" = drive_node_writable.node
  ), false)
$$;
revoke execute on function "better_supabase"."drive_node_writable"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_node_writable"(uuid) to authenticated, service_role;

-- Whether the caller may comment on the node: options.commentRole (commenter).
create or replace function "better_supabase"."drive_can_comment"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select "better_supabase"."drive_can"(drive_can_comment.node, 'commenter')
$$;
revoke execute on function "better_supabase"."drive_can_comment"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_can_comment"(uuid) to authenticated, service_role;

-- Whether downloads of the node's original are blocked on it, a folder above it
-- or its drive. Share links honor the block whatever their role.
create or replace function "better_supabase"."drive_download_blocked"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false or false
$$;
revoke execute on function "better_supabase"."drive_download_blocked"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_download_blocked"(uuid) to service_role;

-- Whether the caller may download the node's original: read access, and no
-- download block unless they hold the write role (editor). Previews only need
-- read access.
create or replace function "better_supabase"."drive_can_download"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(drive_can_download.node, 'viewer')
    and ("better_supabase"."drive_can"(drive_can_download.node, 'editor') or not "better_supabase"."drive_download_blocked"(drive_can_download.node)))
$$;
revoke execute on function "better_supabase"."drive_can_download"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_can_download"(uuid) to authenticated, service_role;

-- Whether the caller may add files to the folder: the write role (editor).
-- External mirrors take no files.
create or replace function "better_supabase"."drive_can_upload"(folder uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x."kind" = 'folder' and not (false or false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor'))
    from "centrakit"."file_node" x where x."id" = drive_can_upload.folder
  ), false)
$$;
revoke execute on function "better_supabase"."drive_can_upload"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_can_upload"(uuid) to authenticated, service_role;

-- create_share_link's check for a node: it exists in the tenant, the caller
-- holds the share role (editor) on it, and an upload link names a folder.
create or replace function "better_supabase"."drive_share_link_allowed"(node text, tenant text, role text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "centrakit"."file_node"%rowtype;
begin
  if drive_share_link_allowed.node !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  select * into v_node from "centrakit"."file_node" x
  where x."id" = drive_share_link_allowed.node::uuid and x."organization_id"::text = drive_share_link_allowed.tenant::text;
  if not found or not "better_supabase"."drive_can"(v_node."id", 'editor') then
    return false;
  end if;
  if drive_share_link_allowed.role = 'upload' and v_node."kind" <> 'folder' then
    raise exception 'an upload link names a folder' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
  end if;
  if "better_supabase"."drive_sharing"(v_node."organization_id") ->> 'links' = 'none' then
    raise exception 'this organization has turned off share links' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drive_share_link_allowed"(text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_share_link_allowed"(text, text, text) to service_role;

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
  select x."id" from "centrakit"."file_node" x
  where coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or (auth.uid() is not null
      and x."organization_id" in (select better_supabase.tenant_ids_with('drive.read'))
      and (x."organization_id" in (select better_supabase.tenant_ids_with('drive.manage'))))
  union
  select s.node_id from "centrakit"."file_node_grant" dg
  cross join lateral "better_supabase"."drive_subtree"(dg."file_node_id") s
  join "centrakit"."file_node" x on x."id" = s.node_id
  where auth.uid() is not null
    and coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], dg."role"::text), 0) >= coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], 'viewer'::text), 0)
    and coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], 'viewer'::text), 0) > 0
    and x."organization_id" in (select better_supabase.tenant_ids_with('drive.read'))
    and (dg."user_id" = auth.uid() or (dg."team_id" is not null and exists (select 1 from "centrakit"."team_members" tm where tm."team_id"::text = dg."team_id"::text and tm."user_id" = auth.uid())))
$$;
revoke execute on function "better_supabase"."drive_readable_ids"() from public, anon;
grant execute on function "better_supabase"."drive_readable_ids"() to authenticated, service_role;

create or replace function "better_supabase"."drive_node_json"(node "centrakit"."file_node")
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."organization_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', null, 'source', null, 'externalId', null, 'externalMetadata', null, 'legalHoldUntil', null, 'lockedBy', null, 'lockedUntil', null, 'lockNote', null, 'downloadBlocked', false, 'previewPages', null, 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', null)
$$;
revoke execute on function "better_supabase"."drive_node_json"("centrakit"."file_node") from public, anon, authenticated;

drop policy if exists bsb_file_node_select on "centrakit"."file_node";
create policy bsb_file_node_select on "centrakit"."file_node"
  for select to authenticated
  using ("id" in (select "better_supabase"."drive_readable_ids"()));

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
      select 1 from "centrakit"."file_node" x
      where x."organization_id" = drive_free_name.tenant and x."parent_id" is not distinct from drive_free_name.parent
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
  v_parent "centrakit"."file_node"%rowtype;
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
  select * into v_parent from "centrakit"."file_node" x
  where x."id" = drive_check_parent.parent and x."organization_id" = drive_check_parent.tenant;
  if not found or not "better_supabase"."drive_can"(v_parent."id", 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not "better_supabase"."drive_can"(v_parent."id", 'editor') then
    raise exception 'not allowed to add items to this folder' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_parent."kind" <> 'folder' then
    raise exception 'a file can''t hold other items' using errcode = '22023', hint = 'DRIVE_PARENT_NOT_FOLDER';
  end if;
  if (false or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
end;
$$;
revoke execute on function "better_supabase"."drive_check_parent"(uuid, uuid, uuid) from public, anon, authenticated;

-- It returns the node table's row type, which differs between managed and
-- adopted tables.
drop function if exists "better_supabase"."drive_insert_node"(uuid, uuid, uuid, text, text, text, jsonb, text);
drop function if exists "better_supabase"."drive_insert_node"(uuid, uuid, uuid, text, text, text, jsonb);
drop function if exists "better_supabase"."drive_insert_node"(uuid, uuid, text, text, text, jsonb);
-- Inserts a node after its siblings. Extra columns come from fields, or
-- from the parent. At the root, the creator gets editor. source 'request' marks a
-- file request upload, which has no creator.
create or replace function "better_supabase"."drive_insert_node"(tenant uuid, drive uuid, parent uuid, kind text, name text, conflict text, fields jsonb, source text default 'internal')
returns "centrakit"."file_node"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "centrakit"."file_node"%rowtype;
  v_parent "centrakit"."file_node"%rowtype;
  v_fields "centrakit"."file_node"%rowtype;
  v_drive uuid := drive_insert_node.drive;
  v_name text;
  v_last text;
begin
  select * into v_parent from "centrakit"."file_node" x where x."id" = drive_insert_node.parent;
  v_name := "better_supabase"."drive_free_name"(drive_insert_node.tenant, v_drive, drive_insert_node.parent, drive_insert_node.name, null, drive_insert_node.conflict);
  v_fields := jsonb_populate_record(null::"centrakit"."file_node", coalesce(drive_insert_node.fields, '{}'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_create"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name;
    end if;
  end;
  insert into "centrakit"."file_node" ("organization_id", "parent_id", "kind", "name", "created_by")
  values (drive_insert_node.tenant, drive_insert_node.parent, better_supabase.as_column_type(drive_insert_node.kind, (null::"centrakit"."file_node")."kind"), v_name, case when drive_insert_node.source = 'request' then null else auth.uid() end)
  returning * into v_node;
  if drive_insert_node.parent is null and auth.uid() is not null then
    delete from "centrakit"."file_node_grant" dg where dg."file_node_id" = v_node."id" and dg."user_id" = auth.uid();
    insert into "centrakit"."file_node_grant" ("organization_id", "file_node_id", "user_id", "role")
    values (v_node."organization_id", v_node."id", auth.uid(), better_supabase.as_column_type('editor', (null::"centrakit"."file_node_grant")."role"));
  end if;
  perform "better_supabase".emit_event('drive_node.created', jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source), 'drive-nodes/' || v_node."id"::text, (v_node."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive_node.created',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'created',
    tenant => (v_node."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source)
  );
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
revoke execute on function "better_supabase"."drive_insert_node"(uuid, uuid, uuid, text, text, text, jsonb, text) from public, anon, authenticated;

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
  v_node "centrakit"."file_node"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not (centrakit.authz_actor_may_write());
  perform "better_supabase"."drive_check_parent"(drive_create_folder.tenant, drive_create_folder.parent, drive_create_folder.drive);
  v_node := "better_supabase"."drive_insert_node"(drive_create_folder.tenant, drive_create_folder.drive, drive_create_folder.parent, 'folder', v_name,
    case when v_conflict = 'replace' then 'fail' else v_conflict end, drive_create_folder.fields);
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
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
  v_node "centrakit"."file_node"%rowtype;
begin
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_get.node;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_get"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_get"(uuid) to authenticated, service_role;

-- A folder's children, folders first, then by name. Without parent, the
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
    select 1 from "centrakit"."file_node" p where p."id" = drive_list.parent and p."organization_id" = drive_list.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(p."id", 'viewer'))
  ) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"))) order by ((c.r)."kind" = 'folder') desc, lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
    from (
      select x as r from "centrakit"."file_node" x
      where x."organization_id" = drive_list.tenant and x."parent_id" is not distinct from drive_list.parent
        and (drive_list.parent is not null or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
      order by (x."kind" = 'folder') desc, lower(x."name"), x."id"
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
  select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"))) order by (c.r)."name", (c.r)."id"), '[]'::jsonb)
  from (
    select x as r from "centrakit"."file_node" x
    where x."organization_id" = drive_shared.tenant
      and auth.uid() is not null
      and exists (
        select 1 from "centrakit"."file_node_grant" dg
        where dg."file_node_id" = x."id"
          and (dg."user_id" = auth.uid() or (dg."team_id" is not null and exists (select 1 from "centrakit"."team_members" tm where tm."team_id"::text = dg."team_id"::text and tm."user_id" = auth.uid())))
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
    join "centrakit"."file_node" x on x."id" = p.id
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
  v_node "centrakit"."file_node"%rowtype;
  v_previous text;
  v_name text := "better_supabase"."drive_clean_name"(drive_rename.name);
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_rename.node for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to rename this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (false or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  
  if v_name = v_node."name" then
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."organization_id", null, v_node."parent_id", v_name, v_node."id",
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
  update "centrakit"."file_node" x set "name" = v_name, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.renamed', jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive_node.renamed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'renamed',
    tenant => (v_node."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_rename"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
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
  v_node "centrakit"."file_node"%rowtype;
  v_previous uuid;
  v_target uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_move.node for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (false or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  
  
  v_previous := v_node."parent_id";
  if drive_move.parent is null then
    if v_previous is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'editor') and coalesce(better_supabase.can('tenant', v_node."organization_id", 'drive.create'), false))) then
      raise exception 'not allowed to move this item to the top of the drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
  else
    perform "better_supabase"."drive_check_parent"(v_node."organization_id", drive_move.parent, drive_move.drive);
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
    v_name := "better_supabase"."drive_free_name"(v_node."organization_id", v_target, drive_move.parent, v_node."name", v_node."id",
      case when "better_supabase"."drive_conflict"(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := "better_supabase"."drive_role"(v_node."id");
      delete from "centrakit"."file_node_grant" dg where dg."file_node_id" = v_node."id" and dg."user_id" = auth.uid();
    insert into "centrakit"."file_node_grant" ("organization_id", "file_node_id", "user_id", "role")
    values (v_node."organization_id", v_node."id", auth.uid(), better_supabase.as_column_type(v_role, (null::"centrakit"."file_node_grant")."role"));
    end if;
    update "centrakit"."file_node" x set "parent_id" = drive_move.parent, "name" = v_name, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive_node.moved', jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive_node.moved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'moved',
    tenant => (v_node."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous)
  );
  
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_move"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (false or false), 'held', "better_supabase"."drive_node_held"((v_node)."id")));
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
  v_node "centrakit"."file_node"%rowtype;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_delete.node;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to delete this item for good' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (false or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  
  delete from "centrakit"."file_node" x where x."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s);
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
  v_node "centrakit"."file_node"%rowtype;
  v_type text := lower(drive_share.principal_type);
  v_id uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_share.node;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'editor') and coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], drive_share.role::text), 0) <= coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], "better_supabase"."drive_role"(v_node."id")::text), 0))) then
    raise exception 'not allowed to share this item with that role' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (false or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], drive_share.role::text), 0) = 0 then
    raise exception 'role must be one of viewer, commenter, editor' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if v_type not in ('user', 'team') or drive_share.principal_id is null then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'DRIVE_PRINCIPAL_INVALID';
  end if;
  if (v_type = 'user' and (drive_share.principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or not exists (
      select 1 from "centrakit"."organization_users" mu
      where mu."organization_id" = v_node."organization_id" and mu."user_id" = drive_share.principal_id::uuid
    )))
    or (v_type = 'team' and not exists (select 1 from "centrakit"."teams" t where t."id"::text = drive_share.principal_id and t."tenant_id" = v_node."organization_id")) then
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
  delete from "centrakit"."file_node_grant" dg where dg."file_node_id" = v_node."id" and case when dg."user_id" is not null then 'user' else 'team' end = v_type and coalesce(dg."user_id"::text, dg."team_id"::text) = drive_share.principal_id;
  insert into "centrakit"."file_node_grant" ("organization_id", "file_node_id", "user_id", "team_id", "role")
  values (v_node."organization_id", v_node."id", case when v_type = 'user' then drive_share.principal_id::uuid end, case when v_type = 'team' then (select t."id" from "centrakit"."teams" t where t."id"::text = drive_share.principal_id) end, better_supabase.as_column_type(drive_share.role, (null::"centrakit"."file_node_grant")."role"))
  returning "id" into v_id;
  perform "better_supabase".emit_event('drive_node.shared', jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role), 'drive-nodes/' || v_node."id"::text, (v_node."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive_node.shared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'shared',
    tenant => (v_node."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role)
  );
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
  v_node "centrakit"."file_node"%rowtype;
  v_type text := lower(drive_unshare.principal_type);
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_unshare.node;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to change who this item is shared with' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (false or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  delete from "centrakit"."file_node_grant" dg where dg."file_node_id" = v_node."id"
    and case when dg."user_id" is not null then 'user' else 'team' end = v_type and coalesce(dg."user_id"::text, dg."team_id"::text) = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('drive_node.unshared', jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id), 'drive-nodes/' || v_node."id"::text, (v_node."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unshared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'unshared',
    tenant => (v_node."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id)
  );
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
    select coalesce(jsonb_agg(jsonb_build_object('id', dg."id", 'nodeId', dg."file_node_id", 'principalType', case when dg."user_id" is not null then 'user' else 'team' end, 'principalId', coalesce(dg."user_id"::text, dg."team_id"::text), 'role', dg."role", 'expiresAt', null, 'inherited', dg."file_node_id" <> drive_grants.node) order by dg."file_node_id" = drive_grants.node, coalesce(array_position(array['viewer', 'commenter', 'editor']::text[], dg."role"::text), 0) desc, dg."id"), '[]'::jsonb)
    from "centrakit"."file_node_grant" dg
    where dg."file_node_id" = any ("better_supabase"."drive_ancestors"(drive_grants.node))
  );
end;
$$;
revoke execute on function "better_supabase"."drive_grants"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_grants"(uuid) to authenticated, service_role;





-- Each node's name and the start of its text, for the drive_node search subject.
create or replace view "better_supabase"."file_node_search" with (security_invoker = true) as
  select s."id" as id, s."name" as name, null::text as content
  from "centrakit"."file_node" s;
revoke all on "better_supabase"."file_node_search" from public, anon, authenticated;
grant select on "better_supabase"."file_node_search" to service_role;


-- Hands every item one member holds at editor in an organization to
-- another member: their editor grants on nodes and drives, and the drives they
-- own. The new holder keeps one grant per item. Needs drive.manage.
create or replace function "better_supabase"."drive_transfer_ownership"(tenant uuid, from_user uuid, to_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_grant "centrakit"."file_node_grant"%rowtype;
  v_node "centrakit"."file_node"%rowtype;
  v_drive_ids uuid[] := '{}';
  v_nodes integer := 0;
  v_drives integer := 0;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_transfer_ownership.tenant, 'drive.manage'), false)) then
    raise exception 'you can''t transfer items in this organization' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_transfer_ownership.from_user is null or drive_transfer_ownership.to_user is null
    or drive_transfer_ownership.from_user = drive_transfer_ownership.to_user then
    raise exception 'name two different users to transfer between' using errcode = '22023', hint = 'DRIVE_TRANSFER_INVALID';
  end if;
  if not exists (
    select 1 from "centrakit"."organization_users" mu
    where mu."organization_id" = drive_transfer_ownership.tenant and mu."user_id" = drive_transfer_ownership.to_user
  ) then
    raise exception 'the new owner is not an active member of this organization' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  for v_grant in
    select gr.* from "centrakit"."file_node_grant" gr
    where gr."organization_id" = drive_transfer_ownership.tenant and gr."role"::text = 'editor'
      and gr."user_id" = drive_transfer_ownership.from_user
  loop
    delete from "centrakit"."file_node_grant" gr where gr."file_node_id" = v_grant."file_node_id" and gr."user_id" = drive_transfer_ownership.to_user;
    update "centrakit"."file_node_grant" set "user_id" = drive_transfer_ownership.to_user where "id" = v_grant."id";
    select * into v_node from "centrakit"."file_node" x where x."id" = v_grant."file_node_id";
    v_nodes := v_nodes + 1;
    perform "better_supabase".emit_event('drive_node.ownership_transferred', jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text), 'drive-nodes/' || v_node."id"::text, (v_node."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive_node.ownership_transferred',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'ownership transferred',
    tenant => (v_node."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text)
  );
  end loop;
  return jsonb_build_object('nodes', v_nodes, 'drives', v_drives);
end;
$$;
revoke execute on function "better_supabase"."drive_transfer_ownership"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."drive_transfer_ownership"(uuid, uuid, uuid) to authenticated, service_role;

-- The organization's drive.sharing setting over the defaults
-- '{"guests": true, "links": "anyone"}'::jsonb.
create or replace function "better_supabase"."drive_sharing"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select '{"guests": true, "links": "anyone"}'::jsonb || coalesce("better_supabase"."organization_setting"(drive_sharing.tenant, 'drive.sharing'), '{}'::jsonb)
$$;
revoke execute on function "better_supabase"."drive_sharing"(uuid) from public, anon, authenticated;

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
drop policy if exists bsb_tenant_scope on "centrakit"."file_node";
drop policy if exists bsb_tenant_scope_select on "centrakit"."file_node";
create policy bsb_tenant_scope_select on "centrakit"."file_node" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("id" in (select "better_supabase"."drive_readable_ids"()))
  );
drop policy if exists bsb_tenant_scope_insert on "centrakit"."file_node";
create policy bsb_tenant_scope_insert on "centrakit"."file_node" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "centrakit"."file_node";
create policy bsb_tenant_scope_update on "centrakit"."file_node" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "centrakit"."file_node";
create policy bsb_tenant_scope_delete on "centrakit"."file_node" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

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
