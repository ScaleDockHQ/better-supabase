import type { CommerceEventData } from "../../core/block-events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { fail, lockTable, schemaPreamble } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import {
  purchaseOrderFunctions,
  transferFunctions,
} from "./inventory-purchasing.ts";
import {
  type InventoryNames,
  columns,
  locationFunctions,
  reservationFunctions,
  stockFunctions,
  strict,
  threshold,
} from "./inventory-stock.ts";

type CommerceKey = keyof CommerceEventData;

const stockEvent = (
  subject: string,
  payload: readonly CommerceKey[],
): { readonly subject: string; readonly payload: readonly CommerceKey[] } => ({
  subject,
  payload: ["organizationId", "id", ...payload],
});

const EVENTS: ModuleEvents = {
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

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_stock_adjust",
    "after_stock_adjust",
    "before_stock_reserve",
    "after_stock_reserve",
  ],
  tables: {
    locations: {
      name: "inventory_locations",
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
      lifecycle: tenantExport,
      columns: {
        tenant: "tenant_id",
        variant: "variant_id",
        location: "location_id",
        onHand: "on_hand",
        reserved: "reserved",
        incoming: "incoming",
        available: "available",
        reorderPoint: "reorder_point",
        updatedAt: "updated_at",
      },
    },
    movements: {
      name: "stock_movements",
      lifecycle: tenantExport,
      columns: {
        id: "id",
        tenant: "tenant_id",
        variant: "variant_id",
        location: "location_id",
        quantity: "quantity",
        reason: "reason",
        referenceType: "reference_type",
        referenceId: "reference_id",
        note: "note",
        actor: "actor_id",
        createdAt: "created_at",
      },
    },
    reservations: {
      name: "stock_reservations",
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
    },
    transfers: {
      name: "stock_transfers",
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
    },
    transferLines: {
      name: "stock_transfer_lines",
      lifecycle: tenantExport,
      optionalTable: true,
      columns: {
        tenant: "tenant_id",
        transfer: "transfer_id",
        variant: "variant_id",
        quantity: "quantity",
      },
    },
    purchaseOrders: {
      name: "purchase_orders",
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
    },
    purchaseOrderLines: {
      name: "purchase_order_lines",
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
  },
};

function tables(ctx: ModuleContext, names: InventoryNames): string {
  if (!ctx.manages) return "";
  const catalog = ctx.of("catalog");
  const variants = `${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete cascade`;
  const t = (name: string): string => ctx.table(name);
  const read = (
    table: string,
  ): string => `drop policy if exists ${ctx.tableName(table).name}_read on ${t(table)};
create policy ${ctx.tableName(table).name}_read on ${t(table)} for select to authenticated
using (${ctx.col(table, "tenant")} in (select better_supabase.tenant_ids_with(${names.read})));`;
  const l = columns(ctx, "locations");
  const lv = columns(ctx, "levels");
  const m = columns(ctx, "movements");
  const r = columns(ctx, "reservations");
  const location = `${t("locations")} (${l("id")}) on delete cascade`;
  const transfers = ctx.hasTable("transfers") && ctx.hasTable("transferLines");
  const orders =
    ctx.hasTable("purchaseOrders") && ctx.hasTable("purchaseOrderLines");
  const tr = columns(ctx, "transfers");
  const tl = columns(ctx, "transferLines");
  const po = columns(ctx, "purchaseOrders");
  const pl = columns(ctx, "purchaseOrderLines");
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
);
${lockTable(t("locations"), { read: true })}
${read("locations")}

create table if not exists ${t("levels")} (
  ${lv("tenant")} ${ctx.idType} not null,
  ${lv("variant")} uuid not null references ${variants},
  ${lv("location")} uuid not null references ${location},
  ${lv("onHand")} integer not null default 0,
  ${lv("reserved")} integer not null default 0 check (${lv("reserved")} >= 0),
  ${lv("incoming")} integer not null default 0 check (${lv("incoming")} >= 0),
  ${lv("available")} integer generated always as (${lv("onHand")} - ${lv("reserved")}) stored,
  ${lv("reorderPoint")} integer check (${lv("reorderPoint")} >= 0),
  ${lv("updatedAt")} timestamptz not null default now(),
  primary key (${lv("variant")}, ${lv("location")})
);
create index if not exists stock_levels_location_idx on ${t("levels")} (${lv("location")});
${lockTable(t("levels"), { read: true })}
${read("levels")}

create table if not exists ${t("movements")} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("variant")} uuid not null references ${variants},
  ${m("location")} uuid not null references ${location},
  ${m("quantity")} integer not null check (${m("quantity")} <> 0),
  ${m("reason")} text not null check (${m("reason")} in ('adjustment', 'damage', 'loss', 'return', 'receipt', 'count', 'sale', 'transfer_out', 'transfer_in')),
  ${m("referenceType")} text,
  ${m("referenceId")} text,
  ${m("note")} text,
  ${m("actor")} uuid default auth.uid(),
  ${m("createdAt")} timestamptz not null default now()
);
create index if not exists stock_movements_variant_idx on ${t("movements")} (${m("variant")}, ${m("location")}, ${m("createdAt")});
create index if not exists stock_movements_location_idx on ${t("movements")} (${m("location")});
${lockTable(t("movements"), { read: true })}
${read("movements")}

create table if not exists ${t("reservations")} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("variant")} uuid not null references ${variants},
  ${r("location")} uuid not null references ${location},
  ${r("quantity")} integer not null check (${r("quantity")} > 0),
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
  ${tl("quantity")} integer not null check (${tl("quantity")} > 0),
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
create index if not exists purchase_orders_location_idx on ${t("purchaseOrders")} (${po("location")});
create index if not exists purchase_orders_status_idx on ${t("purchaseOrders")} (${po("tenant")}, ${po("status")});
${lockTable(t("purchaseOrders"), { read: true })}
${read("purchaseOrders")}

create table if not exists ${t("purchaseOrderLines")} (
  ${pl("id")} uuid primary key default gen_random_uuid(),
  ${pl("tenant")} ${ctx.idType} not null,
  ${pl("order")} uuid not null references ${t("purchaseOrders")} (${po("id")}) on delete cascade,
  ${pl("variant")} uuid not null references ${variants},
  ${pl("quantity")} integer not null check (${pl("quantity")} > 0),
  ${pl("received")} integer not null default 0 check (${pl("received")} between 0 and ${pl("quantity")}),
  ${pl("unitCost")} bigint not null check (${pl("unitCost")} >= 0),
  unique (${pl("order")}, ${pl("variant")})
);
create index if not exists purchase_order_lines_variant_idx on ${t("purchaseOrderLines")} (${pl("variant")});
${lockTable(t("purchaseOrderLines"), { read: true })}
${read("purchaseOrderLines")}
`
      : ""
  }`;
}

/**
 * The ledger: every movement updates its level in the same transaction,
 * and refuses to take a tracked variant below zero.
 */
function ledger(ctx: ModuleContext, names: InventoryNames): string {
  const { fn } = names;
  const levels = ctx.table("levels");
  const movements = ctx.table("movements");
  const lv = columns(ctx, "levels");
  const m = columns(ctx, "movements");
  const { name } = ctx.tableName("movements");
  return `
-- Applies a stock movement to its level. A tracked variant without
-- backorders can't go below zero on hand, and a sale or a transfer out
-- can't take available (on hand minus reserved) below zero.
create or replace function ${fn("apply_stock_movement")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_on_hand integer;
  v_after integer;
  v_point integer;
begin
  insert into ${levels} as x (${lv("tenant")}, ${lv("variant")}, ${lv("location")}, ${lv("onHand")})
  values (new.${m("tenant")}, new.${m("variant")}, new.${m("location")}, new.${m("quantity")})
  on conflict (${lv("variant")}, ${lv("location")}) do update
    set ${lv("onHand")} = x.${lv("onHand")} + excluded.${lv("onHand")}, ${lv("updatedAt")} = now()
  returning x.${lv("onHand")}, x.${lv("available")}, x.${lv("reorderPoint")} into v_on_hand, v_after, v_point;
  if new.${m("quantity")} < 0
    and (v_on_hand < 0 or (v_after < 0 and new.${m("reason")} in ('sale', 'transfer_out')))
    and ${strict(ctx, `new.${m("variant")}`)} then
    ${fail("INVENTORY_INSUFFICIENT", "not enough stock at this location", "23514")}
  end if;
  ${threshold(ctx, {
    tenant: `new.${m("tenant")}`,
    variant: `new.${m("variant")}`,
    location: `new.${m("location")}`,
    before: `(v_after - new.${m("quantity")})`,
    after: "v_after",
    point: "v_point",
  })}
  return null;
end;
$$;
revoke execute on function ${fn("apply_stock_movement")}() from public, anon, authenticated;
drop trigger if exists ${name}_apply on ${movements};
create trigger ${name}_apply after insert on ${movements}
for each row execute function ${fn("apply_stock_movement")}();

-- The ledger is append-only: correct a movement with another one.
create or replace function ${fn("stock_movements_append_only")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  ${fail("INVENTORY_LEDGER_APPEND_ONLY", "stock movements can't change; write a correcting movement", "55000")}
end;
$$;
revoke execute on function ${fn("stock_movements_append_only")}() from public, anon, authenticated;
drop trigger if exists ${name}_append_only on ${movements};
create trigger ${name}_append_only before update on ${movements}
for each row execute function ${fn("stock_movements_append_only")}();
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const names: InventoryNames = {
    fn: (name) => ctx.fn(name),
    manage: ctx.permission("manage", MODULE_PERMISSIONS.inventory.manage),
    read: ctx.permission("read", MODULE_PERMISSIONS.inventory.read),
    reserve: ctx.permission("reserve", MODULE_PERMISSIONS.inventory.reserve),
    purchase: ctx.permission("purchase", MODULE_PERMISSIONS.inventory.purchase),
  };
  return `${schemaPreamble(ctx)}
-- Stock per catalog variant and location: an append-only movement ledger,
-- reservations with expiry, transfers and purchase orders with receiving.
${tables(ctx, names)}${ledger(ctx, names)}${locationFunctions(ctx, names)}${stockFunctions(ctx, names)}${reservationFunctions(ctx, names)}${transferFunctions(ctx, names)}${purchaseOrderFunctions(ctx, names)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const transfers = ctx.hasTable("transfers") && ctx.hasTable("transferLines");
  const orders =
    ctx.hasTable("purchaseOrders") && ctx.hasTable("purchaseOrderLines");
  return [
    {
      name: "save_location",
      args: ["{id}", "uuid", "text", "text", "text"],
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
      args: ["uuid", "uuid", "integer", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "count_stock",
      args: ["uuid", "uuid", "integer", "text"],
      returns: "jsonb",
    },
    {
      name: "set_reorder_point",
      args: ["uuid", "uuid", "integer"],
      returns: "boolean",
    },
    {
      name: "reserve_stock",
      args: ["uuid", "uuid", "integer", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
    { name: "commit_reservation", args: ["uuid"], returns: "jsonb" },
    { name: "release_reservation", args: ["uuid"], returns: "boolean" },
    { name: "expire_reservations", args: ["integer"], returns: "integer" },
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

export const INVENTORY: ModuleDefinition = {
  name: "inventory",
  title: "Inventory",
  description:
    "Stock per catalog variant and location: an append-only movement ledger, reservations with expiry, transfers and purchase orders with partial receiving.",
  requires: ["tenant", "access", "catalog"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
