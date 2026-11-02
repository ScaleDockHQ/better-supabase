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
`;
}
