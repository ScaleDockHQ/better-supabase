import type { BlockSqlContext } from "../context.ts";
import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import {
  activeMembership,
  fail,
  SERVICE_CALLER,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import { driveRoles, UUID_TEXT, usable } from "./drive-kit.ts";
import { driveRoleFunctions } from "./drive-roles.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The sharing policy an organization falls back to without a setting. */
const SHARING_DEFAULT = `'{"guests": true, "links": "anyone"}'::jsonb`;

/**
 * Access requests on nodes, moving a leaving member's items to someone else,
 * and the organization's sharing policy.
 */
export function driveOwnershipSql(kit: DriveKit): string {
  return `${grantAccessSql(kit)}${transferSql(kit)}${sharingSql(kit)}`;
}

/**
 * Whether the contribution to access-requests can render: the grants keep which
 * rows came from a request and when they end, and grants (not a role function)
 * decide access.
 */
export function driveRequestsSupported(ctx: BlockSqlContext): void {
  if (!ctx.has("grants", "accessRequest") || !ctx.has("grants", "expiresAt")) {
    throw new TypeError(
      "access requests on drive nodes need blocks.drive.columns.grants.accessRequest and expiresAt",
    );
  }

  if (driveRoleFunctions(ctx, driveRoles(ctx).all).node !== undefined) {
    throw new TypeError(
      "access requests on drive nodes need grants to decide access, not blocks.drive.options.roleFunctions.node",
    );
  }
}

function grantAccessSql(kit: DriveKit): string {
  const { ctx, T, G, n, g, fn, roles, rank, live, typed, record, accessAudit } =
    kit;

  if (!ctx.has("grants", "accessRequest") || !ctx.has("grants", "expiresAt")) {
    return "";
  }

  const mine = (alias: string): string =>
    typed
      ? `${alias}.${g("principalType")} = 'user' and ${alias}.${g("principalId")} = drive_grant_access.user_id::text`
      : `${alias}.${g("user")} = drive_grant_access.user_id`;

  const columns = typed
    ? `${g("tenant")}, ${g("node")}, ${g("principalType")}, ${g("principalId")}, ${g("role")}, ${g("expiresAt")}, ${g("accessRequest")}${ctx.has("grants", "createdBy") ? `, ${g("createdBy")}` : ""}`
    : `${g("tenant")}, ${g("node")}, ${g("user")}, ${g("role")}, ${g("expiresAt")}, ${g("accessRequest")}${ctx.has("grants", "createdBy") ? `, ${g("createdBy")}` : ""}`;

  const values = `v_node.${n("tenant")}, v_node.${n("id")}, ${typed ? "'user', drive_grant_access.user_id::text" : "drive_grant_access.user_id"}, ${ctx.cast("grants", "role", "v_role")}, drive_grant_access.ends_at, true${ctx.has("grants", "createdBy") ? ", auth.uid()" : ""}`;

  const principal = `, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text`;

  return `
-- The grant an approved access request on a node makes: the user gets the
-- role that matches the action until ends_at, and loses it when ends_at is
-- past. A grant of their own at that role or higher stays as it is; a lower
-- one is replaced. Only access-requests calls it, as the service role.
create or replace function ${fn("drive_grant_access")}(subject_id text, user_id uuid, action text, ends_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_role text := case drive_grant_access.action when 'read' then ${sqlString(roles.read)} when 'comment' then ${sqlString(roles.comment)} when 'write' then ${sqlString(roles.write)} end;
begin
  if drive_grant_access.subject_id !~ ${UUID_TEXT} then
    ${fail("DRIVE_NOT_FOUND", "item not found", "P0002")}
  end if;
  select * into v_node from ${T} x where x.${n("id")} = drive_grant_access.subject_id::uuid${live("x")};
  if not found then
    ${fail("DRIVE_NOT_FOUND", "item not found", "P0002")}
  end if;
  if v_role is null then
    ${fail("DRIVE_ROLE_UNKNOWN", "action must be read, comment or write", "22023")}
  end if;
  if drive_grant_access.ends_at is not null and drive_grant_access.ends_at <= now() then
    delete from ${G} dg where dg.${g("node")} = v_node.${n("id")} and ${mine("dg")} and dg.${g("accessRequest")};
    if found then
      ${record("drive_node.unshared", "v_node", principal, accessAudit("v_node", "access request ended"))}
    end if;
    return;
  end if;
  if exists (
    select 1 from ${G} dg
    where dg.${g("node")} = v_node.${n("id")} and ${mine("dg")} and not dg.${g("accessRequest")}
      and ${rank(`dg.${g("role")}`)} >= ${rank("v_role")}
      and (dg.${g("expiresAt")} is null or dg.${g("expiresAt")} > now())
  ) then
    return;
  end if;
  delete from ${G} dg where dg.${g("node")} = v_node.${n("id")} and ${mine("dg")};
  insert into ${G} (${columns})
  values (${values});
  ${record("drive_node.shared", "v_node", `${principal}, 'role', v_role`, accessAudit("v_node", "access request granted"))}
end;
$$;
revoke execute on function ${fn("drive_grant_access")}(text, uuid, text, timestamptz) from public, anon, authenticated;
${approversSql(kit)}`;
}

/**
 * `drive_access_approvers(subject_id)`: the active members who may share the
 * node, through a grant on it or an ancestor, its drive's grants or owning its
 * drive. access-requests asks them before it falls back to subjects.manage.
 */
function approversSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    G,
    n,
    g,
    fn,
    roles,
    rank,
    tenant,
    m,
    principalMatch,
    grantLive,
    drives,
    D,
    DG,
    d,
    dg,
    driveGrantLive,
    drivePrincipalMatch,
  } = kit;

  const viaDrive =
    drives && D !== undefined && DG !== undefined
      ? `
      or exists (select 1 from ${D} dd where dd.${d("id")} = v_node.${n("drive")} and dd.${d("owner")} = mu.${m("user")})
      or exists (
        select 1 from ${DG} dgr
        where dgr.${dg("drive")} = v_node.${n("drive")}${driveGrantLive("dgr")}
          and ${rank(`dgr.${dg("role")}`)} >= ${rank(sqlString(roles.share))}
          and ${drivePrincipalMatch("dgr", `mu.${m("user")}`, `mu.${m("tenant")}`)}
      )`
      : "";

  return `
create or replace function ${fn("drive_access_approvers")}(subject_id text)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  if drive_access_approvers.subject_id !~ ${UUID_TEXT} then
    return '{}';
  end if;
  select * into v_node from ${T} x where x.${n("id")} = drive_access_approvers.subject_id::uuid;
  if not found then
    return '{}';
  end if;
  return coalesce((
    select array_agg(mu.${m("user")} order by mu.${m("user")})
    from ${tenant.table("memberships")} mu
    where mu.${m("tenant")} = v_node.${n("tenant")}${activeMembership(ctx, "mu")}
      and (exists (
        select 1 from ${G} gr
        where gr.${g("node")} = any (${fn("drive_ancestors")}(v_node.${n("id")}))${grantLive("gr")}
          and ${rank(`gr.${g("role")}`)} >= ${rank(sqlString(roles.share))}
          and ${principalMatch("gr", `mu.${m("user")}`, `mu.${m("tenant")}`)}
      )${viaDrive})
  ), '{}');
end;
$$;
revoke execute on function ${fn("drive_access_approvers")}(text) from public, anon, authenticated;
`;
}

function transferSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    G,
    n,
    g,
    fn,
    roles,
    typed,
    tenant,
    m,
    manage,
    record,
    recordDrive,
    accessAudit,
    driveAudit,
    drives,
    D,
    DG,
    d,
    dg,
    driveTyped,
    driveUserColumn,
  } = kit;

  const top = sqlString(roles.top);
  const users = `, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text`;

  const held = (alias: string, user: string): string =>
    typed
      ? `${alias}.${g("principalType")} = 'user' and ${alias}.${g("principalId")} = ${user}::text`
      : `${alias}.${g("user")} = ${user}`;

  const repoint = typed
    ? `${g("principalId")} = drive_transfer_ownership.to_user::text`
    : `${g("user")} = drive_transfer_ownership.to_user`;

  const driveHeld = (alias: string, user: string): string =>
    driveTyped
      ? `${alias}.${dg("principalType")} = 'user' and ${alias}.${dg("principalId")} = ${user}::text`
      : `${alias}.${dg("user")} = ${user}`;

  const driveRepoint = driveTyped
    ? `${dg("principalId")} = drive_transfer_ownership.to_user::text`
    : `${dg("user")} = drive_transfer_ownership.to_user`;

  const driveGrants =
    drives && DG !== undefined && (driveTyped || driveUserColumn)
      ? `
  for v_drive_grant in
    select dgr.* from ${DG} dgr
    where dgr.${dg("tenant")} = drive_transfer_ownership.tenant and dgr.${dg("role")}::text = ${top}
      and ${driveHeld("dgr", "drive_transfer_ownership.from_user")}
  loop
    delete from ${DG} dgr where dgr.${dg("drive")} = v_drive_grant.${dg("drive")} and ${driveHeld("dgr", "drive_transfer_ownership.to_user")};
    update ${DG} set ${driveRepoint} where ${dg("id")} = v_drive_grant.${dg("id")};
    v_drive_ids := array_append(v_drive_ids, v_drive_grant.${dg("drive")});
  end loop;`
      : "";

  const driveOwners =
    drives && D !== undefined && ctx.has("drives", "owner")
      ? `
  with moved as (
    update ${D} set ${d("owner")} = drive_transfer_ownership.to_user
    where ${d("tenant")} = drive_transfer_ownership.tenant and ${d("owner")} = drive_transfer_ownership.from_user
    returning ${d("id")}
  )
  select v_drive_ids || coalesce(array_agg(moved.${d("id")}), '{}') into v_drive_ids from moved;`
      : "";

  const driveEvents =
    drives && D !== undefined
      ? `
  for v_drive in
    select * from ${D} dd where dd.${d("id")} = any (v_drive_ids)
  loop
    v_drives := v_drives + 1;
    ${recordDrive("drive.ownership_transferred", "v_drive", users, driveAudit("v_drive", "ownership transferred"))}
  end loop;`
      : "";

  return `
-- Hands every item one member holds at ${roles.top} in an organization to
-- another member: their ${roles.top} grants on nodes and drives, and the drives they
-- own. The new holder keeps one grant per item. Needs ${OPERATIONS["drive.manage"]}.
create or replace function ${fn("drive_transfer_ownership")}(tenant ${ctx.idType}, from_user uuid, to_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_grant ${G}%rowtype;
  v_node ${T}%rowtype;${
    drives && D !== undefined
      ? `
  v_drive ${D}%rowtype;`
      : ""
  }${
    drives && DG !== undefined
      ? `
  v_drive_grant ${DG}%rowtype;`
      : ""
  }
  v_drive_ids uuid[] := '{}';
  v_nodes integer := 0;
  v_drives integer := 0;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_transfer_ownership.tenant", manage)}) then
    ${fail("DRIVE_FORBIDDEN", "you can't transfer items in this organization", "42501")}
  end if;
  if drive_transfer_ownership.from_user is null or drive_transfer_ownership.to_user is null
    or drive_transfer_ownership.from_user = drive_transfer_ownership.to_user then
    ${fail("DRIVE_TRANSFER_INVALID", "name two different users to transfer between", "22023")}
  end if;
  if not exists (
    select 1 from ${tenant.table("memberships")} mu
    where mu.${m("tenant")} = drive_transfer_ownership.tenant and mu.${m("user")} = drive_transfer_ownership.to_user${activeMembership(ctx, "mu")}
  ) then
    ${fail("DRIVE_PRINCIPAL_NOT_FOUND", "the new owner is not an active member of this organization", "P0002")}
  end if;
  for v_grant in
    select gr.* from ${G} gr
    where gr.${g("tenant")} = drive_transfer_ownership.tenant and gr.${g("role")}::text = ${top}
      and ${held("gr", "drive_transfer_ownership.from_user")}
  loop
    delete from ${G} gr where gr.${g("node")} = v_grant.${g("node")} and ${held("gr", "drive_transfer_ownership.to_user")};
    update ${G} set ${repoint} where ${g("id")} = v_grant.${g("id")};
    select * into v_node from ${T} x where x.${n("id")} = v_grant.${g("node")};
    v_nodes := v_nodes + 1;
    ${record("drive_node.ownership_transferred", "v_node", users, accessAudit("v_node", "ownership transferred"))}
  end loop;${driveGrants}${driveOwners}${driveEvents}
  return jsonb_build_object('nodes', v_nodes, 'drives', v_drives);
end;
$$;
${userGrant(`${fn("drive_transfer_ownership")}(${ctx.idType}, uuid, uuid)`)}
`;
}

/**
 * `drive_sharing(tenant)`: the organization's `drive.sharing` setting over the
 * defaults. Without the settings block every organization shares freely and
 * nothing renders.
 */
function sharingSql(kit: DriveKit): string {
  const { ctx, fn } = kit;
  const settings = usable(ctx, "settings");

  if (settings === undefined) {
    return "";
  }

  return `
-- The organization's drive.sharing setting over the defaults
-- ${SHARING_DEFAULT}.
create or replace function ${fn("drive_sharing")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${SHARING_DEFAULT} || coalesce(${settings.fn("organization_setting")}(drive_sharing.tenant, 'drive.sharing'), '{}'::jsonb)
$$;
revoke execute on function ${fn("drive_sharing")}(${ctx.idType}) from public, anon, authenticated;
`;
}

/**
 * The check `drive_link` and `drive_link_upload` run over `tenantId` before
 * they open a link: none when the policy is `none`, and only active members
 * when it is `organization`. Empty without the settings block.
 */
export function linkPolicyCheck(kit: DriveKit, tenantId: string): string {
  const { ctx, fn, tenant, m } = kit;

  if (usable(ctx, "settings") === undefined) {
    return "";
  }

  return `
  if ${fn("drive_sharing")}(${tenantId}) ->> 'links' = 'none' then
    ${fail("DRIVE_SHARING_DISABLED", "this organization has turned off share links", "42501")}
  end if;
  if ${fn("drive_sharing")}(${tenantId}) ->> 'links' = 'organization' and not exists (
    select 1 from ${tenant.table("memberships")} mu
    where mu.${m("tenant")} = ${tenantId} and mu.${m("user")} = auth.uid()${activeMembership(ctx, "mu")}
  ) then
    ${fail("DRIVE_SHARING_DISABLED", "sign in as a member of this organization to open this link", "42501")}
  end if;`;
}

/**
 * With guests and settings installed, the trigger that refuses a guest grant on
 * a drive node while the organization's policy turns guests off. It sits on the
 * guests block's grants table, so drive-files renders it.
 */
export function guestPolicySql(kit: DriveKit): string {
  const { ctx, fn, typeLit } = kit;
  const guests = usable(ctx, "guests");

  if (usable(ctx, "settings") === undefined || guests === undefined) {
    return "";
  }

  const table = guests.table("grants");
  const c = (column: string): string => guests.col("grants", column);

  return `
create or replace function ${fn("drive_guest_sharing")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${c("subjectType")} = ${typeLit}
    and (${fn("drive_sharing")}(new.${c("tenant")}) ->> 'guests')::boolean is false then
    ${fail("DRIVE_SHARING_DISABLED", "this organization has turned off sharing drive items with guests", "42501")}
  end if;
  return new;
end;
$$;
${triggerGrant(`${fn("drive_guest_sharing")}()`)}
drop trigger if exists ${ctx.trigger("drive_guest_sharing")} on ${table};
create trigger ${ctx.trigger("drive_guest_sharing")}
  before insert or update of ${c("subjectType")}, ${c("subjectId")} on ${table}
  for each row execute function ${fn("drive_guest_sharing")}();
`;
}
