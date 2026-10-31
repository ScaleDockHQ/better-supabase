import type { DamEvents } from "../../blocks/dam/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { damFunctions } from "./dam-functions.ts";
import { damSql } from "./dam-sql.ts";
import { DAM_RENDITION_STATUSES } from "./dam-values.ts";

const RIGHT = [
  "organizationId",
  "id",
  "nodeId",
  "licensee",
  "expiresOn",
] as const;

const right = { subject: "dam-usage-rights", payload: RIGHT } as const;

const EVENTS: BlockSqlEvents<DamEvents> = {
  "dam_rendition.recorded": {
    subject: "dam-renditions",
    payload: ["organizationId", "id", "nodeId", "kind", "status"],
  },
  "dam_usage_right.granted": right,
  "dam_usage_right.revoked": right,
  "dam_usage_right.expiry_notified": right,
};

const NAMES: BlockSqlNames = {
  entities: {
    dam_usage_right: {
      table: "rights",
      singular: "dam_usage_right",
      primary: true,
      subject: {
        title: "licensee",
        permissions: { read: "read", write: "write" },
      },
    },
    dam_rendition: { table: "renditions", singular: "dam_rendition" },
  },
  events: EVENTS,
  hooks: ["before_dam_usage_right_create", "after_dam_usage_right_create"],
  options: [],
  tables: {
    rights: {
      name: "dam_usage_rights",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        node: "node_id",
        licensee: "licensee",
        territory: "territory",
        channel: "channel",
        startsOn: "starts_on",
        expiresOn: "expires_on",
        note: "note",
        revokedAt: "revoked_at",
        remindedFor: "reminded_for",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    renditions: {
      name: "dam_renditions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        node: "node_id",
        kind: "kind",
        status: "status",
        format: "format",
        width: "width",
        height: "height",
        sizeBytes: "size_bytes",
        path: "path",
        error: "error",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = damSql(ctx);
  const { n, u, renditions, rights } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, q.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  return `
-- The derived versions of a drive file: a thumbnail, a web size. One row per
-- file and kind; the files live in storage under path.
create table if not exists ${renditions} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${n("node")} uuid not null,
  ${n("kind")} text not null check (${n("kind")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${n("status")} text not null default 'ready' check (${n("status")} in (${list(DAM_RENDITION_STATUSES)})),
  ${n("format")} text check (${n("format")} is null or length(${n("format")}) <= 20),
  ${n("width")} integer check (${n("width")} is null or ${n("width")} > 0),
  ${n("height")} integer check (${n("height")} is null or ${n("height")} > 0),
  ${n("sizeBytes")} bigint check (${n("sizeBytes")} is null or ${n("sizeBytes")} >= 0),
  ${n("path")} text check (${n("path")} is null or length(${n("path")}) <= 1000),
  ${n("error")} text check (${n("error")} is null or length(${n("error")}) <= 500),
  ${n("createdAt")} timestamptz not null default now(),
  ${n("updatedAt")} timestamptz not null default now(),
  unique (${n("tenant")}, ${n("node")}, ${n("kind")})
);${appKey("renditions", "tenant_node_kind", `${n("tenant")}, ${n("node")}, ${n("kind")}`)}
${lockTable(renditions, { read: true })}
${readPolicy("renditions", n("tenant"))}

-- Who may use a file, where and until when. A row without territory or channel
-- covers all of them; one without expires_on never ends. A revoked right stays.
create table if not exists ${rights} (
  ${u("id")} uuid primary key default gen_random_uuid(),
  ${u("tenant")} ${ctx.idType} not null,
  ${u("node")} uuid not null,
  ${u("licensee")} text not null check (length(${u("licensee")}) between 1 and 200),
  ${u("territory")} text check (${u("territory")} is null or length(${u("territory")}) between 1 and 100),
  ${u("channel")} text check (${u("channel")} is null or length(${u("channel")}) between 1 and 100),
  ${u("startsOn")} date not null default current_date,
  ${u("expiresOn")} date,
  ${u("note")} text check (${u("note")} is null or length(${u("note")}) <= 2000),
  ${u("revokedAt")} timestamptz,
  -- The expiry date the reminder last went out for.
  ${u("remindedFor")} date,
  ${u("createdBy")} uuid,
  ${u("createdAt")} timestamptz not null default now(),
  check (${u("expiresOn")} is null or ${u("expiresOn")} >= ${u("startsOn")})
);${appKey("rights", "tenant_id", `${u("tenant")}, ${u("id")}`)}
create index if not exists ${name("rights", "node_idx")} on ${rights} (${u("tenant")}, ${u("node")});
create index if not exists ${name("rights", "expiry_idx")} on ${rights} (${u("expiresOn")}) where ${u("revokedAt")} is null and ${u("expiresOn")} is not null;
${lockTable(rights, { read: true })}
${readPolicy("rights", u("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Digital asset management on the drive: renditions of a file and the usage
-- rights that say who may use it, where and until when.
${tables(ctx)}
${damFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "record_rendition",
      args: ["{id}", "uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "list_renditions", args: ["{id}", "uuid"], returns: "jsonb" },
    { name: "grant_usage_right", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "revoke_usage_right", args: ["uuid"], returns: "jsonb" },
    { name: "list_usage_rights", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "check_usage", args: ["{id}", "uuid", "jsonb"], returns: "jsonb" },
    {
      name: "notify_expiring_usage_rights",
      args: ["integer"],
      returns: "integer",
    },
  ];
}

export const DAM: BlockSqlDefinition = {
  name: "dam",
  scopes: ["tenant"],
  title: "Digital asset management",
  description:
    "Renditions of drive files (thumbnails and web sizes made through the drive's preview renderers) and usage rights with a territory, a channel and an expiry date, with a reminder before a right ends.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["drive", "outbox", "audit", "notifications"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
