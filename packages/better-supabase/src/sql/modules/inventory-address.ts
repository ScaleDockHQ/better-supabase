import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { fail, userGrant } from "../shared.ts";
import { columns, guard } from "./inventory-stock.ts";

/** The keys of `locations.address`; every value is text. */
const ADDRESS_KEYS = [
  "line1",
  "line2",
  "postalCode",
  "city",
  "region",
  "country",
] as const;

/** Whether inventory's own locations table has an address column. */
function addressOn(ctx: BlockSqlContext): boolean {
  return ctx.hasTable("locations") && ctx.has("locations", "address");
}

/** The address column on an installed locations table (managed mode). */
export function addressColumn(ctx: BlockSqlContext): string {
  if (!ctx.manages || !addressOn(ctx)) {
    return "";
  }

  const l = columns(ctx, "locations");

  return `
-- Where the location is: line1, line2, postalCode, city, region and country
-- (a two-letter ISO 3166 code).
alter table ${ctx.table("locations")} add column if not exists ${l("address")} jsonb;
alter table ${ctx.table("locations")} drop constraint if exists ${ctx.naming.rename("inventory_locations_address_check")};
alter table ${ctx.table("locations")} add constraint ${ctx.naming.rename("inventory_locations_address_check")} check (${l("address")} is null or jsonb_typeof(${l("address")}) = 'object');
`;
}

/** `set_location_address`: validates the address and stores it. */
export function addressFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  if (!addressOn(ctx)) {
    return "";
  }

  const l = columns(ctx, "locations");

  return `
-- Sets a location's address, or clears it with null. The keys are
-- ${ADDRESS_KEYS.join(", ")}; each value is text, and country is a
-- two-letter code.
create or replace function ${names.fn("set_location_address")}(location uuid, address jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_address jsonb := set_location_address.address;
begin
  select x.${l("tenant")} into v_tenant from ${ctx.table("locations")} x where x.${l("id")} = set_location_address.location;
  if v_tenant is null then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found", "P0002")}
  end if;
  ${guard(names.scope, names.manage, "v_tenant")}
  if v_address is not null and jsonb_typeof(v_address) = 'null' then
    v_address := null;
  end if;
  if v_address is not null then
    if jsonb_typeof(v_address) <> 'object'
      or exists (select 1 from jsonb_each(v_address) e where e.key <> all (array[${ADDRESS_KEYS.map((key) => `'${key}'`).join(", ")}]) or jsonb_typeof(e.value) <> 'string') then
      ${fail("INVENTORY_ADDRESS_INVALID", `an address is an object of text values with the keys ${ADDRESS_KEYS.join(", ")}`, "22023")}
    end if;
    if v_address ? 'country' and (v_address ->> 'country') !~ '^[A-Z]{2}$' then
      ${fail("INVENTORY_ADDRESS_INVALID", "country is a two-letter ISO 3166 code in capitals", "22023")}
    end if;
  end if;
  update ${ctx.table("locations")} x set ${l("address")} = v_address, ${l("updatedAt")} = now() where x.${l("id")} = set_location_address.location;
  return true;
end;
$$;
${userGrant(`${names.fn("set_location_address")}(uuid, jsonb)`)}
`;
}

export function addressContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return addressOn(ctx)
    ? [
        {
          name: "set_location_address",
          args: ["uuid", "jsonb"],
          returns: "boolean",
        },
      ]
    : [];
}
