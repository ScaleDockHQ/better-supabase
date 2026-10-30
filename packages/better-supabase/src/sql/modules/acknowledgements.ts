import type { AcknowledgementsEvents } from "../../blocks/acknowledgements/events.ts";
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
import { acknowledgementFunctions } from "./acknowledgements-functions.ts";
import { moduleOperations } from "./permissions-model.ts";

const SUBJECT_PAYLOAD = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: BlockSqlEvents<AcknowledgementsEvents> = {
  "acknowledgement_assignment.created": {
    subject: "acknowledgement-assignments",
    payload: [
      ...SUBJECT_PAYLOAD,
      "assignmentId",
      "principalType",
      "principalId",
    ],
  },
  "acknowledgement_assignment.deleted": {
    subject: "acknowledgement-assignments",
    payload: [
      ...SUBJECT_PAYLOAD,
      "assignmentId",
      "principalType",
      "principalId",
    ],
  },
  "acknowledgement.created": {
    subject: "acknowledgements",
    payload: [...SUBJECT_PAYLOAD, "versionId", "userId"],
  },
  "acknowledgement.reminded": {
    subject: "acknowledgements",
    payload: [...SUBJECT_PAYLOAD, "versionId", "userId", "dueOn"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    acknowledgement: {
      table: "acknowledgements",
      singular: "acknowledgement",
      primary: true,
    },
    acknowledgement_assignment: {
      table: "assignments",
      singular: "acknowledgement_assignment",
    },
  },
  events: EVENTS,
  hooks: [
    "before_acknowledgement_assignment_create",
    "after_acknowledgement_assignment_create",
    "before_acknowledgement_create",
    "after_acknowledgement_create",
  ],
  tables: {
    assignments: {
      name: "acknowledgement_assignments",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        principalType: "principal_type",
        principalId: "principal_id",
        dueInDays: "due_in_days",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["createdBy", "createdAt"],
    },
    acknowledgements: {
      name: "acknowledgements",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        version: "version_id",
        user: "user_id",
        method: "method",
        signature: "signature_id",
        acknowledgedAt: "acknowledged_at",
      },
      optional: ["method", "signature"],
    },
    notices: {
      name: "acknowledgement_notices",
      app: {},
      lifecycle: { tenant: "tenant", user: "user" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        version: "version_id",
        user: "user_id",
        notifiedAt: "notified_at",
      },
    },
  },
};

/**
 * The acknowledgements tables, also run by the compliance upgrade that moves
 * policy acknowledgements here before the module files.
 */
export function acknowledgementTables(ctx: BlockSqlContext): string {
  const assignments = ctx.table("assignments");
  const acks = ctx.table("acknowledgements");
  const notices = ctx.table("notices");
  const g = (column: string): string => ctx.col("assignments", column);
  const a = (column: string): string => ctx.col("acknowledgements", column);
  const n = (column: string): string => ctx.col("notices", column);

  const read = ctx.permission(
    "read",
    moduleOperations("acknowledgements").read,
  );

  const versions = ctx.of("versions");

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

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

  const versionRef = versions.owns("versions")
    ? ` references ${versions.table("versions")} (${versions.col("versions", "id")}) on delete restrict`
    : "";

  const principalKey = `${g("tenant")}, ${g("subjectType")}, ${g("subjectId")}, ${g("principalType")}, ${g("principalId")}`;
  const ackKey = `${a("subjectType")}, ${a("subjectId")}, ${a("version")}, ${a("user")}`;
  const noticeKey = `${n("subjectType")}, ${n("subjectId")}, ${n("version")}, ${n("user")}`;

  return `
-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists ${assignments} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("subjectType")} text not null,
  ${g("subjectId")} text not null,
  ${g("principalType")} text not null check (${g("principalType")} in ('user', 'team', 'role')),
  ${g("principalId")} text not null check (length(${g("principalId")}) between 1 and 200),
  ${g("dueInDays")} integer check (${g("dueInDays")} is null or (${g("dueInDays")} >= 1 and ${g("dueInDays")} <= 365)),${opt("assignments", "createdBy", () => `${g("createdBy")} uuid default auth.uid()`)}${opt("assignments", "createdAt", () => `${g("createdAt")} timestamptz not null default now()`)}
  unique (${principalKey})
);${appKey("assignments", "principal", principalKey)}
create index if not exists ${name("assignments", "principal_idx")} on ${assignments} (${g("tenant")}, ${g("principalType")}, ${g("principalId")});
${lockTable(assignments, { read: true })}
${readPolicy("assignments", ctx.scope.check(g("tenant"), read))}

-- One row per member and version of a record they acknowledged.
create table if not exists ${acks} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("subjectType")} text not null,
  ${a("subjectId")} text not null,
  ${a("version")} uuid not null${versionRef},
  ${a("user")} uuid not null,${opt("acknowledgements", "method", () => `${a("method")} text not null default 'click' check (${a("method")} in ('click', 'signature'))`)}${opt("acknowledgements", "signature", () => `${a("signature")} uuid`)}
  ${a("acknowledgedAt")} timestamptz not null default now(),
  unique (${ackKey})
);${appKey("acknowledgements", "version_user", ackKey)}
create index if not exists ${name("acknowledgements", "user_idx")} on ${acks} (${a("tenant")}, ${a("user")});
create index if not exists ${name("acknowledgements", "version_idx")} on ${acks} (${a("version")}, ${a("subjectType")}, ${a("subjectId")});
${lockTable(acks, { read: true })}
${readPolicy("acknowledgements", `${a("user")} = (select auth.uid()) or ${ctx.scope.check(a("tenant"), read)}`)}

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists ${notices} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${n("subjectType")} text not null,
  ${n("subjectId")} text not null,
  ${n("version")} uuid not null,
  ${n("user")} uuid not null,
  ${n("notifiedAt")} timestamptz not null default now(),
  unique (${noticeKey})
);${appKey("notices", "version_user", noticeKey)}
${lockTable(notices)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("versions").mode === "custom") {
    throw new TypeError(
      "blocks.acknowledgements needs the versions tables; versions can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.
${acknowledgementTables(ctx)}${acknowledgementFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "assign_acknowledgement",
      args: ["{id}", "text", "text", "text", "text", "integer"],
      returns: "jsonb",
    },
    { name: "unassign_acknowledgement", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_acknowledgement_assignments",
      args: ["text", "text"],
      returns: "jsonb",
    },
    {
      name: "acknowledge",
      args: ["text", "text", "uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_my_acknowledgements",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "acknowledgement_status",
      args: ["text", "text"],
      returns: "jsonb",
    },
    {
      name: "acknowledgements_of",
      args: ["text", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "notify_due_acknowledgements", args: [], returns: "integer" },
  ];
}

export const ACKNOWLEDGEMENTS: BlockSqlDefinition = {
  name: "acknowledgements",
  scopes: ["tenant"],
  title: "Acknowledgements",
  description:
    "Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.",
  requires: ["memberships", "permissions", "versions"],
  integrates: [
    "subjects",
    "teams",
    "signatures",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
