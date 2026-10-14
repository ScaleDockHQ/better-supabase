import type { DriveKit } from "./drive-kit.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import {
  activeMembership,
  addExtraColumns,
  ensureCheck,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { CONFLICTS, READ_ONLY_GUARD, UUID_TEXT } from "./drive-kit.ts";

/** The tree, grants and sharing: the drive module. */
export function driveCoreSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    G,
    n,
    g,
    fn,
    read,
    create,
    manage,
    roles,
    conflict,
    extras,
    pathMode,
    ranked,
    typed,
    teamColumn,
    expiring,
    teams,
    tenant,
    m,
    rolesArray,
    rank,
    live,
    canRead,
    canWrite,
    canShare,
    notFound,
    forbidden,
    record,
    dataAudit,
    accessAudit,
    principalMatch,
    grantLive,
    principalType,
    principalId,
    nodeJson,
    withRole,
    orderBy,
    touch,
    insertColumns,
    insertValues,
    directGrant,
    siblings,
  } = kit;
  const tables = ctx.manages
    ? `create table if not exists ${T} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${n("parent")} uuid references ${T} (${n("id")}) on delete cascade,
  ${n("kind")} text not null check (${n("kind")} in ('folder', 'file')),
  ${n("name")} text not null check (length(btrim(${n("name")})) between 1 and 255 and ${n("name")} !~ '[/[:cntrl:]]'),
  ${n("attachment")} uuid,
  ${n("path")} text not null default '',
  ${n("rank")} text collate "C" not null default 'V' check (${n("rank")} ~ ${RANK_KEY_PATTERN}),
  ${n("deletedAt")} timestamptz,
  ${n("createdBy")} uuid default auth.uid(),
  ${n("createdAt")} timestamptz not null default now(),
  ${n("updatedAt")} timestamptz not null default now()
);${addExtraColumns(T, extras)}
create unique index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_sibling_name_idx`)} on ${T} (${n("tenant")}, coalesce(${n("parent")}, '00000000-0000-0000-0000-000000000000'::uuid), lower(${n("name")})) where ${n("deletedAt")} is null;
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_parent_idx`)} on ${T} (${n("tenant")}, ${n("parent")}, ${n("rank")});
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_parent_fk_idx`)} on ${T} (${n("parent")}) where ${n("parent")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_path_idx`)} on ${T} (${n("path")} text_pattern_ops);
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_attachment_idx`)} on ${T} (${n("attachment")});
${lockTable(T, { read: true })}

create table if not exists ${G} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("node")} uuid not null references ${T} (${n("id")}) on delete cascade,
  ${g("principalType")} text not null check (${g("principalType")} in ('user', 'team', 'role')),
  ${g("principalId")} text not null,
  ${g("role")} text not null,
  ${g("expiresAt")} timestamptz,
  ${g("createdBy")} uuid default auth.uid(),
  ${g("createdAt")} timestamptz not null default now(),
  unique (${g("node")}, ${g("principalType")}, ${g("principalId")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("grants").name}_principal_idx`)} on ${G} (${g("principalType")}, ${g("principalId")});
${ensureCheck(G, "bs_drive_grants_role", `${g("role")} = any (${rolesArray})`)}
${lockTable(G, { read: false })}
`
    : "";

  const ancestors = pathMode
    ? `  select string_to_array(btrim(x.${n("path")}, '/'), '/')::uuid[] from ${T} x where x.${n("id")} = drive_ancestors.node`
    : `  with recursive up (id, parent, depth) as (
    select x.${n("id")}, x.${n("parent")}, 0 from ${T} x where x.${n("id")} = drive_ancestors.node
    union all
    select x.${n("id")}, x.${n("parent")}, up.depth + 1 from ${T} x join up on x.${n("id")} = up.parent where up.depth < 256
  )
  select array_agg(up.id order by up.depth desc) from up`;
  const subtree = pathMode
    ? `  select x.${n("id")}, (length(x.${n("path")}) - length(replace(x.${n("path")}, '/', ''))) - (length(r.${n("path")}) - length(replace(r.${n("path")}, '/', '')))
  from ${T} r join ${T} x on x.${n("path")} like r.${n("path")} || '%'
  where r.${n("id")} = drive_subtree.node`
    : `  with recursive down (id, depth) as (
    select x.${n("id")}, 0 from ${T} x where x.${n("id")} = drive_subtree.node
    union all
    select x.${n("id")}, down.depth + 1 from ${T} x join down on x.${n("parent")} = down.id where down.depth < 256
  )
  select down.id, down.depth from down`;

  const pathTriggers = pathMode
    ? `
-- Keeps path, the ids from the root to the node, in step with parent, so
-- any writer (a function, the service role, a migration) stays consistent.
create or replace function ${fn("drive_node_path")}()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_path text;
  v_parent_tenant text;
  v_parent_kind text;
begin
  if new.${n("parent")} is null then
    new.${n("path")} := '/' || new.${n("id")}::text || '/';
    return new;
  end if;
  select x.${n("path")}, x.${n("tenant")}::text, x.${n("kind")} into v_parent_path, v_parent_tenant, v_parent_kind
  from ${T} x where x.${n("id")} = new.${n("parent")};
  if v_parent_path is null or v_parent_tenant is distinct from new.${n("tenant")}::text then
    ${fail("DRIVE_PARENT_NOT_FOUND", "the parent folder does not exist in this organization", "23503")}
  end if;
  if v_parent_kind <> 'folder' then
    ${fail("DRIVE_PARENT_NOT_FOLDER", "a file can't hold other items", "22023")}
  end if;
  if v_parent_path like '%/' || new.${n("id")}::text || '/%' then
    ${fail("DRIVE_MOVE_CYCLE", "a folder can't move into itself or its own subfolder", "22023")}
  end if;
  new.${n("path")} := v_parent_path || new.${n("id")}::text || '/';
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_path")} on ${T};
create trigger ${ctx.trigger("drive_node_path")}
  before insert or update of ${n("parent")} on ${T}
  for each row execute function ${fn("drive_node_path")}();

create or replace function ${fn("drive_node_moved")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update ${T} x set ${n("path")} = new.${n("path")} || substr(x.${n("path")}, length(old.${n("path")}) + 1)
  where x.${n("path")} like old.${n("path")} || '_%';
  return null;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_moved")} on ${T};
create trigger ${ctx.trigger("drive_node_moved")}
  after update of ${n("parent")} on ${T}
  for each row when (old.${n("parent")} is distinct from new.${n("parent")})
  execute function ${fn("drive_node_moved")}();
`
    : "";

  const grantColumns = typed
    ? `${g("tenant")}, ${g("node")}, ${g("principalType")}, ${g("principalId")}, ${g("role")}${expiring ? `, ${g("expiresAt")}` : ""}${ctx.has("grants", "createdBy") ? `, ${g("createdBy")}` : ""}`
    : `${g("tenant")}, ${g("node")}, ${g("user")}${teamColumn ? `, ${g("team")}` : ""}, ${g("role")}${expiring ? `, ${g("expiresAt")}` : ""}${ctx.has("grants", "createdBy") ? `, ${g("createdBy")}` : ""}`;
  // The team id comes from the teams table, so it has the adopted column's type.
  const teamValue =
    teams === undefined
      ? "null"
      : `case when v_type = 'team' then (select t.${teams.col("teams", "id")} from ${teams.table("teams")} t where t.${teams.col("teams", "id")}::text = drive_share.principal_id) end`;
  const grantValues = typed
    ? `v_node.${n("tenant")}, v_node.${n("id")}, v_type, drive_share.principal_id, drive_share.role${expiring ? ", drive_share.expires_at" : ""}${ctx.has("grants", "createdBy") ? ", auth.uid()" : ""}`
    : `v_node.${n("tenant")}, v_node.${n("id")}, case when v_type = 'user' then drive_share.principal_id::uuid end${teamColumn ? `, ${teamValue}` : ""}, drive_share.role${expiring ? ", drive_share.expires_at" : ""}${ctx.has("grants", "createdBy") ? ", auth.uid()" : ""}`;
  const samePrincipal = (alias: string): string =>
    `${principalType(alias)} = v_type and ${principalId(alias)} = drive_share.principal_id`;
  const principalTypes = typed
    ? "('user', 'team', 'role')"
    : teamColumn
      ? "('user', 'team')"
      : "('user')";
  const teamExists =
    teams === undefined
      ? "false"
      : `exists (select 1 from ${teams.table("teams")} t where t.${teams.col("teams", "id")}::text = drive_share.principal_id and t.${teams.col("teams", "tenant")} = v_node.${n("tenant")})`;

  const core = `${schemaPreamble(ctx)}
${tables}
-- The node's ancestors and itself, root first.
create or replace function ${fn("drive_ancestors")}(node uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
${ancestors}
$$;
revoke execute on function ${fn("drive_ancestors")}(uuid) from public, anon, authenticated;

-- The node and everything under it, with depth 0 for the node.
create or replace function ${fn("drive_subtree")}(node uuid)
returns table (node_id uuid, depth integer)
language sql
stable
security definer
set search_path = ''
as $$
${subtree}
$$;
revoke execute on function ${fn("drive_subtree")}(uuid) from public, anon, authenticated;

-- The caller's role on a node: the highest of the grants on it and its
-- ancestors that name them, one of their teams or their organization role${roles.member === undefined ? "" : `, and options.memberRole (${roles.member}) for every member with ${MODULE_PERMISSIONS.drive.read}`}. ${MODULE_PERMISSIONS.drive.manage} is ${roles.top} everywhere. Grants
-- need ${MODULE_PERMISSIONS.drive.read} in the node's organization too.
create or replace function ${fn("drive_role")}(node uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_tenant ${ctx.idType};
  v_rank integer;
begin
  if ${SERVICE_CALLER} then
    return ${sqlString(roles.top)};
  end if;
  select x.${n("tenant")} into v_tenant from ${T} x where x.${n("id")} = drive_role.node;
  if v_tenant is null or v_uid is null or not ${ctx.can("tenant", "v_tenant", read)} then
    return null;
  end if;
  if ${ctx.can("tenant", "v_tenant", manage)} then
    return ${sqlString(roles.top)};
  end if;
  select max(${rank(`dg.${g("role")}`)}) into v_rank from ${G} dg
  where dg.${g("node")} = any (${fn("drive_ancestors")}(drive_role.node))${grantLive("dg")}
    and ${principalMatch("dg", "v_uid", "v_tenant")};
  ${roles.member === undefined ? "" : `v_rank := greatest(coalesce(v_rank, 0), ${rank(sqlString(roles.member))});`}
  if coalesce(v_rank, 0) = 0 then
    return null;
  end if;
  return (${rolesArray})[v_rank];
end;
$$;
${userGrant(`${fn("drive_role")}(uuid)`)}

create or replace function ${fn("drive_can")}(node uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(${rank(`${fn("drive_role")}(drive_can.node)`)} >= ${rank("drive_can.role")} and ${rank("drive_can.role")} > 0, false)
$$;
${userGrant(`${fn("drive_can")}(uuid, text)`)}

create or replace function ${fn("drive_node_json")}(node ${T})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${nodeJson("")}
$$;
revoke execute on function ${fn("drive_node_json")}(${T}) from public, anon, authenticated;
${
  ctx.manages
    ? `
drop policy if exists "drive_nodes_read" on ${T};
create policy "drive_nodes_read" on ${T} for select to authenticated
  using (${n("deletedAt")} is null and ${canRead(n("id"))});
`
    : ""
}${pathTriggers}
create or replace function ${fn("drive_clean_name")}(name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text := btrim(drive_clean_name.name);
begin
  if v_name is null or v_name = '' or length(v_name) > 255 or v_name ~ '[/[:cntrl:]]' or v_name in ('.', '..') then
    ${fail("DRIVE_NAME_INVALID", "a name needs 1 to 255 characters without / or control characters", "22023")}
  end if;
  return v_name;
end;
$$;
revoke execute on function ${fn("drive_clean_name")}(text) from public, anon, authenticated;

create or replace function ${fn("drive_conflict")}(conflict text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if coalesce(drive_conflict.conflict, ${conflict}) not in (${CONFLICTS.map(sqlString).join(", ")}) then
    ${fail("DRIVE_CONFLICT_INVALID", `conflict must be ${CONFLICTS.join(", ")}`, "22023")}
  end if;
  return coalesce(drive_conflict.conflict, ${conflict});
end;
$$;
revoke execute on function ${fn("drive_conflict")}(text) from public, anon, authenticated;

-- Serializes name checks in one folder.
create or replace function ${fn("drive_lock_siblings")}(tenant ${ctx.idType}, parent uuid)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('better-supabase:drive:' || coalesce(drive_lock_siblings.parent::text, drive_lock_siblings.tenant::text), 0))
$$;
revoke execute on function ${fn("drive_lock_siblings")}(${ctx.idType}, uuid) from public, anon, authenticated;

-- name when no other live item in the folder has it (case-insensitively);
-- with conflict 'rename' the first free "name (2).ext"; otherwise
-- DRIVE_NAME_CONFLICT.
create or replace function ${fn("drive_free_name")}(tenant ${ctx.idType}, parent uuid, name text, exclude uuid, conflict text)
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
  perform ${fn("drive_lock_siblings")}(drive_free_name.tenant, drive_free_name.parent);
  loop
    exit when not exists (
      select 1 from ${T} x
      where ${siblings("x", "drive_free_name.tenant", "drive_free_name.parent")}
        and lower(x.${n("name")}) = lower(v_try) and x.${n("id")} is distinct from drive_free_name.exclude
    );
    if drive_free_name.conflict <> 'rename' then
      ${fail("DRIVE_NAME_CONFLICT", "another item in this folder has this name", "23505")}
    end if;
    if v_n = 1 then
      v_ext := coalesce(substring(drive_free_name.name from '.(\\.[^.]+)$'), '');
      v_base := left(drive_free_name.name, length(drive_free_name.name) - length(v_ext));
    end if;
    v_n := v_n + 1;
    v_try := v_base || ' (' || v_n::text || ')' || v_ext;
  end loop;
  return v_try;
end;
$$;
revoke execute on function ${fn("drive_free_name")}(${ctx.idType}, uuid, text, uuid, text) from public, anon, authenticated;

-- Whether the caller may create an item in parent: ${MODULE_PERMISSIONS.drive.create} at the
-- root, the write role in a folder.
create or replace function ${fn("drive_check_parent")}(tenant ${ctx.idType}, parent uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_parent ${T}%rowtype;
begin
  if ${SERVICE_CALLER} then
    return;
  end if;
  if drive_check_parent.parent is null then
    if not ${ctx.can("tenant", "drive_check_parent.tenant", create)} then
      ${forbidden("create items in this drive")}
    end if;
    return;
  end if;
  select * into v_parent from ${T} x
  where x.${n("id")} = drive_check_parent.parent and x.${n("tenant")} = drive_check_parent.tenant${live("x")};
  if not found or not ${canRead("v_parent." + n("id"))} then
    ${notFound}
  end if;
  if not ${canWrite("v_parent." + n("id"))} then
    ${forbidden("add items to this folder")}
  end if;
  if v_parent.${n("kind")} <> 'folder' then
    ${fail("DRIVE_PARENT_NOT_FOLDER", "a file can't hold other items", "22023")}
  end if;
end;
$$;
revoke execute on function ${fn("drive_check_parent")}(${ctx.idType}, uuid) from public, anon, authenticated;

-- It returns the node table's row type, which differs between managed and
-- adopted tables.
drop function if exists ${fn("drive_insert_node")}(${ctx.idType}, uuid, text, text, text, jsonb);
-- Inserts a node after its siblings. Extra columns come from fields, or
-- from the parent. At the root, the creator gets ${roles.top}.
create or replace function ${fn("drive_insert_node")}(tenant ${ctx.idType}, parent uuid, kind text, name text, conflict text, fields jsonb)
returns ${T}
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_parent ${T}%rowtype;
  v_fields ${T}%rowtype;
  v_name text;
  v_last text;
begin
  v_name := ${fn("drive_free_name")}(drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.name, null, drive_insert_node.conflict);
  select * into v_parent from ${T} x where x.${n("id")} = drive_insert_node.parent;
  v_fields := jsonb_populate_record(null::${T}, coalesce(drive_insert_node.fields, '{}'::jsonb));${
    ranked
      ? `
  select max(x.${n("rank")}) into v_last from ${T} x
  where ${siblings("x", "drive_insert_node.tenant", "drive_insert_node.parent")};`
      : ""
  }
  ${ctx.hook("before_drive_node_create", [
    [ctx.idType, "drive_insert_node.tenant"],
    ["uuid", "drive_insert_node.parent"],
    ["text", "drive_insert_node.kind"],
    ["text", "v_name"],
  ])}
  insert into ${T} (${insertColumns.join(", ")})
  values (${insertValues.join(", ")})
  returning * into v_node;
  if drive_insert_node.parent is null and auth.uid() is not null then
    ${directGrant("v_node", sqlString(roles.top), "auth.uid()")}
  end if;
  ${record("drive.node_created", "v_node", `, 'kind', v_node.${n("kind")}, 'name', v_node.${n("name")}, 'parentId', v_node.${n("parent")}`, dataAudit("v_node", "created"))}
  ${ctx.hook("after_drive_node_create", [["uuid", `v_node.${n("id")}`]])}
  return v_node;
end;
$$;
revoke execute on function ${fn("drive_insert_node")}(${ctx.idType}, uuid, text, text, text, jsonb) from public, anon, authenticated;

create or replace function ${fn("drive_create_folder")}(tenant ${ctx.idType}, parent uuid, name text, conflict text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := ${fn("drive_clean_name")}(drive_create_folder.name);
  v_conflict text := ${fn("drive_conflict")}(drive_create_folder.conflict);
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  perform ${fn("drive_check_parent")}(drive_create_folder.tenant, drive_create_folder.parent);
  v_node := ${fn("drive_insert_node")}(drive_create_folder.tenant, drive_create_folder.parent, 'folder', v_name,
    case when v_conflict = 'replace' then 'fail' else v_conflict end, drive_create_folder.fields);
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_create_folder")}(${ctx.idType}, uuid, text, text, jsonb)`)}
create or replace function ${fn("drive_get")}(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_get.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead("v_node." + n("id"))}) then
    ${notFound}
  end if;
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_get")}(uuid)`)}

-- A folder's children, folders first${ranked ? ", then in rank order" : ", then by name"}. Without parent, the
-- root items the caller can see.
create or replace function ${fn("drive_list")}(tenant ${ctx.idType}, parent uuid default null, page_size integer default 100, skip integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_list.tenant", read)}) then
    ${forbidden("read this organization's drive")}
  end if;
  if drive_list.parent is not null and not exists (
    select 1 from ${T} p where p.${n("id")} = drive_list.parent and p.${n("tenant")} = drive_list.tenant${live("p")}
      and (${SERVICE_CALLER} or ${canRead(`p.${n("id")}`)})
  ) then
    ${notFound}
  end if;
  return (
    select coalesce(jsonb_agg(${withRole("c.r")} order by ${orderBy("(c.r)")}), '[]'::jsonb)
    from (
      select x as r from ${T} x
      where ${siblings("x", "drive_list.tenant", "drive_list.parent")}
        and (drive_list.parent is not null or ${SERVICE_CALLER} or ${canRead(`x.${n("id")}`)})
      order by ${orderBy("x")}
      limit ${pageSize("drive_list.page_size", 100, 500)}
      offset greatest(coalesce(drive_list.skip, 0), 0)
    ) c
  );
end;
$$;
${userGrant(`${fn("drive_list")}(${ctx.idType}, uuid, integer, integer)`)}

-- Items shared with the caller directly, whose folder they can't open.
create or replace function ${fn("drive_shared")}(tenant ${ctx.idType}, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
  select coalesce(jsonb_agg(${withRole("c.r")} order by (c.r).${n("name")}, (c.r).${n("id")}), '[]'::jsonb)
  from (
    select x as r from ${T} x
    where x.${n("tenant")} = drive_shared.tenant${live("x")}
      and auth.uid() is not null
      and exists (
        select 1 from ${G} dg
        where dg.${g("node")} = x.${n("id")}${grantLive("dg")}
          and ${principalMatch("dg", "auth.uid()", "x." + n("tenant"))}
      )
      and (x.${n("parent")} is null or not ${canRead(`x.${n("parent")}`)})
      and ${canRead(`x.${n("id")}`)}
    order by x.${n("name")}, x.${n("id")}
    limit ${pageSize("drive_shared.page_size", 100, 500)}
  ) c
  );
end;
$$;
${userGrant(`${fn("drive_shared")}(${ctx.idType}, integer)`)}

-- The breadcrumb: the node's ancestors the caller can open, root first.
create or replace function ${fn("drive_path")}(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${canRead("drive_path.node")}) then
    ${notFound}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x.${n("id")}, 'name', x.${n("name")}, 'kind', x.${n("kind")}) order by p.ord), '[]'::jsonb)
    from unnest(${fn("drive_ancestors")}(drive_path.node)) with ordinality p (id, ord)
    join ${T} x on x.${n("id")} = p.id
    where ${SERVICE_CALLER} or ${canRead(`x.${n("id")}`)}
  );
end;
$$;
${userGrant(`${fn("drive_path")}(uuid)`)}

create or replace function ${fn("drive_rename")}(node uuid, name text, conflict text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_previous text;
  v_name text := ${fn("drive_clean_name")}(drive_rename.name);
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_rename.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead("v_node." + n("id"))}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite("v_node." + n("id"))}) then
    ${forbidden("rename this item")}
  end if;
  if v_name = v_node.${n("name")} then
    return ${withRole("v_node")};
  end if;
  v_name := ${fn("drive_free_name")}(v_node.${n("tenant")}, v_node.${n("parent")}, v_name, v_node.${n("id")},
    case when ${fn("drive_conflict")}(drive_rename.conflict) = 'rename' then 'rename' else 'fail' end);
  ${ctx.hook("before_drive_node_rename", [
    ["uuid", `v_node.${n("id")}`],
    ["text", "v_name"],
  ])}
  v_previous := v_node.${n("name")};
  update ${T} x set ${n("name")} = v_name${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  ${record("drive.node_renamed", "v_node", ", 'name', v_node." + n("name") + ", 'previousName', v_previous", dataAudit("v_node", "renamed"))}
  ${ctx.hook("after_drive_node_rename", [["uuid", `v_node.${n("id")}`]])}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_rename")}(uuid, text, text)`)}

-- Moves a node into parent (null for the root) at rank, after the last
-- item by default. Moving to the root needs the share role and
-- ${MODULE_PERMISSIONS.drive.create}, and keeps the mover's role as a grant.
create or replace function ${fn("drive_move")}(node uuid, parent uuid, rank text default null, conflict text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_previous uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_move.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead("v_node." + n("id"))}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite("v_node." + n("id"))}) then
    ${forbidden("move this item")}
  end if;
  ${
    ranked
      ? `if drive_move.rank is not null and drive_move.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("DRIVE_RANK_INVALID", "rank must be a key from rankBetween", "22023")}
  end if;`
      : ""
  }
  v_previous := v_node.${n("parent")};
  if drive_move.parent is null then
    if v_previous is not null and not (${SERVICE_CALLER} or (${canShare("v_node." + n("id"))} and ${ctx.can("tenant", `v_node.${n("tenant")}`, create)})) then
      ${forbidden("move this item to the top of the drive")}
    end if;
  else
    perform ${fn("drive_check_parent")}(v_node.${n("tenant")}, drive_move.parent);
    if v_node.${n("id")} = any (${fn("drive_ancestors")}(drive_move.parent)) then
      ${fail("DRIVE_MOVE_CYCLE", "a folder can't move into itself or its own subfolder", "22023")}
    end if;
  end if;
  ${ctx.hook("before_drive_node_move", [
    ["uuid", `v_node.${n("id")}`],
    ["uuid", "drive_move.parent"],
  ])}
  if v_previous is distinct from drive_move.parent then
    v_name := ${fn("drive_free_name")}(v_node.${n("tenant")}, drive_move.parent, v_node.${n("name")}, v_node.${n("id")},
      case when ${fn("drive_conflict")}(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := ${fn("drive_role")}(v_node.${n("id")});
      ${directGrant("v_node", "v_role", "auth.uid()")}
    end if;${
      ranked
        ? `
    if drive_move.rank is null then
      select max(x.${n("rank")}) into v_last from ${T} x
      where ${siblings("x", `v_node.${n("tenant")}`, "drive_move.parent")};
    end if;`
        : ""
    }
    update ${T} x set ${n("parent")} = drive_move.parent, ${n("name")} = v_name${ranked ? `, ${n("rank")} = coalesce(drive_move.rank, ${rankAfter("v_last")})` : ""}${touch}
    where x.${n("id")} = v_node.${n("id")}
    returning * into v_node;
    ${record("drive.node_moved", "v_node", ", 'parentId', v_node." + n("parent") + ", 'previousParentId', v_previous", dataAudit("v_node", "moved"))}
  ${
    ranked
      ? `elsif drive_move.rank is not null then
    update ${T} x set ${n("rank")} = drive_move.rank${touch}
    where x.${n("id")} = v_node.${n("id")}
    returning * into v_node;`
      : ""
  }
  end if;
  ${ctx.hook("after_drive_node_move", [["uuid", `v_node.${n("id")}`]])}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_move")}(uuid, uuid, text, text)`)}

-- Deletes a node and everything under it for good (the share role).
create or replace function ${fn("drive_delete")}(node uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_delete.node;
  if not found or not (${SERVICE_CALLER} or ${canRead("v_node." + n("id"))}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare("v_node." + n("id"))}) then
    ${forbidden("delete this item for good")}
  end if;
  delete from ${T} x where x.${n("id")} in (select s.node_id from ${fn("drive_subtree")}(v_node.${n("id")}) s);
  return true;
end;
$$;
${userGrant(`${fn("drive_delete")}(uuid)`)}

-- Grants role on a node (and what is under it) to a user, a team or an
-- organization role. Needs the share role, and no more than the caller's.
create or replace function ${fn("drive_share")}(node uuid, principal_type text, principal_id text, role text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_type text := lower(drive_share.principal_type);
  v_id uuid;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_share.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead("v_node." + n("id"))}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (${canShare("v_node." + n("id"))} and ${rank("drive_share.role")} <= ${rank(`${fn("drive_role")}(v_node.${n("id")})`)})) then
    ${forbidden("share this item with that role")}
  end if;
  if ${rank("drive_share.role")} = 0 then
    ${fail("DRIVE_ROLE_UNKNOWN", `role must be one of ${roles.all.join(", ")}`, "22023")}
  end if;
  if v_type not in ${principalTypes} or drive_share.principal_id is null then
    ${fail("DRIVE_PRINCIPAL_INVALID", "principal_type must be user, team or role", "22023")}
  end if;
  if (v_type = 'user' and (drive_share.principal_id !~ ${UUID_TEXT} or not exists (
      select 1 from ${tenant.table("memberships")} mu
      where mu.${m("tenant")} = v_node.${n("tenant")} and mu.${m("user")} = drive_share.principal_id::uuid${activeMembership(ctx, "mu")}
    )))
    or (v_type = 'team' and not ${teamExists}) then
    ${fail("DRIVE_PRINCIPAL_NOT_FOUND", "no member or team of this organization has that id", "P0002")}
  end if;
  ${ctx.hook("before_drive_node_share", [
    ["uuid", `v_node.${n("id")}`],
    ["text", "v_type"],
    ["text", "drive_share.principal_id"],
    ["text", "drive_share.role"],
  ])}
  delete from ${G} dg where dg.${g("node")} = v_node.${n("id")} and ${samePrincipal("dg")};
  insert into ${G} (${grantColumns})
  values (${grantValues})
  returning ${g("id")} into v_id;
  ${record("drive.node_shared", "v_node", ", 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role", accessAudit("v_node", "shared"))}
  ${ctx.hook("after_drive_node_share", [
    ["uuid", `v_node.${n("id")}`],
    ["uuid", "v_id"],
  ])}
  return jsonb_build_object('id', v_id, 'nodeId', v_node.${n("id")}, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role, 'expiresAt', drive_share.expires_at, 'inherited', false);
end;
$$;
${userGrant(`${fn("drive_share")}(uuid, text, text, text, timestamptz)`)}

create or replace function ${fn("drive_unshare")}(node uuid, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_type text := lower(drive_unshare.principal_type);
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_unshare.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead("v_node." + n("id"))}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare("v_node." + n("id"))}) then
    ${forbidden("change who this item is shared with")}
  end if;
  delete from ${G} dg where dg.${g("node")} = v_node.${n("id")}
    and ${principalType("dg")} = v_type and ${principalId("dg")} = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  ${record("drive.node_unshared", "v_node", ", 'principalType', v_type, 'principalId', drive_unshare.principal_id", accessAudit("v_node", "unshared"))}
  return true;
end;
$$;
${userGrant(`${fn("drive_unshare")}(uuid, text, text)`)}

-- Who has access: the grants on the node and, marked inherited, on its
-- ancestors.
create or replace function ${fn("drive_grants")}(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${canRead("drive_grants.node")}) then
    ${notFound}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', dg.${g("id")}, 'nodeId', dg.${g("node")}, 'principalType', ${principalType("dg")}, 'principalId', ${principalId("dg")}, 'role', dg.${g("role")}, 'expiresAt', ${expiring ? `dg.${g("expiresAt")}` : "null"}, 'inherited', dg.${g("node")} <> drive_grants.node) order by dg.${g("node")} = drive_grants.node, ${rank(`dg.${g("role")}`)} desc, dg.${g("id")}), '[]'::jsonb)
    from ${G} dg
    where dg.${g("node")} = any (${fn("drive_ancestors")}(drive_grants.node))${grantLive("dg")}
  );
end;
$$;
${userGrant(`${fn("drive_grants")}(uuid)`)}
`;

  return core;
}
