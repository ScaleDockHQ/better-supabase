import type { CasesEvents } from "../../blocks/cases/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { RANK_KEY_PATTERN } from "../rank-sql.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { caseCloseFunctions } from "./cases-close.ts";
import { caseFunctions } from "./cases-functions.ts";
import { caseReadFunctions } from "./cases-read.ts";
import {
  CASE_ACTION_TYPES,
  CASE_STAGES,
  CASE_STATUSES,
  casesSql,
} from "./cases-sql.ts";
import { myWorkTenant } from "./subjects.ts";

const CASE = [
  "organizationId",
  "caseId",
  "kind",
  "number",
  "title",
  "status",
] as const;

const kase = { subject: "cases", payload: CASE } as const;

const kind = {
  subject: "case-kinds",
  payload: ["organizationId", "caseKindId", "key", "name", "prefix"],
} as const;

const EVENTS: BlockSqlEvents<CasesEvents> = {
  "case_kind.created": kind,
  "case_kind.updated": kind,
  "case_kind.archived": kind,
  "case.created": kase,
  "case.updated": { subject: "cases", payload: [...CASE, "changed"] },
  "case.root_cause_recorded": {
    subject: "cases",
    payload: [...CASE, "rootCause"],
  },
  "case_action.created": {
    subject: "cases",
    payload: [...CASE, "actionId", "taskId", "type", "required"],
  },
  "case_action.deleted": {
    subject: "cases",
    payload: [...CASE, "actionId", "taskId", "type"],
  },
  "case.effectiveness_recorded": {
    subject: "cases",
    payload: [...CASE, "effective", "note"],
  },
  "case.effectiveness_date_reached": {
    subject: "cases",
    payload: [...CASE, "ownerId", "effectivenessDueOn"],
  },
  "case.closed": { subject: "cases", payload: [...CASE, "note"] },
  "case.reopened": { subject: "cases", payload: [...CASE, "reason"] },
  "case.cancelled": { subject: "cases", payload: [...CASE, "reason"] },
};

const NAMES: BlockSqlNames = {
  entities: {
    case: {
      table: "cases",
      singular: "case",
      primary: true,
      subject: {
        title: "title",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "write" },
        rank: { column: "rank", group: "stage" },
        search: {
          title: "title",
          body: ["number", "description", "rootCause"],
        },
      },
    },
    case_kind: { table: "kinds", singular: "case_kind" },
    case_action: { table: "actions", singular: "case_action" },
  },
  events: EVENTS,
  hooks: [
    "before_case_open",
    "after_case_open",
    "before_case_close",
    "after_case_close",
  ],
  options: ["severities", "sources", "kinds", "intakeKind", "extraColumns"],
  tables: {
    kinds: {
      name: "case_kinds",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        prefix: "prefix",
        pipeline: "pipeline_id",
        investigationForm: "investigation_form_id",
        effectivenessForm: "effectiveness_form_id",
        effectivenessAfterDays: "effectiveness_after_days",
        requiresRootCause: "requires_root_cause",
        requiresActions: "requires_actions",
        requiresEffectiveness: "requires_effectiveness",
        requiresRevisions: "requires_revisions",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    cases: {
      name: "cases",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind_id",
        number: "number",
        sequence: "sequence",
        title: "title",
        description: "description",
        severity: "severity",
        source: "source",
        reporter: "reporter_id",
        reporterContact: "reporter_contact",
        owner: "owner_id",
        occurredAt: "occurred_at",
        detectedAt: "detected_at",
        dueOn: "due_on",
        pipeline: "pipeline_id",
        stage: "stage_id",
        stageEnteredAt: "stage_entered_at",
        status: "status",
        rootCause: "root_cause",
        rootCauseSubmission: "root_cause_submission_id",
        effective: "effective",
        effectivenessDueOn: "effectiveness_due_on",
        effectivenessNotifiedFor: "effectiveness_notified_for",
        effectivenessNote: "effectiveness_note",
        effectivenessSubmission: "effectiveness_submission_id",
        closedAt: "closed_at",
        closedBy: "closed_by",
        closeNote: "close_note",
        rank: "rank",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "reporterContact", "createdBy"],
    },
    actions: {
      name: "case_actions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        case: "case_id",
        task: "task_id",
        type: "type",
        required: "required",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = casesSql(ctx);
  const { k, c, a, kinds, cases, actions } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

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

  const text = (column: string, max: number): string =>
    `${column} text check (${column} is null or length(${column}) <= ${String(max)})`;

  return `
create table if not exists ${kinds} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("key")} text not null check (${k("key")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${k("name")} text not null check (length(${k("name")}) between 1 and 200),
  -- The capital letters case numbers start with, such as NC-2026-0001.
  ${k("prefix")} text not null check (${k("prefix")} ~ '^[A-Z]{1,6}$'),
  -- The kind's pipeline, one per kind (pipelines scope cases by kind).
  ${k("pipeline")} uuid,
  ${k("investigationForm")} uuid,
  ${k("effectivenessForm")} uuid,
  ${k("effectivenessAfterDays")} integer check (${k("effectivenessAfterDays")} is null or ${k("effectivenessAfterDays")} between 1 and 365),
  ${k("requiresRootCause")} boolean not null default true,
  ${k("requiresActions")} boolean not null default true,
  ${k("requiresEffectiveness")} boolean not null default false,
  ${k("requiresRevisions")} boolean not null default false,
  ${k("archivedAt")} timestamptz,
  ${k("createdAt")} timestamptz not null default now(),
  ${k("updatedAt")} timestamptz not null default now(),
  unique (${k("tenant")}, ${k("key")}),
  unique (${k("tenant")}, ${k("id")})
);${appKey("kinds", "tenant_key", `${k("tenant")}, ${k("key")}`)}${appKey("kinds", "tenant_id", `${k("tenant")}, ${k("id")}`)}
${lockTable(kinds, { read: true })}
${readPolicy("kinds", k("tenant"))}

create table if not exists ${cases} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("kind")} uuid not null,
  -- The kind's prefix and the number numbering gives, such as NC-2026-0001.
  ${c("number")} text not null check (length(${c("number")}) between 1 and 100),
  ${c("sequence")} bigint not null,
  ${c("title")} text not null check (length(${c("title")}) between 1 and 200),${opt("cases", "description", () => text(c("description"), 20_000))}
  -- One of options.severities and options.sources; the functions check them.
  ${c("severity")} text check (${c("severity")} is null or length(${c("severity")}) between 1 and 41),
  ${c("source")} text not null default 'internal' check (length(${c("source")}) between 1 and 41),
  ${c("reporter")} uuid,${opt("cases", "reporterContact", () => `${c("reporterContact")} jsonb check (${c("reporterContact")} is null or jsonb_typeof(${c("reporterContact")}) = 'object')`)}
  ${c("owner")} uuid,
  ${c("occurredAt")} timestamptz,
  ${c("detectedAt")} timestamptz not null default now(),
  ${c("dueOn")} date,
  ${c("pipeline")} uuid,
  ${c("stage")} uuid,
  ${c("stageEnteredAt")} timestamptz,
  -- Follows the stage's outcome: open, closed (success) or canceled (failure).
  ${c("status")} text not null default 'open' check (${c("status")} in (${list(CASE_STATUSES)})),
  ${text(c("rootCause"), 10_000)},
  ${c("rootCauseSubmission")} uuid,
  ${c("effective")} boolean,
  ${c("effectivenessDueOn")} date,
  -- The due date notify_due_case_effectiveness last reported, so each date notifies once.
  ${c("effectivenessNotifiedFor")} date,
  ${text(c("effectivenessNote"), 4000)},
  ${c("effectivenessSubmission")} uuid,
  ${c("closedAt")} timestamptz,
  ${c("closedBy")} uuid,
  ${text(c("closeNote"), 4000)},
  ${c("rank")} text collate "C" check (${c("rank")} is null or ${c("rank")} ~ ${RANK_KEY_PATTERN}),
  ${c("archivedAt")} timestamptz,${opt("cases", "createdBy", () => `${c("createdBy")} uuid default auth.uid()`)}
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  unique (${c("tenant")}, ${c("number")}),
  unique (${c("tenant")}, ${c("id")}),
  foreign key (${c("tenant")}, ${c("kind")}) references ${kinds} (${k("tenant")}, ${k("id")}) on delete restrict
);${addExtraColumns(cases, q.extras)}${appKey("cases", "tenant_number", `${c("tenant")}, ${c("number")}`)}${appKey("cases", "tenant_id", `${c("tenant")}, ${c("id")}`)}
create index if not exists ${name("cases", "status_idx")} on ${cases} (${c("tenant")}, ${c("status")});
create index if not exists ${name("cases", "kind_stage_idx")} on ${cases} (${c("tenant")}, ${c("kind")}, ${c("stage")});
create index if not exists ${name("cases", "board_idx")} on ${cases} (${c("pipeline")}, ${c("stage")}, ${c("rank")});
create index if not exists ${name("cases", "owner_idx")} on ${cases} (${c("owner")}) where ${c("owner")} is not null;
create index if not exists ${name("cases", "effectiveness_idx")} on ${cases} (${c("effectivenessDueOn")}) where ${c("effective")} is null and ${c("status")} = 'open';
${lockTable(cases, { read: true })}
${readPolicy("cases", c("tenant"))}

create table if not exists ${actions} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("case")} uuid not null,
  -- A work item of the tasks block.
  -- No foreign key: the work items table renders after this one.
  ${a("task")} uuid not null,
  ${a("type")} text not null check (${a("type")} in (${list(CASE_ACTION_TYPES)})),
  ${a("required")} boolean not null default true,
  ${a("createdAt")} timestamptz not null default now(),
  unique (${a("case")}, ${a("task")}),
  foreign key (${a("tenant")}, ${a("case")}) references ${cases} (${c("tenant")}, ${c("id")}) on delete cascade
);${appKey("actions", "case_task", `${a("case")}, ${a("task")}`)}
create index if not exists ${name("actions", "tenant_parent_idx")} on ${actions} (${a("tenant")}, ${a("case")});
create index if not exists ${name("actions", "task_idx")} on ${actions} (${a("task")});
${lockTable(actions, { read: true })}
${readPolicy("actions", a("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Cases per organization: nonconformities, complaints, incidents, near misses,
-- changes and findings of tenant-editable kinds, each on its kind's pipeline,
-- with a root cause, actions as work items, an effectiveness check and a close
-- guard that names what still blocks closing.
${tables(ctx)}
${caseFunctions(ctx)}
${caseCloseFunctions(ctx)}
${caseReadFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_case_kind",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "uuid",
        "uuid",
        "integer",
        "boolean",
        "boolean",
        "boolean",
        "boolean",
        "uuid",
      ],
      returns: "jsonb",
    },
    { name: "archive_case_kind", args: ["uuid"], returns: "jsonb" },
    { name: "list_case_kinds", args: ["{id}", "boolean"], returns: "jsonb" },
    {
      name: "open_case",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "timestamptz",
        "uuid",
        "date",
        "jsonb",
      ],
      returns: "jsonb",
    },
    { name: "case_from_submission", args: ["uuid"], returns: "jsonb" },
    { name: "update_case", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "record_case_root_cause",
      args: ["uuid", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "create_case_action",
      args: ["uuid", "text", "text", "uuid", "timestamptz", "boolean"],
      returns: "jsonb",
    },
    {
      name: "link_case_action",
      args: ["uuid", "uuid", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "remove_case_action", args: ["uuid"], returns: "jsonb" },
    {
      name: "record_case_effectiveness",
      args: ["uuid", "boolean", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "case_close_blockers", args: ["uuid"], returns: "text[]" },
    { name: "close_case", args: ["uuid", "text"], returns: "jsonb" },
    { name: "reopen_case", args: ["uuid", "text"], returns: "jsonb" },
    { name: "cancel_case", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_case", args: ["uuid"], returns: "jsonb" },
    { name: "list_cases", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "case_stats",
      args: ["{id}", "text", "date", "date", "text"],
      returns: "jsonb",
    },
    { name: "notify_due_case_effectiveness", args: [], returns: "integer" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  numbering: (own) => [
    {
      entity: own.resolved.entityNaming.rename("case"),
      entry: { period: "year", format: "{yyyy}-{n:4}" },
    },
  ],
  pipelines: (own) => {
    const { schema, name } = own.tableName("cases");

    return [
      {
        type: own.naming.rename("case"),
        table: `${schema}.${name}`,
        tenant: own.colName("cases", "tenant"),
        entry: {
          stage: own.colName("cases", "stage"),
          pipeline: own.colName("cases", "pipeline"),
          enteredAt: own.colName("cases", "stageEnteredAt"),
          scope: own.colName("cases", "kind"),
          categories: { open: "open", closed: "success", canceled: "failure" },
          stages: CASE_STAGES,
        },
      },
    ];
  },
  relations: (own) => [
    {
      kind: "affects",
      inverse: "affected_by",
      types: { source: [own.naming.rename("case")] },
    },
  ],
  subjects: (own) => {
    const c = (column: string): string => `c.${own.col("cases", column)}`;

    return [
      {
        work: `select 'owned'::text, ${sqlString(own.naming.rename("case"))}::text, ${c("id")}::text, ${c("number")}::text, ${c("title")}::text,
      coalesce(${c("dueOn")}::timestamptz, ${c("createdAt")})
    from ${own.table("cases")} c
    where ${c("owner")} = v_me
      and ${c("status")} = 'open'
      and ${c("archivedAt")} is null
      and ${myWorkTenant(c("tenant"))}`,
      },
    ];
  },
};

export const CASES: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "cases",
  scopes: ["tenant"],
  title: "Cases",
  description:
    "Cases per organization: nonconformities, complaints, incidents, near misses, observations, improvements, change requests and audit findings of tenant-editable kinds, numbered per kind, each kind on its own pipeline, with a root cause, containment and corrective actions as work items, an effectiveness check, public intake through forms, and a close guard that refuses to close while a blocker remains.",
  requires: ["memberships", "permissions", "subjects", "pipelines"],
  // The pipelines module binds the cases table, so the table comes first.
  before: "pipelines",
  integrates: [
    "tasks",
    "numbering",
    "forms",
    "relations",
    "drive",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
