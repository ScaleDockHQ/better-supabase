import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import { UUID_TEXT } from "./drive-kit.ts";

const LOCKED_MESSAGE = "this item is checked out by someone else";

const lockedRaise = (kit: DriveKit, row: string): string =>
  `raise exception ${sqlString(LOCKED_MESSAGE)} using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', ${row}.${kit.n("lockedBy")}, 'lockedUntil', ${row}.${kit.n("lockedUntil")})::text;`;

/** Refuses the change while someone else holds a live lock on `alias`. */
export function lockGuard(kit: DriveKit, alias: string): string {
  return kit.lockColumns
    ? `if ${kit.lockedByOther(alias)} then
    ${lockedRaise(kit, alias)}
  end if;`
    : "";
}

/**
 * Refuses the change while someone else holds a live lock on the node or on
 * anything under it. Declares nothing: `v_locked` must be a `%rowtype` of the
 * node table.
 */
export function subtreeLockGuard(kit: DriveKit, node: string): string {
  const { T, n, fn, lockColumns, lockedByOther } = kit;

  return lockColumns
    ? `select * into v_locked from ${T} lk
  where lk.${n("id")} in (select s.node_id from ${fn("drive_subtree")}(${node}) s)
    and ${lockedByOther("lk")}
  limit 1;
  if found then
    ${lockedRaise(kit, "v_locked")}
  end if;`
    : "";
}

/**
 * The comment and download checks. They render before the functions that call
 * them, since `language sql` bodies are checked when they are created.
 */
export function driveAccessSql(kit: DriveKit): string {
  const {
    T,
    n,
    fn,
    roles,
    drives,
    D,
    d,
    canRead,
    canWrite,
    canShare,
    canComment,
    downloadColumn,
    driveDownloadColumn,
  } = kit;

  const nodeBlocked = downloadColumn
    ? `exists (select 1 from ${T} b where b.${n("id")} = any (${fn("drive_ancestors")}(drive_download_blocked.node)) and b.${n("downloadBlocked")})`
    : "false";

  const driveBlocked =
    drives && driveDownloadColumn && D !== undefined
      ? `exists (select 1 from ${T} x join ${D} dd on dd.${d("id")} = x.${n("drive")} where x.${n("id")} = drive_download_blocked.node and dd.${d("downloadBlocked")})`
      : "false";

  return `
-- Whether the caller may comment on the node: options.commentRole (${roles.comment}).
create or replace function ${fn("drive_can_comment")}(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${canComment("drive_can_comment.node")}
$$;
${userGrant(`${fn("drive_can_comment")}(uuid)`)}

-- Whether downloads of the node's original are blocked on it, a folder above it
-- or its drive. Share links honor the block whatever their role.
create or replace function ${fn("drive_download_blocked")}(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${nodeBlocked} or ${driveBlocked}
$$;
${serviceGrant(`${fn("drive_download_blocked")}(uuid)`)}

-- Whether the caller may download the node's original: read access, and no
-- download block unless they hold the write role (${roles.write}). Previews only need
-- read access.
create or replace function ${fn("drive_can_download")}(node uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${SERVICE_CALLER} or (${canRead("drive_can_download.node")}
    and (${canWrite("drive_can_download.node")} or not ${fn("drive_download_blocked")}(drive_can_download.node)))
$$;
${userGrant(`${fn("drive_can_download")}(uuid)`)}

-- create_share_link's check for a node: it exists in the tenant, the caller
-- holds the share role (${roles.share}) on it, and an upload link names a folder.
create or replace function ${fn("drive_share_link_allowed")}(node text, tenant text, role text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  if drive_share_link_allowed.node !~ ${UUID_TEXT} then
    return false;
  end if;
  select * into v_node from ${T} x
  where x.${n("id")} = drive_share_link_allowed.node::uuid and x.${n("tenant")}::text = drive_share_link_allowed.tenant::text;
  if not found or not ${canShare(`v_node.${n("id")}`)} then
    return false;
  end if;
  if drive_share_link_allowed.role = 'upload' and v_node.${n("kind")} <> 'folder' then
    ${fail("DRIVE_LINK_ROLE_INVALID", "an upload link names a folder", "22023")}
  end if;
  return true;
end;
$$;
${serviceGrant(`${fn("drive_share_link_allowed")}(text, text, text)`)}
`;
}

/** Check-out locks and download blocks. */
export function driveLocksSql(kit: DriveKit): string {
  const {
    T,
    n,
    fn,
    has,
    live,
    canRead,
    canShare,
    readOnly,
    notFound,
    forbidden,
    touch,
    record,
    recordDrive,
    dataAudit,
    accessAudit,
    driveAudit,
    withRole,
    withDriveRole,
    roles,
    drives,
    D,
    d,
    lockColumns,
    downloadColumn,
    driveDownloadColumn,
  } = kit;

  const readOnlyFail = fail(
    "DRIVE_READ_ONLY",
    "this item mirrors an external account and is read-only",
    "42501",
  );

  const note = has("lockNote");

  const locks = lockColumns
    ? `
-- Checks a file out: only the holder may change it until the lock ends
-- (8 hours by default, 30 days at most) or the holder releases it. Holding it
-- already extends it.
create or replace function ${fn("drive_lock")}(node uuid, until timestamptz default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_until timestamptz := coalesce(drive_lock.until, now() + interval '8 hours');
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_lock.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if auth.uid() is null then
    ${forbidden("check out an item without a user")}
  end if;
  if not ${fn("drive_node_writable")}(v_node.${n("id")}) then
    if ${readOnly("v_node")} then
      ${readOnlyFail}
    end if;
    ${forbidden("check out this item")}
  end if;
  if v_node.${n("kind")} <> 'file' then
    ${fail("DRIVE_NOT_A_FILE", "only a file can be checked out", "22023")}
  end if;
  if v_until <= now() or v_until > now() + interval '30 days' then
    ${fail("DRIVE_LOCK_INVALID", "a lock ends in the future and within 30 days", "22023")}
  end if;
  if length(drive_lock.note) > 500 then
    ${fail("DRIVE_LOCK_INVALID", "a lock note is at most 500 characters", "22023")}
  end if;
  ${lockGuard(kit, "v_node")}
  update ${T} x set ${n("lockedBy")} = auth.uid(), ${n("lockedUntil")} = v_until${note ? `, ${n("lockNote")} = drive_lock.note` : ""}${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  ${record("drive.node_locked", "v_node", `, 'lockedBy', v_node.${n("lockedBy")}::text, 'lockedUntil', v_node.${n("lockedUntil")}`, dataAudit("v_node", "checked out"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_lock")}(uuid, timestamptz, text)`)}

-- Releases a lock: the holder, or with force the share role (${roles.share}). An
-- item without a live lock comes back unchanged.
create or replace function ${fn("drive_unlock")}(node uuid, force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_holder uuid;
  v_forced boolean := false;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_unlock.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if v_node.${n("lockedUntil")} is null or v_node.${n("lockedUntil")} <= now() then
    if v_node.${n("lockedBy")} is not null then
      update ${T} x set ${n("lockedBy")} = null, ${n("lockedUntil")} = null${note ? `, ${n("lockNote")} = null` : ""}
      where x.${n("id")} = v_node.${n("id")}
      returning * into v_node;
    end if;
    return ${withRole("v_node")};
  end if;
  v_holder := v_node.${n("lockedBy")};
  if v_holder is distinct from auth.uid() and not ${SERVICE_CALLER} then
    if not coalesce(drive_unlock.force, false) then
      ${lockedRaise(kit, "v_node")}
    end if;
    if not ${canShare(`v_node.${n("id")}`)} then
      ${forbidden("break someone else's lock")}
    end if;
    v_forced := true;
  end if;
  update ${T} x set ${n("lockedBy")} = null, ${n("lockedUntil")} = null${note ? `, ${n("lockNote")} = null` : ""}${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  ${record("drive.node_unlocked", "v_node", ", 'lockedBy', v_holder::text, 'forced', v_forced", dataAudit("v_node", "checked in"))}
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_unlock")}(uuid, boolean)`)}
`
    : "";

  const driveTarget =
    drives && driveDownloadColumn && D !== undefined
      ? `
  if drive_set_download_blocked.target_type = 'drive' then
    select * into v_drive from ${D} dd where dd.${d("id")} = drive_set_download_blocked.target_id for update;
    if not found or not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(v_drive.${d("id")}, ${sqlString(roles.read)})) then
      ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
    end if;
    if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(v_drive.${d("id")}, ${sqlString(roles.share)})) then
      ${forbidden("change downloads of this drive")}
    end if;
    if v_drive.${d("connection")} is not null then
      ${fail("DRIVE_READ_ONLY", "this drive mirrors an external account and is read-only", "42501")}
    end if;
    if v_drive.${d("downloadBlocked")} is distinct from drive_set_download_blocked.blocked then
      update ${D} dd set ${d("downloadBlocked")} = drive_set_download_blocked.blocked${kit.ctx.has("drives", "updatedAt") ? `, ${d("updatedAt")} = now()` : ""}
      where dd.${d("id")} = v_drive.${d("id")}
      returning * into v_drive;
      ${recordDrive("drive.download_blocked_changed", "v_drive", `, 'downloadBlocked', v_drive.${d("downloadBlocked")}`, driveAudit("v_drive", "download block changed"))}
    end if;
    return ${withDriveRole("v_drive")};
  end if;`
      : "";

  const targets = [
    ...(downloadColumn ? ["'node'"] : []),
    ...(driveTarget === "" ? [] : ["'drive'"]),
  ];

  const nodeTarget = downloadColumn
    ? `
  select * into v_node from ${T} x where x.${n("id")} = drive_set_download_blocked.target_id${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare(`v_node.${n("id")}`)}) then
    ${forbidden("change downloads of this item")}
  end if;
  if ${readOnly("v_node")} then
    ${readOnlyFail}
  end if;
  if v_node.${n("downloadBlocked")} is distinct from drive_set_download_blocked.blocked then
    update ${T} x set ${n("downloadBlocked")} = drive_set_download_blocked.blocked${touch}
    where x.${n("id")} = v_node.${n("id")}
    returning * into v_node;
    ${record("drive.node_download_blocked_changed", "v_node", `, 'downloadBlocked', v_node.${n("downloadBlocked")}`, accessAudit("v_node", "download block changed"))}
  end if;
  return ${withRole("v_node")};`
    : `
  ${fail("DRIVE_TARGET_INVALID", "downloads can be blocked on a drive only", "22023")}`;

  const downloads =
    targets.length === 0
      ? ""
      : `
-- Blocks or allows downloads of the originals on a node and everything under
-- it, or on a whole drive (the share role, ${roles.share}). Readers keep previews; the
-- write role (${roles.write}) still downloads.
create or replace function ${fn("drive_set_download_blocked")}(target_type text, target_id uuid, blocked boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;${driveTarget === "" ? "" : `\n  v_drive ${D}%rowtype;`}
begin
  if drive_set_download_blocked.target_type is null or drive_set_download_blocked.target_type not in (${targets.join(", ")}) then
    ${fail("DRIVE_TARGET_INVALID", `target_type must be ${targets.map((target) => target.replaceAll("'", "")).join(" or ")}`, "22023")}
  end if;
  if drive_set_download_blocked.blocked is null then
    ${fail("DRIVE_TARGET_INVALID", "blocked must be true or false", "22023")}
  end if;${driveTarget}${nodeTarget}
end;
$$;
${userGrant(`${fn("drive_set_download_blocked")}(text, uuid, boolean)`)}
`;

  return `${locks}${downloads}`;
}
