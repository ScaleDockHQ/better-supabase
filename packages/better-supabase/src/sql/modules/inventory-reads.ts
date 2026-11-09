import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlRead } from "../reads.ts";

import { declareRead } from "../reads.ts";
import { userGrant } from "../shared.ts";
import { columns } from "./inventory-stock.ts";

/** What `inventory_overview` returns. */
export const INVENTORY_OVERVIEW_RESULT: ReadType = {
  levelCount: "number",
  lowStockCount: "number",
  lowStock: [
    {
      variantId: "text",
      locationId: "text",
      onHand: "text",
      available: "text",
      reorderPoint: "text",
    },
  ],
  expiring: [
    {
      lotId: "text",
      code: "text",
      variantId: "text",
      locationId: "text",
      expiresOn: "text",
      onHand: "text",
    },
  ],
};

export interface InventoryLowStock {
  readonly variantId: string;
  readonly locationId: string;
  /** Quantities are text, in the variant's unit. */
  readonly onHand: string;
  readonly available: string;
  readonly reorderPoint: string;
}

export interface InventoryExpiringLot {
  readonly lotId: string;
  readonly code: string;
  readonly variantId: string;
  readonly locationId: string;
  readonly expiresOn: string;
  readonly onHand: string;
}

/** What `inventory.overview` returns. */
export interface InventoryOverview {
  /** How many variant and location pairs hold a stock level. */
  readonly levelCount: number;
  /** All levels at or below their reorder point, not just the listed ones. */
  readonly lowStockCount: number;
  /** The emptiest levels first, up to `limit`. */
  readonly lowStock: readonly InventoryLowStock[];
  /** Lots with stock that expire within `expiryDays`, soonest first. */
  readonly expiring: readonly InventoryExpiringLot[];
}

export const INVENTORY_READS: readonly BlockSqlRead[] = [
  declareRead(
    "overview",
    "inventory_overview",
    {
      organizationId: { param: "tenant", type: "id" },
      limit: { param: "row_limit", type: "int", optional: true },
      expiryDays: { param: "expiry_days", type: "int", optional: true },
    },
    INVENTORY_OVERVIEW_RESULT,
    "The stock page in one call: how many levels exist, the levels at or below their reorder point and the lots that expire soon.",
    ["levels", "lots", "buckets"],
  ),
];

/**
 * `inventory_overview`: a plpgsql function that runs as the caller, so row
 * security decides which levels the caller sees. Lots come from
 * `expiring_lots`, which checks the read permission itself.
 */
export function inventoryReads(ctx: BlockSqlContext): string {
  const fn = ctx.fn("inventory_overview");
  const lv = columns(ctx, "levels");
  const ledger = ctx.of("ledger");
  const transactions = ledger.table("transactions");
  const tx = (column: string): string => ledger.col("transactions", column);

  return `
-- The stock page in one call: the level count, the levels at or below their
-- reorder point (the emptiest first) and the lots that expire soon.
create or replace function ${fn}(tenant ${ctx.idType}, row_limit integer default 20, expiry_days integer default 30)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_low jsonb;
  v_low_count integer;
  v_level_count integer;
  v_expiring jsonb;
begin
  select count(*)::integer into v_level_count
  from ${ctx.table("levels")} y where y.${lv("tenant")} = inventory_overview.tenant;

  select count(*)::integer into v_low_count
  from ${ctx.table("levels")} y
  where y.${lv("tenant")} = inventory_overview.tenant
    and y.${lv("reorderPoint")} is not null and y.${lv("available")} <= y.${lv("reorderPoint")};

  select coalesce(jsonb_agg(jsonb_build_object(
      'variantId', x.${lv("variant")}, 'locationId', x.${lv("location")},
      'onHand', x.${lv("onHand")}::text, 'available', x.${lv("available")}::text,
      'reorderPoint', x.${lv("reorderPoint")}::text)
    order by x.${lv("available")} - x.${lv("reorderPoint")}, x.${lv("variant")}, x.${lv("location")}), '[]'::jsonb)
  into v_low
  from (
    select * from ${ctx.table("levels")} y
    where y.${lv("tenant")} = inventory_overview.tenant
      and y.${lv("reorderPoint")} is not null and y.${lv("available")} <= y.${lv("reorderPoint")}
    order by y.${lv("available")} - y.${lv("reorderPoint")}, y.${lv("variant")}, y.${lv("location")}
    limit greatest(coalesce(inventory_overview.row_limit, 20), 0)
  ) x;

  ${
    ctx.hasTable("lots") && ctx.hasTable("buckets")
      ? `select coalesce(jsonb_agg(jsonb_build_object(
      'lotId', e ->> 'lotId', 'code', e ->> 'code', 'variantId', e ->> 'variantId',
      'locationId', e ->> 'locationId', 'expiresOn', e ->> 'expiresOn', 'onHand', e ->> 'onHand')), '[]'::jsonb)
  into v_expiring
  from jsonb_array_elements(${ctx.fn("expiring_lots")}(inventory_overview.tenant,
    current_date + greatest(coalesce(inventory_overview.expiry_days, 30), 0))) e;`
      : "v_expiring := '[]'::jsonb;"
  }

  return jsonb_build_object('levelCount', v_level_count, 'lowStockCount', v_low_count,
    'lowStock', v_low, 'expiring', v_expiring);
end;
$$;
${userGrant(`${fn}(${ctx.idType}, integer, integer)`)}

-- Levels for the requested variants. A null variant list reads every level of
-- the organization; a list uses the level primary key and does not scan the rest.
create or replace function ${ctx.fn("inventory_levels")}(tenant ${ctx.idType}, variant_ids uuid[] default null, location_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'variantId', y.${lv("variant")},
    'locationId', y.${lv("location")},
    'onHand', y.${lv("onHand")}::text,
    'allocated', y.${lv("reserved")}::text,
    'available', y.${lv("available")}::text,
    'incoming', y.${lv("incoming")}::text,
    'reorderPoint', y.${lv("reorderPoint")}::text,
    'status', case
      when y.${lv("available")} <= 0 then 'out'
      when y.${lv("reorderPoint")} is not null and y.${lv("available")} <= y.${lv("reorderPoint")} then 'low'
      else 'in_stock'
    end
  )), '[]'::jsonb)
  from ${ctx.table("levels")} y
  where y.${lv("tenant")} = inventory_levels.tenant
    and (inventory_levels.variant_ids is null or y.${lv("variant")} = any (inventory_levels.variant_ids))
    and (inventory_levels.location_id is null or y.${lv("location")} = inventory_levels.location_id)
$$;
${userGrant(`${ctx.fn("inventory_levels")}(${ctx.idType}, uuid[], uuid)`)}

create or replace function ${ctx.fn("inventory_status_counts")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'inStock', count(*) filter (where y.${lv("available")} > 0 and (y.${lv("reorderPoint")} is null or y.${lv("available")} > y.${lv("reorderPoint")})),
    'low', count(*) filter (where y.${lv("reorderPoint")} is not null and y.${lv("available")} <= y.${lv("reorderPoint")} and y.${lv("available")} > 0),
    'out', count(*) filter (where y.${lv("available")} <= 0)
  )
  from ${ctx.table("levels")} y
  where y.${lv("tenant")} = inventory_status_counts.tenant
$$;
${userGrant(`${ctx.fn("inventory_status_counts")}(${ctx.idType})`)}

create or replace function ${ctx.fn("list_inventory_movements")}(tenant ${ctx.idType}, variant uuid default null, location uuid default null, bin uuid default null, lot uuid default null, document_type text default null, document_id text default null, row_limit integer default 50, row_offset integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.${tx("id")},
    'kind', x.${tx("kind")},
    'variantId', x.${tx("metadata")} ->> 'variantId',
    'locationId', x.${tx("metadata")} ->> 'locationId',
    'binId', x.${tx("metadata")} ->> 'binId',
    'lotId', x.${tx("metadata")} ->> 'lotId',
    'quantity', x.${tx("metadata")} ->> 'quantity',
    'documentType', x.${tx("referenceType")},
    'documentId', x.${tx("referenceId")},
    'effectiveAt', x.${tx("effectiveAt")}
  )), '[]'::jsonb)
  from (
    select *
    from ${transactions} y
    where y.${tx("tenant")} = list_inventory_movements.tenant
      and y.${tx("kind")} like 'stock.%'
      and (list_inventory_movements.variant is null or y.${tx("metadata")} ->> 'variantId' = list_inventory_movements.variant::text)
      and (list_inventory_movements.location is null or y.${tx("metadata")} ->> 'locationId' = list_inventory_movements.location::text)
      and (list_inventory_movements.bin is null or y.${tx("metadata")} ->> 'binId' = list_inventory_movements.bin::text)
      and (list_inventory_movements.lot is null or y.${tx("metadata")} ->> 'lotId' = list_inventory_movements.lot::text)
      and (list_inventory_movements.document_type is null or y.${tx("referenceType")} = list_inventory_movements.document_type)
      and (list_inventory_movements.document_id is null or y.${tx("referenceId")} = list_inventory_movements.document_id)
    order by y.${tx("effectiveAt")} desc, y.${tx("id")}
    limit least(greatest(coalesce(list_inventory_movements.row_limit, 50), 0), 200)
    offset greatest(coalesce(list_inventory_movements.row_offset, 0), 0)
  ) x
$$;
${userGrant(`${ctx.fn("list_inventory_movements")}(${ctx.idType}, uuid, uuid, uuid, uuid, text, text, integer, integer)`)}
`;
}
