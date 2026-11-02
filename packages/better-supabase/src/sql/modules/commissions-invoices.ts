import type { BlockSqlContext } from "../context.ts";
import type { CommissionSql } from "./commissions-sql.ts";

/** Whether `blocks.commissions.options.invoices` turns the integration on. */
export function accruesInvoices(ctx: BlockSqlContext): boolean {
  if (!ctx.flag("invoices", false)) {
    return false;
  }

  if (!ctx.installed("invoices")) {
    throw new TypeError(
      "blocks.commissions.options.invoices needs the invoices block",
    );
  }

  if (!ctx.of("invoices").has("invoices", "createdBy")) {
    throw new TypeError(
      "blocks.commissions.options.invoices needs the invoices createdBy column",
    );
  }

  return true;
}

/**
 * A trigger that accrues a commission for the invoice's creator when a sales
 * invoice becomes paid, whichever function paid it. The commission is the
 * seller's plan applied to the invoice total, once per invoice.
 */
export function invoiceCommissionSql(
  ctx: BlockSqlContext,
  k: CommissionSql,
): string {
  const invoices = ctx.of("invoices");
  const i = (column: string): string => invoices.col("invoices", column);
  const fn = ctx.fn("bsb_commission_invoice");
  const trigger = ctx.naming.rename("invoices_commission");

  const sales = invoices.has("invoices", "direction")
    ? `\n  if new.${i("direction")} <> 'sales' then\n    return null;\n  end if;`
    : "";

  return `
-- A commission for the creator of each invoice that becomes paid
-- (options.invoices): the seller's plan applied to the invoice total, once
-- per invoice. An invoice without a creator or a plan accrues nothing.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${i("status")} <> 'paid' or old.${i("status")} = 'paid' or new.${i("createdBy")} is null or new.${i("total")} <= 0 then
    return null;
  end if;${sales}
  perform ${k.fn("commission_accrue")}(new.${i("tenant")}, new.${i("createdBy")}, 'invoices', new.${i("id")}::text,
    new.${i("total")}, new.${i("currency")}::text, coalesce(new.${i("paidAt")}, now())::date, null, null);
  return null;
end;
$$;
revoke all on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${invoices.table("invoices")};
create trigger ${trigger}
after update of ${i("status")} on ${invoices.table("invoices")}
for each row execute function ${fn}();
`;
}
