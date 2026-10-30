import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import {
  activeMembership,
  fail,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { UUID_TEXT } from "./drive-kit.ts";

/** Sharing a node and listing who has access to it. */
export function driveGrantsSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    G,
    n,
    g,
    fn,
    roles,
    expiring,
    typed,
    teamColumn,
    teams,
    tenant,
    m,
    rank,
    live,
    readOnly,
    canRead,
    canShare,
    notFound,
    forbidden,
    record,
    accessAudit,
    principalType,
    principalId,
    grantLive,
  } = kit;

  const grantColumns = typed
    ? `${g("tenant")}, ${g("node")}, ${g("principalType")}, ${g("principalId")}, ${g("role")}${expiring ? `, ${g("expiresAt")}` : ""}${ctx.has("grants", "createdBy") ? `, ${g("createdBy")}` : ""}`
    : `${g("tenant")}, ${g("node")}, ${g("user")}${teamColumn ? `, ${g("team")}` : ""}, ${g("role")}${expiring ? `, ${g("expiresAt")}` : ""}${ctx.has("grants", "createdBy") ? `, ${g("createdBy")}` : ""}`;

  // The team id comes from the teams table, so it has the adopted column's type.
  const teamValue =
    teams === undefined
      ? "null"
      : `case when v_type = 'team' then (select t.${teams.col("teams", "id")} from ${teams.table("teams")} t where t.${teams.col("teams", "id")}::text = drive_share.principal_id) end`;

  const grantValues = typed
    ? `v_node.${n("tenant")}, v_node.${n("id")}, v_type, drive_share.principal_id, ${ctx.cast("grants", "role", "drive_share.role")}${expiring ? ", drive_share.expires_at" : ""}${ctx.has("grants", "createdBy") ? ", auth.uid()" : ""}`
    : `v_node.${n("tenant")}, v_node.${n("id")}, case when v_type = 'user' then drive_share.principal_id::uuid end${teamColumn ? `, ${teamValue}` : ""}, ${ctx.cast("grants", "role", "drive_share.role")}${expiring ? ", drive_share.expires_at" : ""}${ctx.has("grants", "createdBy") ? ", auth.uid()" : ""}`;

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

  return `
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
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (${canShare(`v_node.${n("id")}`)} and ${rank("drive_share.role")} <= ${rank(`${fn("drive_role")}(v_node.${n("id")})`)})) then
    ${forbidden("share this item with that role")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if ${rank("drive_share.role")} = 0${roles.upload === undefined ? "" : ` and drive_share.role is distinct from ${sqlString(roles.upload)}`} then
    ${fail("DRIVE_ROLE_UNKNOWN", `role must be one of ${[...roles.all, ...(roles.upload === undefined ? [] : [roles.upload])].join(", ")}`, "22023")}
  end if;${
    roles.upload === undefined
      ? ""
      : `
  if drive_share.role = ${sqlString(roles.upload)} and v_node.${n("kind")} <> 'folder' then
    raise exception 'the upload role is for folders' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN', detail = '{"reason":"upload role is for folders"}';
  end if;`
  }
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
  ${record("drive_node.shared", "v_node", ", 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role", accessAudit("v_node", "shared"))}
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
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare(`v_node.${n("id")}`)}) then
    ${forbidden("change who this item is shared with")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  delete from ${G} dg where dg.${g("node")} = v_node.${n("id")}
    and ${principalType("dg")} = v_type and ${principalId("dg")} = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  ${record("drive_node.unshared", "v_node", ", 'principalType', v_type, 'principalId', drive_unshare.principal_id", accessAudit("v_node", "unshared"))}
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
}
