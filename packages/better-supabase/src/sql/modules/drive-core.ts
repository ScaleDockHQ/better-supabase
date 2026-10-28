import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import {
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { driveDrivesSql } from "./drive-drives.ts";
import { driveGrantsSql } from "./drive-grants.ts";
import { driveHoldsSql } from "./drive-holds.ts";
import { CONFLICTS, READ_ONLY_GUARD } from "./drive-kit.ts";
import { driveTablesSql, driveTriggersSql } from "./drive-tables.ts";
import { OPERATIONS } from "./permissions-model.ts";

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
    pathMode,
    ranked,
    drives,
    D,
    DG,
    d,
    dg,
    readOnly,
    held,
    driveGrantLive,
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
    principalMatch,
    drivePrincipalMatch,
    grantLive,
    nodeJson,
    withRole,
    orderBy,
    touch,
    insertColumns,
    insertValues,
    directGrant,
    siblings,
    nodeRole,
    driveRole,
    readPolicy,
    driveColumn,
  } = kit;

  const tables = driveTablesSql(kit);

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

-- Whether the node, a folder above it or anything under it is under a legal
-- hold, which purge has to respect.
create or replace function ${fn("drive_node_held")}(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${T} h
    where (h.${n("id")} in (select s.node_id from ${fn("drive_subtree")}(drive_node_held.node) s)
        or h.${n("id")} = any (${fn("drive_ancestors")}(drive_node_held.node)))
      and ${held("h")}
  )
$$;
${userGrant(`${fn("drive_node_held")}(uuid)`)}
${
  drives
    ? `
-- The caller's role on a drive: ${driveRole === undefined ? `${OPERATIONS["drive.manage"]} is ${roles.top}, the owner holds ${roles.top} too${roles.member === undefined ? "" : `, options.memberRole (${roles.member}) covers every member with ${OPERATIONS["drive.read"]}`}, and a grant that names them or one of their teams adds its role` : `options.roleFunctions.drive (${driveRole.label}) decides it`}. ${OPERATIONS["drive.read"]} in the drive's organization is required.
create or replace function ${fn("drive_drive_role")}(drive uuid)
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
  v_owner uuid;
  v_rank integer;
begin
  if ${SERVICE_CALLER} then
    return ${sqlString(roles.top)};
  end if;
  select d.${d("tenant")}, d.${d("owner")} into v_tenant, v_owner from ${D} d where d.${d("id")} = drive_drive_role.drive;
  if v_tenant is null or v_uid is null or not ${ctx.can("tenant", "v_tenant", read)} then
    return null;
  end if;${driveRole === undefined ? "" : `\n  return (select r from (select ${driveRole.role("drive_drive_role.drive", "v_uid")}) x(r) where r = any (${rolesArray}));`}
  if ${ctx.can("tenant", "v_tenant", manage)} or v_owner = v_uid then
    return ${sqlString(roles.top)};
  end if;
  select max(${rank(`dg.${dg("role")}`)}) into v_rank from ${DG} dg
  where dg.${dg("drive")} = drive_drive_role.drive${driveGrantLive("dg")}
    and ${drivePrincipalMatch("dg", "v_uid", "v_tenant")};
  ${roles.member === undefined ? "" : `v_rank := greatest(coalesce(v_rank, 0), ${rank(sqlString(roles.member))});`}
  if coalesce(v_rank, 0) = 0 then
    return null;
  end if;
  return (${rolesArray})[v_rank];
end;
$$;
${userGrant(`${fn("drive_drive_role")}(uuid)`)}

create or replace function ${fn("drive_drive_can")}(drive uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(${rank(`${fn("drive_drive_role")}(drive_drive_can.drive)`)} >= ${rank("drive_drive_can.role")} and ${rank("drive_drive_can.role")} > 0, false)
$$;
${userGrant(`${fn("drive_drive_can")}(uuid, text)`)}

-- The drives drive_drive_can(drive, ${sqlString(roles.read)}) is true for, as one set, for the
-- drives read policy.
create or replace function ${fn("drive_drive_readable_ids")}()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
${
  driveRole === undefined
    ? `  select d.${d("id")} from ${D} d
  where ${SERVICE_CALLER}
    or (auth.uid() is not null
      and d.${d("tenant")} in (select ${ctx.scope.ids(read)})
      and (d.${d("tenant")} in (select ${ctx.scope.ids(manage)}) or d.${d("owner")} = auth.uid()${roles.member === undefined ? "" : ` or ${rank(sqlString(roles.member))} >= ${rank(sqlString(roles.read))}`}))
  union
  select dg.${dg("drive")} from ${DG} dg
  join ${D} d on d.${d("id")} = dg.${dg("drive")}
  where auth.uid() is not null${driveGrantLive("dg")}
    and ${rank(`dg.${dg("role")}`)} >= ${rank(sqlString(roles.read))}
    and ${rank(sqlString(roles.read))} > 0
    and d.${d("tenant")} in (select ${ctx.scope.ids(read)})
    and ${drivePrincipalMatch("dg", "auth.uid()", `d.${d("tenant")}`)}`
    : `  select d.${d("id")} from ${D} d
  where ${SERVICE_CALLER}
    or (auth.uid() is not null
      and d.${d("tenant")} in (select ${ctx.scope.ids(read)})
      and (${driveRole.role(`d.${d("id")}`, "auth.uid()")}) = any (${rolesArray}))`
}
$$;
${userGrant(`${fn("drive_drive_readable_ids")}()`)}
`
    : ""
}

-- The caller's role on a node: ${nodeRole === undefined ? `the highest of the grants on it and its ancestors that name them, one of their teams or their organization role${roles.member === undefined ? "" : `, and options.memberRole (${roles.member}) for every member with ${OPERATIONS["drive.read"]}`}. ${OPERATIONS["drive.manage"]} is ${roles.top} everywhere` : `options.roleFunctions.node (${nodeRole.label}) decides it`}. Grants
-- need ${OPERATIONS["drive.read"]} in the node's organization too.
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
  ${drives ? "v_drive uuid;" : ""}
  v_rank integer;
begin
  if ${SERVICE_CALLER} then
    return ${sqlString(roles.top)};
  end if;
  select x.${n("tenant")}${drives ? `, x.${n("drive")}` : ""} into v_tenant${drives ? ", v_drive" : ""} from ${T} x where x.${n("id")} = drive_role.node;
  if v_tenant is null or v_uid is null or not ${ctx.can("tenant", "v_tenant", read)} then
    return null;
  end if;${nodeRole === undefined ? "" : `\n  return (select r from (select ${nodeRole.role("drive_role.node", "v_uid")}) x(r) where r = any (${rolesArray}));`}
  if ${ctx.can("tenant", "v_tenant", manage)} then
    return ${sqlString(roles.top)};
  end if;
  ${drives ? `v_rank := ${rank(`${fn("drive_drive_role")}(v_drive)`)};` : ""}
  select greatest(coalesce(v_rank, 0), coalesce(max(${rank(`dg.${g("role")}`)}), 0)) into v_rank from ${G} dg
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

-- Whether the caller may change the node: the write role, and not a read-only
-- mirror of an external account.
create or replace function ${fn("drive_node_writable")}(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select ${canWrite(`x.${n("id")}`)} and not ${readOnly("x")}
    from ${T} x where x.${n("id")} = drive_node_writable.node
  ), false)
$$;
${userGrant(`${fn("drive_node_writable")}(uuid)`)}

-- The nodes drive_can(node, ${sqlString(roles.read)}) is true for, as one set, so the read policy
-- runs it once per statement instead of once per row: every node in an organization
-- the caller manages${roles.member === undefined ? "" : " or reads with options.memberRole"}, and the subtree of each grant that names them.
create or replace function ${fn("drive_readable_ids")}()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
${
  nodeRole === undefined
    ? `  select x.${n("id")} from ${T} x
  where ${SERVICE_CALLER}
    or (auth.uid() is not null
      and x.${n("tenant")} in (select ${ctx.scope.ids(read)})
      and (x.${n("tenant")} in (select ${ctx.scope.ids(manage)})${roles.member === undefined ? "" : ` or ${rank(sqlString(roles.member))} >= ${rank(sqlString(roles.read))}`}))
  union
  select s.node_id from ${G} dg
  cross join lateral ${fn("drive_subtree")}(dg.${g("node")}) s
  join ${T} x on x.${n("id")} = s.node_id
  where auth.uid() is not null${grantLive("dg")}
    and ${rank(`dg.${g("role")}`)} >= ${rank(sqlString(roles.read))}
    and ${rank(sqlString(roles.read))} > 0
    and x.${n("tenant")} in (select ${ctx.scope.ids(read)})
    and ${principalMatch("dg", "auth.uid()", `x.${n("tenant")}`)}${
      drives
        ? `
  union
  select x.${n("id")} from ${T} x
  join ${D} d on d.${d("id")} = x.${n("drive")}
  where auth.uid() is not null
    and x.${n("tenant")} in (select ${ctx.scope.ids(read)})
    and (x.${n("tenant")} in (select ${ctx.scope.ids(manage)}) or d.${d("owner")} = auth.uid()${roles.member === undefined ? "" : ` or ${rank(sqlString(roles.member))} >= ${rank(sqlString(roles.read))}`})
  union
  select x.${n("id")} from ${T} x
  join ${DG} dg on dg.${dg("drive")} = x.${n("drive")}
  where auth.uid() is not null${driveGrantLive("dg")}
    and ${rank(`dg.${dg("role")}`)} >= ${rank(sqlString(roles.read))}
    and ${rank(sqlString(roles.read))} > 0
    and x.${n("tenant")} in (select ${ctx.scope.ids(read)})
    and ${drivePrincipalMatch("dg", "auth.uid()", `x.${n("tenant")}`)}`
        : ""
    }`
    : `  select x.${n("id")} from ${T} x
  where ${SERVICE_CALLER}
    or (auth.uid() is not null
      and x.${n("tenant")} in (select ${ctx.scope.ids(read)})
      and (${nodeRole.role(`x.${n("id")}`, "auth.uid()")}) = any (${rolesArray}))`
}
$$;
${userGrant(`${fn("drive_readable_ids")}()`)}

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
  ctx.manages && readPolicy
    ? `
${renderPolicy(makePolicy({ table: T, name: ctx.naming.rename("drive_nodes_read"), command: "select", roles: ["authenticated"], using: `${ctx.has("nodes", "deletedAt") ? `${n("deletedAt")} is null and ` : ""}${n("id")} in (select ${fn("drive_readable_ids")}())` }), { drop: true, target: T })}
`
    : ""
}${
    readPolicy && drives && D !== undefined && ctx.owns("drives")
      ? `
${renderPolicy(makePolicy({ table: D, name: ctx.naming.rename("drive_drives_read"), command: "select", roles: ["authenticated"], using: `${d("id")} in (select ${fn("drive_drive_readable_ids")}())` }), { drop: true, target: D })}
`
      : ""
  }${
    readPolicy && drives && DG !== undefined && ctx.owns("driveGrants")
      ? `
${renderPolicy(makePolicy({ table: DG, name: ctx.naming.rename("drive_drive_grants_read"), command: "select", roles: ["authenticated"], using: `${dg("drive")} in (select ${fn("drive_drive_readable_ids")}())` }), { drop: true, target: DG })}
`
      : ""
  }${driveTriggersSql(kit)}
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

-- Serializes name checks in one folder${drives ? " of one drive" : ""}.
create or replace function ${fn("drive_lock_siblings")}(tenant ${ctx.idType}, drive uuid, parent uuid)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('better-supabase:drive:' || coalesce(drive_lock_siblings.parent::text, drive_lock_siblings.tenant::text) || ':' || coalesce(drive_lock_siblings.drive::text, ''), 0))
$$;
revoke execute on function ${fn("drive_lock_siblings")}(${ctx.idType}, uuid, uuid) from public, anon, authenticated;

-- name when no other live item in the folder has it (case-insensitively);
-- with conflict 'rename' the first free "name (2).ext"; otherwise
-- DRIVE_NAME_CONFLICT.
create or replace function ${fn("drive_free_name")}(tenant ${ctx.idType}, drive uuid, parent uuid, name text, exclude uuid, conflict text)
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
  perform ${fn("drive_lock_siblings")}(drive_free_name.tenant, drive_free_name.drive, drive_free_name.parent);
  loop
    exit when not exists (
      select 1 from ${T} x
      where ${siblings("x", "drive_free_name.tenant", "drive_free_name.parent", "drive_free_name.drive")}
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
revoke execute on function ${fn("drive_free_name")}(${ctx.idType}, uuid, uuid, text, uuid, text) from public, anon, authenticated;

-- Whether the caller may create an item in parent: ${OPERATIONS["drive.create"]} and the
-- drive's write role at the root, the write role in a folder. External
-- mirrors are read-only.
create or replace function ${fn("drive_check_parent")}(tenant ${ctx.idType}, parent uuid, drive uuid)
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
    end if;${
      drives
        ? `
    if drive_check_parent.drive is null then
      ${fail("DRIVE_REQUIRED", "a top-level item needs a drive", "22023")}
    end if;
    if not exists (select 1 from ${D} d where d.${d("id")} = drive_check_parent.drive and d.${d("tenant")} = drive_check_parent.tenant) then
      ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
    end if;
    if not ${fn("drive_drive_can")}(drive_check_parent.drive, ${sqlString(roles.write)}) then
      ${forbidden("add items to this drive")}
    end if;
    if exists (select 1 from ${D} d where d.${d("id")} = drive_check_parent.drive and d.${d("connection")} is not null) then
      ${fail("DRIVE_READ_ONLY", "this drive mirrors an external account and is read-only", "42501")}
    end if;`
        : ""
    }
    return;
  end if;
  select * into v_parent from ${T} x
  where x.${n("id")} = drive_check_parent.parent and x.${n("tenant")} = drive_check_parent.tenant${live("x")};
  if not found or not ${canRead(`v_parent.${n("id")}`)} then
    ${notFound}
  end if;
  if not ${canWrite(`v_parent.${n("id")}`)} then
    ${forbidden("add items to this folder")}
  end if;
  if v_parent.${n("kind")} <> 'folder' then
    ${fail("DRIVE_PARENT_NOT_FOLDER", "a file can't hold other items", "22023")}
  end if;
  if ${readOnly("v_parent")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
end;
$$;
revoke execute on function ${fn("drive_check_parent")}(${ctx.idType}, uuid, uuid) from public, anon, authenticated;

-- It returns the node table's row type, which differs between managed and
-- adopted tables.
drop function if exists ${fn("drive_insert_node")}(${ctx.idType}, uuid, uuid, text, text, text, jsonb);
drop function if exists ${fn("drive_insert_node")}(${ctx.idType}, uuid, text, text, text, jsonb);
-- Inserts a node after its siblings. Extra columns come from fields, or
-- from the parent.${nodeRole === undefined ? ` At the root, the creator gets ${roles.top}.` : ""}
create or replace function ${fn("drive_insert_node")}(tenant ${ctx.idType}, drive uuid, parent uuid, kind text, name text, conflict text, fields jsonb)
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
  v_drive uuid := drive_insert_node.drive;
  v_name text;
  v_last text;
begin
  select * into v_parent from ${T} x where x.${n("id")} = drive_insert_node.parent;${
    driveColumn
      ? `
  if drive_insert_node.parent is not null then
    v_drive := v_parent.${n("drive")};
  end if;`
      : ""
  }
  v_name := ${fn("drive_free_name")}(drive_insert_node.tenant, v_drive, drive_insert_node.parent, drive_insert_node.name, null, drive_insert_node.conflict);
  v_fields := jsonb_populate_record(null::${T}, coalesce(drive_insert_node.fields, '{}'::jsonb));${
    ranked
      ? `
  select max(x.${n("rank")}) into v_last from ${T} x
  where ${siblings("x", "drive_insert_node.tenant", "drive_insert_node.parent", "v_drive")};`
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
${
  nodeRole === undefined
    ? `  if drive_insert_node.parent is null and auth.uid() is not null then
    ${directGrant("v_node", sqlString(roles.top), "auth.uid()")}
  end if;
`
    : ""
}  ${record("drive.node_created", "v_node", `, 'kind', v_node.${n("kind")}, 'name', v_node.${n("name")}, 'parentId', v_node.${n("parent")}`, dataAudit("v_node", "created"))}
  ${ctx.hook("after_drive_node_create", [["uuid", `v_node.${n("id")}`]])}
  return v_node;
end;
$$;
revoke execute on function ${fn("drive_insert_node")}(${ctx.idType}, uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;

create or replace function ${fn("drive_create_folder")}(tenant ${ctx.idType}, parent uuid, name text, conflict text default null, fields jsonb default null, drive uuid default null)
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
  perform ${fn("drive_check_parent")}(drive_create_folder.tenant, drive_create_folder.parent, drive_create_folder.drive);
  v_node := ${fn("drive_insert_node")}(drive_create_folder.tenant, drive_create_folder.drive, drive_create_folder.parent, 'folder', v_name,
    case when v_conflict = 'replace' then 'fail' else v_conflict end, drive_create_folder.fields);
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_create_folder")}(${ctx.idType}, uuid, text, text, jsonb, uuid)`)}
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
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_get")}(uuid)`)}

-- A folder's children, folders first${ranked ? ", then in rank order" : ", then by name"}. Without parent, the
-- root items of drive, or of every drive the caller can read.
create or replace function ${fn("drive_list")}(tenant ${ctx.idType}, parent uuid default null, page_size integer default 100, skip integer default 0, drive uuid default null)
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
  end if;${
    drives
      ? `
  if drive_list.parent is null and drive_list.drive is not null and not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_list.drive, ${sqlString(roles.read)})) then
    ${notFound}
  end if;`
      : ""
  }
  return (
    select coalesce(jsonb_agg(${withRole("c.r")} order by ${orderBy("(c.r)")}), '[]'::jsonb)
    from (
      select x as r from ${T} x
      where x.${n("tenant")} = drive_list.tenant and x.${n("parent")} is not distinct from drive_list.parent${live("x")}${
        drives
          ? `
        and (drive_list.drive is null or x.${n("drive")} = drive_list.drive)`
          : ""
      }
        and (drive_list.parent is not null or ${SERVICE_CALLER} or ${canRead(`x.${n("id")}`)})
      order by ${orderBy("x")}
      limit ${pageSize("drive_list.page_size", 100, 500)}
      offset greatest(coalesce(drive_list.skip, 0), 0)
    ) c
  );
end;
$$;
${userGrant(`${fn("drive_list")}(${ctx.idType}, uuid, integer, integer, uuid)`)}

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
          and ${principalMatch("dg", "auth.uid()", `x.${n("tenant")}`)}
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
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("rename this item")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if v_name = v_node.${n("name")} then
    return ${withRole("v_node")};
  end if;
  v_name := ${fn("drive_free_name")}(v_node.${n("tenant")}, ${driveColumn ? `v_node.${n("drive")}` : "null"}, v_node.${n("parent")}, v_name, v_node.${n("id")},
    case when ${fn("drive_conflict")}(drive_rename.conflict) = 'rename' then 'rename' else 'fail' end);
  ${ctx.hook("before_drive_node_rename", [
    ["uuid", `v_node.${n("id")}`],
    ["text", "v_name"],
  ])}
  v_previous := v_node.${n("name")};
  update ${T} x set ${n("name")} = v_name${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  ${record("drive.node_renamed", "v_node", `, 'name', v_node.${n("name")}, 'previousName', v_previous`, dataAudit("v_node", "renamed"))}
  ${ctx.hook("after_drive_node_rename", [["uuid", `v_node.${n("id")}`]])}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_rename")}(uuid, text, text)`)}

-- Moves a node into parent (null for the root) at rank, after the last
-- item by default${drives ? ", possibly into another drive" : ""}. Moving to the root needs the share role and
-- ${OPERATIONS["drive.create"]}, and keeps the mover's role as a grant.
create or replace function ${fn("drive_move")}(node uuid, parent uuid, rank text default null, conflict text default null, drive uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_previous uuid;
  v_target uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_move.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("move this item")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  ${
    ranked
      ? `if drive_move.rank is not null and drive_move.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("DRIVE_RANK_INVALID", "rank must be a key from rankBetween", "22023")}
  end if;`
      : ""
  }
  v_previous := v_node.${n("parent")};
  if drive_move.parent is null then${
    driveColumn
      ? `
    v_target := coalesce(drive_move.drive, v_node.${n("drive")});`
      : ""
  }${
    drives
      ? `
    if v_target is null then
      ${fail("DRIVE_REQUIRED", "a top-level item needs a drive", "22023")}
    end if;
    if not exists (select 1 from ${D} d where d.${d("id")} = v_target and d.${d("tenant")} = v_node.${n("tenant")}) then
      ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
    end if;
    if exists (select 1 from ${D} d where d.${d("id")} = v_target and d.${d("connection")} is not null) then
      ${fail("DRIVE_READ_ONLY", "this drive mirrors an external account and is read-only", "42501")}
    end if;
    if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(v_target, ${sqlString(roles.write)})) then
      ${forbidden("add items to this drive")}
    end if;
    if (v_previous is not null or v_target is distinct from v_node.${n("drive")})
      and not (${SERVICE_CALLER} or (${canShare(`v_node.${n("id")}`)} and ${ctx.can("tenant", `v_node.${n("tenant")}`, create)})) then
      ${forbidden("move this item to the top of the drive")}
    end if;`
      : `
    if v_previous is not null and not (${SERVICE_CALLER} or (${canShare(`v_node.${n("id")}`)} and ${ctx.can("tenant", `v_node.${n("tenant")}`, create)})) then
      ${forbidden("move this item to the top of the drive")}
    end if;`
  }
  else
    perform ${fn("drive_check_parent")}(v_node.${n("tenant")}, drive_move.parent, drive_move.drive);
    if v_node.${n("id")} = any (${fn("drive_ancestors")}(drive_move.parent)) then
      ${fail("DRIVE_MOVE_CYCLE", "a folder can't move into itself or its own subfolder", "22023")}
    end if;${
      driveColumn
        ? `
    select x.${n("drive")} into v_target from ${T} x where x.${n("id")} = drive_move.parent;`
        : ""
    }${
      drives
        ? `
    if v_target is distinct from v_node.${n("drive")} and not (${SERVICE_CALLER} or ${canShare(`v_node.${n("id")}`)}) then
      ${forbidden("move this item to another drive")}
    end if;`
        : ""
    }
  end if;
  ${ctx.hook("before_drive_node_move", [
    ["uuid", `v_node.${n("id")}`],
    ["uuid", "drive_move.parent"],
  ])}
  if v_previous is distinct from drive_move.parent${driveColumn ? ` or v_target is distinct from v_node.${n("drive")}` : ""} then
    v_name := ${fn("drive_free_name")}(v_node.${n("tenant")}, v_target, drive_move.parent, v_node.${n("name")}, v_node.${n("id")},
      case when ${fn("drive_conflict")}(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := ${fn("drive_role")}(v_node.${n("id")});
      ${directGrant("v_node", "v_role", "auth.uid()")}
    end if;${
      ranked
        ? `
    if drive_move.rank is null then
      select max(x.${n("rank")}) into v_last from ${T} x
      where ${siblings("x", `v_node.${n("tenant")}`, "drive_move.parent", "v_target")};
    end if;`
        : ""
    }
    update ${T} x set ${n("parent")} = drive_move.parent, ${n("name")} = v_name${driveColumn ? `, ${n("drive")} = v_target` : ""}${ranked ? `, ${n("rank")} = coalesce(drive_move.rank, ${rankAfter("v_last")})` : ""}${touch}
    where x.${n("id")} = v_node.${n("id")}
    returning * into v_node;
    ${record("drive.node_moved", "v_node", `, 'parentId', v_node.${n("parent")}, 'previousParentId', v_previous`, dataAudit("v_node", "moved"))}
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
${userGrant(`${fn("drive_move")}(uuid, uuid, text, text, uuid)`)}

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
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare(`v_node.${n("id")}`)}) then
    ${forbidden("delete this item for good")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if ${fn("drive_node_held")}(v_node.${n("id")}) then
    ${fail("DRIVE_HELD", "this item is under a legal hold", "42501")}
  end if;
  delete from ${T} x where x.${n("id")} in (select s.node_id from ${fn("drive_subtree")}(v_node.${n("id")}) s);
  return true;
end;
$$;
${userGrant(`${fn("drive_delete")}(uuid)`)}

${driveGrantsSql(kit)}
${driveHoldsSql(kit)}
${driveDrivesSql(kit)}
`;

  return core;
}
