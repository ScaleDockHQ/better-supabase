import type { WarehouseEvents } from "../../blocks/warehouse/events.ts";
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
import { locationsOf } from "./inventory-stock.ts";
import { QUANTITY } from "./inventory-tracking.ts";
import { warehouseCounting } from "./warehouse-counting.ts";
import { warehousePicking } from "./warehouse-picking.ts";
import { warehousePutaway } from "./warehouse-putaway.ts";
import { warehouseSql } from "./warehouse-sql.ts";
import {
  PICK_LINE_STATUSES,
  PICK_LIST_STATUSES,
  PICK_WAVE_STATUSES,
} from "./warehouse-values.ts";

const WAVE = ["organizationId", "id", "name", "locationId", "status"] as const;

const LIST = [
  "organizationId",
  "id",
  "waveId",
  "locationId",
  "documentType",
  "documentId",
  "status",
] as const;

const PLAN = ["organizationId", "id", "name", "locationId"] as const;

const EVENTS: BlockSqlEvents<WarehouseEvents> = {
  "pick_wave.created": { subject: "pick-waves", payload: WAVE },
  "pick_wave.released": { subject: "pick-waves", payload: WAVE },
  "pick_wave.completed": { subject: "pick-waves", payload: WAVE },
  "pick_list.created": { subject: "pick-lists", payload: LIST },
  "pick_list.picked": { subject: "pick-lists", payload: [...LIST, "short"] },
  "count_plan.created": { subject: "count-plans", payload: PLAN },
  "count_plan.executed": {
    subject: "count-plans",
    payload: [...PLAN, "countId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    pick_list: { table: "lists", singular: "pick_list", primary: true },
    pick_wave: { table: "waves", singular: "pick_wave" },
    pick_line: { table: "lines", singular: "pick_line" },
    count_plan: { table: "plans", singular: "count_plan" },
    putaway_rule: { table: "rules", singular: "putaway_rule" },
    bin_slot: { table: "slots", singular: "bin_slot" },
    variant_size: { table: "sizes", singular: "variant_size" },
  },
  events: EVENTS,
  hooks: ["before_pick_list_create", "after_pick_list_create"],
  options: [],
  tables: {
    waves: {
      name: "pick_waves",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        location: "location_id",
        status: "status",
        releasedAt: "released_at",
        completedAt: "completed_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    lists: {
      name: "pick_lists",
      app: {},
      lifecycle: { tenant: "tenant", user: "assignee", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        wave: "wave_id",
        location: "location_id",
        documentType: "document_type",
        documentId: "document_id",
        status: "status",
        assignee: "assignee_id",
        task: "task_id",
        pickedAt: "picked_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    lines: {
      name: "pick_lines",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        list: "pick_list_id",
        allocation: "allocation_id",
        variant: "variant_id",
        bin: "bin_id",
        lot: "lot_id",
        serials: "serials",
        quantity: "quantity",
        picked: "picked",
        route: "route_position",
        status: "status",
        pickedAt: "picked_at",
        pickedBy: "picked_by",
      },
    },
    plans: {
      name: "count_plans",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        location: "location_id",
        everyDays: "every_days",
        variants: "variant_ids",
        varianceLimit: "variance_limit_pct",
        nextRunOn: "next_run_on",
        lastRunAt: "last_run_at",
        lastCount: "last_count_id",
        active: "active",
        createdAt: "created_at",
      },
    },
    rules: {
      name: "putaway_rules",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        location: "location_id",
        bin: "bin_id",
        variant: "variant_id",
        priority: "priority",
        maxQuantity: "max_quantity",
        active: "active",
        createdAt: "created_at",
      },
    },
    slots: {
      name: "bin_slots",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        bin: "bin_id",
        walkRank: "walk_rank",
        capacity: "capacity",
        updatedAt: "updated_at",
      },
    },
    sizes: {
      name: "variant_sizes",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        variant: "variant_id",
        size: "size",
        updatedAt: "updated_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = warehouseSql(ctx);
  const { w, p, l, n, r, s, z, waves, lists, lines, plans, inventory } = q;
  const rules = q.rules;
  const slots = q.slots;
  const sizes = q.sizes;
  const bins = inventory.table("bins");
  const loc = locationsOf(inventory);
  const allocations = inventory.table("allocations");
  const catalog = inventory.of("catalog");
  const variants = catalog.table("variants");

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_tenant_id_key`)} on ${ctx.table(logical)} (${columns});`;

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
-- A wave groups pick lists that are picked together.
create table if not exists ${waves} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  ${w("name")} text not null check (length(${w("name")}) between 1 and 200),
  ${w("location")} uuid not null references ${loc.table} (${loc.col("id")}) on delete cascade,
  ${w("status")} text not null default 'draft' check (${w("status")} in (${list(PICK_WAVE_STATUSES)})),
  ${w("releasedAt")} timestamptz,
  ${w("completedAt")} timestamptz,
  ${w("createdBy")} uuid,
  ${w("createdAt")} timestamptz not null default now(),
  unique (${w("tenant")}, ${w("id")})
);${appKey("waves", `${w("tenant")}, ${w("id")}`)}
create index if not exists ${name("waves", "tenant_idx")} on ${waves} (${w("tenant")}, ${w("status")}, ${w("createdAt")} desc);
create index if not exists ${name("waves", "location_idx")} on ${waves} (${w("location")});
${lockTable(waves, { read: true })}
${readPolicy("waves", w("tenant"))}

-- One document's stock to pick at one location, as a work item for a picker.
create table if not exists ${lists} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("wave")} uuid,
  ${p("location")} uuid not null references ${loc.table} (${loc.col("id")}) on delete cascade,
  ${p("documentType")} text not null check (${p("documentType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${p("documentId")} text not null check (length(${p("documentId")}) between 1 and 200),
  ${p("status")} text not null default 'open' check (${p("status")} in (${list(PICK_LIST_STATUSES)})),
  ${p("assignee")} uuid,
  -- The tasks block's work item for the picker, when it is installed.
  ${p("task")} uuid,
  ${p("pickedAt")} timestamptz,
  ${p("createdBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("id")}),
  foreign key (${p("tenant")}, ${p("wave")}) references ${waves} (${w("tenant")}, ${w("id")}) on delete cascade,
  check ((${p("status")} = 'picked') = (${p("pickedAt")} is not null))
);${appKey("lists", `${p("tenant")}, ${p("id")}`)}
create index if not exists ${name("lists", "wave_idx")} on ${lists} (${p("tenant")}, ${p("wave")});
create index if not exists ${name("lists", "document_idx")} on ${lists} (${p("tenant")}, ${p("documentType")}, ${p("documentId")});
create index if not exists ${name("lists", "assignee_idx")} on ${lists} (${p("tenant")}, ${p("assignee")}, ${p("status")});
create index if not exists ${name("lists", "location_idx")} on ${lists} (${p("location")});
${lockTable(lists, { read: true })}
${readPolicy("lists", p("tenant"))}

-- One allocation to pick. bin_id and lot_id are where to find the stock, set
-- from the stock levels when the line is made and by the picker when picked.
create table if not exists ${lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("list")} uuid not null,
  ${l("allocation")} uuid not null references ${allocations} (${inventory.col("allocations", "id")}) on delete cascade,
  ${l("variant")} uuid not null references ${variants} (${catalog.col("variants", "id")}) on delete cascade,
  ${l("bin")} uuid,
  ${l("lot")} uuid,
  ${l("serials")} text[],
  ${l("quantity")} ${QUANTITY} not null check (${l("quantity")} > 0),
  ${l("route")} integer check (${l("route")} > 0),
  ${l("picked")} ${QUANTITY} not null default 0 check (${l("picked")} >= 0 and ${l("picked")} <= ${l("quantity")}),
  ${l("status")} text not null default 'open' check (${l("status")} in (${list(PICK_LINE_STATUSES)})),
  ${l("pickedAt")} timestamptz,
  ${l("pickedBy")} uuid,
  foreign key (${l("tenant")}, ${l("list")}) references ${lists} (${p("tenant")}, ${p("id")}) on delete cascade
);
create index if not exists ${name("lines", "parent_idx")} on ${lines} (${l("tenant")}, ${l("list")});
create index if not exists ${name("lines", "allocation_idx")} on ${lines} (${l("allocation")});
create index if not exists ${name("lines", "variant_idx")} on ${lines} (${l("variant")});
-- An allocation is on one open pick line at a time.
create unique index if not exists ${name("lines", "open_key")} on ${lines} (${l("allocation")}) where ${l("status")} = 'open';
${lockTable(lines, { read: true })}
${readPolicy("lines", l("tenant"))}

-- A cycle count schedule: every_days days a count of the location opens, of
-- all its stock or of variant_ids only. A posted count whose variance stays
-- under variance_limit_pct of what the books held posts without a review.
create table if not exists ${plans} (
  ${n("id")} uuid primary key default gen_random_uuid(),
  ${n("tenant")} ${ctx.idType} not null,
  ${n("name")} text not null check (length(${n("name")}) between 1 and 200),
  ${n("location")} uuid not null references ${loc.table} (${loc.col("id")}) on delete cascade,
  ${n("everyDays")} integer not null check (${n("everyDays")} between 1 and 3660),
  ${n("variants")} uuid[],
  ${n("varianceLimit")} numeric(6, 2) not null default 5 check (${n("varianceLimit")} >= 0),
  ${n("nextRunOn")} date not null default current_date,
  ${n("lastRunAt")} timestamptz,
  ${n("lastCount")} uuid,
  ${n("active")} boolean not null default true,
  ${n("createdAt")} timestamptz not null default now(),
  unique (${n("tenant")}, ${n("id")})
);${appKey("plans", `${n("tenant")}, ${n("id")}`)}
create index if not exists ${name("plans", "due_idx")} on ${plans} (${n("tenant")}, ${n("nextRunOn")}) where ${n("active")};
create index if not exists ${name("plans", "location_idx")} on ${plans} (${n("location")});
${lockTable(plans, { read: true })}
${readPolicy("plans", n("tenant"))}

-- Where a receipt's stock goes: the bin to suggest for a variant (or for any
-- variant), first by priority, up to max_quantity of that variant in the bin.
create table if not exists ${rules} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("location")} uuid not null references ${loc.table} (${loc.col("id")}) on delete cascade,
  ${r("bin")} uuid not null references ${bins} (${inventory.col("bins", "id")}) on delete cascade,
  ${r("variant")} uuid references ${variants} (${catalog.col("variants", "id")}) on delete cascade,
  ${r("priority")} integer not null default 100 check (${r("priority")} between 0 and 10000),
  ${r("maxQuantity")} ${QUANTITY} check (${r("maxQuantity")} > 0),
  ${r("active")} boolean not null default true,
  ${r("createdAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("id")})
);${appKey("rules", `${r("tenant")}, ${r("id")}`)}
create index if not exists ${name("rules", "lookup_idx")} on ${rules} (${r("tenant")}, ${r("location")}, ${r("variant")}, ${r("priority")}) where ${r("active")};
create index if not exists ${name("rules", "bin_idx")} on ${rules} (${r("bin")});
${lockTable(rules, { read: true })}
${readPolicy("rules", r("tenant"))}

-- How far a bin is from the dispatch area (walk_rank, lowest is closest) and
-- how much it holds, in the same unit as variant_sizes.size.
create table if not exists ${slots} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("bin")} uuid not null unique references ${bins} (${inventory.col("bins", "id")}) on delete cascade,
  ${s("walkRank")} integer not null default 0 check (${s("walkRank")} between 0 and 100000),
  ${s("capacity")} ${QUANTITY} check (${s("capacity")} > 0),
  ${s("updatedAt")} timestamptz not null default now(),
  unique (${s("tenant")}, ${s("id")})
);${appKey("slots", `${s("tenant")}, ${s("id")}`)}
${ctx.owns("slots") ? "" : `create unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("slots").name}_bin_key`)} on ${slots} (${s("bin")});\n`}${lockTable(slots, { read: true })}
${readPolicy("slots", s("tenant"))}

-- The space one unit of a variant takes in a bin; a variant without a row
-- takes 1.
create table if not exists ${sizes} (
  ${z("id")} uuid primary key default gen_random_uuid(),
  ${z("tenant")} ${ctx.idType} not null,
  ${z("variant")} uuid not null unique references ${variants} (${catalog.col("variants", "id")}) on delete cascade,
  ${z("size")} ${QUANTITY} not null check (${z("size")} > 0),
  ${z("updatedAt")} timestamptz not null default now(),
  unique (${z("tenant")}, ${z("id")})
);${appKey("sizes", `${z("tenant")}, ${z("id")}`)}
${ctx.owns("sizes") ? "" : `create unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("sizes").name}_variant_key`)} on ${sizes} (${z("variant")});\n`}${lockTable(sizes, { read: true })}
${readPolicy("sizes", z("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Warehouse work over the inventory block: waves of pick lists made from a
-- document's stock allocations, each a work item for a picker, with the bin,
-- lot and serial numbers the picker confirms, and cycle count plans that open
-- the inventory block's stock counts on a schedule and hold large variances for
-- a review before they post.
${tables(ctx)}
${warehousePicking(ctx)}
${warehouseCounting(ctx)}
${warehousePutaway(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_pick_wave", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "create_pick_list", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "release_pick_wave", args: ["uuid"], returns: "jsonb" },
    { name: "cancel_pick_wave", args: ["uuid"], returns: "jsonb" },
    { name: "record_pick", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "complete_pick_list", args: ["uuid"], returns: "jsonb" },
    { name: "get_pick_list", args: ["uuid"], returns: "jsonb" },
    { name: "list_pick_lists", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_pick_waves", args: ["{id}"], returns: "jsonb" },
    { name: "create_count_plan", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_count_plans", args: ["{id}"], returns: "jsonb" },
    { name: "run_count_plan", args: ["uuid"], returns: "jsonb" },
    { name: "run_due_count_plans", args: ["{id}"], returns: "jsonb" },
    { name: "get_cycle_count_variance", args: ["uuid"], returns: "jsonb" },
    { name: "post_cycle_count", args: ["uuid", "boolean"], returns: "jsonb" },
    { name: "save_putaway_rule", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "delete_putaway_rule", args: ["uuid"], returns: "boolean" },
    { name: "list_putaway_rules", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "save_bin_slot", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "save_variant_size", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_bin_slots", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "suggest_putaway", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "suggest_slotting", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "set_pick_route", args: ["uuid", "uuid[]"], returns: "jsonb" },
    ...(ctx.of("inventory").hasTable("receipts")
      ? [{ name: "suggest_receipt_putaway", args: ["uuid"], returns: "jsonb" }]
      : []),
  ];
}

export const WAREHOUSE: BlockSqlDefinition = {
  name: "warehouse",
  scopes: ["tenant"],
  title: "Warehouse",
  description:
    "Warehouse work over inventory: pick waves and pick lists made from stock allocations, picking tasks as work items, confirmed bins, lots and serials, and cycle count plans that hold large variances for review.",
  requires: ["memberships", "permissions", "inventory"],
  integrates: ["tasks", "relations", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
