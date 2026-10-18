-- better-supabase module: drive-files (0.8.0)
-- @bs-module drive-files@1 managed
-- The part of the drive module that needs attachments, versions, trash and share-links: file uploads and revisions, storage policies, the bin, starred and recent items, folder share links and the purge event. Installed with drive.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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

-- Before a node is deleted for good, its stored objects go into
-- drive.node_purged for the app to remove through Storage; after, its
-- grants, attachments and starred state go too.
create or replace function "better_supabase"."drive_node_purging"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_objects jsonb := '[]'::jsonb;
begin
  perform "better_supabase".emit_event('drive.node_purged', jsonb_build_object('organizationId', old."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects), 'drive-nodes/' || old."id"::text, (old."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'drive.node_purged',
    category => 'data',
    target_type => 'drive_node',
    record_id => old."id"::text,
    target_label => old."name",
    summary => 'deleted for good',
    tenant => (old."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', old."organization_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects)
  );
  return old;
end;
$$;
drop trigger if exists "bs_drive_node_purging" on "centrakit"."file_node";
create trigger "bs_drive_node_purging"
  before delete on "centrakit"."file_node"
  for each row execute function "better_supabase"."drive_node_purging"();

create or replace function "better_supabase"."drive_node_purged"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "centrakit"."file_node_grant" pg where pg."file_node_id" = old."id";
  delete from "centrakit"."subject_user_state" ps where ps."subject_type" = 'drive_node' and ps."subject_id" = old."id"::text;
  return null;
end;
$$;
drop trigger if exists "bs_drive_node_purged" on "centrakit"."file_node";
create trigger "bs_drive_node_purged"
  after delete on "centrakit"."file_node"
  for each row execute function "better_supabase"."drive_node_purged"();

create or replace function "better_supabase"."drive_star"(node uuid, starred boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not "better_supabase"."drive_can"(drive_star.node, 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  insert into "centrakit"."subject_user_state" ("subject_type", "subject_id", "user_id", "starred_at")
  values ('drive_node', drive_star.node::text, auth.uid(), case when drive_star.starred then now() end)
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "starred_at" = case when drive_star.starred then coalesce("centrakit"."subject_user_state"."starred_at", now()) end;
  return drive_star.starred;
end;
$$;
revoke execute on function "better_supabase"."drive_star"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."drive_star"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."drive_open"(node uuid)
returns jsonb
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
  select * into v_node from "centrakit"."file_node" x where x."id" = drive_open.node;
  if not found or auth.uid() is null or not "better_supabase"."drive_can"(v_node."id", 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  insert into "centrakit"."subject_user_state" ("subject_type", "subject_id", "user_id", "last_opened_at")
  values ('drive_node', v_node."id"::text, auth.uid(), now())
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "last_opened_at" = now();
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_open"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_open"(uuid) to authenticated, service_role;

-- The caller's starred nodes (recent false) or recently opened ones (true).
create or replace function "better_supabase"."drive_marked"(tenant uuid, recent boolean default false, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(t.node order by t.marked_at desc), '[]'::jsonb) from (
    select ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"))) || jsonb_build_object('starredAt', s."starred_at", 'openedAt', s."last_opened_at") as node,
      case when drive_marked.recent then s."last_opened_at" else s."starred_at" end as marked_at
    from "centrakit"."subject_user_state" s
    join "centrakit"."file_node" x on x."id"::text = s."subject_id"
    where s."subject_type" = 'drive_node' and s."user_id" = auth.uid()
      and x."organization_id" = drive_marked.tenant
      and case when drive_marked.recent then s."last_opened_at" else s."starred_at" end is not null
      and "better_supabase"."drive_can"(x."id", 'viewer')
    order by marked_at desc
    limit least(greatest(coalesce(drive_marked.page_size, 50), 1), 200)
  ) t
$$;
revoke execute on function "better_supabase"."drive_marked"(uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."drive_marked"(uuid, boolean, integer) to authenticated, service_role;

-- What a share link on a node opens: the node and, for a folder, its
-- children. node picks an item under the linked folder. For a file, file
-- carries the object for the server to sign a download URL with.
create or replace function "better_supabase"."drive_link"(token text, node uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link_id uuid;
  v_role text;
  v_root text;
  v_expires timestamptz;
  v_node "centrakit"."file_node"%rowtype;
begin
  select l."id", l."role", l."subject_id", l."expires_at"
    into v_link_id, v_role, v_root, v_expires
  from "centrakit"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(drive_link.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'drive_node'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now());
  if v_link_id is null or v_root !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  select * into v_node from "centrakit"."file_node" x where x."id" = coalesce(drive_link.node, v_root::uuid);
  if not found or not (v_root::uuid = any ("better_supabase"."drive_ancestors"(v_node."id"))) then
    raise exception 'this link does not open that item' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'link', jsonb_build_object('id', v_link_id, 'role', v_role, 'nodeId', v_root::uuid, 'expiresAt', v_expires),
    'node', "better_supabase"."drive_node_json"(v_node),
    'children', case when v_node."kind" = 'folder' then (
      select coalesce(jsonb_agg("better_supabase"."drive_node_json"(c.r) order by ((c.r)."kind" = 'folder') desc, lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
      from (select y as r from "centrakit"."file_node" y where y."parent_id" = v_node."id" order by (y."kind" = 'folder') desc, lower(y."name"), y."id" limit 500) c
    ) end
  );
end;
$$;
revoke all on function "better_supabase"."drive_link"(text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_link"(text, uuid) to anon, authenticated, service_role;

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
