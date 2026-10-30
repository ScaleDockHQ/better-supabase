-- better-supabase module: drive
-- @bsb-block drive@2 managed
-- @bsb-hash sha256:4ff154eab8342eb7ae22a03ef54cd1c7d544da57b76da3381fd8ce800def376a
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
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."drive_node_texts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."drive_node_texts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."drive_node_texts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."drive_node_texts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."drive_node_texts";
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
  "source" text not null default 'internal',
  "external_id" text,
  "external_metadata" jsonb not null default '{}'::jsonb,
  "legal_hold_until" timestamptz,
  "locked_by" uuid,
  "locked_until" timestamptz,
  "lock_note" text check (length("lock_note") <= 500),
  "download_blocked" boolean not null default false,
  "preview_pages" integer check ("preview_pages" >= 0),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("external_id" is null or "source" <> 'internal')
);
create unique index if not exists "drive_nodes_sibling_name_idx" on "better_supabase"."drive_nodes" ("tenant_id", coalesce("parent_id", '00000000-0000-0000-0000-000000000000'::uuid), lower("name")) where "deleted_at" is null and "source" = 'internal';
create index if not exists "drive_nodes_parent_idx" on "better_supabase"."drive_nodes" ("tenant_id", "parent_id", "rank");
create index if not exists "drive_nodes_parent_fk_idx" on "better_supabase"."drive_nodes" ("parent_id") where "parent_id" is not null;
create index if not exists "drive_nodes_path_idx" on "better_supabase"."drive_nodes" ("path" text_pattern_ops);
create index if not exists "drive_nodes_attachment_idx" on "better_supabase"."drive_nodes" ("attachment_id");
create unique index if not exists "drive_nodes_external_idx" on "better_supabase"."drive_nodes" ("tenant_id", "source", "external_id") where "external_id" is not null and "deleted_at" is null;
alter table "better_supabase"."drive_nodes" add column if not exists "locked_by" uuid;
alter table "better_supabase"."drive_nodes" add column if not exists "locked_until" timestamptz;
alter table "better_supabase"."drive_nodes" add column if not exists "lock_note" text check (length("lock_note") <= 500);
alter table "better_supabase"."drive_nodes" add column if not exists "download_blocked" boolean not null default false;
alter table "better_supabase"."drive_nodes" add column if not exists "preview_pages" integer check ("preview_pages" >= 0);
alter table "better_supabase"."drive_nodes" drop constraint if exists "drive_nodes_source_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."drive_nodes"'::regclass and c.conname = 'bsb_drive_nodes_source'
  ), 'pg_constraint'), '') <> 'better-supabase check 91469035' then
    alter table "better_supabase"."drive_nodes" drop constraint if exists "bsb_drive_nodes_source";
    alter table "better_supabase"."drive_nodes" add constraint "bsb_drive_nodes_source" check ("source" = any (array['internal', 'request', 'google-drive', 'onedrive']::text[]));
    comment on constraint "bsb_drive_nodes_source" on "better_supabase"."drive_nodes" is 'better-supabase check 91469035';
  end if;
end;
$$;
alter table "better_supabase"."drive_nodes" add column if not exists "document_number" text check (length("document_number") between 1 and 100);
alter table "better_supabase"."drive_nodes" add column if not exists "document_type" text check (length("document_type") between 1 and 63);
alter table "better_supabase"."drive_nodes" add column if not exists "document_status" text check ("document_status" in ('draft', 'in_review', 'effective', 'obsolete'));
alter table "better_supabase"."drive_nodes" add column if not exists "document_owner_id" uuid;
alter table "better_supabase"."drive_nodes" add column if not exists "effective_version_id" uuid;
alter table "better_supabase"."drive_nodes" add column if not exists "effective_from" timestamptz;
alter table "better_supabase"."drive_nodes" add column if not exists "review_interval_months" integer check ("review_interval_months" between 1 and 120);
alter table "better_supabase"."drive_nodes" add column if not exists "next_review_on" date;
alter table "better_supabase"."drive_nodes" add column if not exists "review_notified_for" date;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."drive_nodes"'::regclass and c.conname = 'bsb_drive_nodes_document_file'
  ), 'pg_constraint'), '') <> 'better-supabase check 3f65769f' then
    alter table "better_supabase"."drive_nodes" drop constraint if exists "bsb_drive_nodes_document_file";
    alter table "better_supabase"."drive_nodes" add constraint "bsb_drive_nodes_document_file" check ("document_status" is null or "kind" = 'file');
    comment on constraint "bsb_drive_nodes_document_file" on "better_supabase"."drive_nodes" is 'better-supabase check 3f65769f';
  end if;
end;
$$;
create unique index if not exists "drive_nodes_document_number_idx" on "better_supabase"."drive_nodes" ("tenant_id", "document_number") where "document_number" is not null;
create index if not exists "drive_nodes_document_owner_idx" on "better_supabase"."drive_nodes" ("document_owner_id") where "document_owner_id" is not null;
create index if not exists "drive_nodes_effective_version_idx" on "better_supabase"."drive_nodes" ("effective_version_id") where "effective_version_id" is not null;
create index if not exists "drive_nodes_next_review_idx" on "better_supabase"."drive_nodes" ("next_review_on") where "document_status" = 'effective';
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
  ), 'pg_constraint'), '') <> 'better-supabase check 8f832167' then
    alter table "better_supabase"."drive_grants" drop constraint if exists "bsb_drive_grants_role";
    alter table "better_supabase"."drive_grants" add constraint "bsb_drive_grants_role" check ("role" = any (array['viewer', 'editor', 'owner', 'contributor']::text[]));
    comment on constraint "bsb_drive_grants_role" on "better_supabase"."drive_grants" is 'better-supabase check 8f832167';
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
  
  select greatest(coalesce(v_rank, 0), coalesce(max(coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"::text), 0)), 0)) into v_rank from "better_supabase"."drive_grants" dg
  where dg."node_id" = any ("better_supabase"."drive_ancestors"(drive_role.node)) and (dg."expires_at" is null or dg."expires_at" > now())
    and ((dg."principal_type" = 'user' and dg."principal_id" = v_uid::text)
      or (dg."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = dg."principal_id"::text and tm."user_id" = v_uid))
      or (dg."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = v_uid and mr."role"::text = dg."principal_id")));
  
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
  select coalesce(coalesce(array_position(array['viewer', 'editor', 'owner']::text[], "better_supabase"."drive_role"(drive_can.node)::text), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_can.role::text), 0) and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_can.role::text), 0) > 0, false)
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
    select "better_supabase"."drive_can"(x."id", 'editor') and not (coalesce(x."source"::text, 'internal') not in ('internal', 'request') or false)
    from "better_supabase"."drive_nodes" x where x."id" = drive_node_writable.node
  ), false)
$$;
revoke execute on function "better_supabase"."drive_node_writable"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_node_writable"(uuid) to authenticated, service_role;

-- Whether the caller may comment on the node: options.commentRole (editor).
create or replace function "better_supabase"."drive_can_comment"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select "better_supabase"."drive_can"(drive_can_comment.node, 'editor')
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
  select exists (select 1 from "better_supabase"."drive_nodes" b where b."id" = any ("better_supabase"."drive_ancestors"(drive_download_blocked.node)) and b."download_blocked") or false
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

-- Whether the caller may add files to the folder: the write role (editor), or a
-- live options.uploadRole (contributor) grant on it or a folder above it, which reads nothing.
-- External mirrors take no files.
create or replace function "better_supabase"."drive_can_upload"(folder uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x."kind" = 'folder' and not (coalesce(x."source"::text, 'internal') not in ('internal', 'request') or false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor') or (auth.uid() is not null
      and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
      and exists (select 1 from "better_supabase"."drive_grants" ug
        where ug."node_id" = any ("better_supabase"."drive_ancestors"(x."id")) and ug."role" = 'contributor' and (ug."expires_at" is null or ug."expires_at" > now())
          and ((ug."principal_type" = 'user' and ug."principal_id" = auth.uid()::text)
      or (ug."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = ug."principal_id"::text and tm."user_id" = auth.uid()))
      or (ug."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = ug."principal_id"))))))
    from "better_supabase"."drive_nodes" x where x."id" = drive_can_upload.folder and x."deleted_at" is null
  ), false)
$$;
revoke execute on function "better_supabase"."drive_can_upload"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_can_upload"(uuid) to authenticated, service_role;

-- Whether the node is a file the caller added under the upload role and may
-- still finish uploading: they created it, and may still upload to its folder.
create or replace function "better_supabase"."drive_uploaded_own"(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x."kind" = 'file' and x."parent_id" is not null
      and x."created_by" = auth.uid() and "better_supabase"."drive_can_upload"(x."parent_id")
    from "better_supabase"."drive_nodes" x where x."id" = drive_uploaded_own.node and x."deleted_at" is null
  ), false)
$$;
revoke execute on function "better_supabase"."drive_uploaded_own"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_uploaded_own"(uuid) to authenticated, service_role;

-- create_share_link's check for a node: it exists in the tenant, the caller
-- holds the share role (owner) on it, and an upload link names a folder.
create or replace function "better_supabase"."drive_share_link_allowed"(node text, tenant text, role text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if drive_share_link_allowed.node !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x
  where x."id" = drive_share_link_allowed.node::uuid and x."tenant_id"::text = drive_share_link_allowed.tenant::text;
  if not found or not "better_supabase"."drive_can"(v_node."id", 'owner') then
    return false;
  end if;
  if drive_share_link_allowed.role = 'upload' and v_node."kind" <> 'folder' then
    raise exception 'an upload link names a folder' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
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
    and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"::text), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'viewer'::text), 0)
    and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'viewer'::text), 0) > 0
    and x."tenant_id" in (select better_supabase.tenant_ids_with('drive.read'))
    and ((dg."principal_type" = 'user' and dg."principal_id" = auth.uid()::text)
      or (dg."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = dg."principal_id"::text and tm."user_id" = auth.uid()))
      or (dg."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = dg."principal_id")))
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
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."tenant_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', ($1)."rank", 'source', ($1)."source", 'externalId', ($1)."external_id", 'externalMetadata', ($1)."external_metadata", 'legalHoldUntil', ($1)."legal_hold_until", 'lockedBy', case when ($1)."locked_until" > now() then ($1)."locked_by" end, 'lockedUntil', case when ($1)."locked_until" > now() then ($1)."locked_until" end, 'lockNote', case when ($1)."locked_until" > now() then ($1)."lock_note" end, 'downloadBlocked', ($1)."download_blocked", 'previewPages', ($1)."preview_pages", 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', ($1)."deleted_at")
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
  if (coalesce(v_parent."source"::text, 'internal') not in ('internal', 'request') or false) then
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
-- from the parent. At the root, the creator gets owner. source 'request' marks a
-- file request upload, which has no creator.
create or replace function "better_supabase"."drive_insert_node"(tenant uuid, drive uuid, parent uuid, kind text, name text, conflict text, fields jsonb, source text default 'internal')
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
  insert into "better_supabase"."drive_nodes" ("tenant_id", "parent_id", "kind", "name", "rank", "source", "created_by")
  values (drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end, drive_insert_node.source, case when drive_insert_node.source = 'request' then null else auth.uid() end)
  returning * into v_node;
  if drive_insert_node.parent is null and auth.uid() is not null then
    insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, 'owner')
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role";
  end if;
  perform "better_supabase".emit_event('drive.node_created', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_created',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'created',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source)
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
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  perform "better_supabase"."drive_check_parent"(drive_create_folder.tenant, drive_create_folder.parent, drive_create_folder.drive);
  v_node := "better_supabase"."drive_insert_node"(drive_create_folder.tenant, drive_create_folder.drive, drive_create_folder.parent, 'folder', v_name,
    case when v_conflict = 'replace' then 'fail' else v_conflict end, drive_create_folder.fields);
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
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
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
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
    select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"), 'downloadable', "better_supabase"."drive_can_download"((c.r)."id"))) order by ((c.r)."kind" = 'folder') desc, (c.r)."rank", lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
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
  select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"), 'downloadable', "better_supabase"."drive_can_download"((c.r)."id"))) order by (c.r)."name", (c.r)."id"), '[]'::jsonb)
  from (
    select x as r from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_shared.tenant and x."deleted_at" is null
      and auth.uid() is not null
      and exists (
        select 1 from "better_supabase"."drive_grants" dg
        where dg."node_id" = x."id" and (dg."expires_at" is null or dg."expires_at" > now())
          and ((dg."principal_type" = 'user' and dg."principal_id" = auth.uid()::text)
      or (dg."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = dg."principal_id"::text and tm."user_id" = auth.uid()))
      or (dg."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = dg."principal_id")))
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
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_name = v_node."name" then
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
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
  perform "better_supabase".emit_event('drive.node_renamed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_renamed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'renamed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_rename"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
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
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
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
    perform "better_supabase".emit_event('drive.node_moved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_moved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'moved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous)
  );
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
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
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
  v_locked "better_supabase"."drive_nodes"%rowtype;
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
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  select * into v_locked from "better_supabase"."drive_nodes" lk
  where lk."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s)
    and (lk."locked_until" > now() and lk."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
  limit 1;
  if found then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_locked."locked_by", 'lockedUntil', v_locked."locked_until")::text;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role::text), 0) <= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], "better_supabase"."drive_role"(v_node."id")::text), 0))) then
    raise exception 'not allowed to share this item with that role' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role::text), 0) = 0 and drive_share.role is distinct from 'contributor' then
    raise exception 'role must be one of viewer, editor, owner, contributor' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if drive_share.role = 'contributor' and v_node."kind" <> 'folder' then
    raise exception 'the upload role is for folders' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN', detail = '{"reason":"upload role is for folders"}';
  end if;
  if v_type not in ('user', 'team', 'role') or drive_share.principal_id is null then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'DRIVE_PRINCIPAL_INVALID';
  end if;
  if (v_type = 'user' and (drive_share.principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or not exists (
      select 1 from "public"."memberships" mu
      where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_share.principal_id::uuid
    )))
    or (v_type = 'team' and not exists (select 1 from "better_supabase"."teams" t where t."id"::text = drive_share.principal_id and t."tenant_id" = v_node."tenant_id")) then
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
  perform "better_supabase".emit_event('drive.node_shared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_shared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'shared',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role)
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
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id"
    and dg."principal_type" = v_type and dg."principal_id" = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('drive.node_unshared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_unshared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'unshared',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id)
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
    select coalesce(jsonb_agg(jsonb_build_object('id', dg."id", 'nodeId', dg."node_id", 'principalType', dg."principal_type", 'principalId', dg."principal_id", 'role', dg."role", 'expiresAt', dg."expires_at", 'inherited', dg."node_id" <> drive_grants.node) order by dg."node_id" = drive_grants.node, coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"::text), 0) desc, dg."id"), '[]'::jsonb)
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
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if drive_hold.until is null or drive_hold.until <= now() then
    raise exception 'a legal hold needs an end in the future' using errcode = '22023', hint = 'DRIVE_HOLD_INVALID';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_until" = drive_hold.until, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive.node_hold_placed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_until"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_hold_placed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'held',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_until")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
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
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_until" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive.node_hold_released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_hold_released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_release_hold"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_release_hold"(uuid) to authenticated, service_role;



-- Checks a file out: only the holder may change it until the lock ends
-- (8 hours by default, 30 days at most) or the holder releases it. Holding it
-- already extends it.
create or replace function "better_supabase"."drive_lock"(node uuid, until timestamptz default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_until timestamptz := coalesce(drive_lock.until, now() + interval '8 hours');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_lock.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if auth.uid() is null then
    raise exception 'not allowed to check out an item without a user' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if not "better_supabase"."drive_node_writable"(v_node."id") then
    if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
      raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
    end if;
    raise exception 'not allowed to check out this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be checked out' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_until <= now() or v_until > now() + interval '30 days' then
    raise exception 'a lock ends in the future and within 30 days' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if length(drive_lock.note) > 500 then
    raise exception 'a lock note is at most 500 characters' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = auth.uid(), "locked_until" = v_until, "lock_note" = drive_lock.note, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive.node_locked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."locked_until"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_locked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked out',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."locked_until")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_lock"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."drive_lock"(uuid, timestamptz, text) to authenticated, service_role;

-- Releases a lock: the holder, or with force the share role (owner). An
-- item without a live lock comes back unchanged.
create or replace function "better_supabase"."drive_unlock"(node uuid, force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_holder uuid;
  v_forced boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unlock.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."locked_until" is null or v_node."locked_until" <= now() then
    if v_node."locked_by" is not null then
      update "better_supabase"."drive_nodes" x set "locked_by" = null, "locked_until" = null, "lock_note" = null
      where x."id" = v_node."id"
      returning * into v_node;
    end if;
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_holder := v_node."locked_by";
  if v_holder is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    if not coalesce(drive_unlock.force, false) then
      raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
    end if;
    if not "better_supabase"."drive_can"(v_node."id", 'owner') then
      raise exception 'not allowed to break someone else''s lock' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
    v_forced := true;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = null, "locked_until" = null, "lock_note" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive.node_unlocked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_unlocked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked in',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_unlock"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."drive_unlock"(uuid, boolean) to authenticated, service_role;

-- Blocks or allows downloads of the originals on a node and everything under
-- it, or on a whole drive (the share role, owner). Readers keep previews; the
-- write role (editor) still downloads.
create or replace function "better_supabase"."drive_set_download_blocked"(target_type text, target_id uuid, blocked boolean)
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
  if drive_set_download_blocked.target_type is null or drive_set_download_blocked.target_type not in ('node') then
    raise exception 'target_type must be node' using errcode = '22023', hint = 'DRIVE_TARGET_INVALID';
  end if;
  if drive_set_download_blocked.blocked is null then
    raise exception 'blocked must be true or false' using errcode = '22023', hint = 'DRIVE_TARGET_INVALID';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_set_download_blocked.target_id and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to change downloads of this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if v_node."download_blocked" is distinct from drive_set_download_blocked.blocked then
    update "better_supabase"."drive_nodes" x set "download_blocked" = drive_set_download_blocked.blocked, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive.node_download_blocked_changed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'downloadBlocked', v_node."download_blocked"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_download_blocked_changed',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'download block changed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'downloadBlocked', v_node."download_blocked")
  );
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_set_download_blocked"(text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."drive_set_download_blocked"(text, uuid, boolean) to authenticated, service_role;

-- The text drive_set_text stored for each file's current content.
create table if not exists "better_supabase"."drive_node_texts" (
  "node_id" uuid primary key references "better_supabase"."drive_nodes" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "attachment_id" uuid not null,
  "extractor" text,
  "content" text not null,
  "extracted_at" timestamptz not null default now()
);
create index if not exists "drive_node_texts_tenant_idx" on "better_supabase"."drive_node_texts" ("tenant_id");
alter table "better_supabase"."drive_node_texts" enable row level security;
revoke all on "better_supabase"."drive_node_texts" from public, anon, authenticated;
grant select on "better_supabase"."drive_node_texts" to authenticated;
grant all on "better_supabase"."drive_node_texts" to service_role;
drop policy if exists drive_node_texts_read on "better_supabase"."drive_node_texts";
create policy drive_node_texts_read on "better_supabase"."drive_node_texts"
  for select to authenticated
  using ("better_supabase"."drive_can"("node_id", 'viewer'));

-- Each node's name and the start of its text, for the drive_node search subject.
create or replace view "better_supabase"."drive_node_search" with (security_invoker = true) as
  select s."id" as id, s."name" as name, left(t."content", 100000) as content
  from "better_supabase"."drive_nodes" s
  left join "better_supabase"."drive_node_texts" t on t."node_id" = s."id";
revoke all on "better_supabase"."drive_node_search" from public, anon, authenticated;
grant select on "better_supabase"."drive_node_search" to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."drive_node_texts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."drive_node_texts";
create policy bsb_tenant_scope_select on "better_supabase"."drive_node_texts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."drive_can"("node_id", 'viewer'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."drive_node_texts";
create policy bsb_tenant_scope_insert on "better_supabase"."drive_node_texts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."drive_node_texts";
create policy bsb_tenant_scope_update on "better_supabase"."drive_node_texts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."drive_node_texts";
create policy bsb_tenant_scope_delete on "better_supabase"."drive_node_texts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.drive.api: entry points for the Data API.
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

create or replace function "api"."drive_node_held"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_node_held"($1) $$;
revoke execute on function "api"."drive_node_held"(uuid) from public, anon;
grant execute on function "api"."drive_node_held"(uuid) to authenticated, service_role;

create or replace function "api"."drive_role"(node uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_role"($1) $$;
revoke execute on function "api"."drive_role"(uuid) from public, anon;
grant execute on function "api"."drive_role"(uuid) to authenticated, service_role;

create or replace function "api"."drive_can"(node uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_can"($1, $2) $$;
revoke execute on function "api"."drive_can"(uuid, text) from public, anon;
grant execute on function "api"."drive_can"(uuid, text) to authenticated, service_role;

create or replace function "api"."drive_node_readable"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_node_readable"($1) $$;
revoke execute on function "api"."drive_node_readable"(uuid) from public, anon;
grant execute on function "api"."drive_node_readable"(uuid) to authenticated, service_role;

create or replace function "api"."drive_node_writable"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_node_writable"($1) $$;
revoke execute on function "api"."drive_node_writable"(uuid) from public, anon;
grant execute on function "api"."drive_node_writable"(uuid) to authenticated, service_role;

create or replace function "api"."drive_can_comment"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_can_comment"($1) $$;
revoke execute on function "api"."drive_can_comment"(uuid) from public, anon;
grant execute on function "api"."drive_can_comment"(uuid) to authenticated, service_role;

create or replace function "api"."drive_download_blocked"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_download_blocked"($1) $$;
revoke execute on function "api"."drive_download_blocked"(uuid) from public, anon, authenticated;
grant execute on function "api"."drive_download_blocked"(uuid) to service_role;

create or replace function "api"."drive_can_download"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_can_download"($1) $$;
revoke execute on function "api"."drive_can_download"(uuid) from public, anon;
grant execute on function "api"."drive_can_download"(uuid) to authenticated, service_role;

create or replace function "api"."drive_can_upload"(folder uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_can_upload"($1) $$;
revoke execute on function "api"."drive_can_upload"(uuid) from public, anon;
grant execute on function "api"."drive_can_upload"(uuid) to authenticated, service_role;

create or replace function "api"."drive_uploaded_own"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_uploaded_own"($1) $$;
revoke execute on function "api"."drive_uploaded_own"(uuid) from public, anon;
grant execute on function "api"."drive_uploaded_own"(uuid) to authenticated, service_role;

create or replace function "api"."drive_share_link_allowed"(node text, tenant text, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_share_link_allowed"($1, $2, $3) $$;
revoke execute on function "api"."drive_share_link_allowed"(text, text, text) from public, anon, authenticated;
grant execute on function "api"."drive_share_link_allowed"(text, text, text) to service_role;

create or replace function "api"."drive_readable_ids"()
returns setof uuid
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."drive_readable_ids"() $$;
revoke execute on function "api"."drive_readable_ids"() from public, anon;
grant execute on function "api"."drive_readable_ids"() to authenticated, service_role;

create or replace function "api"."drive_create_folder"(tenant uuid, parent uuid, name text, conflict text default null, fields jsonb default null, drive uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_create_folder"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."drive_create_folder"(uuid, uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "api"."drive_create_folder"(uuid, uuid, text, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."drive_get"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_get"($1) $$;
revoke execute on function "api"."drive_get"(uuid) from public, anon;
grant execute on function "api"."drive_get"(uuid) to authenticated, service_role;

create or replace function "api"."drive_list"(tenant uuid, parent uuid default null, page_size integer default 100, skip integer default 0, drive uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_list"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."drive_list"(uuid, uuid, integer, integer, uuid) from public, anon;
grant execute on function "api"."drive_list"(uuid, uuid, integer, integer, uuid) to authenticated, service_role;

create or replace function "api"."drive_shared"(tenant uuid, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_shared"($1, $2) $$;
revoke execute on function "api"."drive_shared"(uuid, integer) from public, anon;
grant execute on function "api"."drive_shared"(uuid, integer) to authenticated, service_role;

create or replace function "api"."drive_path"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_path"($1) $$;
revoke execute on function "api"."drive_path"(uuid) from public, anon;
grant execute on function "api"."drive_path"(uuid) to authenticated, service_role;

create or replace function "api"."drive_rename"(node uuid, name text, conflict text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_rename"($1, $2, $3) $$;
revoke execute on function "api"."drive_rename"(uuid, text, text) from public, anon;
grant execute on function "api"."drive_rename"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."drive_move"(node uuid, parent uuid, rank text default null, conflict text default null, drive uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_move"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."drive_move"(uuid, uuid, text, text, uuid) from public, anon;
grant execute on function "api"."drive_move"(uuid, uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."drive_delete"(node uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_delete"($1) $$;
revoke execute on function "api"."drive_delete"(uuid) from public, anon;
grant execute on function "api"."drive_delete"(uuid) to authenticated, service_role;

create or replace function "api"."drive_share"(node uuid, principal_type text, principal_id text, role text, expires_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_share"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."drive_share"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "api"."drive_share"(uuid, text, text, text, timestamptz) to authenticated, service_role;

create or replace function "api"."drive_unshare"(node uuid, principal_type text, principal_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_unshare"($1, $2, $3) $$;
revoke execute on function "api"."drive_unshare"(uuid, text, text) from public, anon;
grant execute on function "api"."drive_unshare"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."drive_grants"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_grants"($1) $$;
revoke execute on function "api"."drive_grants"(uuid) from public, anon;
grant execute on function "api"."drive_grants"(uuid) to authenticated, service_role;

create or replace function "api"."drive_hold"(node uuid, until timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_hold"($1, $2) $$;
revoke execute on function "api"."drive_hold"(uuid, timestamptz) from public, anon;
grant execute on function "api"."drive_hold"(uuid, timestamptz) to authenticated, service_role;

create or replace function "api"."drive_release_hold"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_release_hold"($1) $$;
revoke execute on function "api"."drive_release_hold"(uuid) from public, anon;
grant execute on function "api"."drive_release_hold"(uuid) to authenticated, service_role;

create or replace function "api"."drive_lock"(node uuid, until timestamptz default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_lock"($1, $2, $3) $$;
revoke execute on function "api"."drive_lock"(uuid, timestamptz, text) from public, anon;
grant execute on function "api"."drive_lock"(uuid, timestamptz, text) to authenticated, service_role;

create or replace function "api"."drive_unlock"(node uuid, force boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_unlock"($1, $2) $$;
revoke execute on function "api"."drive_unlock"(uuid, boolean) from public, anon;
grant execute on function "api"."drive_unlock"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."drive_set_download_blocked"(target_type text, target_id uuid, blocked boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_set_download_blocked"($1, $2, $3) $$;
revoke execute on function "api"."drive_set_download_blocked"(text, uuid, boolean) from public, anon;
grant execute on function "api"."drive_set_download_blocked"(text, uuid, boolean) to authenticated, service_role;

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
