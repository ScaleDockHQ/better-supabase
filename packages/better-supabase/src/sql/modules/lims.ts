import type { LimsEvents } from "../../blocks/lims/events.ts";
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
import { limsFunctions } from "./lims-functions.ts";
import { limsSql } from "./lims-sql.ts";
import { LIMS_RESULT_OUTCOMES, LIMS_SAMPLE_STATUSES } from "./lims-values.ts";

const sample = {
  subject: "lims-samples",
  payload: ["organizationId", "id", "number", "status"],
} as const;

const method = {
  subject: "lims-methods",
  payload: ["organizationId", "id", "key"],
} as const;

const result = {
  subject: "lims-samples",
  payload: [
    "organizationId",
    "id",
    "sampleId",
    "methodId",
    "value",
    "outcome",
    "caseId",
  ],
} as const;

const EVENTS: BlockSqlEvents<LimsEvents> = {
  "lims_method.created": method,
  "lims_method.updated": method,
  "lims_method.archived": method,
  "lims_sample.registered": sample,
  "lims_sample.completed": sample,
  "lims_sample.released": sample,
  "lims_sample.rejected": sample,
  "lims_result.recorded": result,
  "lims_result.flagged": result,
};

const NAMES: BlockSqlNames = {
  entities: {
    lims_sample: {
      table: "samples",
      singular: "lims_sample",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    lims_method: { table: "methods", singular: "lims_method" },
    lims_result: { table: "results", singular: "lims_result" },
  },
  events: EVENTS,
  hooks: [
    "before_lims_sample_register",
    "after_lims_sample_register",
    "before_lims_result_record",
    "after_lims_result_record",
  ],
  options: ["instrumentQualification", "nonconformityKind"],
  tables: {
    methods: {
      name: "lims_methods",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        unit: "unit",
        lowerLimit: "lower_limit",
        upperLimit: "upper_limit",
        form: "form_id",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    samples: {
      name: "lims_samples",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        sequence: "sequence",
        title: "title",
        kind: "kind",
        lot: "lot",
        receivedOn: "received_on",
        status: "status",
        notes: "notes",
        rejectionReason: "rejection_reason",
        completedAt: "completed_at",
        releasedAt: "released_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    results: {
      name: "lims_results",
      app: {},
      lifecycle: { tenant: "tenant", user: "testedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        sample: "sample_id",
        method: "method_id",
        value: "value",
        outcome: "outcome",
        instrument: "instrument_id",
        submission: "submission_id",
        case: "case_id",
        note: "note",
        testedBy: "tested_by",
        testedAt: "tested_at",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = limsSql(ctx);
  const { m, s, r, methods, samples, results } = q;

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
-- What a laboratory measures: a key, a unit and the specification limits a
-- result must stay within. form_id names the form that captures the readings.
create table if not exists ${methods} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("key")} text not null check (${m("key")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${m("name")} text not null check (length(${m("name")}) between 1 and 200),
  ${m("unit")} text check (${m("unit")} is null or length(${m("unit")}) <= 40),
  ${m("lowerLimit")} numeric,
  ${m("upperLimit")} numeric,
  ${m("form")} uuid,
  ${m("archivedAt")} timestamptz,
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("key")}),
  check (${m("lowerLimit")} is null or ${m("upperLimit")} is null or ${m("lowerLimit")} <= ${m("upperLimit")})
);${appKey("methods", "tenant_key", `${m("tenant")}, ${m("key")}`)}
${lockTable(methods, { read: true })}
${readPolicy("methods", m("tenant"))}

-- A sample received for testing. The number is SMP-1, SMP-2 and so on, or the
-- numbering block's format.
create table if not exists ${samples} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("number")} text not null,
  ${s("sequence")} bigint not null,
  ${s("title")} text not null check (length(${s("title")}) between 1 and 200),
  ${s("kind")} text check (${s("kind")} is null or length(${s("kind")}) <= 100),
  ${s("lot")} text check (${s("lot")} is null or length(${s("lot")}) <= 100),
  ${s("receivedOn")} date not null default current_date,
  ${s("status")} text not null default 'registered' check (${s("status")} in (${list(LIMS_SAMPLE_STATUSES)})),
  ${s("notes")} text check (${s("notes")} is null or length(${s("notes")}) <= 4000),
  ${s("rejectionReason")} text check (${s("rejectionReason")} is null or length(${s("rejectionReason")}) <= 500),
  ${s("completedAt")} timestamptz,
  ${s("releasedAt")} timestamptz,
  ${s("createdBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now(),
  unique (${s("tenant")}, ${s("sequence")})
);${appKey("samples", "tenant_id", `${s("tenant")}, ${s("id")}`)}
create index if not exists ${name("samples", "status_idx")} on ${samples} (${s("tenant")}, ${s("status")});
${lockTable(samples, { read: true })}
${readPolicy("samples", s("tenant"))}

-- One measurement of a method on a sample. outcome is decided from the
-- method's limits when the result is recorded; a retest adds a row and the
-- latest per method counts. instrument_id is an asset, submission_id the form
-- submission with the readings, case_id the nonconformity an out of
-- specification result raised.
create table if not exists ${results} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("sample")} uuid not null,
  ${r("method")} uuid not null,
  ${r("value")} numeric not null,
  ${r("outcome")} text not null check (${r("outcome")} in (${list(LIMS_RESULT_OUTCOMES)})),
  ${r("instrument")} uuid,
  ${r("submission")} uuid,
  ${r("case")} uuid,
  ${r("note")} text check (${r("note")} is null or length(${r("note")}) <= 2000),
  ${r("testedBy")} uuid,
  ${r("testedAt")} timestamptz not null default now(),
  ${r("createdAt")} timestamptz not null default now()
);${appKey("results", "tenant_id", `${r("tenant")}, ${r("id")}`)}
create index if not exists ${name("results", "sample_idx")} on ${results} (${r("sample")}, ${r("method")}, ${r("testedAt")} desc);
${lockTable(results, { read: true })}
${readPolicy("results", r("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- A laboratory information system: samples, test methods with specification
-- limits, results and the instruments that produced them.
${tables(ctx)}
${limsFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_lims_method",
      args: ["{id}", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "archive_lims_method", args: ["uuid"], returns: "jsonb" },
    { name: "list_lims_methods", args: ["{id}", "boolean"], returns: "jsonb" },
    { name: "register_sample", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "get_sample", args: ["uuid"], returns: "jsonb" },
    { name: "list_samples", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "complete_sample", args: ["uuid"], returns: "jsonb" },
    { name: "release_sample", args: ["uuid"], returns: "jsonb" },
    { name: "reject_sample", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "record_lims_result",
      args: ["uuid", "uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "instrument_status",
      args: ["{id}", "uuid", "date"],
      returns: "jsonb",
    },
  ];
}

export const LIMS: BlockSqlDefinition = {
  name: "lims",
  scopes: ["tenant"],
  title: "Laboratory information system",
  description:
    "Samples, test methods with specification limits, results through forms, a nonconformity case for every out of specification result and instruments from assets that must hold a valid qualification.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: [
    "forms",
    "cases",
    "assets",
    "qualifications",
    "numbering",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
