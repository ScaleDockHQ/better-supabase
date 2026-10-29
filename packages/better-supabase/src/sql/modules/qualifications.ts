import type { QualificationsEvents } from "../../blocks/qualifications/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";
import { qualificationFunctions } from "./qualifications-functions.ts";
import { qualificationGapFunctions } from "./qualifications-gaps.ts";
import {
  evidenceAttachments,
  HOLDER_TYPES,
  holderTypes,
  QUALIFICATION_RESERVED,
  renewalWindow,
  SOURCES,
  sqlList,
  TARGET_TYPES,
} from "./qualifications-shared.ts";

const HOLDING = [
  "organizationId",
  "qualificationId",
  "qualificationTypeId",
  "typeKey",
  "holderType",
  "holderId",
] as const;

const EVENTS: BlockSqlEvents<QualificationsEvents> = {
  "qualification_type.created": {
    subject: "qualification-types",
    payload: ["organizationId", "qualificationTypeId", "key", "name"],
  },
  "qualification_type.updated": {
    subject: "qualification-types",
    payload: ["organizationId", "qualificationTypeId", "key", "name"],
  },
  "qualification_type.archived": {
    subject: "qualification-types",
    payload: ["organizationId", "qualificationTypeId", "key"],
  },
  "qualification.granted": {
    subject: "qualifications",
    payload: [...HOLDING, "grantedOn", "expiresOn", "source"],
  },
  "qualification.revoked": {
    subject: "qualifications",
    payload: [...HOLDING, "reason"],
  },
  "qualification.expiry_warned": {
    subject: "qualifications",
    payload: [...HOLDING, "expiresOn"],
  },
  "qualification.expired": {
    subject: "qualifications",
    payload: [...HOLDING, "expiresOn"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    qualification: {
      table: "qualifications",
      singular: "qualification",
      primary: true,
    },
    qualification_type: {
      table: "types",
      singular: "qualification_type",
      subject: {
        title: "name",
        permissions: { read: "read", write: "manage" },
      },
    },
    qualification_requirement: {
      table: "requirements",
      singular: "qualification_requirement",
    },
  },
  events: EVENTS,
  hooks: [
    "before_qualification_type_save",
    "after_qualification_type_save",
    "before_qualification_grant",
    "after_qualification_grant",
    "before_qualification_revoke",
    "after_qualification_revoke",
  ],
  options: ["holderTypes", "renewalWindowDays", "extraColumns"],
  tables: {
    types: {
      name: "qualification_types",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        description: "description",
        holderTypes: "holder_types",
        validForMonths: "valid_for_months",
        evidenceRequired: "evidence_required",
        course: "course_id",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "course", "createdAt", "updatedAt"],
    },
    requirements: {
      name: "qualification_requirements",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        type: "type_id",
        targetType: "target_type",
        targetValue: "target_value",
        createdAt: "created_at",
      },
      optional: ["createdAt"],
    },
    qualifications: {
      name: "qualifications",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        type: "type_id",
        holderType: "holder_type",
        holderId: "holder_id",
        grantedOn: "granted_on",
        expiresOn: "expires_on",
        revokedAt: "revoked_at",
        revokeReason: "revoke_reason",
        evidenceAttachment: "evidence_attachment_id",
        evidenceNote: "evidence_note",
        source: "source",
        sourceId: "source_id",
        grantedBy: "granted_by",
        notifiedStatus: "notified_status",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "revokeReason",
        "evidenceNote",
        "grantedBy",
        "createdAt",
        "updatedAt",
      ],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const types = ctx.table("types");
  const requirements = ctx.table("requirements");
  const holdings = ctx.table("qualifications");
  const t = (column: string): string => ctx.col("types", column);
  const r = (column: string): string => ctx.col("requirements", column);
  const q = (column: string): string => ctx.col("qualifications", column);
  const read = ctx.permission("read", moduleOperations("qualifications").read);
  const extras = ctx.extraColumns("qualifications", QUALIFICATION_RESERVED);
  const attachments = evidenceAttachments(ctx);

  const courses =
    ctx.installed("courses") && ctx.of("courses").owns("courses")
      ? ctx.of("courses")
      : undefined;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const stamps = (logical: string, columns: readonly string[]): string =>
    columns
      .map((column) =>
        opt(
          logical,
          column,
          () =>
            `${ctx.col(logical, column)} timestamptz not null default now()`,
        ),
      )
      .join("");

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const courseRef =
    courses === undefined
      ? ""
      : ` references ${courses.table("courses")} (${courses.col("courses", "id")}) on delete set null`;

  const attachmentRef =
    attachments === undefined
      ? ""
      : ` references ${attachments.table("attachments")} (${attachments.col("attachments", "id")}) on delete set null`;

  // Members read the types and requirements of their organizations, so they
  // see what they need; holdings are theirs or need qualifications.read.
  const memberOf = (column: string): string =>
    `${ctx.scope.check(column, read)} or ${column} in (select ${ctx.scope.members()})`;

  return `
create table if not exists ${types} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("key")} text not null check (${t("key")} ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  ${t("name")} text not null check (length(${t("name")}) between 1 and 200),${opt("types", "description", () => `${t("description")} text check (${t("description")} is null or length(${t("description")}) <= 4000)`)}
  -- The holders the type applies to: member, company or asset.
  ${t("holderTypes")} text[] not null check (cardinality(${t("holderTypes")}) > 0),
  -- A holding expires this many months after it is granted; null never expires.
  ${t("validForMonths")} integer check (${t("validForMonths")} is null or ${t("validForMonths")} between 1 and 240),
  ${t("evidenceRequired")} boolean not null default false,${opt("types", "course", () => `${t("course")} uuid${courseRef}`)}
  ${t("archivedAt")} timestamptz,${stamps("types", ["createdAt", "updatedAt"])}
  unique (${t("tenant")}, ${t("key")}),
  unique (${t("tenant")}, ${t("id")})
);${appKey("types", "tenant_key", `${t("tenant")}, ${t("key")}`)}${appKey("types", "tenant_id", `${t("tenant")}, ${t("id")}`)}${
    ctx.has("types", "course")
      ? `\ncreate index if not exists ${name("types", "course_idx")} on ${types} (${t("course")}) where ${t("course")} is not null;`
      : ""
  }
${lockModuleTable(ctx, "types", { read: true })}
${readPolicy("types", memberOf(t("tenant")))}

create table if not exists ${requirements} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("type")} uuid not null,
  -- Who must hold the type: a role, a team, a job title, an asset kind, a
  -- segment of companies, or one holder.
  ${r("targetType")} text not null check (${r("targetType")} in ${sqlList(Object.keys(TARGET_TYPES))}),
  ${r("targetValue")} text not null check (length(${r("targetValue")}) between 1 and 200),${stamps("requirements", ["createdAt"])}
  unique (${r("type")}, ${r("targetType")}, ${r("targetValue")}),
  foreign key (${r("tenant")}, ${r("type")}) references ${types} (${t("tenant")}, ${t("id")}) on delete cascade
);${appKey("requirements", "target_key", `${r("type")}, ${r("targetType")}, ${r("targetValue")}`)}
create index if not exists ${name("requirements", "tenant_idx")} on ${requirements} (${r("tenant")}, ${r("type")});
${lockModuleTable(ctx, "requirements", { read: true })}
${readPolicy("requirements", memberOf(r("tenant")))}

create table if not exists ${holdings} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("type")} uuid not null,
  ${q("holderType")} text not null check (${q("holderType")} in ${sqlList(HOLDER_TYPES)}),
  ${q("holderId")} text not null check (length(${q("holderId")}) between 1 and 200),
  ${q("grantedOn")} date not null,
  ${q("expiresOn")} date,
  ${q("revokedAt")} timestamptz,${opt("qualifications", "revokeReason", () => `${q("revokeReason")} text check (${q("revokeReason")} is null or length(${q("revokeReason")}) <= 2000)`)}
  ${q("evidenceAttachment")} uuid${attachmentRef},${opt("qualifications", "evidenceNote", () => `${q("evidenceNote")} text check (${q("evidenceNote")} is null or length(${q("evidenceNote")}) <= 4000)`)}
  ${q("source")} text not null default 'manual' check (${q("source")} in ${sqlList(SOURCES)}),
  -- The record behind a course or import holding, such as the certificate id.
  ${q("sourceId")} text,${opt("qualifications", "grantedBy", () => `${q("grantedBy")} uuid`)}
  -- The status notify_expiring_qualifications last reported, so each one
  -- notifies once.
  ${q("notifiedStatus")} text check (${q("notifiedStatus")} is null or ${q("notifiedStatus")} in ('expiring', 'expired')),${stamps("qualifications", ["createdAt", "updatedAt"])}
  check (${q("expiresOn")} is null or ${q("expiresOn")} >= ${q("grantedOn")}),
  foreign key (${q("tenant")}, ${q("type")}) references ${types} (${t("tenant")}, ${t("id")}) on delete cascade
);${addExtraColumns(holdings, extras)}
create index if not exists ${name("qualifications", "holder_idx")} on ${holdings} (${q("tenant")}, ${q("holderType")}, ${q("holderId")});
create index if not exists ${name("qualifications", "type_idx")} on ${holdings} (${q("tenant")}, ${q("type")});
create index if not exists ${name("qualifications", "expiry_idx")} on ${holdings} (${q("type")}, ${q("expiresOn")});
create index if not exists ${name("qualifications", "source_idx")} on ${holdings} (${q("source")}, ${q("sourceId")}) where ${q("sourceId")} is not null;${
    attachmentRef === ""
      ? ""
      : `\ncreate index if not exists ${name("qualifications", "evidence_idx")} on ${holdings} (${q("evidenceAttachment")}) where ${q("evidenceAttachment")} is not null;`
  }
${lockModuleTable(ctx, "qualifications", { read: true })}
${readPolicy("qualifications", `(${q("holderType")} = 'member' and ${q("holderId")} = (select auth.uid())::text) or ${ctx.scope.check(q("tenant"), read)}`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  holderTypes(ctx);
  renewalWindow(ctx);

  return `${schemaPreamble(ctx)}
-- Qualifications: types of certification, licence or skill, who must hold
-- them (requirements), and the holdings of members, companies and assets
-- with their expiry.
${tables(ctx)}${qualificationFunctions(ctx)}${qualificationGapFunctions(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("qualifications", QUALIFICATION_RESERVED),
  ).contract;

  return [
    {
      name: "save_qualification_type",
      args: [
        "{id}",
        "text",
        "text",
        "text[]",
        "integer",
        "boolean",
        "uuid",
        "text",
        "uuid",
      ],
      returns: "jsonb",
    },
    { name: "archive_qualification_type", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_qualification_types",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "add_qualification_requirement",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "remove_qualification_requirement",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "list_qualification_requirements",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "grant_qualification",
      args: ["{id}", "text", "text", "text", "date", "uuid", "text", ...extra],
      returns: "jsonb",
    },
    { name: "revoke_qualification", args: ["uuid", "text"], returns: "jsonb" },
    { name: "qualifications_of", args: ["text", "text"], returns: "jsonb" },
    {
      name: "qualification_gaps",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "qualified_holders",
      args: ["{id}", "text", "text", "date"],
      returns: "jsonb",
    },
    { name: "notify_expiring_qualifications", args: [], returns: "integer" },
  ];
}

export const QUALIFICATIONS: BlockSqlDefinition = {
  name: "qualifications",
  scopes: ["tenant"],
  title: "Qualifications",
  description:
    "Qualification types (certifications, licences, skills) with a validity in months and optional evidence, requirements naming who must hold them (a role, a team, a job title, an asset kind, a segment or one holder), holdings of members, companies and assets that expire, a gap report, the holders qualified on a date, expiry notifications, and holdings granted from course certificates.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: [
    "courses",
    "employees",
    "teams",
    "contacts",
    "assets",
    "segments",
    "attachments",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  internal: ["qualification_course_certificate"],
};
