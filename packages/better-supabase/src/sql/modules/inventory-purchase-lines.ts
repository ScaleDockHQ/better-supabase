import type { BlockSqlContext } from "../context.ts";

import { fail } from "../shared.ts";
import { columns } from "./inventory-stock.ts";

/** A line's unit cost: minor units as digits (ADR 0037). */
export const UNIT_COST = "'^[0-9]{1,18}$'";

const UUID =
  "'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'";

const QUANTITY = "'^[0-9]{1,14}([.][0-9]{1,6})?$'";

/**
 * Raises unless `lines` is a non-empty array of objects whose `key` is a uuid
 * (once each) and whose `quantity` is a positive number with up to six
 * decimals. The variant's scale decides how many it may have (ADR 0127).
 */
export function linesCheck(lines: string, key: string, extra = ""): string {
  return `if jsonb_typeof(${lines}) is distinct from 'array' or jsonb_array_length(${lines}) = 0
    or exists (
      select 1 from jsonb_array_elements(${lines}) e
      where jsonb_typeof(e) <> 'object'
        or coalesce(e ->> '${key}', '') !~ ${UUID}
        or case when coalesce(e ->> 'quantity', '') ~ ${QUANTITY} then (e ->> 'quantity')::numeric <= 0 else true end${extra}
    )
    or (select count(distinct e ->> '${key}') from jsonb_array_elements(${lines}) e) <> jsonb_array_length(${lines}) then
    ${fail("INVENTORY_LINES_INVALID", `lines must be a non-empty list with a unique ${key} and a positive quantity each`, "22023")}
  end if;`;
}

/** Raises unless every line's `variantId` is a variant of the tenant. */
export function linesVariantCheck(
  ctx: BlockSqlContext,
  lines: string,
  tenant: string,
): string {
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  return `if exists (
    select 1 from jsonb_array_elements(${lines}) e
    where not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = (e ->> 'variantId')::uuid and cv.${v("tenant")} = ${tenant})
  ) then
    ${fail("INVENTORY_VARIANT_NOT_FOUND", "a line names a variant outside this organization", "P0002")}
  end if;`;
}
