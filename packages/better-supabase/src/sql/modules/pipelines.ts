import type { PipelinesEvents } from "../../blocks/pipelines/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Names } from "./pipelines-bindings.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import { pipelineBindings } from "./pipelines-bindings.ts";
import {
  defaultPipeline,
  manageFunctions,
  readFunctions,
  stageTrigger,
} from "./pipelines-sql.ts";

const STAGE_PAYLOAD = [
  "organizationId",
  "subjectType",
  "subjectId",
  "pipelineId",
  "fromStageId",
  "toStageId",
  "category",
  "outcome",
] as const;

const EVENTS: BlockSqlEvents<PipelinesEvents> = {
  "pipeline.created": {
    subject: "pipelines",
    payload: ["organizationId", "pipelineId", "subjectType", "key"],
  },
  "pipeline.updated": {
    subject: "pipelines",
    payload: ["organizationId", "pipelineId", "subjectType", "key"],
  },
  "pipeline.archived": {
    subject: "pipelines",
    payload: ["organizationId", "pipelineId", "subjectType"],
  },
  "pipeline_stage.saved": {
    subject: "pipelines",
    payload: ["organizationId", "pipelineId", "stageId", "key", "category"],
  },
  "pipeline_stage.archived": {
    subject: "pipelines",
    payload: ["organizationId", "pipelineId", "stageId"],
  },
  "pipeline.stage_changed": {
    subject: "pipelines",
    payload: [...STAGE_PAYLOAD],
  },
};

const tenantExport = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    pipeline: { table: "pipelines", singular: "pipeline", primary: true },
  },
  events: EVENTS,
  hooks: [
    "before_pipeline_save",
    "after_pipeline_save",
    "before_pipeline_stage_save",
    "after_pipeline_stage_save",
    "before_pipeline_stage_change",
    "after_pipeline_stage_change",
  ],
  options: ["extraColumns"],
  tables: {
    pipelines: {
      name: "pipelines",
      lifecycle: tenantExport,
      app: {},
      optional: ["createdAt", "updatedAt"],
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        scope: "scope_id",
        key: "key",
        name: "name",
        rank: "rank",
        isDefault: "is_default",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    stages: {
      name: "pipeline_stages",
      lifecycle: tenantExport,
      app: {},
      optional: [
        "systemKey",
        "color",
        "probability",
        "rottingAfterDays",
        "wipLimit",
        "createdAt",
        "updatedAt",
      ],
      typed: ["category", "outcome"],
      columns: {
        id: "id",
        tenant: "tenant_id",
        pipeline: "pipeline_id",
        key: "key",
        systemKey: "system_key",
        name: "name",
        color: "color",
        rank: "rank",
        category: "category",
        outcome: "outcome",
        probability: "probability",
        rottingAfterDays: "rotting_after_days",
        wipLimit: "wip_limit",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    transitions: {
      name: "pipeline_transitions",
      optionalTable: true,
      lifecycle: tenantExport,
      app: {},
      columns: {
        tenant: "tenant_id",
        pipeline: "pipeline_id",
        from: "from_stage_id",
        to: "to_stage_id",
      },
    },
    history: {
      name: "pipeline_stage_history",
      lifecycle: { tenant: "tenant", user: "actor", export: true },
      app: {},
      optional: ["stageName", "category", "amount", "currency", "actor"],
      typed: ["category", "outcome"],
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        pipeline: "pipeline_id",
        fromStage: "from_stage_id",
        toStage: "to_stage_id",
        stageName: "stage_name",
        category: "category",
        outcome: "outcome",
        amount: "amount",
        currency: "currency",
        actor: "actor_user_id",
        enteredAt: "entered_at",
        exitedAt: "exited_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext, names: Names): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = names;

  const optional = (
    table: string,
    column: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, column) ? `\n  ${definition(c(table, column))},` : "";

  const stamps = (table: string): string =>
    `${optional(table, "createdAt", (x) => `${x} timestamptz not null default now()`)}${optional(table, "updatedAt", (x) => `${x} timestamptz not null default now()`)}`;

  // Over the app's table the render drops the inline keys the module relies on.
  const key = (
    table: string,
    suffix: string,
    columns: string,
    nulls = "",
  ): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${suffix}`)} on ${t(table)} (${columns})${nulls};`;

  const read = (table: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(c(table, "tenant"), names.read),
      }),
      { drop: true, target: t(table) },
    );

  const transitions = ctx.hasTable("transitions")
    ? `
create table if not exists ${t("transitions")} (
  ${c("transitions", "tenant")} ${ctx.idType} not null,
  ${c("transitions", "pipeline")} uuid not null references ${t("pipelines")} (${c("pipelines", "id")}) on delete cascade,
  ${c("transitions", "from")} uuid not null references ${t("stages")} (${c("stages", "id")}) on delete cascade,
  ${c("transitions", "to")} uuid not null references ${t("stages")} (${c("stages", "id")}) on delete cascade,
  primary key (${c("transitions", "from")}, ${c("transitions", "to")})
);${key("transitions", "pair_key", `${c("transitions", "from")}, ${c("transitions", "to")}`)}
create index if not exists ${ctx.naming.rename("pipeline_transitions_pipeline_idx")} on ${t("transitions")} (${c("transitions", "pipeline")});
create index if not exists ${ctx.naming.rename("pipeline_transitions_to_idx")} on ${t("transitions")} (${c("transitions", "to")});
${lockTable(t("transitions"), { read: true })}
${read("transitions")}
`
    : "";

  const h = (column: string): string => c("history", column);
  const canSubject = ctx.of("subjects").fn("can_subject");

  return `
create table if not exists ${t("pipelines")} (
  ${c("pipelines", "id")} uuid primary key default gen_random_uuid(),
  ${c("pipelines", "tenant")} ${ctx.idType} not null,
  ${c("pipelines", "subjectType")} text not null,
  ${c("pipelines", "scope")} text,
  ${c("pipelines", "key")} text not null check (${c("pipelines", "key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${c("pipelines", "name")} text not null check (length(${c("pipelines", "name")}) between 1 and 200),
  ${c("pipelines", "rank")} text collate "C" not null default 'V',
  ${c("pipelines", "isDefault")} boolean not null default false,
  ${c("pipelines", "archivedAt")} timestamptz,${stamps("pipelines")}
  unique nulls not distinct (${c("pipelines", "tenant")}, ${c("pipelines", "subjectType")}, ${c("pipelines", "scope")}, ${c("pipelines", "key")})
);${key("pipelines", "key_key", `${c("pipelines", "tenant")}, ${c("pipelines", "subjectType")}, ${c("pipelines", "scope")}, ${c("pipelines", "key")}`, " nulls not distinct")}
create unique index if not exists ${ctx.naming.rename("pipelines_default_idx")} on ${t("pipelines")} (${c("pipelines", "tenant")}, ${c("pipelines", "subjectType")}, coalesce(${c("pipelines", "scope")}, ''))
  where ${c("pipelines", "isDefault")} and ${c("pipelines", "archivedAt")} is null;${addExtraColumns(t("pipelines"), names.extras)}
${lockTable(t("pipelines"), { read: true })}
${read("pipelines")}

create table if not exists ${t("stages")} (
  ${c("stages", "id")} uuid primary key default gen_random_uuid(),
  ${c("stages", "tenant")} ${ctx.idType} not null,
  ${c("stages", "pipeline")} uuid not null references ${t("pipelines")} (${c("pipelines", "id")}) on delete cascade,
  ${c("stages", "key")} text not null check (${c("stages", "key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),${optional("stages", "systemKey", (x) => `${x} text`)}
  ${c("stages", "name")} text not null check (length(${c("stages", "name")}) between 1 and 200),${optional("stages", "color", (x) => `${x} text`)}
  ${c("stages", "rank")} text collate "C" not null default 'V',
  ${c("stages", "category")} text not null,
  ${c("stages", "outcome")} text not null check (${c("stages", "outcome")} in ('open', 'success', 'failure')),${optional("stages", "probability", (x) => `${x} smallint check (${x} >= 0 and ${x} <= 100)`)}${optional("stages", "rottingAfterDays", (x) => `${x} integer check (${x} > 0)`)}${optional("stages", "wipLimit", (x) => `${x} integer check (${x} > 0)`)}
  ${c("stages", "archivedAt")} timestamptz,${stamps("stages")}
  unique (${c("stages", "pipeline")}, ${c("stages", "key")})
);${key("stages", "key_key", `${c("stages", "pipeline")}, ${c("stages", "key")}`)}
create index if not exists ${ctx.naming.rename("pipeline_stages_pipeline_idx")} on ${t("stages")} (${c("stages", "pipeline")}, ${c("stages", "rank")});
${lockTable(t("stages"), { read: true })}
${read("stages")}
${transitions}
create table if not exists ${t("history")} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("subjectType")} text not null,
  ${h("subjectId")} text not null,
  ${h("pipeline")} uuid not null,
  ${h("fromStage")} uuid,
  ${h("toStage")} uuid not null,${optional("history", "stageName", (x) => `${x} text not null`)}${optional("history", "category", (x) => `${x} text not null`)}
  ${h("outcome")} text not null,${optional("history", "amount", (x) => `${x} bigint`)}${optional("history", "currency", (x) => `${x} char(3)`)}${optional("history", "actor", (x) => `${x} uuid`)}
  ${h("enteredAt")} timestamptz not null default now(),
  ${h("exitedAt")} timestamptz
);
create index if not exists ${ctx.naming.rename("pipeline_stage_history_subject_idx")} on ${t("history")} (${h("subjectType")}, ${h("subjectId")}, ${h("enteredAt")});
create index if not exists ${ctx.naming.rename("pipeline_stage_history_pipeline_idx")} on ${t("history")} (${h("pipeline")}, ${h("enteredAt")});
create unique index if not exists ${ctx.naming.rename("pipeline_stage_history_open_idx")} on ${t("history")} (${h("subjectType")}, ${h("subjectId")}) where ${h("exitedAt")} is null;
${lockTable(t("history"), { read: true })}
-- A history row is visible to whoever can read its record.
${renderPolicy(makePolicy({ table: t("history"), name: ctx.naming.rename("pipeline_stage_history_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(h("tenant"), names.read)} and ${canSubject}(${h("subjectType")}, ${h("subjectId")}, 'read')` }), { drop: true, target: t("history") })}
`;
}

/**
 * Row `alias` of logical table `table` as JSON keyed by the module's column
 * names. Over the app's table it lists the module's columns only, with null for
 * the ones the app lacks.
 */
function rowJson(ctx: BlockSqlContext, table: string, alias: string): string {
  if (ctx.owns(table)) {
    return ctx.rowJson(table, alias);
  }

  const columns = Object.entries(NAMES.tables[table]?.columns ?? {}).map(
    ([logical, name]) =>
      `${sqlString(name)}, ${ctx.has(table, logical) ? ctx.label(table, logical, `${alias}.${ctx.col(table, logical)}`) : "null"}`,
  );

  return `jsonb_build_object(${columns.join(", ")})`;
}

/**
 * `options.extraColumns`, added to the pipelines table. `stages` is reserved:
 * `list_pipelines` returns it next to the row.
 */
const extrasOf = (ctx: BlockSqlContext) =>
  ctx.extraColumns("pipelines", ["stages", "fields"]);

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("pipelines");

  const names: Names = {
    fn: (name) => ctx.fn(name),
    extras: extrasOf(ctx),
    read: ctx.permission("read", keys.read),
    manage: ctx.permission("manage", keys.manage),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    has: (table, column) => ctx.has(table, column),
    json: (table, alias) => rowJson(ctx, table, alias),
  };

  const bindings = pipelineBindings(ctx);

  return `${schemaPreamble(ctx)}
-- Pipelines (ADR 0028): tenant-editable stages per subject type, each with
-- a category that maps to a fixed outcome, a stage history and board totals.
${tables(ctx, names)}${defaultPipeline(ctx, names, bindings)}
${bindings.map((binding) => stageTrigger(ctx, names, binding)).join("\n")}
${manageFunctions(ctx, names, bindings)}${readFunctions(ctx.idType, names, bindings)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_pipeline",
      args: [
        "{id}",
        "uuid",
        "text",
        "text",
        "text",
        "text",
        "boolean",
        ...extraFieldsArg(extrasOf(ctx)).contract,
      ],
      returns: "jsonb",
    },
    { name: "archive_pipeline", args: ["uuid"], returns: "boolean" },
    {
      name: "save_pipeline_stage",
      args: [
        "uuid",
        "uuid",
        "text",
        "text",
        "text",
        "integer",
        "integer",
        "integer",
        "text",
      ],
      returns: "jsonb",
    },
    { name: "rank_pipeline_stage", args: ["uuid", "text"], returns: "boolean" },
    { name: "archive_pipeline_stage", args: ["uuid"], returns: "boolean" },
    ...(ctx.hasTable("transitions")
      ? [
          {
            name: "set_pipeline_transitions",
            args: ["uuid", "jsonb"],
            returns: "integer",
          },
        ]
      : []),
    {
      name: "pipeline_board",
      args: ["text", "uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "pipeline_stats",
      args: ["uuid", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    { name: "pipeline_health", args: ["uuid"], returns: "jsonb" },
    { name: "list_pipelines", args: ["{id}", "text"], returns: "jsonb" },
  ];
}

export const PIPELINES: BlockSqlDefinition = {
  name: "pipelines",
  scopes: ["tenant"],
  title: "Pipelines",
  description:
    "Tenant-editable pipelines for any registered subject: ordered stages whose categories map to open, success or failure, a stage history with time in stage, board totals per currency and a status mapping that runs through state-machine.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["outbox", "audit", "state-machine", "notifications"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
