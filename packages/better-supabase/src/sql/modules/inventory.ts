import type { InventoryEvents } from "../../blocks/inventory/events.ts";
import type { CommerceEventData } from "../../core/block-events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import {
  ALLOCATION_TABLES,
  allocationFunctions,
  allocationTable,
} from "./inventory-allocations.ts";
import { counterCase, stockLedger } from "./inventory-ledger.ts";
import {
  purchaseOrderFunctions,
  transferFunctions,
} from "./inventory-purchasing.ts";
import {
  columns,
  locationFunctions,
  locationsOf,
  reservationFunctions,
  stockFunctions,
} from "./inventory-stock.ts";
import {
  QUANTITY,
  TRACKING_TABLES,
  trackingFunctions,
  trackingTables,
} from "./inventory-tracking.ts";
import { ledgerRebalance, ledgerTables } from "./ledger.ts";
import { OPERATIONS } from "./permissions-model.ts";

type CommerceKey = keyof CommerceEventData;

const stockEvent = (
  subject: string,
  payload: readonly CommerceKey[],
): { readonly subject: string; readonly payload: readonly CommerceKey[] } => ({
  subject,
  payload: ["organizationId", "id", ...payload],
});

const EVENTS: BlockSqlEvents<InventoryEvents> = {
  "stock.adjusted": stockEvent("stock-movements", [
    "variantId",
    "locationId",
    "quantity",
    "reason",
    "available",
  ]),
  "stock.reorder_point_reached": {
    subject: "stock-levels",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "variantId",
      "locationId",
      "available",
      "reorderPoint",
    ],
  },
  "reservation.created": stockEvent("stock-reservations", [
    "variantId",
    "locationId",
    "quantity",
  ]),
  "reservation.committed": stockEvent("stock-reservations", [
    "variantId",
    "locationId",
    "quantity",
  ]),
  "reservation.released": stockEvent("stock-reservations", [
    "variantId",
    "locationId",
    "quantity",
    "reason",
  ]),
  "allocation.created": stockEvent("stock-allocations", [
    "variantId",
    "locationId",
    "documentType",
    "documentId",
    "quantity",
    "allocated",
  ]),
  "allocation.filled": stockEvent("stock-allocations", [
    "variantId",
    "locationId",
    "documentType",
    "documentId",
    "quantity",
    "allocated",
  ]),
  "allocation.released": stockEvent("stock-allocations", [
    "variantId",
    "locationId",
    "documentType",
    "documentId",
    "quantity",
  ]),
  "transfer.shipped": stockEvent("stock-transfers", ["from", "to", "status"]),
  "transfer.received": stockEvent("stock-transfers", ["from", "to", "status"]),
  "transfer.cancelled": stockEvent("stock-transfers", ["from", "to", "status"]),
  "purchase_order.placed": stockEvent("purchase-orders", [
    "locationId",
    "status",
    "supplierType",
    "supplierId",
  ]),
  "purchase_order.received": stockEvent("purchase-orders", [
    "locationId",
    "status",
    "supplierType",
    "supplierId",
  ]),
  "purchase_order.cancelled": stockEvent("purchase-orders", [
    "locationId",
    "status",
    "supplierType",
    "supplierId",
  ]),
};

const tenantExport = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    location: {
      table: "locations",
      singular: "inventory_location",
      primary: true,
    },
    purchase_order: { table: "purchaseOrders", singular: "purchase_order" },
  },
  events: EVENTS,
  options: ["extraColumns"],
  hooks: [
    "before_stock_adjust",
    "after_stock_adjust",
    "before_stock_reserve",
    "after_stock_reserve",
  ],
  tables: {
    locations: {
      name: "inventory_locations",
      app: {},
      optionalTable: true,
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        name: "name",
        kind: "kind",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    levels: {
      name: "stock_levels",
      app: {},
      lifecycle: tenantExport,
      columns: {
        tenant: "tenant_id",
        variant: "variant_id",
        location: "location_id",
        onHand: "on_hand",
        reserved: "reserved",
        held: "held",
        incoming: "incoming",
        available: "available",
        reorderPoint: "reorder_point",
        updatedAt: "updated_at",
      },
    },
    reservations: {
      name: "stock_reservations",
      app: {},
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        variant: "variant_id",
        location: "location_id",
        quantity: "quantity",
        status: "status",
        referenceType: "reference_type",
        referenceId: "reference_id",
        expiresAt: "expires_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      typed: ["status"],
    },
    transfers: {
      name: "stock_transfers",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        from: "from_location_id",
        to: "to_location_id",
        status: "status",
        note: "note",
        createdAt: "created_at",
        shippedAt: "shipped_at",
        receivedAt: "received_at",
      },
      typed: ["status"],
    },
    transferLines: {
      name: "stock_transfer_lines",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        transfer: "transfer_id",
        variant: "variant_id",
        quantity: "quantity",
        detail: "detail",
      },
    },
    purchaseOrders: {
      name: "purchase_orders",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        location: "location_id",
        supplierType: "supplier_type",
        supplierId: "supplier_id",
        status: "status",
        currency: "currency",
        expectedAt: "expected_at",
        note: "note",
        createdAt: "created_at",
        updatedAt: "updated_at",
        placedAt: "placed_at",
      },
      typed: ["status"],
    },
    purchaseOrderLines: {
      name: "purchase_order_lines",
      app: {},
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "purchase_order_id",
        variant: "variant_id",
        quantity: "quantity_ordered",
        received: "quantity_received",
        unitCost: "unit_cost",
      },
    },
    ...TRACKING_TABLES,
    ...ALLOCATION_TABLES,
  },
};

/** Inventory's own locations table, when stock doesn't live at assets'. */
function ownLocations(
  ctx: BlockSqlContext,
  names: InventoryNames,
  read: (table: string) => string,
): string {
  const t = (name: string): string => ctx.table(name);
  const l = columns(ctx, "locations");

  return `
create table if not exists ${t("locations")} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("code")} text not null,
  ${l("name")} text not null check (length(${l("name")}) between 1 and 200),
  ${l("kind")} text not null default 'warehouse' check (${l("kind")} in ('warehouse', 'store', 'virtual')),
  ${l("active")} boolean not null default true,
  ${l("createdAt")} timestamptz not null default now(),
  ${l("updatedAt")} timestamptz not null default now(),
  unique (${l("tenant")}, ${l("code")})
);${addExtraColumns(t("locations"), names.extras)}
${lockTable(t("locations"), { read: true })}
${read("locations")}
`;
}

function tables(ctx: BlockSqlContext, names: InventoryNames): string {
  if (!ctx.manages) {
    return "";
  }

  const catalog = ctx.of("catalog");
  const variants = `${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete cascade`;
  const t = (name: string): string => ctx.table(name);

  const read = (table: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: `${ctx.col(table, "tenant")} in (select ${ctx.scope.ids(names.read)})`,
      }),
      { drop: true, target: t(table) },
    );

  const lock = (table: string): string => lockTable(t(table), { read: true });

  const loc = locationsOf(ctx);
  const lv = columns(ctx, "levels");
  const r = columns(ctx, "reservations");
  const location = `${loc.table} (${loc.col("id")}) on delete cascade`;
  const transfers = ctx.hasTable("transfers") && ctx.hasTable("transferLines");

  const orders =
    ctx.hasTable("purchaseOrders") && ctx.hasTable("purchaseOrderLines");

  const tr = columns(ctx, "transfers");
  const tl = columns(ctx, "transferLines");
  const po = columns(ctx, "purchaseOrders");
  const pl = columns(ctx, "purchaseOrderLines");

  return `${loc.shared ? "" : ownLocations(ctx, names, read)}
create table if not exists ${t("levels")} (
  ${lv("tenant")} ${ctx.idType} not null,
  ${lv("variant")} uuid not null references ${variants},
  ${lv("location")} uuid not null references ${location},
  ${lv("onHand")} ${QUANTITY} not null default 0,
  ${lv("reserved")} ${QUANTITY} not null default 0 check (${lv("reserved")} >= 0),
  ${lv("held")} ${QUANTITY} not null default 0 check (${lv("held")} >= 0),
  ${lv("incoming")} ${QUANTITY} not null default 0 check (${lv("incoming")} >= 0),
  ${lv("available")} ${QUANTITY} generated always as (${lv("onHand")} - ${lv("reserved")} - ${lv("held")}) stored,
  ${lv("reorderPoint")} ${QUANTITY} check (${lv("reorderPoint")} >= 0),
  ${lv("updatedAt")} timestamptz not null default now(),
  primary key (${lv("variant")}, ${lv("location")})
);
create index if not exists stock_levels_location_idx on ${t("levels")} (${lv("location")});
${lockTable(t("levels"), { read: true })}
${read("levels")}

create table if not exists ${t("reservations")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("variant")} uuid not null references ${variants},
  ${r("location")} uuid not null references ${location},
  ${r("quantity")} ${QUANTITY} not null check (${r("quantity")} > 0),
  ${r("status")} text not null default 'active' check (${r("status")} in ('active', 'committed', 'released', 'expired')),
  ${r("referenceType")} text,
  ${r("referenceId")} text,
  ${r("expiresAt")} timestamptz not null,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now()
);
create index if not exists stock_reservations_active_idx on ${t("reservations")} (${r("expiresAt")}) where ${r("status")} = 'active';
create index if not exists stock_reservations_level_idx on ${t("reservations")} (${r("variant")}, ${r("location")});
create index if not exists stock_reservations_location_idx on ${t("reservations")} (${r("location")});
${lockTable(t("reservations"), { read: true })}
${read("reservations")}
${
  transfers
    ? `
create table if not exists ${t("transfers")} (
  ${tr("id")} uuid primary key default gen_random_uuid(),
  ${tr("tenant")} ${ctx.idType} not null,
  ${tr("from")} uuid not null references ${location},
  ${tr("to")} uuid not null references ${location},
  ${tr("status")} text not null default 'draft' check (${tr("status")} in ('draft', 'in_transit', 'received', 'cancelled')),
  ${tr("note")} text,
  ${tr("createdAt")} timestamptz not null default now(),
  ${tr("shippedAt")} timestamptz,
  ${tr("receivedAt")} timestamptz,
  check (${tr("from")} <> ${tr("to")})
);
create index if not exists stock_transfers_from_idx on ${t("transfers")} (${tr("from")});
create index if not exists stock_transfers_to_idx on ${t("transfers")} (${tr("to")});
${lockTable(t("transfers"), { read: true })}
${read("transfers")}

create table if not exists ${t("transferLines")} (
  ${tl("tenant")} ${ctx.idType} not null,
  ${tl("transfer")} uuid not null references ${t("transfers")} (${tr("id")}) on delete cascade,
  ${tl("variant")} uuid not null references ${variants},
  ${tl("quantity")} ${QUANTITY} not null check (${tl("quantity")} > 0),
  -- The lots and serial numbers the transfer took out, so receiving puts the same ones in.
  ${tl("detail")} jsonb,
  primary key (${tl("transfer")}, ${tl("variant")})
);
create index if not exists stock_transfer_lines_variant_idx on ${t("transferLines")} (${tl("variant")});
${lockTable(t("transferLines"), { read: true })}
${read("transferLines")}
`
    : ""
}${
    orders
      ? `
create table if not exists ${t("purchaseOrders")} (
  ${po("id")} uuid primary key default gen_random_uuid(),
  ${po("tenant")} ${ctx.idType} not null,
  ${po("location")} uuid not null references ${location},
  ${po("supplierType")} text,
  ${po("supplierId")} text,
  ${po("status")} text not null default 'draft' check (${po("status")} in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  ${po("currency")} char(3) not null check (${po("currency")} ~ '^[A-Z]{3}$'),
  ${po("expectedAt")} timestamptz,
  ${po("note")} text,
  ${po("createdAt")} timestamptz not null default now(),
  ${po("updatedAt")} timestamptz not null default now(),
  ${po("placedAt")} timestamptz,
  check ((${po("supplierType")} is null) = (${po("supplierId")} is null))
);
create index if not exists ${ctx.naming.rename("purchase_orders_location_idx")} on ${t("purchaseOrders")} (${po("location")});
create index if not exists ${ctx.naming.rename("purchase_orders_status_idx")} on ${t("purchaseOrders")} (${po("tenant")}, ${po("status")});
${lockTable(t("purchaseOrders"), { read: true })}
${read("purchaseOrders")}

create table if not exists ${t("purchaseOrderLines")} (
  ${pl("id")} uuid primary key default gen_random_uuid(),
  ${pl("tenant")} ${ctx.idType} not null,
  ${pl("order")} uuid not null references ${t("purchaseOrders")} (${po("id")}) on delete cascade,
  ${pl("variant")} uuid not null references ${variants},
  ${pl("quantity")} ${QUANTITY} not null check (${pl("quantity")} > 0),
  ${pl("received")} ${QUANTITY} not null default 0 check (${pl("received")} between 0 and ${pl("quantity")}),
  ${pl("unitCost")} bigint not null check (${pl("unitCost")} >= 0),
  unique (${pl("order")}, ${pl("variant")})
);
create index if not exists ${ctx.naming.rename("purchase_order_lines_variant_idx")} on ${t("purchaseOrderLines")} (${pl("variant")});
${lockTable(t("purchaseOrderLines"), { read: true })}
${read("purchaseOrderLines")}
`
      : ""
  }${trackingTables(ctx, read, lock)}${allocationTable(ctx, read, lock)}`;
}

/** Copies `stock_movements` into the ledger, keeping each movement's id. */
function stockMovementsUpgrade(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const ledger = ctx.of("ledger");
  const a = columns(ledger, "accounts");
  const t = columns(ledger, "transactions");
  const e = columns(ledger, "entries");
  const old = `${ctx.schema}.stock_movements`;
  // The old table took the tenant column the block names on its other tables.
  const mt = ctx.col("levels", "tenant");
  const read = ctx.permission("read", OPERATIONS["inventory.read"]);
  const accounts = ledger.table("accounts");
  const memo = ledger.has("transactions", "memo");

  return `${ledgerTables(ledger)}
do $upgrade$
begin
  if to_regclass('${ctx.schemaName}.stock_movements') is null then
    return;
  end if;
  insert into ${accounts} (${a("tenant")}, ${a("kind")}, ${a("code")}, ${a("name")}, ${a("unit")}, ${a("holderType")}, ${a("holderId")}, ${a("allowNegative")}, ${a("readPermission")}, ${a("managedBy")}, ${a("metadata")})
  select distinct m.${mt}, 'stock', 'stock:' || m.variant_id::text || ':' || m.location_id::text, 'Stock', 'item', 'product-variants', m.variant_id::text, true, ${read}, 'inventory',
    jsonb_build_object('variantId', m.variant_id, 'locationId', m.location_id)
  from ${old} m
  on conflict do nothing;
  insert into ${accounts} (${a("tenant")}, ${a("kind")}, ${a("code")}, ${a("name")}, ${a("unit")}, ${a("allowNegative")}, ${a("readPermission")}, ${a("managedBy")})
  select distinct m.${mt}, 'stock_counter', ${counterCase("m.reason", 0)}, ${counterCase("m.reason", 1)}, 'item', true, ${read}, 'inventory'
  from ${old} m
  on conflict do nothing;
  insert into ${ledger.table("transactions")} (${t("id")}, ${t("tenant")}, ${t("kind")}, ${t("referenceType")}, ${t("referenceId")}, ${memo ? `${t("memo")}, ` : ""}${t("metadata")}, ${t("effectiveAt")}, ${t("actor")}, ${t("createdAt")})
  select m.id, m.${mt}, 'stock.' || m.reason, m.reference_type, m.reference_id,${memo ? " m.note," : ""}
    jsonb_build_object('variantId', m.variant_id, 'locationId', m.location_id, 'reason', m.reason), m.created_at, m.actor_id, m.created_at
  from ${old} m
  on conflict do nothing;
  insert into ${ledger.table("entries")} (${e("tenant")}, ${e("transaction")}, ${e("account")}, ${e("amount")}, ${e("unit")}, ${e("createdAt")})
  select m.${mt}, m.id, x.${a("id")}, m.quantity, 'item', m.created_at
  from ${old} m join ${accounts} x on x.${a("tenant")} = m.${mt} and x.${a("code")} = 'stock:' || m.variant_id::text || ':' || m.location_id::text
  union all
  select m.${mt}, m.id, x.${a("id")}, -m.quantity, 'item', m.created_at
  from ${old} m join ${accounts} x on x.${a("tenant")} = m.${mt} and x.${a("code")} = ${counterCase("m.reason", 0)};
  ${ledgerRebalance(ledger)}
  drop table ${old};
  drop function if exists ${ctx.fn("apply_stock_movement")}();
  drop function if exists ${ctx.fn("stock_movements_append_only")}();
end;
$upgrade$;`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const names: InventoryNames = {
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", OPERATIONS["inventory.manage"]),
    read: ctx.permission("read", OPERATIONS["inventory.read"]),
    reserve: ctx.permission("reserve", OPERATIONS["inventory.reserve"]),
    purchase: ctx.permission("purchase", OPERATIONS["inventory.purchase"]),
    extras: ctx.hasTable("locations") ? ctx.extraColumns("locations") : [],
  };

  return `${schemaPreamble(ctx)}
-- Stock per catalog variant and location in a unit with decimals: movements
-- posted to the ledger in base units, lots, serial numbers, expiry, bins,
-- weighted average cost, reservations with expiry, allocations with
-- backorders, transfers and purchase orders with receiving.
${tables(ctx, names)}${stockLedger(ctx, names)}${trackingFunctions(ctx, names)}${allocationFunctions(ctx, names)}${locationFunctions(ctx, names)}${stockFunctions(ctx, names)}${reservationFunctions(ctx, names)}${transferFunctions(ctx, names)}${purchaseOrderFunctions(ctx, names)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const transfers = ctx.hasTable("transfers") && ctx.hasTable("transferLines");

  const orders =
    ctx.hasTable("purchaseOrders") && ctx.hasTable("purchaseOrderLines");

  return [
    {
      name: "save_location",
      args: ["{id}", "uuid", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "set_location_active",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "delete_location", args: ["uuid"], returns: "boolean" },
    {
      name: "adjust_stock",
      args: ["uuid", "uuid", "numeric", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "count_stock",
      args: ["uuid", "uuid", "numeric", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "set_reorder_point",
      args: ["uuid", "uuid", "numeric"],
      returns: "boolean",
    },
    {
      name: "reserve_stock",
      args: ["uuid", "uuid", "numeric", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
    { name: "commit_reservation", args: ["uuid"], returns: "jsonb" },
    { name: "release_reservation", args: ["uuid"], returns: "boolean" },
    { name: "expire_reservations", args: ["integer"], returns: "integer" },
    {
      name: "set_stock_item",
      args: ["uuid", "text", "smallint", "text", "boolean", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "save_bin",
      args: ["uuid", "uuid", "text", "text", "boolean", "boolean"],
      returns: "jsonb",
    },
    { name: "save_lot", args: ["uuid", "text", "date"], returns: "jsonb" },
    { name: "stock_detail", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "expiring_lots", args: ["{id}", "date"], returns: "jsonb" },
    { name: "expire_lots", args: ["{id}", "date"], returns: "integer" },
    { name: "stock_valuation", args: ["uuid"], returns: "jsonb" },
    {
      name: "allocate_stock",
      args: [
        "{id}",
        "uuid",
        "uuid",
        "numeric",
        "text",
        "text",
        "text",
        "boolean",
      ],
      returns: "jsonb",
    },
    {
      name: "fulfill_allocation",
      args: ["uuid", "numeric", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "restore_allocation",
      args: ["uuid", "numeric", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "release_allocations",
      args: ["{id}", "text", "text"],
      returns: "integer",
    },
    {
      name: "list_allocations",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    ...(transfers
      ? [
          {
            name: "create_transfer",
            args: ["{id}", "uuid", "uuid", "jsonb", "text"],
            returns: "jsonb",
          },
          { name: "ship_transfer", args: ["uuid"], returns: "boolean" },
          { name: "receive_transfer", args: ["uuid"], returns: "boolean" },
          { name: "cancel_transfer", args: ["uuid"], returns: "boolean" },
        ]
      : []),
    ...(orders
      ? [
          {
            name: "save_purchase_order",
            args: [
              "{id}",
              "uuid",
              "uuid",
              "text",
              "text",
              "text",
              "timestamptz",
              "jsonb",
              "text",
            ],
            returns: "jsonb",
          },
          { name: "place_purchase_order", args: ["uuid"], returns: "boolean" },
          {
            name: "receive_purchase_order",
            args: ["uuid", "jsonb"],
            returns: "jsonb",
          },
          { name: "cancel_purchase_order", args: ["uuid"], returns: "boolean" },
        ]
      : []),
  ];
}

const REQUIRES = ["memberships", "permissions", "catalog", "ledger"] as const;

export const INVENTORY: BlockSqlDefinition = {
  name: "inventory",
  scopes: ["tenant"],
  title: "Inventory",
  description:
    "Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers and purchase orders with partial receiving.",
  requires: [...REQUIRES],
  dependencies: (layout) =>
    layout.modules?.["inventory"]?.tables?.["locations"] === null
      ? [...REQUIRES, "assets"]
      : [...REQUIRES],
  integrates: ["outbox", "assets"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "Stock movements move onto the ledger block: each movement becomes a ledger transaction between the variant's stock account and a counter account, and stock_movements is dropped.",
      sql: stockMovementsUpgrade,
    },
    {
      from: 2,
      description:
        "Quantities become numeric with a unit and scale per variant, posted to the ledger in base units. Adds lots, serial numbers, expiry, bins, weighted average cost and allocations with backorders; stock already on hand stays outside any bin or lot, so no data moves.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
