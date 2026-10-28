import type { DriveKit } from "./drive-kit.ts";

import { sqlString } from "../../core/template.ts";
import {
  activeMembership,
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { READ_ONLY_GUARD, UUID_TEXT } from "./drive-kit.ts";

/** The drives, their sharing and their external connections. */
export function driveDrivesSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    n,
    fn,
    read,
    create,
    manage,
    roles,
    driveTyped,
    driveTeamColumn,
    drivePrincipalTypes,
    drivePrincipalType,
    drivePrincipalId,
    drives,
    driveKinds,
    driveKindsArray,
    sources,
    sourcesArray,
    D,
    DG,
    C,
    d,
    dg,
    c,
    has,
    binColumn,
    sourceColumn,
    externalColumn,
    metadataColumn,
    driveHeld,
    connectionJson,
    withDriveRole,
    driveExpiring,
    driveGrantLive,
    driveAudit,
    connectionAudit,
    recordDrive,
    recordConnection,
    teams,
    tenant,
    m,
    rank,
    forbidden,
    touch,
  } = kit;

  const teamExistsDrive =
    !drives || teams === undefined
      ? "false"
      : `exists (select 1 from ${teams.table("teams")} t where t.${teams.col("teams", "id")}::text = drive_share_drive.principal_id and t.${teams.col("teams", "tenant")} = v_drive.${d("tenant")})`;

  const driveTeamValue =
    drives && driveTeamColumn
      ? teams === undefined
        ? "null"
        : `case when v_type = 'team' then (select t.${teams.col("teams", "id")} from ${teams.table("teams")} t where t.${teams.col("teams", "id")}::text = drive_share_drive.principal_id and t.${teams.col("teams", "tenant")} = v_drive.${d("tenant")}) end`
      : undefined;

  const driveGrantColumns = drives
    ? driveTyped
      ? `${dg("tenant")}, ${dg("drive")}, ${dg("principalType")}, ${dg("principalId")}, ${dg("role")}${driveExpiring ? `, ${dg("expiresAt")}` : ""}${ctx.has("driveGrants", "createdBy") ? `, ${dg("createdBy")}` : ""}`
      : `${dg("tenant")}, ${dg("drive")}, ${dg("user")}${driveTeamColumn ? `, ${dg("team")}` : ""}, ${dg("role")}${driveExpiring ? `, ${dg("expiresAt")}` : ""}${ctx.has("driveGrants", "createdBy") ? `, ${dg("createdBy")}` : ""}`
    : "";

  const driveGrantValues = drives
    ? driveTyped
      ? `v_drive.${d("tenant")}, v_drive.${d("id")}, v_type, drive_share_drive.principal_id, drive_share_drive.role${driveExpiring ? ", drive_share_drive.expires_at" : ""}${ctx.has("driveGrants", "createdBy") ? ", auth.uid()" : ""}`
      : `v_drive.${d("tenant")}, v_drive.${d("id")}, case when v_type = 'user' then drive_share_drive.principal_id::uuid end${driveTeamColumn ? `, ${driveTeamValue}` : ""}, drive_share_drive.role${driveExpiring ? ", drive_share_drive.expires_at" : ""}${ctx.has("driveGrants", "createdBy") ? ", auth.uid()" : ""}`
    : "";

  const principalError = drives
    ? driveTyped
      ? "principal_type must be user, team or role"
      : driveTeamColumn
        ? "principal_type must be user or team"
        : "principal_type must be user"
    : "";

  return drives
    ? `
-- The drives of an organization, with the caller's role on each.
create or replace function ${fn("drive_create_drive")}(tenant ${ctx.idType}, name text, kind text default null, owner uuid default null, connection uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := ${fn("drive_clean_name")}(drive_create_drive.name);
  v_kind text := coalesce(lower(drive_create_drive.kind), ${sqlString(driveKinds[0] ?? "shared")});
  v_owner uuid := drive_create_drive.owner;
  v_connection ${C}%rowtype;
  v_drive ${D}%rowtype;
begin
  ${READ_ONLY_GUARD}
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_create_drive.tenant", create)}) then
    ${forbidden("create a drive")}
  end if;
  if v_kind <> all (${driveKindsArray}) then
    ${fail("DRIVE_KIND_INVALID", `kind must be one of ${driveKinds.join(", ")}`, "22023")}
  end if;
  if drive_create_drive.connection is not null then
    select * into v_connection from ${C} c
    where c.${c("id")} = drive_create_drive.connection and c.${c("tenant")} = drive_create_drive.tenant;
    if not found then
      ${fail("DRIVE_CONNECTION_NOT_FOUND", "connection not found", "P0002")}
    end if;
    if not (${SERVICE_CALLER} or v_connection.${c("user")} = auth.uid()) then
      ${forbidden("use this connection")}
    end if;
    v_owner := v_connection.${c("user")};
  else
    if v_owner is null then
      v_owner := auth.uid();
    end if;
    if v_owner is not null and not (${SERVICE_CALLER} or v_owner = auth.uid() or ${ctx.can("tenant", "drive_create_drive.tenant", manage)}) then
      ${forbidden("create a drive for another member")}
    end if;
    if v_owner is not null and not exists (
      select 1 from ${tenant.table("memberships")} mu
      where mu.${m("tenant")} = drive_create_drive.tenant and mu.${m("user")} = v_owner${activeMembership(ctx, "mu")}
    ) then
      ${fail("DRIVE_OWNER_NOT_MEMBER", "the owner is not an active member of this organization", "P0002")}
    end if;
  end if;
  if exists (select 1 from ${D} d where d.${d("tenant")} = drive_create_drive.tenant and lower(d.${d("name")}) = lower(v_name)) then
    ${fail("DRIVE_NAME_CONFLICT", "another drive already has this name", "23505")}
  end if;
  insert into ${D} (${d("tenant")}, ${d("name")}, ${d("kind")}, ${d("owner")}, ${d("connection")}${ctx.has("drives", "createdBy") ? `, ${d("createdBy")}` : ""})
  values (drive_create_drive.tenant, v_name, v_kind, v_owner, drive_create_drive.connection${ctx.has("drives", "createdBy") ? ", auth.uid()" : ""})
  returning * into v_drive;
  ${recordDrive("drive.created", "v_drive", `, 'name', v_drive.${d("name")}`, driveAudit("v_drive", "created"))}
  return ${withDriveRole("v_drive")};
end;
$$;
${userGrant(`${fn("drive_create_drive")}(${ctx.idType}, text, text, uuid, uuid)`)}

create or replace function ${fn("drive_get_drive")}(drive uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_get_drive.drive, ${sqlString(roles.read)})) then
    ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
  end if;
  return (
    select ${withDriveRole("d")} from ${D} d where d.${d("id")} = drive_get_drive.drive
  );
end;
$$;
${userGrant(`${fn("drive_get_drive")}(uuid)`)}

create or replace function ${fn("drive_list_drives")}(tenant ${ctx.idType}, page_size integer default 100, skip integer default 0)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_list_drives.tenant", read)}) then
    ${forbidden("read this organization's drives")}
  end if;
  return (
    with page as (
      select dd.* from ${D} dd
      where dd.${d("tenant")} = drive_list_drives.tenant
        and (${SERVICE_CALLER} or dd.${d("id")} in (select ${fn("drive_drive_readable_ids")}()))
      order by lower(dd.${d("name")}), dd.${d("id")}
      limit ${pageSize("drive_list_drives.page_size", 100, 500)}
      offset greatest(coalesce(drive_list_drives.skip, 0), 0)
    )
    select coalesce(jsonb_agg(${withDriveRole("d")} order by lower(d.${d("name")}), d.${d("id")}), '[]'::jsonb)
    from page d
  );
end;
$$;
${userGrant(`${fn("drive_list_drives")}(${ctx.idType}, integer, integer)`)}

create or replace function ${fn("drive_rename_drive")}(drive uuid, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_drive ${D}%rowtype;
  v_previous text;
  v_name text := ${fn("drive_clean_name")}(drive_rename_drive.name);
begin
  select * into v_drive from ${D} d where d.${d("id")} = drive_rename_drive.drive for update;
  if not found or not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_rename_drive.drive, ${sqlString(roles.read)})) then
    ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_rename_drive.drive, ${sqlString(roles.share)})) then
    ${forbidden("rename this drive")}
  end if;
  ${READ_ONLY_GUARD}
  if v_name = v_drive.${d("name")} then
    return ${withDriveRole("v_drive")};
  end if;
  if exists (
    select 1 from ${D} d
    where d.${d("tenant")} = v_drive.${d("tenant")}
      and d.${d("id")} <> v_drive.${d("id")}
      and lower(d.${d("name")}) = lower(v_name)
  ) then
    ${fail("DRIVE_NAME_CONFLICT", "another drive already has this name", "23505")}
  end if;
  v_previous := v_drive.${d("name")};
  update ${D} d set ${d("name")} = v_name${ctx.has("drives", "updatedAt") ? `, ${d("updatedAt")} = now()` : ""}
  where d.${d("id")} = v_drive.${d("id")}
  returning * into v_drive;
  ${recordDrive("drive.renamed", "v_drive", `, 'name', v_drive.${d("name")}, 'previousName', v_previous`, driveAudit("v_drive", "renamed"))}
  return ${withDriveRole("v_drive")};
end;
$$;
${userGrant(`${fn("drive_rename_drive")}(uuid, text)`)}

create or replace function ${fn("drive_delete_drive")}(drive uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_drive ${D}%rowtype;
begin
  select * into v_drive from ${D} d where d.${d("id")} = drive_delete_drive.drive for update;
  if not found or not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_delete_drive.drive, ${sqlString(roles.read)})) then
    ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_delete_drive.drive, ${sqlString(roles.share)})) then
    ${forbidden("delete this drive")}
  end if;
  ${READ_ONLY_GUARD}
  if ${driveHeld("v_drive")} then
    ${fail("DRIVE_HELD", "this drive holds an item under a legal hold", "42501")}
  end if;
  ${recordDrive("drive.deleted", "v_drive", "", driveAudit("v_drive", "deleted"))}
  delete from ${D} d where d.${d("id")} = v_drive.${d("id")};
  return true;
end;
$$;
${userGrant(`${fn("drive_delete_drive")}(uuid)`)}

create or replace function ${fn("drive_share_drive")}(drive uuid, principal_type text, principal_id text, role text, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_drive ${D}%rowtype;
  v_type text := lower(drive_share_drive.principal_type);
  v_id uuid;
begin
  select * into v_drive from ${D} d where d.${d("id")} = drive_share_drive.drive;
  if not found or not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_share_drive.drive, ${sqlString(roles.read)})) then
    ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or (${fn("drive_drive_can")}(drive_share_drive.drive, ${sqlString(roles.share)}) and ${rank("drive_share_drive.role")} <= ${rank(`${fn("drive_drive_role")}(drive_share_drive.drive)`)})) then
    ${forbidden("share this drive with that role")}
  end if;
  ${READ_ONLY_GUARD}
  if ${rank("drive_share_drive.role")} = 0 then
    ${fail("DRIVE_ROLE_UNKNOWN", `role must be one of ${roles.all.join(", ")}`, "22023")}
  end if;
  if v_type not in ${drivePrincipalTypes} or drive_share_drive.principal_id is null then
    ${fail("DRIVE_PRINCIPAL_INVALID", principalError, "22023")}
  end if;
  if (v_type = 'user' and (drive_share_drive.principal_id !~ ${UUID_TEXT} or not exists (
      select 1 from ${tenant.table("memberships")} mu
      where mu.${m("tenant")} = v_drive.${d("tenant")} and mu.${m("user")} = drive_share_drive.principal_id::uuid${activeMembership(ctx, "mu")}
    ))
    or (v_type = 'team' and not ${teamExistsDrive})) then
    ${fail("DRIVE_PRINCIPAL_NOT_FOUND", "no member or team of this organization has that id", "P0002")}
  end if;
  delete from ${DG} dg where dg.${dg("drive")} = v_drive.${d("id")}
    and ${drivePrincipalType("dg")} = v_type and ${drivePrincipalId("dg")} = drive_share_drive.principal_id;
  insert into ${DG} (${driveGrantColumns})
  values (${driveGrantValues})
  returning ${dg("id")} into v_id;
  ${recordDrive("drive.shared", "v_drive", ", 'principalType', v_type, 'principalId', drive_share_drive.principal_id, 'role', drive_share_drive.role", driveAudit("v_drive", "shared"))}
  return jsonb_build_object('id', v_id, 'driveId', v_drive.${d("id")}, 'principalType', v_type, 'principalId', drive_share_drive.principal_id, 'role', drive_share_drive.role, 'expiresAt', drive_share_drive.expires_at);
end;
$$;
${userGrant(`${fn("drive_share_drive")}(uuid, text, text, text, timestamptz)`)}

create or replace function ${fn("drive_unshare_drive")}(drive uuid, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_drive ${D}%rowtype;
  v_type text := lower(drive_unshare_drive.principal_type);
begin
  select * into v_drive from ${D} d where d.${d("id")} = drive_unshare_drive.drive;
  if not found or not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_unshare_drive.drive, ${sqlString(roles.read)})) then
    ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_unshare_drive.drive, ${sqlString(roles.share)})) then
    ${forbidden("change who this drive is shared with")}
  end if;
  ${READ_ONLY_GUARD}
  delete from ${DG} dg where dg.${dg("drive")} = v_drive.${d("id")}
    and ${drivePrincipalType("dg")} = v_type and ${drivePrincipalId("dg")} = drive_unshare_drive.principal_id;
  if not found then
    return false;
  end if;
  ${recordDrive("drive.unshared", "v_drive", ", 'principalType', v_type, 'principalId', drive_unshare_drive.principal_id", driveAudit("v_drive", "unshared"))}
  return true;
end;
$$;
${userGrant(`${fn("drive_unshare_drive")}(uuid, text, text)`)}

create or replace function ${fn("drive_grants_for_drive")}(drive uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${fn("drive_drive_can")}(drive_grants_for_drive.drive, ${sqlString(roles.read)})) then
    ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', dg.${dg("id")}, 'driveId', dg.${dg("drive")}, 'principalType', ${drivePrincipalType("dg")}, 'principalId', ${drivePrincipalId("dg")}, 'role', dg.${dg("role")}, 'expiresAt', ${driveExpiring ? `dg.${dg("expiresAt")}` : "null"}) order by ${rank(`dg.${dg("role")}`)} desc, dg.${dg("id")}), '[]'::jsonb)
    from ${DG} dg
    where dg.${dg("drive")} = drive_grants_for_drive.drive${driveGrantLive("dg")}
  );
end;
$$;
${userGrant(`${fn("drive_grants_for_drive")}(uuid)`)}

create or replace function ${fn("drive_connect")}(tenant ${ctx.idType}, provider text, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := ${fn("drive_clean_name")}(drive_connect.name);
  v_provider text := lower(drive_connect.provider);
  v_connection ${C}%rowtype;
begin
  ${READ_ONLY_GUARD}
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_connect.tenant", create)}) then
    ${forbidden("connect an external account")}
  end if;
  if v_provider <> all (${sourcesArray}) or v_provider = 'internal' then
    ${fail("DRIVE_PROVIDER_INVALID", `provider must be one of ${sources.join(", ")}`, "22023")}
  end if;
  if auth.uid() is null and not ${SERVICE_CALLER} then
    ${forbidden("connect an external account")}
  end if;
  if exists (
    select 1 from ${C} c
    where c.${c("tenant")} = drive_connect.tenant
      and c.${c("user")} = auth.uid()
      and c.${c("provider")} = v_provider
      and lower(c.${c("name")}) = lower(v_name)
  ) then
    ${fail("DRIVE_CONNECTION_EXISTS", "this account is already connected", "23505")}
  end if;
  insert into ${C} (${c("tenant")}, ${c("user")}, ${c("provider")}, ${c("name")}${ctx.has("connections", "createdBy") ? `, ${c("createdBy")}` : ""})
  values (drive_connect.tenant, auth.uid(), v_provider, v_name${ctx.has("connections", "createdBy") ? ", auth.uid()" : ""})
  returning * into v_connection;
  ${recordConnection("drive.connection_created", "v_connection", `, 'name', v_connection.${c("name")}`, connectionAudit("v_connection", "created"))}
  return ${connectionJson("v_connection")};
end;
$$;
${userGrant(`${fn("drive_connect")}(${ctx.idType}, text, text)`)}

create or replace function ${fn("drive_disconnect")}(connection uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_connection ${C}%rowtype;
begin
  select * into v_connection from ${C} c where c.${c("id")} = drive_disconnect.connection for update;
  if not found or not (${SERVICE_CALLER} or v_connection.${c("user")} = auth.uid()) then
    ${fail("DRIVE_NOT_FOUND", "connection not found", "P0002")}
  end if;
  ${READ_ONLY_GUARD}
  if exists (
    select 1 from ${D} d
    where d.${d("connection")} = v_connection.${c("id")} and ${driveHeld("d")}
  ) then
    ${fail("DRIVE_HELD", "a drive of this connection holds an item under a legal hold", "42501")}
  end if;
  ${recordConnection("drive.connection_removed", "v_connection", "", connectionAudit("v_connection", "removed"))}
  delete from ${C} c where c.${c("id")} = v_connection.${c("id")};
  return true;
end;
$$;
${userGrant(`${fn("drive_disconnect")}(uuid)`)}

create or replace function ${fn("drive_list_connections")}(tenant ${ctx.idType}, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_list_connections.tenant", read)}) then
    ${forbidden("read this organization's connections")}
  end if;
  return (
    with page as (
      select cc.* from ${C} cc
      where cc.${c("tenant")} = drive_list_connections.tenant
        and (${SERVICE_CALLER} or cc.${c("user")} = auth.uid())
      order by lower(cc.${c("name")}), cc.${c("id")}
      limit ${pageSize("drive_list_connections.page_size", 100, 500)}
    )
    select coalesce(jsonb_agg(${connectionJson("c")} order by lower(c.${c("name")}), c.${c("id")}), '[]'::jsonb)
    from page c
  );
end;
$$;
${userGrant(`${fn("drive_list_connections")}(${ctx.idType}, integer)`)}${
        sourceColumn && externalColumn && metadataColumn
          ? `
-- Applies one page of provider changes to a connected drive mirror. Items
-- carry the provider id, parent provider id, name, kind and metadata; removed
-- items are deleted with their subtree. Items whose parent is the provider
-- root become top-level nodes, and top-level nodes with any other parent are
-- dropped, so the mirror only holds the tree under root_external_id. A full
-- listing stamps every node with sync_run, and its final call passes prune to
-- remove every mirrored node without that stamp.
create or replace function ${fn("drive_sync_batch")}(drive uuid, items jsonb, root_external_id text, sync_run text default null, prune boolean default false, cursor text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_drive ${D}%rowtype;
  v_connection ${C}%rowtype;
  v_source text;
  v_count integer := 0;
begin
  select * into v_drive from ${D} d where d.${d("id")} = drive_sync_batch.drive for update;
  if not found or v_drive.${d("connection")} is null then
    ${fail("DRIVE_NOT_CONNECTED", "drive is not a connected drive", "P0002")}
  end if;
  select * into v_connection from ${C} c where c.${c("id")} = v_drive.${d("connection")};
  if not found then
    ${fail("DRIVE_CONNECTION_NOT_FOUND", "connection not found", "P0002")}
  end if;
  v_source := v_connection.${c("provider")};
  create temporary table pg_temp.drive_sync_items on commit drop as
  select distinct on (item ->> 'externalId')
    item ->> 'externalId' as external_id,
    nullif(item ->> 'parentExternalId', '') as parent_external_id,
    left(regexp_replace(coalesce(nullif(btrim(item ->> 'name'), ''), 'Untitled'), '[/[:cntrl:]]', '-', 'g'), 240) as name,
    (case when item ->> 'kind' = 'folder' then 'folder' else 'file' end) as kind,
    coalesce(item -> 'metadata', '{}'::jsonb)
      || jsonb_build_object('parentExternalId', nullif(item ->> 'parentExternalId', ''), 'syncRun', drive_sync_batch.sync_run) as metadata,
    coalesce((item ->> 'removed')::boolean, false) as removed
  from jsonb_array_elements(coalesce(drive_sync_batch.items, '[]'::jsonb)) with ordinality as entry(item, position)
  where nullif(item ->> 'externalId', '') is not null
  order by item ->> 'externalId', position desc;
  delete from ${T} s
  using pg_temp.drive_sync_items item
  where item.removed
    and s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = v_source
    and s.${n("externalId")} = item.external_id${
      binColumn
        ? `
    and s.${n("deletedAt")} is null`
        : ""
    }
    and not ${fn("drive_node_held")}(s.${n("id")});
  insert into ${T} (${n("tenant")}, ${n("drive")}, ${n("parent")}, ${n("kind")}, ${n("name")}, ${n("source")}, ${n("externalId")}, ${n("externalMetadata")}${has("createdBy") ? `, ${n("createdBy")}` : ""})
  select
    v_drive.${d("tenant")},
    drive_sync_batch.drive,
    null,
    item.kind,
    item.name,
    v_source,
    item.external_id,
    item.metadata${has("createdBy") ? `, v_drive.${d("owner")}` : ""}
  from pg_temp.drive_sync_items item
  where not item.removed
  on conflict (${n("drive")}, ${n("source")}, ${n("externalId")}) where ${n("externalId")} is not null${binColumn ? ` and ${n("deletedAt")} is null` : ""}
  do update set
    ${n("kind")} = excluded.${n("kind")},
    ${n("name")} = excluded.${n("name")},
    ${n("externalMetadata")} = excluded.${n("externalMetadata")}${
      touch
        ? `,
    ${n("updatedAt")} = now()`
        : ""
    };
  get diagnostics v_count = row_count;
  update ${T} s
  set ${n("parent")} = p.${n("id")}
  from pg_temp.drive_sync_items item
  left join ${T} p
    on p.${n("drive")} = drive_sync_batch.drive
    and p.${n("source")} = v_source
    and p.${n("externalId")} = item.parent_external_id
    and p.${n("kind")} = 'folder'${
      binColumn
        ? `
    and p.${n("deletedAt")} is null`
        : ""
    }
  where not item.removed
    and s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = v_source
    and s.${n("externalId")} = item.external_id
    and s.${n("parent")} is distinct from p.${n("id")}
    and (p.${n("id")} is null or p.${n("id")} <> s.${n("id")});
  delete from ${T} s
  where s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = v_source
    and s.${n("parent")} is null
    and s.${n("externalMetadata")} ->> 'parentExternalId' is not null
    and s.${n("externalMetadata")} ->> 'parentExternalId' <> drive_sync_batch.root_external_id
    and not ${fn("drive_node_held")}(s.${n("id")});
  if drive_sync_batch.prune and drive_sync_batch.sync_run is not null then
    delete from ${T} s
    where s.${n("drive")} = drive_sync_batch.drive
      and s.${n("source")} = v_source
      and coalesce(s.${n("externalMetadata")} ->> 'syncRun', '') <> drive_sync_batch.sync_run
      and not ${fn("drive_node_held")}(s.${n("id")});
  end if;
  update ${C} c set
    ${c("syncCursor")} = coalesce(drive_sync_batch.cursor, c.${c("syncCursor")}),
    ${c("syncClaimedAt")} = null,
    ${c("lastSyncedAt")} = now(),
    ${c("lastSyncError")} = null${
      ctx.has("connections", "updatedAt")
        ? `,
    ${c("updatedAt")} = now()`
        : ""
    }
  where c.${c("id")} = v_connection.${c("id")};
  drop table pg_temp.drive_sync_items;
  return v_count;
end;
$$;
revoke execute on function ${fn("drive_sync_batch")}(uuid, jsonb, text, text, boolean, text) from public, anon, authenticated;
${serviceGrant(`${fn("drive_sync_batch")}(uuid, jsonb, text, text, boolean, text)`)}
`
          : ""
      }
`
    : "";
}
