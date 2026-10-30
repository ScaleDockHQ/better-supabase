import type { ManufacturingEvents } from "../../blocks/manufacturing/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  accountingContributions,
  accountingSourcesSql,
} from "../accounting-sources-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { locationsOf } from "./inventory-stock.ts";
import { QUANTITY } from "./inventory-tracking.ts";
import { manufacturingAccountingSources } from "./manufacturing-accounting.ts";
import { bomFunctions } from "./manufacturing-boms.ts";
import { productionFunctions } from "./manufacturing-orders.ts";
import { manufacturingSql, linked } from "./manufacturing-sql.ts";
import { traceFunctions } from "./manufacturing-trace.ts";
import {
  BOM_STATUSES,
  PRODUCTION_OPERATION_STATUSES,
  PRODUCTION_ORDER_STATUSES,
} from "./manufacturing-values.ts";

const ORDER = [
  "organizationId",
  "id",
  "number",
  "variantId",
  "quantity",
  "status",
] as const;

const order = { subject: "production-orders", payload: ORDER } as const;

const EVENTS: BlockSqlEvents<ManufacturingEvents> = {
  "bom.activated": {
    subject: "boms",
    payload: ["organizationId", "id", "variantId", "version", "status"],
  },
  "production_order.released": order,
  "production_order.completed": {
    subject: "production-orders",
    payload: [...ORDER, "producedQuantity", "scrapQuantity", "outputLotId"],
  },
  "production_order.canceled": {
    subject: "production-orders",
    payload: [...ORDER, "reason"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    production_order: {
      table: "orders",
      singular: "production_order",
      primary: true,
      subject: {
        title: "number",
        permissions: { read: "read", write: "write" },
        search: { title: "number", body: ["note"] },
      },
    },
    bom: { table: "boms", singular: "bom" },
    bom_component: { table: "components", singular: "bom_component" },
    bom_operation: { table: "operations", singular: "bom_operation" },
    work_center: {
      table: "workCenters",
      singular: "work_center",
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "manage" },
      },
    },
    production_order_operation: {
      table: "orderOperations",
      singular: "production_order_operation",
    },
    production_consumption: {
      table: "consumptions",
      singular: "production_consumption",
    },
    stock_lot_link: { table: "lotLinks", singular: "stock_lot_link" },
  },
  events: EVENTS,
  hooks: [
    "before_production_order_release",
    "after_production_order_release",
    "before_production_order_complete",
    "after_production_order_complete",
  ],
  options: ["extraColumns"],
  tables: {
    boms: {
      name: "boms",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        variant: "variant_id",
        version: "version",
        status: "status",
        quantity: "quantity",
        note: "note",
        activatedAt: "activated_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    workCenters: {
      name: "work_centers",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        asset: "asset_id",
        hoursPerDay: "hours_per_day",
        costRate: "cost_rate",
        currency: "currency",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    operations: {
      name: "bom_operations",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        bom: "bom_id",
        sequence: "sequence",
        workCenter: "work_center_id",
        title: "title",
        setupMinutes: "setup_minutes",
        runMinutes: "run_minutes_per_unit",
        instructions: "instructions_node_id",
        inspectionTemplate: "inspection_template",
      },
    },
    components: {
      name: "bom_components",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        bom: "bom_id",
        position: "position",
        variant: "variant_id",
        quantity: "quantity",
        scrapBps: "scrap_bps",
        operation: "operation_id",
      },
    },
    orders: {
      name: "production_orders",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        sequence: "sequence",
        variant: "variant_id",
        bom: "bom_id",
        quantity: "quantity",
        location: "location_id",
        dueOn: "due_on",
        status: "status",
        produced: "produced_quantity",
        scrap: "scrap_quantity",
        outputLot: "output_lot_id",
        materialCost: "material_cost",
        laborCost: "labor_cost",
        currency: "currency",
        note: "note",
        releasedAt: "released_at",
        startedAt: "started_at",
        completedAt: "completed_at",
        canceledAt: "canceled_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    orderOperations: {
      name: "production_order_operations",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        operation: "operation_id",
        sequence: "sequence",
        workCenter: "work_center_id",
        title: "title",
        plannedMinutes: "planned_minutes",
        status: "status",
        startedAt: "started_at",
        finishedAt: "finished_at",
        operator: "operator_id",
        minutes: "minutes",
        inspection: "inspection_id",
      },
    },
    consumptions: {
      name: "production_consumptions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        variant: "variant_id",
        lot: "lot_id",
        serial: "serial",
        quantity: "quantity",
        cost: "cost",
        currency: "currency",
        movement: "movement_id",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    lotLinks: {
      name: "stock_lot_links",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        parent: "parent_lot_id",
        child: "child_lot_id",
        order: "order_id",
        quantity: "quantity",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = manufacturingSql(ctx);
  const { b, c, w, o, po, op, pc, ll } = q;
  const inventory = q.inventory;
  const catalog = q.catalog;
  const assets = linked(ctx, "assets");
  const drive = linked(ctx, "drive");
  const inspections = linked(ctx, "inspections");

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

  const ref = (
    owner: BlockSqlContext | undefined,
    table: string,
    action: string,
  ): string =>
    owner?.owns(table)
      ? ` references ${owner.table(table)} (${owner.col(table, "id")}) on delete ${action}`
      : "";

  const locations = locationsOf(inventory);
  const variantRef = ref(catalog, "variants", "restrict");
  const lotRef = (action: string): string => ref(inventory, "lots", action);

  return `
create table if not exists ${q.workCenters} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  ${w("name")} text not null check (length(${w("name")}) between 1 and 200),
  -- The machine or line, an asset of the assets block.
  ${w("asset")} uuid${ref(assets, "assets", "set null")},
  ${w("hoursPerDay")} numeric(5, 2) not null default 8 check (${w("hoursPerDay")} > 0 and ${w("hoursPerDay")} <= 24),
  -- Minor units per hour of work, in currency.
  ${w("costRate")} bigint not null default 0 check (${w("costRate")} >= 0),
  ${w("currency")} char(3) check (${w("currency")} ~ '^[A-Z]{3}$'),
  ${w("archivedAt")} timestamptz,
  ${w("createdAt")} timestamptz not null default now(),
  ${w("updatedAt")} timestamptz not null default now(),
  unique (${w("tenant")}, ${w("id")}),
  check (${w("costRate")} = 0 or ${w("currency")} is not null)
);${appKey("workCenters", "tenant_id", `${w("tenant")}, ${w("id")}`)}
create index if not exists ${name("workCenters", "tenant_idx")} on ${q.workCenters} (${w("tenant")}, ${w("name")});
create index if not exists ${name("workCenters", "asset_idx")} on ${q.workCenters} (${w("asset")}) where ${w("asset")} is not null;
${lockTable(q.workCenters, { read: true })}
${readPolicy("workCenters", w("tenant"))}

create table if not exists ${q.boms} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${ctx.idType} not null,
  -- The variant the bill of materials makes.
  ${b("variant")} uuid not null${variantRef},
  -- 1, 2, 3 per variant; a production order pins one version.
  ${b("version")} integer not null check (${b("version")} > 0),
  ${b("status")} text not null default 'draft' check (${b("status")} in (${list(BOM_STATUSES)})),
  -- How much of the variant one run of the components makes.
  ${b("quantity")} ${QUANTITY} not null default 1 check (${b("quantity")} > 0),
  ${b("note")} text check (${b("note")} is null or length(${b("note")}) <= 10000),
  ${b("activatedAt")} timestamptz,
  ${b("createdBy")} uuid,
  ${b("createdAt")} timestamptz not null default now(),
  ${b("updatedAt")} timestamptz not null default now(),
  unique (${b("tenant")}, ${b("id")}),
  unique (${b("variant")}, ${b("version")})
);${appKey("boms", "tenant_id", `${b("tenant")}, ${b("id")}`)}${appKey("boms", "variant_version", `${b("variant")}, ${b("version")}`)}
-- One active version per variant.
create unique index if not exists ${name("boms", "active_key")} on ${q.boms} (${b("variant")}) where ${b("status")} = 'active';
create index if not exists ${name("boms", "tenant_idx")} on ${q.boms} (${b("tenant")}, ${b("status")});
${lockTable(q.boms, { read: true })}
${readPolicy("boms", b("tenant"))}

create table if not exists ${q.operations} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("tenant")} ${ctx.idType} not null,
  ${o("bom")} uuid not null,
  -- 10, 20, 30: the order operations run in.
  ${o("sequence")} integer not null check (${o("sequence")} > 0),
  ${o("workCenter")} uuid not null,
  ${o("title")} text not null check (length(${o("title")}) between 1 and 200),
  ${o("setupMinutes")} numeric(10, 2) not null default 0 check (${o("setupMinutes")} >= 0),
  ${o("runMinutes")} numeric(10, 4) not null default 0 check (${o("runMinutes")} >= 0),
  -- A drive node with the work instructions.
  ${o("instructions")} uuid${ref(drive, "nodes", "set null")},
  -- An inspection kind; starting the operation schedules one.
  ${o("inspectionTemplate")} text check (${o("inspectionTemplate")} is null or length(${o("inspectionTemplate")}) between 1 and 63),
  unique (${o("bom")}, ${o("sequence")}),
  foreign key (${o("tenant")}, ${o("bom")}) references ${q.boms} (${b("tenant")}, ${b("id")}) on delete cascade,
  foreign key (${o("tenant")}, ${o("workCenter")}) references ${q.workCenters} (${w("tenant")}, ${w("id")}) on delete restrict
);${appKey("operations", "bom_sequence", `${o("bom")}, ${o("sequence")}`)}
create index if not exists ${name("operations", "parent_idx")} on ${q.operations} (${o("tenant")}, ${o("bom")}, ${o("sequence")});
create index if not exists ${name("operations", "work_center_idx")} on ${q.operations} (${o("tenant")}, ${o("workCenter")});
create index if not exists ${name("operations", "instructions_idx")} on ${q.operations} (${o("instructions")}) where ${o("instructions")} is not null;
${lockTable(q.operations, { read: true })}
${readPolicy("operations", o("tenant"))}

create table if not exists ${q.components} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("bom")} uuid not null,
  ${c("position")} integer not null default 0,
  ${c("variant")} uuid not null${variantRef},
  -- Per bom quantity of the made variant, in the component's unit.
  ${c("quantity")} ${QUANTITY} not null check (${c("quantity")} > 0),
  -- Expected loss in basis points: 250 plans 2.5% more.
  ${c("scrapBps")} integer not null default 0 check (${c("scrapBps")} between 0 and 10000),
  -- The operation that uses it, or null for the start of the run.
  ${c("operation")} uuid references ${q.operations} (${o("id")}) on delete set null,
  foreign key (${c("tenant")}, ${c("bom")}) references ${q.boms} (${b("tenant")}, ${b("id")}) on delete cascade
);
create index if not exists ${name("components", "parent_idx")} on ${q.components} (${c("tenant")}, ${c("bom")}, ${c("position")});
create index if not exists ${name("components", "variant_idx")} on ${q.components} (${c("variant")});
create index if not exists ${name("components", "operation_idx")} on ${q.components} (${c("operation")}) where ${c("operation")} is not null;
${lockTable(q.components, { read: true })}
${readPolicy("components", c("tenant"))}

create table if not exists ${q.orders} (
  ${po("id")} uuid primary key default gen_random_uuid(),
  ${po("tenant")} ${ctx.idType} not null,
  -- MO-2026-0001, from the numbering block when it numbers production orders.
  ${po("number")} text not null check (length(${po("number")}) between 1 and 100),
  ${po("sequence")} bigint not null,
  ${po("variant")} uuid not null${variantRef},
  -- The bill of materials version the order was planned with.
  ${po("bom")} uuid not null,
  ${po("quantity")} ${QUANTITY} not null check (${po("quantity")} > 0),
  -- The inventory location the components come from and the output goes to.
  ${po("location")} uuid not null references ${locations.table} (${locations.col("id")}) on delete restrict,
  ${po("dueOn")} date,
  ${po("status")} text not null default 'draft' check (${po("status")} in (${list(PRODUCTION_ORDER_STATUSES)})),
  ${po("produced")} ${QUANTITY} not null default 0 check (${po("produced")} >= 0),
  ${po("scrap")} ${QUANTITY} not null default 0 check (${po("scrap")} >= 0),
  ${po("outputLot")} uuid${lotRef("set null")},
  -- What completion valued the output at, in minor units of currency: the
  -- consumed components' stock value and the work centers' labor.
  ${po("materialCost")} bigint not null default 0,
  ${po("laborCost")} bigint not null default 0 check (${po("laborCost")} >= 0),
  ${po("currency")} char(3),
  ${po("note")} text check (${po("note")} is null or length(${po("note")}) <= 10000),
  ${po("releasedAt")} timestamptz,
  ${po("startedAt")} timestamptz,
  ${po("completedAt")} timestamptz,
  ${po("canceledAt")} timestamptz,
  ${po("createdBy")} uuid,
  ${po("createdAt")} timestamptz not null default now(),
  ${po("updatedAt")} timestamptz not null default now(),
  unique (${po("tenant")}, ${po("number")}),
  unique (${po("tenant")}, ${po("id")}),
  foreign key (${po("tenant")}, ${po("bom")}) references ${q.boms} (${b("tenant")}, ${b("id")}) on delete restrict
);${addExtraColumns(q.orders, q.extras)}${appKey("orders", "tenant_number", `${po("tenant")}, ${po("number")}`)}${appKey("orders", "tenant_id", `${po("tenant")}, ${po("id")}`)}
create index if not exists ${name("orders", "tenant_idx")} on ${q.orders} (${po("tenant")}, ${po("status")}, ${po("dueOn")});
create index if not exists ${name("orders", "bom_idx")} on ${q.orders} (${po("tenant")}, ${po("bom")});
create index if not exists ${name("orders", "variant_idx")} on ${q.orders} (${po("variant")}, ${po("status")});
create index if not exists ${name("orders", "location_idx")} on ${q.orders} (${po("location")});
create index if not exists ${name("orders", "output_lot_idx")} on ${q.orders} (${po("outputLot")}) where ${po("outputLot")} is not null;
${lockTable(q.orders, { read: true })}
${readPolicy("orders", po("tenant"))}

create table if not exists ${q.orderOperations} (
  ${op("id")} uuid primary key default gen_random_uuid(),
  ${op("tenant")} ${ctx.idType} not null,
  ${op("order")} uuid not null,
  ${op("operation")} uuid references ${q.operations} (${o("id")}) on delete set null,
  ${op("sequence")} integer not null check (${op("sequence")} > 0),
  ${op("workCenter")} uuid not null,
  ${op("title")} text not null check (length(${op("title")}) between 1 and 200),
  -- Setup plus run time for the order's quantity.
  ${op("plannedMinutes")} numeric(12, 2) not null default 0 check (${op("plannedMinutes")} >= 0),
  ${op("status")} text not null default 'pending' check (${op("status")} in (${list(PRODUCTION_OPERATION_STATUSES)})),
  ${op("startedAt")} timestamptz,
  ${op("finishedAt")} timestamptz,
  ${op("operator")} uuid,
  -- The minutes worked, set when the operation finishes.
  ${op("minutes")} numeric(12, 2) check (${op("minutes")} is null or ${op("minutes")} >= 0),
  -- The inspection its inspection template scheduled.
  ${op("inspection")} uuid${ref(inspections, "inspections", "set null")},
  unique (${op("order")}, ${op("sequence")}),
  foreign key (${op("tenant")}, ${op("order")}) references ${q.orders} (${po("tenant")}, ${po("id")}) on delete cascade,
  foreign key (${op("tenant")}, ${op("workCenter")}) references ${q.workCenters} (${w("tenant")}, ${w("id")}) on delete restrict
);${appKey("orderOperations", "order_sequence", `${op("order")}, ${op("sequence")}`)}
create index if not exists ${name("orderOperations", "parent_idx")} on ${q.orderOperations} (${op("tenant")}, ${op("order")}, ${op("sequence")});
create index if not exists ${name("orderOperations", "work_center_idx")} on ${q.orderOperations} (${op("tenant")}, ${op("workCenter")}, ${op("status")});
create index if not exists ${name("orderOperations", "operation_idx")} on ${q.orderOperations} (${op("operation")}) where ${op("operation")} is not null;
create index if not exists ${name("orderOperations", "inspection_idx")} on ${q.orderOperations} (${op("inspection")}) where ${op("inspection")} is not null;
${lockTable(q.orderOperations, { read: true })}
${readPolicy("orderOperations", op("tenant"))}

create table if not exists ${q.consumptions} (
  ${pc("id")} uuid primary key default gen_random_uuid(),
  ${pc("tenant")} ${ctx.idType} not null,
  ${pc("order")} uuid not null,
  ${pc("variant")} uuid not null${variantRef},
  ${pc("lot")} uuid${lotRef("restrict")},
  ${pc("serial")} text check (${pc("serial")} is null or length(${pc("serial")}) between 1 and 100),
  ${pc("quantity")} ${QUANTITY} not null check (${pc("quantity")} > 0),
  -- The stock value it took, in minor units of currency; 0 without costing.
  ${pc("cost")} bigint not null default 0,
  ${pc("currency")} char(3),
  -- The stock movement, a ledger transaction.
  ${pc("movement")} uuid not null,
  ${pc("createdBy")} uuid,
  ${pc("createdAt")} timestamptz not null default now(),
  foreign key (${pc("tenant")}, ${pc("order")}) references ${q.orders} (${po("tenant")}, ${po("id")}) on delete cascade
);
create index if not exists ${name("consumptions", "parent_idx")} on ${q.consumptions} (${pc("tenant")}, ${pc("order")}, ${pc("createdAt")});
create index if not exists ${name("consumptions", "variant_idx")} on ${q.consumptions} (${pc("variant")});
create index if not exists ${name("consumptions", "lot_idx")} on ${q.consumptions} (${pc("lot")}) where ${pc("lot")} is not null;
create index if not exists ${name("consumptions", "movement_idx")} on ${q.consumptions} (${pc("movement")});
${lockTable(q.consumptions, { read: true })}
${readPolicy("consumptions", pc("tenant"))}

-- Lot genealogy: the output lot of a production order (parent) and each lot
-- it consumed (child).
create table if not exists ${q.lotLinks} (
  ${ll("tenant")} ${ctx.idType} not null,
  ${ll("parent")} uuid not null${lotRef("cascade")},
  ${ll("child")} uuid not null${lotRef("cascade")},
  ${ll("order")} uuid not null,
  -- How much of the child lot went into the parent.
  ${ll("quantity")} ${QUANTITY} not null check (${ll("quantity")} > 0),
  ${ll("createdAt")} timestamptz not null default now(),
  primary key (${ll("parent")}, ${ll("child")}, ${ll("order")}),
  foreign key (${ll("tenant")}, ${ll("order")}) references ${q.orders} (${po("tenant")}, ${po("id")}) on delete cascade
);${appKey("lotLinks", "parent_child_order", `${ll("parent")}, ${ll("child")}, ${ll("order")}`)}
create index if not exists ${name("lotLinks", "child_idx")} on ${q.lotLinks} (${ll("child")});
create index if not exists ${name("lotLinks", "order_idx")} on ${q.lotLinks} (${ll("tenant")}, ${ll("order")});
${lockTable(q.lotLinks, { read: true })}
${readPolicy("lotLinks", ll("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  for (const module of ["inventory", "catalog"]) {
    if (ctx.of(module).mode === "custom") {
      throw new TypeError(
        `blocks.manufacturing needs the ${module} tables; ${module} can't be in custom mode`,
      );
    }
  }

  return `${schemaPreamble(ctx)}
-- Manufacturing per organization: versioned bills of materials, work centers,
-- production orders that take components and receive output through the
-- inventory block's stock movements, and lot genealogy.
${tables(ctx)}
${bomFunctions(ctx)}
${productionFunctions(ctx)}
${traceFunctions(ctx)}
${accountingSourcesSql(ctx, manufacturingAccountingSources(ctx))}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_bom",
      args: ["{id}", "uuid", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "activate_bom", args: ["uuid"], returns: "jsonb" },
    { name: "get_bom", args: ["uuid"], returns: "jsonb" },
    { name: "list_boms", args: ["{id}", "uuid"], returns: "jsonb" },
    { name: "explode_bom", args: ["uuid", "numeric"], returns: "jsonb" },
    { name: "bom_where_used", args: ["uuid"], returns: "jsonb" },
    {
      name: "save_work_center",
      args: ["{id}", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "list_work_centers", args: ["{id}"], returns: "jsonb" },
    {
      name: "create_production_order",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "release_production_order",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "start_production_operation", args: ["uuid"], returns: "jsonb" },
    {
      name: "finish_production_operation",
      args: ["uuid", "numeric"],
      returns: "jsonb",
    },
    {
      name: "record_production_consumption",
      args: ["uuid", "uuid", "numeric", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "complete_production_order",
      args: ["uuid", "numeric", "numeric", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "cancel_production_order",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    { name: "get_production_order", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_production_orders",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "lot_genealogy", args: ["uuid", "text"], returns: "jsonb" },
    { name: "lot_recall", args: ["uuid"], returns: "jsonb" },
    {
      name: "material_requirements",
      args: ["{id}", "integer"],
      returns: "jsonb",
    },
    {
      name: "create_from_requirements",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
  ];
}

const CONTRIBUTES: BlockContributes = {
  numbering: (own) => [
    {
      entity: own.resolved.entityNaming.rename("production_order"),
      entry: { period: "year", format: "MO-{yyyy}-{n:4}" },
    },
  ],
  accounting: (own) =>
    accountingContributions(own, manufacturingAccountingSources(own)),
};

export const MANUFACTURING: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "manufacturing",
  scopes: ["tenant"],
  title: "Manufacturing",
  description:
    "Versioned bills of materials with routings on work centers, production orders numbered MO-2026-0001 that allocate and consume components and receive the output at component plus work center cost through inventory, lot genealogy and recall, and material requirements that suggest purchase and production orders.",
  requires: ["memberships", "permissions", "catalog", "inventory", "numbering"],
  integrates: [
    "assets",
    "drive",
    "inspections",
    "accounting",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
