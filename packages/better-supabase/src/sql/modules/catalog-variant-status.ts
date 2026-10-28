import type { BlockSqlContext } from "../context.ts";
import type { Names } from "./catalog-names.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { guard } from "./catalog-functions.ts";

export function variantStatusFunction(
  ctx: BlockSqlContext,
  names: Names,
): string {
  const hasValues =
    ctx.hasTable("variantValues") &&
    ctx.hasTable("optionValues") &&
    ctx.hasTable("options");

  const { fn } = names;

  if (
    typeof ctx.config.columns["variants"]?.["status"] !== "string" ||
    !ctx.has("variants", "status")
  ) {
    return `
-- Variants have no status column (columns.variants.status), so this refuses.
create or replace function ${fn("set_variant_status")}(variant uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${fail("CATALOG_VARIANT_STATUS_UNSUPPORTED", "this variants table has no status column", "22023")}
end;
$$;
${userGrant(`${fn("set_variant_status")}(uuid, text)`)}
`;
  }

  const variants = ctx.table("variants");
  const v = (column: string): string => ctx.col("variants", column);
  const map = ctx.config.values?.["variants"];

  const labels = [
    ...new Set([
      "active",
      "archived",
      ...(isRecord(map) && isRecord(map["status"])
        ? Object.keys(map["status"])
        : []),
    ]),
  ];

  const live = ctx.is(
    "variants",
    "status",
    `x.${v("status")}::text`,
    ["archived"],
    true,
  );

  const liveChecks = hasValues
    ? (() => {
        const options = ctx.table("options");
        const variantValues = ctx.table("variantValues");
        const o = (column: string): string => ctx.col("options", column);
        const vv = (column: string): string => ctx.col("variantValues", column);

        const valueSet = (alias: string): string =>
          `coalesce((select array_agg(y.${vv("value")} order by y.${vv("value")}) from ${variantValues} y where y.${vv("variant")} = ${alias}), '{}'::uuid[])`;

        return `
  if exists (select 1 from ${variants} x where x.${v("id")} = set_variant_status.variant and ${live}) then
    if (select count(*) from ${options} o where o.${o("product")} = v_product) <> (select count(*) from ${variantValues} y where y.${vv("variant")} = set_variant_status.variant) then
      ${fail("CATALOG_VARIANT_OPTIONS", "a live variant needs one value of each product option; set them with save_variant", "22023")}
    end if;
    if exists (
      select 1 from ${variants} x
      where x.${v("product")} = v_product and x.${v("id")} <> set_variant_status.variant and ${live}
        and ${valueSet(`x.${v("id")}`)} = ${valueSet("set_variant_status.variant")}
    ) then
      ${fail("CATALOG_VARIANT_DUPLICATE", "another live variant has these option values", "23505")}
    end if;
  end if;`;
      })()
    : "";

  return `
-- Moves a variant to another status: active, archived or a label
-- values.variants.status maps. A variant that goes live again needs a free
-- combination of option values.
create or replace function ${fn("set_variant_status")}(variant uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_product uuid;
  v_sku text;
  v_from text;
  v_to text;
begin
  select x.${v("tenant")}, x.${v("product")}, x.${v("sku")}, ${ctx.label("variants", "status", `x.${v("status")}`)} into v_tenant, v_product, v_sku, v_from
  from ${variants} x where x.${v("id")} = set_variant_status.variant for update;
  if v_tenant is null then
    ${fail("CATALOG_VARIANT_NOT_FOUND", "variant not found", "P0002")}
  end if;
  ${guard(names, "v_tenant", names.update)}
  if set_variant_status.status is null or not (set_variant_status.status = any (${sqlString(`{${labels.join(",")}}`)}::text[])) then
    ${fail("CATALOG_STATUS_INVALID", `the status must be ${labels.join(", ")}`, "22023")}
  end if;
  update ${variants} x set ${v("status")} = ${ctx.cast("variants", "status", "set_variant_status.status")}, ${v("updatedAt")} = now()
  where x.${v("id")} = set_variant_status.variant
  returning ${ctx.label("variants", "status", `x.${v("status")}`)} into v_to;${liveChecks}
  ${ctx.record({
    type: "variant.updated",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', set_variant_status.variant, 'productId', v_product, 'sku', v_sku)`,
    subject: `'variants/' || set_variant_status.variant::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return jsonb_build_object('id', set_variant_status.variant, 'status', v_to, 'from', v_from);
end;
$$;
${userGrant(`${fn("set_variant_status")}(uuid, text)`)}
`;
}
