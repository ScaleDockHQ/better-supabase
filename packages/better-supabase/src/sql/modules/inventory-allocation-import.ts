import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail, serviceGrant } from "../shared.ts";
import { columns, locationsOf } from "./inventory-stock.ts";

/** An import target names its functions as `schema.function`, without quotes. */
const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * The import target of the `stock_allocation` entity (ADR 0668): a document's
 * stock allocation as the source system had it, without moving stock. The
 * invoices block owns `import_allocation` for payment allocations, so this one
 * is named for stock.
 */
export function allocationImportFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  const { fn } = names;
  const allocations = ctx.table("allocations");
  const levels = ctx.table("levels");
  const loc = locationsOf(ctx);
  const l = loc.col;
  const a = columns(ctx, "allocations");
  const lv = columns(ctx, "levels");
  const catalog = ctx.of("catalog");
  const v = columns(catalog, "variants");

  return `
-- The import target of the stock_allocation entity: item.data is { variantId or
-- sku, locationId or location (a code), documentType, documentId, lineId?,
-- quantity, allocated?, fulfilled?, status? (open, fulfilled or released) }.
-- allocated is the part held for the document now and fulfilled the part that
-- already shipped; both default to zero, and a fulfilled or released
-- allocation holds nothing. An open allocation adds what it holds to the
-- location's reserved stock, and nothing else moves: no movement, no event.
-- Importing the same key again replaces an open allocation and keeps a
-- fulfilled or released one as it is, with a warning.
create or replace function ${fn("import_stock_allocation")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_stock_allocation.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_stock_allocation.item -> 'data';
  v_variant uuid;
  v_location uuid;
  v_quantity numeric;
  v_allocated numeric;
  v_fulfilled numeric;
  v_status text := coalesce(nullif(v_data ->> 'status', ''), 'open');
  v_row record;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_variant := nullif(v_data ->> 'variantId', '')::uuid;
    v_location := nullif(v_data ->> 'locationId', '')::uuid;
    v_quantity := (v_data ->> 'quantity')::numeric;
    v_allocated := coalesce((v_data ->> 'allocated')::numeric, 0);
    v_fulfilled := coalesce((v_data ->> 'fulfilled')::numeric, 0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${fail("IMPORT_ITEM_INVALID", "ids are uuids and quantity, allocated and fulfilled are numbers", "22023")}
  end;
  if v_status not in ('open', 'fulfilled', 'released') then
    ${fail("IMPORT_ITEM_INVALID", "status is open, fulfilled or released", "22023")}
  end if;
  if v_quantity is null or v_quantity <= 0 or v_allocated < 0 or v_fulfilled < 0 or v_allocated + v_fulfilled > v_quantity then
    ${fail("IMPORT_ITEM_INVALID", "quantity is above zero and allocated plus fulfilled isn't more than the quantity", "22023")}
  end if;
  if coalesce(v_data ->> 'documentType', '') !~ '^[a-z][a-z0-9_]{0,62}$' or length(coalesce(v_data ->> 'documentId', '')) not between 1 and 200 then
    ${fail("IMPORT_ITEM_INVALID", "an allocation names its document type (lower case, with underscores) and its document id", "22023")}
  end if;
  if v_variant is null then
    select y.${v("id")} into v_variant from ${catalog.table("variants")} y where y.${v("tenant")} = v_tenant and y.${v("sku")} = v_data ->> 'sku';
  end if;
  if v_variant is null or not exists (select 1 from ${catalog.table("variants")} y where y.${v("id")} = v_variant and y.${v("tenant")} = v_tenant) then
    ${fail("IMPORT_ITEM_INVALID", "the allocation's variant isn't in this organization", "22023")}
  end if;
  if v_location is null then
    select x.${l("id")} into v_location from ${loc.table} x where x.${l("tenant")} = v_tenant and x.${l("code")} = v_data ->> 'location';
  elsif not exists (select 1 from ${loc.table} x where x.${l("id")} = v_location and x.${l("tenant")} = v_tenant) then
    v_location := null;
  end if;
  if v_location is null then
    ${fail("IMPORT_ITEM_INVALID", "the allocation's location isn't in this organization", "22023")}
  end if;
  if v_status <> 'open' then
    v_allocated := 0;
  end if;
  if v_status = 'fulfilled' then
    v_fulfilled := v_quantity;
  end if;
  insert into ${levels} (${lv("tenant")}, ${lv("variant")}, ${lv("location")})
  values (v_tenant, v_variant, v_location)
  on conflict (${lv("variant")}, ${lv("location")}) do nothing;
  if import_stock_allocation.subject_id is not null then
    select x.${a("id")} as id, x.${a("variant")} as variant, x.${a("location")} as location, x.${a("allocated")} as allocated,
      x.${a("status")} as status, x.${a("updatedAt")} as updated_at
    into v_row from ${allocations} x
    where x.${a("id")} = import_stock_allocation.subject_id::uuid and x.${a("tenant")} = v_tenant for update;
    if v_row.id is null then
      ${fail("IMPORT_ITEM_INVALID", "the stock allocation no longer exists", "22023")}
    end if;
    if v_row.status <> 'open' then
      return jsonb_build_object('subjectId', v_row.id::text, 'updatedAt', v_row.updated_at, 'warnings', jsonb_build_array(jsonb_build_object(
        'code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'a fulfilled or released stock allocation is kept as imported')));
    end if;
    update ${levels} x set ${lv("reserved")} = greatest(x.${lv("reserved")} - v_row.allocated, 0), ${lv("updatedAt")} = now()
    where x.${lv("variant")} = v_row.variant and x.${lv("location")} = v_row.location;
    update ${allocations} x set ${a("variant")} = v_variant, ${a("location")} = v_location, ${a("documentType")} = v_data ->> 'documentType',
      ${a("documentId")} = v_data ->> 'documentId', ${a("line")} = nullif(v_data ->> 'lineId', ''), ${a("quantity")} = v_quantity,
      ${a("allocated")} = v_allocated, ${a("fulfilled")} = v_fulfilled, ${a("status")} = v_status, ${a("updatedAt")} = now()
    where x.${a("id")} = v_row.id returning x.${a("id")}, x.${a("updatedAt")} into v_id, v_updated;
  else
    insert into ${allocations} as x (${a("tenant")}, ${a("variant")}, ${a("location")}, ${a("documentType")}, ${a("documentId")}, ${a("line")},
      ${a("quantity")}, ${a("allocated")}, ${a("fulfilled")}, ${a("status")})
    values (v_tenant, v_variant, v_location, v_data ->> 'documentType', v_data ->> 'documentId', nullif(v_data ->> 'lineId', ''),
      v_quantity, v_allocated, v_fulfilled, v_status)
    returning x.${a("id")}, x.${a("updatedAt")} into v_id, v_updated;
  end if;
  update ${levels} x set ${lv("reserved")} = x.${lv("reserved")} + v_allocated, ${lv("updatedAt")} = now()
  where x.${lv("variant")} = v_variant and x.${lv("location")} = v_location;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_stock_allocation")}(uuid, jsonb, text)`)}

create or replace function ${fn("stock_allocation_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${a("updatedAt")} from ${allocations} x where x.${a("id")} = $1::uuid
$$;
${serviceGrant(`${fn("stock_allocation_updated_at")}(text)`)}
`;
}

/** What `contributes.imports` adds for stock allocations. */
export function allocationImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return [
    {
      entity: "stock_allocation",
      subjectType: "stock_allocation",
      write: plain(own.fn("import_stock_allocation")),
      updatedAt: plain(own.fn("stock_allocation_updated_at")),
    },
  ];
}
