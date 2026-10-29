import type { BlockSqlContext } from "../context.ts";
import type { QuoteNames } from "./quotes-functions.ts";

import { sqlString } from "../../core/template.ts";
import { countedLine, declared, lineColumn } from "../line-items-sql.ts";
import { serviceGrant, triggerGrant } from "../shared.ts";
import { variantTracked } from "./catalog-tracking.ts";

/** The inventory document type of a quote version's stock holds. */
const DOCUMENT = "'quote_version'";

/** The statuses that end a quote's holds: back to draft, or closed unanswered. */
const RELEASED = ["draft", "withdrawn", "expired", "rejected"] as const;

/**
 * `options.holds`: whether sending a quote holds stock for its catalog lines.
 * Needs the inventory block and product columns on the quote lines.
 */
export function quoteHolds(ctx: BlockSqlContext): boolean {
  if (!ctx.flag("holds", false)) {
    return false;
  }

  if (!ctx.installed("inventory")) {
    throw new TypeError(
      "blocks.quotes.options.holds needs the inventory block",
    );
  }

  if (
    !declared(ctx, "lines", "productType") ||
    !declared(ctx, "lines", "productId")
  ) {
    throw new TypeError(
      "blocks.quotes.options.holds needs columns.lines.productType and columns.lines.productId",
    );
  }

  return true;
}

/**
 * PL/pgSQL for `send_quote`: releases the holds of the versions sent before and
 * allocates each counted, tracked catalog line of version `v_version`, keeping
 * what isn't available on backorder. Runs once per version.
 */
export function holdsOnSend(ctx: BlockSqlContext, n: QuoteNames): string {
  if (!quoteHolds(ctx)) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const catalog = ctx.of("catalog");
  const a = (column: string): string => inventory.col("allocations", column);
  const cv = (column: string): string => catalog.col("variants", column);
  const l = (column: string): string => n.c("lines", column);
  const q = (column: string): string => n.c("quotes", column);

  const line = (column: string): string =>
    lineColumn(ctx, "lines", "x", column);

  const variantType = sqlString(catalog.naming.rename("product_variant"));

  return `
  perform ${n.fn("release_quote_holds")}(v_row.${q("id")});
  if not exists (select 1 from ${inventory.table("allocations")} y where y.${a("tenant")} = v_row.${q("tenant")}
    and y.${a("documentType")} = ${DOCUMENT} and y.${a("documentId")} = v_version::text) then
    for v_hold in
      select x.${l("id")} as id, cv.${cv("id")} as variant, x.${l("quantity")}::numeric as quantity
      from ${n.t("lines")} x
      join ${catalog.table("variants")} cv on ${line("productType")}::text = ${variantType} and ${line("productId")} ~* '^[0-9a-f-]{36}$'
        and cv.${cv("id")} = ${line("productId")}::uuid and cv.${cv("tenant")} = v_row.${q("tenant")}
      where x.${l("parent")} = v_row.${q("id")} and ${countedLine(ctx, "lines", "x")} and x.${l("quantity")} > 0
        and ${variantTracked(catalog, "cv")}
      order by x.${l("position")}
    loop
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform ${inventory.fn("allocate_stock")}(v_row.${q("tenant")}, v_hold.variant, null, v_hold.quantity, ${DOCUMENT}, v_version::text, v_hold.id::text, true);
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end loop;
  end if;`;
}

/** The `declare` entries `holdsOnSend` needs. */
export function holdsDeclare(ctx: BlockSqlContext): string {
  return quoteHolds(ctx) ? "\n  v_hold record;\n  v_claims text;" : "";
}

/**
 * `release_quote_holds`, which releases the open stock holds of every version
 * of a quote, and the trigger that calls it when the quote goes back to draft
 * or closes unanswered.
 */
export function holdsSql(ctx: BlockSqlContext, n: QuoteNames): string {
  if (!quoteHolds(ctx)) {
    return "";
  }

  const inventory = ctx.of("inventory");
  const q = (column: string): string => n.c("quotes", column);
  const v = (column: string): string => n.c("versions", column);
  const trigger = ctx.trigger("quote_holds_release");
  const triggerFn = `better_supabase.${trigger.replaceAll('"', "")}()`;

  return `
-- Releases the open stock holds of every published version of a quote.
-- Returns how many it released.
create or replace function ${n.fn("release_quote_holds")}(quote uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version record;
  v_claims text := current_setting('request.jwt.claims', true);
  v_count integer := 0;
begin
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  for v_version in
    select x.${v("id")} as id, x.${v("tenant")} as tenant from ${n.t("versions")} x where x.${v("quote")} = release_quote_holds.quote
  loop
    v_count := v_count + ${inventory.fn("release_allocations")}(v_version.tenant, ${DOCUMENT}, v_version.id::text);
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v_count;
end;
$$;
${serviceGrant(`${n.fn("release_quote_holds")}(uuid)`)}
create or replace function ${triggerFn}
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${ctx.is("quotes", "status", `new.${q("status")}`, RELEASED)} then
    perform ${n.fn("release_quote_holds")}(new.${q("id")});
  end if;
  return null;
end;
$$;
${triggerGrant(triggerFn)}
drop trigger if exists ${trigger} on ${n.t("quotes")};
create trigger ${trigger} after update of ${q("status")} on ${n.t("quotes")}
for each row when (old.${q("status")} is distinct from new.${q("status")})
execute function ${triggerFn};
`;
}
