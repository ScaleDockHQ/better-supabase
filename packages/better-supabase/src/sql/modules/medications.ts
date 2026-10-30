import type { MedicationsEvents } from "../../blocks/medications/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, schemaPreamble } from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { medicationAdministrationFunctions } from "./medications-administrations.ts";
import { medicationFunctions } from "./medications-functions.ts";
import {
  ADMINISTRATION_STATUSES,
  CODE_SYSTEMS,
  medicationKeys,
  medicationTimeZone,
  missedAfterMinutes,
  ORDER_RESERVED,
  ORDER_SOURCES,
  ORDER_STATUSES,
  sqlList,
} from "./medications-shared.ts";
import { lockModuleTable } from "./over-app.ts";

const ORDER = [
  "organizationId",
  "medicationOrderId",
  "medicationId",
  "subjectType",
  "subjectId",
  "status",
] as const;

const ADMINISTRATION = [
  "organizationId",
  "medicationOrderId",
  "medicationAdministrationId",
  "subjectType",
  "subjectId",
  "status",
  "scheduledAt",
  "administeredAt",
] as const;

const EVENTS: BlockSqlEvents<MedicationsEvents> = {
  "medication_order.created": { subject: "medication-orders", payload: ORDER },
  "medication_order.updated": { subject: "medication-orders", payload: ORDER },
  "medication_order.paused": { subject: "medication-orders", payload: ORDER },
  "medication_order.stopped": {
    subject: "medication-orders",
    payload: [...ORDER, "reason"],
  },
  "medication_administration.recorded": {
    subject: "medication-orders",
    payload: ADMINISTRATION,
  },
  "medication_administration.missed": {
    subject: "medication-orders",
    payload: ADMINISTRATION,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    medication: { table: "medications", singular: "medication", primary: true },
    medication_order: { table: "orders", singular: "medication_order" },
    medication_administration: {
      table: "administrations",
      singular: "medication_administration",
    },
  },
  events: EVENTS,
  hooks: [
    "before_medication_order_prescribe",
    "after_medication_order_prescribe",
    "before_medication_order_stop",
    "after_medication_order_stop",
    "before_medication_administration_record",
    "after_medication_administration_record",
  ],
  options: ["missedAfterMinutes", "missedCaseKind", "timeZone", "extraColumns"],
  tables: {
    medications: {
      name: "medications",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        codeSystem: "code_system",
        code: "code",
        form: "form",
        strength: "strength",
        unit: "unit",
        highRisk: "high_risk",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["form", "strength", "createdAt", "updatedAt"],
    },
    orders: {
      name: "medication_orders",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        medication: "medication_id",
        dose: "dose",
        doseUnit: "dose_unit",
        route: "route",
        schedule: "schedule",
        asNeeded: "as_needed",
        asNeededReason: "as_needed_reason",
        maxPerDay: "max_per_day",
        startsOn: "starts_on",
        endsOn: "ends_on",
        prescriber: "prescriber",
        source: "source",
        externalId: "external_id",
        requiresDoubleCheck: "requires_double_check",
        status: "status",
        stoppedReason: "stopped_reason",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["prescriber", "createdBy", "createdAt", "updatedAt"],
    },
    administrations: {
      name: "medication_administrations",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        scheduledAt: "scheduled_at",
        administeredAt: "administered_at",
        status: "status",
        dose: "dose",
        performer: "performer_id",
        checkedBy: "checked_by",
        reason: "reason",
        note: "note",
      },
      optional: ["note"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const medications = ctx.table("medications");
  const orders = ctx.table("orders");
  const administrations = ctx.table("administrations");
  const m = (column: string): string => ctx.col("medications", column);
  const o = (column: string): string => ctx.col("orders", column);
  const a = (column: string): string => ctx.col("administrations", column);
  const { read } = medicationKeys(ctx);
  const canSubject = ctx.of("subjects").fn("can_subject");

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

  return `
create table if not exists ${medications} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("name")} text not null check (length(${m("name")}) between 1 and 300),
  -- The catalog the code is from; custom is the organization's own entry.
  ${m("codeSystem")} text not null default 'custom' check (${m("codeSystem")} in ${sqlList(CODE_SYSTEMS)}),
  ${m("code")} text check (${m("code")} is null or length(${m("code")}) between 1 and 100),${opt("medications", "form", () => `${m("form")} text check (${m("form")} is null or length(${m("form")}) <= 100)`)}${opt("medications", "strength", () => `${m("strength")} text check (${m("strength")} is null or length(${m("strength")}) <= 100)`)}
  ${m("unit")} text not null check (length(${m("unit")}) between 1 and 50),
  -- A dose of a high-risk medication needs a second member to check it.
  ${m("highRisk")} boolean not null default false,
  ${m("archivedAt")} timestamptz,${stamps("medications", ["createdAt", "updatedAt"])}
  unique (${m("tenant")}, ${m("id")})
);${appKey("medications", "tenant_id", `${m("tenant")}, ${m("id")}`)}
create index if not exists ${name("medications", "tenant_idx")} on ${medications} (${m("tenant")}, ${m("name")});
create unique index if not exists ${name("medications", "code_idx")} on ${medications} (${m("tenant")}, ${m("codeSystem")}, ${m("code")}) where ${m("code")} is not null;
${lockModuleTable(ctx, "medications", { read: true })}
${readPolicy("medications", ctx.scope.check(m("tenant"), read))}

create table if not exists ${orders} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("tenant")} ${ctx.idType} not null,
  -- The record the order is for, a type in config.subjects.
  ${o("subjectType")} text not null,
  ${o("subjectId")} text not null,
  ${o("medication")} uuid not null,
  ${o("dose")} numeric not null check (${o("dose")} > 0),
  ${o("doseUnit")} text not null check (length(${o("doseUnit")}) between 1 and 50),
  ${o("route")} text check (${o("route")} is null or length(${o("route")}) <= 100),
  -- {times: ["08:00"]} or {everyHours: 8, startTime: "06:00"}, with optional
  -- ISO weekdays; null for an order given only as needed.
  ${o("schedule")} jsonb,
  ${o("asNeeded")} boolean not null default false,
  ${o("asNeededReason")} text check (${o("asNeededReason")} is null or length(${o("asNeededReason")}) <= 500),
  -- The most of the dose unit given in any 24 hours, for an as-needed order.
  ${o("maxPerDay")} numeric check (${o("maxPerDay")} is null or ${o("maxPerDay")} > 0),
  ${o("startsOn")} date not null,
  ${o("endsOn")} date,${opt("orders", "prescriber", () => `${o("prescriber")} text check (${o("prescriber")} is null or length(${o("prescriber")}) <= 300)`)}
  ${o("source")} text not null default 'prescriber' check (${o("source")} in ${sqlList(ORDER_SOURCES)}),
  -- The order's id in the pharmacy or prescribing system it was imported from.
  ${o("externalId")} text check (${o("externalId")} is null or length(${o("externalId")}) <= 200),
  ${o("requiresDoubleCheck")} boolean not null default false,
  ${o("status")} text not null default 'active' check (${o("status")} in ${sqlList(ORDER_STATUSES)}),
  ${o("stoppedReason")} text check (${o("stoppedReason")} is null or length(${o("stoppedReason")}) <= 1000),${opt("orders", "createdBy", () => `${o("createdBy")} uuid`)}${stamps("orders", ["createdAt", "updatedAt"])}
  check (${o("endsOn")} is null or ${o("endsOn")} >= ${o("startsOn")}),
  check (${o("asNeeded")} or ${o("schedule")} is not null),
  unique (${o("tenant")}, ${o("id")}),
  foreign key (${o("tenant")}, ${o("medication")}) references ${medications} (${m("tenant")}, ${m("id")})
);${addExtraColumns(orders, ctx.extraColumns("orders", ORDER_RESERVED))}${appKey("orders", "tenant_id", `${o("tenant")}, ${o("id")}`)}
create index if not exists ${name("orders", "item_idx")} on ${orders} (${o("tenant")}, ${o("medication")});
create index if not exists ${name("orders", "subject_idx")} on ${orders} (${o("subjectType")}, ${o("subjectId")});
create index if not exists ${name("orders", "status_idx")} on ${orders} (${o("tenant")}, ${o("status")});
create unique index if not exists ${name("orders", "external_idx")} on ${orders} (${o("tenant")}, ${o("externalId")}) where ${o("externalId")} is not null;
${lockModuleTable(ctx, "orders", { read: true })}
${readPolicy("orders", `${ctx.scope.check(o("tenant"), read)} and coalesce(${canSubject}(${o("subjectType")}, ${o("subjectId")}, 'read'), false)`)}

create table if not exists ${administrations} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("order")} uuid not null,
  -- The planned time; null for an as-needed dose.
  ${a("scheduledAt")} timestamptz,
  ${a("administeredAt")} timestamptz,
  ${a("status")} text not null default 'planned' check (${a("status")} in ${sqlList(ADMINISTRATION_STATUSES)}),
  ${a("dose")} numeric check (${a("dose")} is null or ${a("dose")} > 0),
  ${a("performer")} uuid,
  -- The second member who checked a high-risk dose.
  ${a("checkedBy")} uuid,
  ${a("reason")} text check (${a("reason")} is null or length(${a("reason")}) <= 1000),${opt("administrations", "note", () => `${a("note")} text check (${a("note")} is null or length(${a("note")}) <= 2000)`)}
  check (${a("checkedBy")} is null or ${a("checkedBy")} is distinct from ${a("performer")}),
  unique (${a("order")}, ${a("scheduledAt")}),
  foreign key (${a("tenant")}, ${a("order")}) references ${orders} (${o("tenant")}, ${o("id")}) on delete cascade
);${appKey("administrations", "order_time_key", `${a("order")}, ${a("scheduledAt")}`)}
create index if not exists ${name("administrations", "order_idx")} on ${administrations} (${a("tenant")}, ${a("order")});
create index if not exists ${name("administrations", "planned_idx")} on ${administrations} (${a("scheduledAt")}) where ${a("status")} = 'planned';
create index if not exists ${name("administrations", "given_idx")} on ${administrations} (${a("order")}, ${a("administeredAt")}) where ${a("status")} = 'given';
${lockModuleTable(ctx, "administrations", { read: true })}
${readPolicy("administrations", `${ctx.scope.check(a("tenant"), read)} and exists (select 1 from ${orders} x where x.${o("id")} = ${a("order")} and coalesce(${canSubject}(x.${o("subjectType")}, x.${o("subjectId")}, 'read'), false))`)}
`;
}

/** Moves the orders of a merged record to the record it merged into. */
function orderMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("orders"),
        type: ctx.col("orders", "subjectType"),
        id: ctx.col("orders", "subjectId"),
      },
      "v_type",
    ),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  missedAfterMinutes(ctx);
  medicationTimeZone(ctx);

  return `${schemaPreamble(ctx)}
-- Medications: the organization's catalog, orders for a record with a dose,
-- route and schedule, planned doses, and each dose given, refused, skipped or
-- missed, with a second check for high-risk medication.
${tables(ctx)}${medicationFunctions(ctx)}${medicationAdministrationFunctions(ctx)}${orderMerges(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_medication",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
        "boolean",
        "uuid",
      ],
      returns: "jsonb",
    },
    { name: "archive_medication", args: ["uuid"], returns: "jsonb" },
    { name: "import_medication", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "list_medications",
      args: ["{id}", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "prescribe_medication",
      args: ["{id}", "text", "text", "uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "import_medication_orders",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "update_medication_order",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "pause_medication_order",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "stop_medication_order", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "medication_orders_of",
      args: ["text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "plan_medication_administrations",
      args: ["{id}", "timestamptz"],
      returns: "integer",
    },
    {
      name: "record_medication_administration",
      args: ["uuid", "text", "numeric", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "record_as_needed_administration",
      args: ["uuid", "numeric", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "mark_missed_medication_administrations",
      args: [],
      returns: "integer",
    },
    {
      name: "medication_chart",
      args: ["text", "text", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
  ];
}

export const MEDICATIONS: BlockSqlDefinition = {
  name: "medications",
  scopes: ["tenant"],
  title: "Medications",
  description:
    "A medication catalog per organization, orders for a record with a dose, route, schedule and an as-needed maximum, orders imported from a pharmacy, planned doses, each dose recorded as given, refused, skipped or missed with a second check for high-risk medication, and a medication chart per record.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["notifications", "outbox", "audit", "cases"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
