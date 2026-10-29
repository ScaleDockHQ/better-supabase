import type { DriveKit } from "./drive-kit.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { RANK_KEY_PATTERN } from "../rank-sql.ts";
import { addExtraColumns, ensureCheck, fail, lockTable } from "../shared.ts";

/** The drive tables and the triggers that keep paths and drives in step. */
export function driveTablesSql(kit: DriveKit): string {
  const {
    ctx,
    T,
    G,
    n,
    g,
    read,
    driveKinds,
    driveKindsArray,
    sourcesArray,
    drives,
    D,
    DG,
    C,
    d,
    dg,
    c,
    extras,
    sourceColumn,
    externalColumn,
    metadataColumn,
    holdColumn,
    lockColumns,
    downloadColumn,
    driveDownloadColumn,
    previewColumn,
    has,
    binColumn,
    rolesArray,
    typed,
    teamColumn,
    driveColumn,
    driveTyped,
    driveTeamColumn,
  } = kit;

  const connectionTable =
    drives && ctx.owns("connections") && C !== undefined
      ? `create table if not exists ${C} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("user")} uuid not null,
  ${c("provider")} text not null check (${c("provider")} = any (${sourcesArray}) and ${c("provider")} <> 'internal'),
  ${c("name")} text not null check (length(btrim(${c("name")})) between 1 and 255),
  ${c("status")} text not null default 'active' check (${c("status")} in ('active', 'error')),
  ${c("syncCursor")} text,
  ${c("syncClaimedAt")} timestamptz,
  ${c("lastSyncedAt")} timestamptz,
  ${c("lastSyncError")} text,
  ${c("createdBy")} uuid default auth.uid(),
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  unique nulls not distinct (${c("tenant")}, ${c("user")}, ${c("provider")}, ${c("name")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("connections").name}_user_idx`)} on ${C} (${c("tenant")}, ${c("user")});
create index if not exists ${sqlIdent(`${ctx.tableName("connections").name}_sync_idx`)} on ${C} (${c("lastSyncedAt")} nulls first) where ${c("status")} = 'active';
${lockTable(C, { read: false })}
${renderPolicy(makePolicy({ table: C, name: ctx.naming.rename("drive_connections_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(c("tenant"), read)} and ${c("user")} = auth.uid()` }), { drop: true, target: C })}
`
      : "";

  const driveTable =
    drives && ctx.owns("drives") && D !== undefined
      ? `create table if not exists ${D} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("name")} text not null check (length(btrim(${d("name")})) between 1 and 255),
  ${d("kind")} text not null default ${sqlString(driveKinds[0] ?? "shared")} check (${d("kind")} = any (${driveKindsArray})),
  ${d("owner")} uuid,
  ${d("connection")} uuid${ctx.has("connections", "id") && C !== undefined ? ` references ${C} (${c("id")}) on delete cascade` : ""},
  ${driveDownloadColumn ? `${d("downloadBlocked")} boolean not null default false,` : ""}
  ${d("createdBy")} uuid default auth.uid(),
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now(),
  unique (${d("id")}, ${d("tenant")})
);
create unique index if not exists ${sqlIdent(`${ctx.tableName("drives").name}_name_idx`)} on ${D} (${d("tenant")}, lower(${d("name")}));
create index if not exists ${sqlIdent(`${ctx.tableName("drives").name}_kind_idx`)} on ${D} (${d("tenant")}, ${d("kind")});
create index if not exists ${sqlIdent(`${ctx.tableName("drives").name}_owner_idx`)} on ${D} (${d("owner")}) where ${d("owner")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("drives").name}_connection_idx`)} on ${D} (${d("connection")}) where ${d("connection")} is not null;
${driveDownloadColumn ? `alter table ${D} add column if not exists ${d("downloadBlocked")} boolean not null default false;\n` : ""}${lockTable(D, { read: true })}
`
      : "";

  const driveGrantIdentity =
    drives && DG !== undefined
      ? driveTyped
        ? `  ${dg("principalType")} text not null check (${dg("principalType")} in ('user', 'team', 'role')),
  ${dg("principalId")} text not null,`
        : `  ${dg("user")} uuid${driveTeamColumn ? "" : " not null"},${
            driveTeamColumn
              ? `
  ${dg("team")} uuid,
  check ((${dg("user")} is not null)::int + (${dg("team")} is not null)::int = 1),`
              : ""
          }`
      : "";

  const driveGrantUnique =
    drives && DG !== undefined && driveTyped
      ? `  unique (${dg("drive")}, ${dg("principalType")}, ${dg("principalId")}),
`
      : "";

  const driveGrantIndexes =
    drives && DG !== undefined
      ? driveTyped
        ? `create index if not exists ${sqlIdent(`${ctx.tableName("driveGrants").name}_principal_idx`)} on ${DG} (${dg("principalType")}, ${dg("principalId")});`
        : `create unique index if not exists ${sqlIdent(`${ctx.tableName("driveGrants").name}_user_idx`)} on ${DG} (${dg("drive")}, ${dg("user")}) where ${dg("user")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("driveGrants").name}_user_principal_idx`)} on ${DG} (${dg("user")}) where ${dg("user")} is not null;${
            driveTeamColumn
              ? `
create unique index if not exists ${sqlIdent(`${ctx.tableName("driveGrants").name}_team_idx`)} on ${DG} (${dg("drive")}, ${dg("team")}) where ${dg("team")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("driveGrants").name}_team_principal_idx`)} on ${DG} (${dg("team")}) where ${dg("team")} is not null;`
              : ""
          }`
      : "";

  const driveGrantTable =
    drives && ctx.owns("driveGrants") && DG !== undefined && D !== undefined
      ? `create table if not exists ${DG} (
  ${dg("id")} uuid primary key default gen_random_uuid(),
  ${dg("tenant")} ${ctx.idType} not null,
  ${dg("drive")} uuid not null,
${driveGrantIdentity}
  ${dg("role")} text not null,
  ${dg("expiresAt")} timestamptz,
  ${dg("createdBy")} uuid default auth.uid(),
  ${dg("createdAt")} timestamptz not null default now(),
${driveGrantUnique}  foreign key (${dg("drive")}, ${dg("tenant")}) references ${D} (${d("id")}, ${d("tenant")}) on delete cascade
);
${driveGrantIndexes}
${ensureCheck(DG, "bsb_drive_drive_grants_role", `${dg("role")} = any (${rolesArray})`)}
${lockTable(DG, { read: true })}
`
      : "";

  const nodeColumns = [
    lockColumns
      ? `alter table ${T} add column if not exists ${n("lockedBy")} uuid;\nalter table ${T} add column if not exists ${n("lockedUntil")} timestamptz;\n`
      : "",
    has("lockNote")
      ? `alter table ${T} add column if not exists ${n("lockNote")} text check (length(${n("lockNote")}) <= 500);\n`
      : "",
    downloadColumn
      ? `alter table ${T} add column if not exists ${n("downloadBlocked")} boolean not null default false;\n`
      : "",
    previewColumn
      ? `alter table ${T} add column if not exists ${n("previewPages")} integer check (${n("previewPages")} >= 0);\n`
      : "",
  ].join("");

  const nodeTable = ctx.owns("nodes")
    ? `create table if not exists ${T} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${driveColumn ? `${n("drive")} uuid not null,` : ""}
  ${n("parent")} uuid references ${T} (${n("id")}) on delete cascade,
  ${n("kind")} text not null check (${n("kind")} in ('folder', 'file')),
  ${n("name")} text not null check (length(btrim(${n("name")})) between 1 and 255 and ${n("name")} !~ '[/[:cntrl:]]'),
  ${n("attachment")} uuid,
  ${n("path")} text not null default '',
  ${n("rank")} text collate "C" not null default 'V' check (${n("rank")} ~ ${RANK_KEY_PATTERN}),
  ${n("deletedAt")} timestamptz,
  ${sourceColumn ? `${n("source")} text not null default 'internal' check (${n("source")} = any (${sourcesArray})),` : ""}
  ${externalColumn ? `${n("externalId")} text,` : ""}
  ${metadataColumn ? `${n("externalMetadata")} jsonb not null default '{}'::jsonb,` : ""}
  ${holdColumn ? `${n("legalHoldUntil")} timestamptz,` : ""}
  ${lockColumns ? `${n("lockedBy")} uuid,\n  ${n("lockedUntil")} timestamptz,` : ""}
  ${has("lockNote") ? `${n("lockNote")} text check (length(${n("lockNote")}) <= 500),` : ""}
  ${downloadColumn ? `${n("downloadBlocked")} boolean not null default false,` : ""}
  ${previewColumn ? `${n("previewPages")} integer check (${n("previewPages")} >= 0),` : ""}
  ${n("createdBy")} uuid default auth.uid(),
  ${n("createdAt")} timestamptz not null default now(),
  ${n("updatedAt")} timestamptz not null default now()${
    drives
      ? `,
  foreign key (${n("drive")}, ${n("tenant")}) references ${D} (${d("id")}, ${d("tenant")}) on delete cascade`
      : ""
  }${
    externalColumn && sourceColumn
      ? `,
  check (${n("externalId")} is null or ${n("source")} <> 'internal')`
      : ""
  }
);${addExtraColumns(T, extras)}
create unique index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_sibling_name_idx`)} on ${T} (${n("tenant")}${driveColumn ? `, ${n("drive")}` : ""}, coalesce(${n("parent")}, '00000000-0000-0000-0000-000000000000'::uuid), lower(${n("name")})) where ${n("deletedAt")} is null${sourceColumn ? ` and ${n("source")} = 'internal'` : ""};
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_parent_idx`)} on ${T} (${n("tenant")}${driveColumn ? `, ${n("drive")}` : ""}, ${n("parent")}, ${n("rank")});
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_parent_fk_idx`)} on ${T} (${n("parent")}) where ${n("parent")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_path_idx`)} on ${T} (${n("path")} text_pattern_ops);
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_attachment_idx`)} on ${T} (${n("attachment")});${
        driveColumn
          ? `
create index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_drive_idx`)} on ${T} (${n("tenant")}, ${n("drive")}, ${n("parent")}, ${n("rank")});`
          : ""
      }${
        externalColumn
          ? `
create unique index if not exists ${sqlIdent(`${ctx.tableName("nodes").name}_external_idx`)} on ${T} (${driveColumn ? `${n("drive")}, ` : `${n("tenant")}, `}${n("source")}, ${n("externalId")}) where ${n("externalId")} is not null${binColumn ? ` and ${n("deletedAt")} is null` : ""};`
          : ""
      }
${nodeColumns}${lockTable(T, { read: true })}
`
    : "";

  const grantIdentity = ctx.owns("grants")
    ? typed
      ? `  ${g("principalType")} text not null check (${g("principalType")} in ('user', 'team', 'role')),
  ${g("principalId")} text not null,`
      : `  ${g("user")} uuid${teamColumn ? "" : " not null"},${
          teamColumn
            ? `
  ${g("team")} uuid,
  check ((${g("user")} is not null)::int + (${g("team")} is not null)::int = 1),`
            : ""
        }`
    : "";

  const grantUnique =
    ctx.owns("grants") && typed
      ? `  unique (${g("node")}, ${g("principalType")}, ${g("principalId")})`
      : "";

  const grantIndexes = ctx.owns("grants")
    ? typed
      ? `create index if not exists ${sqlIdent(`${ctx.tableName("grants").name}_principal_idx`)} on ${G} (${g("principalType")}, ${g("principalId")});`
      : `create unique index if not exists ${sqlIdent(`${ctx.tableName("grants").name}_user_idx`)} on ${G} (${g("node")}, ${g("user")}) where ${g("user")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("grants").name}_user_principal_idx`)} on ${G} (${g("user")}) where ${g("user")} is not null;${
          teamColumn
            ? `
create unique index if not exists ${sqlIdent(`${ctx.tableName("grants").name}_team_idx`)} on ${G} (${g("node")}, ${g("team")}) where ${g("team")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("grants").name}_team_principal_idx`)} on ${G} (${g("team")}) where ${g("team")} is not null;`
            : ""
        }`
    : "";

  const grantTable = ctx.owns("grants")
    ? `create table if not exists ${G} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("node")} uuid not null references ${T} (${n("id")}) on delete cascade,
${grantIdentity}
  ${g("role")} text not null,
  ${g("expiresAt")} timestamptz,
  ${g("createdBy")} uuid default auth.uid(),
  ${g("createdAt")} timestamptz not null default now()${grantUnique ? "," : ""}
${grantUnique ? `${grantUnique}\n` : ""});
${grantIndexes}
${ensureCheck(G, "bsb_drive_grants_role", `${g("role")} = any (${rolesArray})`)}
${lockTable(G, { read: false })}
`
    : "";

  return `${connectionTable}${driveTable}${driveGrantTable}${nodeTable}${grantTable}`;
}

export function driveTriggersSql(kit: DriveKit): string {
  const { ctx, T, n, fn, drives, D, d, pathMode } = kit;

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

  const driveTriggers = drives
    ? `
-- A node belongs to its drive: the root names it, children inherit it, and
-- a subtree keeps its drive when it moves.
create or replace function ${fn("drive_node_drive")}()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_drive uuid;
  v_parent_tenant text;
begin
  if new.${n("parent")} is null then
    if new.${n("drive")} is null then
      ${fail("DRIVE_REQUIRED", "a top-level item needs a drive", "22023")}
    end if;
    if not exists (
      select 1 from ${D} d where d.${d("id")} = new.${n("drive")} and d.${d("tenant")} = new.${n("tenant")}
    ) then
      ${fail("DRIVE_NOT_FOUND", "drive not found", "P0002")}
    end if;
    return new;
  end if;
  select x.${n("drive")}, x.${n("tenant")}::text into v_parent_drive, v_parent_tenant
  from ${T} x where x.${n("id")} = new.${n("parent")};
  if v_parent_drive is null or v_parent_tenant is distinct from new.${n("tenant")}::text then
    ${fail("DRIVE_PARENT_NOT_FOUND", "the parent folder does not exist in this organization", "23503")}
  end if;
  new.${n("drive")} := v_parent_drive;
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_drive")} on ${T};
create trigger ${ctx.trigger("drive_node_drive")}
  before insert or update of ${n("parent")}, ${n("drive")} on ${T}
  for each row execute function ${fn("drive_node_drive")}();

create or replace function ${fn("drive_node_drive_cascade")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.${n("drive")} is not distinct from new.${n("drive")} then
    return null;
  end if;
  with recursive down (id) as (
    select x.${n("id")} from ${T} x where x.${n("id")} = new.${n("id")}
    union all
    select x.${n("id")} from ${T} x join down on x.${n("parent")} = down.id
  )
  update ${T} x set ${n("drive")} = new.${n("drive")}
  where x.${n("id")} in (select id from down) and x.${n("drive")} is distinct from new.${n("drive")};
  return null;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_drive_cascade")} on ${T};
create trigger ${ctx.trigger("drive_node_drive_cascade")}
  after update of ${n("drive")} on ${T}
  for each row execute function ${fn("drive_node_drive_cascade")}();
`
    : "";

  return `${pathTriggers}${driveTriggers}`;
}
