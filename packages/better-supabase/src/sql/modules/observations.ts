import type { ObservationsEvents } from "../../blocks/observations/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  defaultPartition,
  defaultPartitionName,
  extraFieldsArg,
  MONTHLY_PARTITIONS,
  registerPartitions,
  schemaPreamble,
} from "../shared.ts";
import { observationFunctions } from "./observations-functions.ts";
import { observationReads } from "./observations-reads.ts";
import {
  defaultSet,
  FLAGS,
  OBSERVATION_RESERVED,
  observationForms,
  observationsPartitioned,
  SOURCES,
  sqlList,
  STATUSES,
  VALUE_TYPES,
  vitalsData,
} from "./observations-shared.ts";
import { observationSubmissions } from "./observations-submissions.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const OBSERVATION = [
  "organizationId",
  "observationId",
  "definitionKey",
  "subjectType",
  "subjectId",
] as const;

const EVENTS: BlockSqlEvents<ObservationsEvents> = {
  "observation_definition.created": {
    subject: "observation-definitions",
    payload: ["organizationId", "definitionId", "key", "title"],
  },
  "observation_definition.updated": {
    subject: "observation-definitions",
    payload: ["organizationId", "definitionId", "key", "title"],
  },
  "observation.recorded": {
    subject: "observations",
    payload: [...OBSERVATION, "observedAt", "flag", "source"],
  },
  "observation.critical": {
    subject: "observations",
    payload: [...OBSERVATION, "observedAt", "flag"],
  },
  "observation.amended": {
    subject: "observations",
    payload: [...OBSERVATION, "replacesId", "reason"],
  },
  "observation.marked_error": {
    subject: "observations",
    payload: [...OBSERVATION, "reason"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    observation: {
      table: "observations",
      singular: "observation",
      primary: true,
    },
    observation_definition: {
      table: "definitions",
      singular: "observation_definition",
    },
  },
  events: EVENTS,
  hooks: [
    "before_observation_definition_save",
    "after_observation_definition_save",
    "before_observation_record",
    "after_observation_record",
    "before_observation_amend",
    "after_observation_amend",
    "before_observation_mark_error",
    "after_observation_mark_error",
  ],
  options: ["defaults", "partitioned", "extraColumns"],
  tables: {
    definitions: {
      name: "observation_definitions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        title: "title",
        valueType: "value_type",
        unit: "unit",
        codeSystem: "code_system",
        code: "code",
        components: "components",
        decimals: "decimals",
        validLow: "valid_low",
        validHigh: "valid_high",
        referenceLow: "reference_low",
        referenceHigh: "reference_high",
        criticalLow: "critical_low",
        criticalHigh: "critical_high",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["createdAt", "updatedAt"],
    },
    observations: {
      name: "observations",
      app: {},
      lifecycle: { tenant: "tenant", user: "performer", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        definition: "definition_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        observedAt: "observed_at",
        valueNumber: "value_number",
        valueText: "value_text",
        valueCode: "value_code",
        components: "components",
        flag: "flag",
        status: "status",
        replaces: "replaces_id",
        reason: "reason",
        method: "method",
        device: "device",
        source: "source",
        externalId: "external_id",
        submission: "submission_id",
        performer: "performer_id",
        note: "note",
        createdAt: "created_at",
      },
      optional: ["reason", "method", "device", "note"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const definitions = ctx.table("definitions");
  const observations = ctx.table("observations");
  const d = (column: string): string => ctx.col("definitions", column);
  const o = (column: string): string => ctx.col("observations", column);
  const read = ctx.permission("read", moduleOperations("observations").read);
  const extras = ctx.extraColumns("observations", OBSERVATION_RESERVED);
  const partitioned = observationsPartitioned(ctx);
  const canSubject = ctx.of("subjects").fn("can_subject");

  const forms = observationForms(ctx) ? ctx.of("forms") : undefined;

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

  const appKey = (logical: string, what: string, unique: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} ${unique};`;

  const range = (table: string, low: string, high: string): string =>
    `check (${ctx.col(table, low)} is null or ${ctx.col(table, high)} is null or ${ctx.col(table, low)} <= ${ctx.col(table, high)})`;

  const submissionRef =
    forms === undefined
      ? ""
      : ` references ${forms.table("submissions")} (${forms.col("submissions", "id")}) on delete set null`;

  // A partitioned table can't reference itself or hold a unique key without
  // the partition column, so the functions check both instead.
  const replacesRef = partitioned
    ? ""
    : ` references ${observations} (${o("id")}) on delete set null`;

  const fallback = defaultPartitionName(ctx.tableName("observations"));

  const reasonColumn = opt(
    "observations",
    "reason",
    () =>
      `${o("reason")} text check (${o("reason")} is null or length(${o("reason")}) <= 2000)`,
  );

  const text = (column: string, max: number): string =>
    opt(
      "observations",
      column,
      () =>
        `${o(column)} text check (${o(column)} is null or length(${o(column)}) <= ${String(max)})`,
    );

  return `
create table if not exists ${definitions} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  -- Null for a system definition every organization reads.
  ${d("tenant")} ${ctx.idType},
  ${d("key")} text not null check (${d("key")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${d("title")} text not null check (length(${d("title")}) between 1 and 200),
  ${d("valueType")} text not null check (${d("valueType")} in ${sqlList(VALUE_TYPES)}),
  -- A UCUM unit, such as /min, mm[Hg] or Cel.
  ${d("unit")} text check (${d("unit")} is null or length(${d("unit")}) <= 50),
  -- The code that names the observation, such as a LOINC code.
  ${d("codeSystem")} text check (${d("codeSystem")} is null or length(${d("codeSystem")}) <= 200),
  ${d("code")} text check (${d("code")} is null or length(${d("code")}) <= 100),
  -- The parts of a components value, such as systolic and diastolic: an
  -- array of objects with a key, a title, a unit, a code and ranges.
  ${d("components")} jsonb check (${d("components")} is null or jsonb_typeof(${d("components")}) = 'array'),
  ${d("decimals")} integer check (${d("decimals")} is null or ${d("decimals")} between 0 and 6),
  -- Values outside the valid range are rejected; outside the reference range
  -- they are flagged low or high, at or past a critical bound critical.
  ${d("validLow")} numeric,
  ${d("validHigh")} numeric,
  ${d("referenceLow")} numeric,
  ${d("referenceHigh")} numeric,
  ${d("criticalLow")} numeric,
  ${d("criticalHigh")} numeric,
  ${d("archivedAt")} timestamptz,${stamps("definitions", ["createdAt", "updatedAt"])}
  ${range("definitions", "validLow", "validHigh")},
  ${range("definitions", "referenceLow", "referenceHigh")},
  ${range("definitions", "criticalLow", "criticalHigh")},
  unique nulls not distinct (${d("tenant")}, ${d("key")})
);${appKey("definitions", "tenant_key", `(${d("tenant")}, ${d("key")}) nulls not distinct`)}
${lockModuleTable(ctx, "definitions", { read: true })}
${readPolicy("definitions", `${d("tenant")} is null or ${ctx.scope.check(d("tenant"), read)} or ${d("tenant")} in (select ${ctx.scope.members()})`)}

create table if not exists ${observations} (
  ${partitioned ? `${o("id")} uuid not null default gen_random_uuid()` : `${o("id")} uuid primary key default gen_random_uuid()`},
  ${o("tenant")} ${ctx.idType} not null,
  ${o("definition")} uuid not null references ${definitions} (${d("id")}) on delete restrict,
  ${o("subjectType")} text not null check (length(${o("subjectType")}) between 1 and 100),
  ${o("subjectId")} text not null check (length(${o("subjectId")}) between 1 and 200),
  ${o("observedAt")} timestamptz not null default now(),
  -- One of these holds the value, by the definition's value type; a
  -- boolean is stored as true or false in the code column.
  ${o("valueNumber")} numeric,
  ${o("valueText")} text check (${o("valueText")} is null or length(${o("valueText")}) <= 4000),
  ${o("valueCode")} text check (${o("valueCode")} is null or length(${o("valueCode")}) <= 200),
  ${o("components")} jsonb check (${o("components")} is null or jsonb_typeof(${o("components")}) = 'object'),
  ${o("flag")} text not null default 'normal' check (${o("flag")} in ${sqlList(FLAGS)}),
  ${o("status")} text not null default 'final' check (${o("status")} in ${sqlList(STATUSES)}),
  -- The observation this one corrects.
  ${o("replaces")} uuid${replacesRef},${reasonColumn}${text("method", 200)}${text("device", 200)}
  ${o("source")} text not null default 'manual' check (${o("source")} in ${sqlList(SOURCES)}),
  -- The id a device or an import gives the reading, so ingesting it again
  -- changes nothing.
  ${o("externalId")} text check (${o("externalId")} is null or length(${o("externalId")}) between 1 and 200),
  ${o("submission")} uuid${submissionRef},
  ${o("performer")} uuid,${text("note", 4000)}
  ${o("createdAt")} timestamptz not null default now()${partitioned ? `,\n  primary key (${o("id")}, ${o("createdAt")})` : ""}
)${partitioned ? ` partition by range (${o("createdAt")});\n${defaultPartition(observations, fallback)}` : ";"}${addExtraColumns(observations, extras)}
create index if not exists ${name("observations", "series_idx")} on ${observations} (${o("subjectType")}, ${o("subjectId")}, ${o("definition")}, ${o("observedAt")} desc);
create index if not exists ${name("observations", "definition_idx")} on ${observations} (${o("definition")});
create index if not exists ${name("observations", "tenant_idx")} on ${observations} (${o("tenant")}, ${o("observedAt")} desc);
create index if not exists ${name("observations", "replaces_idx")} on ${observations} (${o("replaces")}) where ${o("replaces")} is not null;
create index if not exists ${name("observations", "submission_idx")} on ${observations} (${o("submission")}) where ${o("submission")} is not null;
create ${partitioned ? "" : "unique "}index if not exists ${name("observations", "external_key")} on ${observations} (${o("tenant")}, ${o("externalId")}) where ${o("externalId")} is not null;
${lockModuleTable(ctx, "observations", { read: true })}
${readPolicy("observations", `${ctx.scope.check(o("tenant"), read)} and coalesce(${canSubject}(${o("subjectType")}, ${o("subjectId")}, 'read'), false)`)}${partitioned ? `\n\n${MONTHLY_PARTITIONS}\n${registerPartitions(observations)}` : ""}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  defaultSet(ctx);

  return `${schemaPreamble(ctx)}
-- Observations: typed measurements of a record (vital signs, scores, lab
-- values) against definitions with a unit, a code and ranges that flag
-- them, with amendments and entered-in-error corrections kept as history.
${tables(ctx)}${observationFunctions(ctx)}${observationReads(ctx)}${observationSubmissions(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("observations", OBSERVATION_RESERVED),
  ).contract;

  return [
    {
      name: "save_observation_definition",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "archive_observation_definition",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "list_observation_definitions",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "record_observation",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "jsonb",
        "timestamptz",
        "jsonb",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "record_observations", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "ingest_observations", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "amend_observation",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "mark_observation_error",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "list_observations",
      args: ["text", "text", "text", "boolean", "integer"],
      returns: "jsonb",
    },
    {
      name: "observation_series",
      args: ["text", "text", "text", "timestamptz", "timestamptz", "text"],
      returns: "jsonb",
    },
    { name: "latest_observations", args: ["text", "text"], returns: "jsonb" },
    ...(observationForms(ctx)
      ? [
          {
            name: "observations_from_submission",
            args: ["uuid"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}

export const OBSERVATIONS: BlockSqlDefinition = {
  name: "observations",
  scopes: ["tenant"],
  title: "Observations",
  description:
    "Typed measurements of a record against definitions with a UCUM unit, a code (LOINC for the shipped vital signs) and valid, reference and critical ranges: a computed flag, critical alerts to the record team's leads, amendments and entered-in-error corrections, idempotent device ingest, series and latest values, and observations mapped from form submissions.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["forms", "notifications", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  data: vitalsData,
  internal: ["observation_submission_trigger"],
};
