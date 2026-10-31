import type { MaintenanceEvents } from "../../blocks/maintenance/events.ts";
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
import { maintenanceFunctions } from "./maintenance-functions.ts";
import { maintenanceSql } from "./maintenance-sql.ts";
import {
  MAINTENANCE_CALIBRATION_RESULTS,
  MAINTENANCE_PLAN_KINDS,
  MAINTENANCE_PLAN_STATUSES,
  MAINTENANCE_PRIORITIES,
} from "./maintenance-values.ts";

const PLAN = ["organizationId", "id", "title", "kind", "status"] as const;

const plan = { subject: "maintenance-plans", payload: PLAN } as const;

const EVENTS: BlockSqlEvents<MaintenanceEvents> = {
  "maintenance_plan.created": plan,
  "maintenance_plan.updated": plan,
  "maintenance_plan.deleted": plan,
  "maintenance_plan.triggered": {
    subject: "maintenance-plans",
    payload: [...PLAN, "workOrderId"],
  },
  "maintenance_plan.completed": {
    subject: "maintenance-plans",
    payload: [...PLAN, "workOrderId"],
  },
  "maintenance_meter_reading.recorded": {
    subject: "maintenance-meters",
    payload: ["organizationId", "meterId", "value", "readAt"],
  },
  "maintenance_calibration.recorded": {
    subject: "maintenance-calibrations",
    payload: ["organizationId", "id", "assetId", "instrument", "result"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    maintenance_plan: {
      table: "plans",
      singular: "maintenance_plan",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
    maintenance_plan_part: {
      table: "parts",
      singular: "maintenance_plan_part",
    },
    maintenance_meter: { table: "meters", singular: "maintenance_meter" },
    maintenance_meter_reading: {
      table: "readings",
      singular: "maintenance_meter_reading",
    },
    maintenance_calibration: {
      table: "calibrations",
      singular: "maintenance_calibration",
    },
  },
  events: EVENTS,
  hooks: ["before_maintenance_plan_create", "after_maintenance_plan_create"],
  options: [],
  tables: {
    plans: {
      name: "maintenance_plans",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        asset: "asset_id",
        kind: "kind",
        everyDays: "every_days",
        meter: "meter_id",
        everyValue: "every_value",
        priority: "priority",
        status: "status",
        lastDoneAt: "last_done_at",
        lastDoneValue: "last_done_value",
        nextDueAt: "next_due_at",
        workOrder: "work_order_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    parts: {
      name: "maintenance_plan_parts",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        plan: "plan_id",
        name: "name",
        quantity: "quantity",
        variant: "variant_id",
      },
    },
    meters: {
      name: "maintenance_meters",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        unit: "unit",
        asset: "asset_id",
        reading: "reading",
        readAt: "read_at",
        createdAt: "created_at",
      },
    },
    readings: {
      name: "maintenance_meter_readings",
      app: {},
      lifecycle: { tenant: "tenant", user: "readBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        meter: "meter_id",
        value: "value",
        readAt: "read_at",
        readBy: "read_by",
      },
    },
    calibrations: {
      name: "maintenance_calibrations",
      app: {},
      lifecycle: { tenant: "tenant", user: "performedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        asset: "asset_id",
        instrument: "instrument",
        performedAt: "performed_at",
        dueAt: "due_at",
        result: "result",
        reference: "reference",
        performedBy: "performed_by",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = maintenanceSql(ctx);
  const { p, s, m, r, c, plans, parts, meters, readings, calibrations } = q;

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
create table if not exists ${meters} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("name")} text not null check (length(${m("name")}) between 1 and 200),
  ${m("unit")} text not null check (length(${m("unit")}) between 1 and 30),
  ${m("asset")} uuid,
  -- The latest reading. Readings only go up, so a plan can count from it.
  ${m("reading")} numeric not null default 0 check (${m("reading")} >= 0),
  ${m("readAt")} timestamptz,
  ${m("createdAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("id")})
);${appKey("meters", "tenant_id", `${m("tenant")}, ${m("id")}`)}
create index if not exists ${name("meters", "asset_idx")} on ${meters} (${m("tenant")}, ${m("asset")});
${lockTable(meters, { read: true })}
${readPolicy("meters", m("tenant"))}

create table if not exists ${readings} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("meter")} uuid not null,
  ${r("value")} numeric not null check (${r("value")} >= 0),
  ${r("readAt")} timestamptz not null default now(),
  ${r("readBy")} uuid,
  foreign key (${r("tenant")}, ${r("meter")}) references ${meters} (${m("tenant")}, ${m("id")}) on delete cascade
);
create index if not exists ${name("readings", "meter_idx")} on ${readings} (${r("tenant")}, ${r("meter")}, ${r("readAt")} desc);
${lockTable(readings, { read: true })}
${readPolicy("readings", r("tenant"))}

create table if not exists ${plans} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("title")} text not null check (length(${p("title")}) between 1 and 200),
  ${p("asset")} uuid,
  ${p("kind")} text not null check (${p("kind")} in (${list(MAINTENANCE_PLAN_KINDS)})),
  -- A time plan falls due every_days after it was last done.
  ${p("everyDays")} integer check (${p("everyDays")} is null or ${p("everyDays")} > 0),
  -- A meter plan falls due every_value units of the meter after it was last done.
  ${p("meter")} uuid,
  ${p("everyValue")} numeric check (${p("everyValue")} is null or ${p("everyValue")} > 0),
  ${p("priority")} text not null default 'normal' check (${p("priority")} in (${list(MAINTENANCE_PRIORITIES)})),
  ${p("status")} text not null default 'active' check (${p("status")} in (${list(MAINTENANCE_PLAN_STATUSES)})),
  ${p("lastDoneAt")} timestamptz,
  ${p("lastDoneValue")} numeric,
  ${p("nextDueAt")} timestamptz,
  -- The open work order, so a plan never has two at once.
  ${p("workOrder")} uuid,
  ${p("createdBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("id")}),
  foreign key (${p("tenant")}, ${p("meter")}) references ${meters} (${m("tenant")}, ${m("id")}),
  check (
    (${p("kind")} = 'time' and ${p("everyDays")} is not null and ${p("meter")} is null and ${p("everyValue")} is null)
    or (${p("kind")} = 'meter' and ${p("everyDays")} is null and ${p("meter")} is not null and ${p("everyValue")} is not null)
  )
);${appKey("plans", "tenant_id", `${p("tenant")}, ${p("id")}`)}
create index if not exists ${name("plans", "tenant_idx")} on ${plans} (${p("tenant")}, ${p("status")}, ${p("nextDueAt")});
create index if not exists ${name("plans", "asset_idx")} on ${plans} (${p("tenant")}, ${p("asset")});
create index if not exists ${name("plans", "meter_idx")} on ${plans} (${p("tenant")}, ${p("meter")});
create index if not exists ${name("plans", "work_order_idx")} on ${plans} (${p("workOrder")}) where ${p("workOrder")} is not null;
${lockTable(plans, { read: true })}
${readPolicy("plans", p("tenant"))}

-- The spare parts a plan's work order carries, copied to it when it opens.
create table if not exists ${parts} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("plan")} uuid not null,
  ${s("name")} text not null check (length(${s("name")}) between 1 and 200),
  ${s("quantity")} numeric not null default 1 check (${s("quantity")} > 0),
  ${s("variant")} uuid,
  foreign key (${s("tenant")}, ${s("plan")}) references ${plans} (${p("tenant")}, ${p("id")}) on delete cascade
);
create index if not exists ${name("parts", "plan_idx")} on ${parts} (${s("tenant")}, ${s("plan")});
${lockTable(parts, { read: true })}
${readPolicy("parts", s("tenant"))}

create table if not exists ${calibrations} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("asset")} uuid,
  ${c("instrument")} text not null check (length(${c("instrument")}) between 1 and 200),
  ${c("performedAt")} timestamptz not null,
  ${c("dueAt")} timestamptz,
  ${c("result")} text not null check (${c("result")} in (${list(MAINTENANCE_CALIBRATION_RESULTS)})),
  ${c("reference")} text check (${c("reference")} is null or length(${c("reference")}) <= 200),
  ${c("performedBy")} uuid,
  check (${c("dueAt")} is null or ${c("dueAt")} >= ${c("performedAt")})
);
create index if not exists ${name("calibrations", "asset_idx")} on ${calibrations} (${c("tenant")}, ${c("asset")}, ${c("performedAt")} desc);
create index if not exists ${name("calibrations", "due_idx")} on ${calibrations} (${c("tenant")}, ${c("dueAt")});
${lockTable(calibrations, { read: true })}
${readPolicy("calibrations", c("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("dispatch").mode === "custom") {
    throw new TypeError(
      "blocks.maintenance needs the dispatch tables for its work orders; dispatch can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Preventive maintenance per organization: plans that fall due by time or by a
-- meter, meter readings, calibration records, and the dispatch work orders the
-- plans open.
${tables(ctx)}
${maintenanceFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_maintenance_plan",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "update_maintenance_plan",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_maintenance_plan", args: ["uuid"], returns: "jsonb" },
    {
      name: "create_maintenance_meter",
      args: ["{id}", "text", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "record_meter_reading",
      args: ["uuid", "numeric", "timestamptz"],
      returns: "jsonb",
    },
    { name: "record_calibration", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "list_maintenance_plans",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "list_maintenance_meters", args: ["{id}"], returns: "jsonb" },
    { name: "list_calibrations", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "generate_maintenance_work_orders",
      args: ["{id}"],
      returns: "jsonb",
    },
  ];
}

export const MAINTENANCE: BlockSqlDefinition = {
  name: "maintenance",
  scopes: ["tenant"],
  title: "Maintenance",
  description:
    "Preventive maintenance plans that fall due by time or by a meter, meter readings, calibration records, and the dispatch work orders the plans open with their spare parts.",
  requires: ["memberships", "permissions", "subjects", "dispatch"],
  integrates: ["assets", "inventory", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
