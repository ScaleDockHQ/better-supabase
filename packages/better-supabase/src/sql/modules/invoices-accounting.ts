import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

import { countedLine, lineAmount, lineColumn } from "../line-items-sql.ts";
import { invoiceParty } from "./invoices-functions.ts";

/**
 * What invoices books in accounting: an issued invoice or credit note in the
 * sales journal (the receivable against revenue and tax per rate), and each
 * payment or refund in the bank journal (bank against the receivable).
 */
export function invoiceAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const invoices = ctx.table("invoices");
  const lines = ctx.table("lines");
  const i = (column: string): string => ctx.col("invoices", column);
  const l = (column: string): string => ctx.col("lines", column);
  const ledger = ctx.of("ledger");
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const la = (column: string): string => ledger.col("accounts", column);
  const amount = lineAmount(ctx, "lines", "l");
  const discount = `round(${amount} * ${lineColumn(ctx, "lines", "l", "discountBps")} / 10000.0)`;
  const rate = lineColumn(ctx, "lines", "l", "taxRateBps");
  const code = lineColumn(ctx, "lines", "l", "taxCode");

  const inclusive = ctx.has("invoices", "pricesIncludeTax")
    ? `x.${i("pricesIncludeTax")}`
    : "false";

  const party = (alias: string): string => {
    const id = (["company", "contact"] as const).find(
      (each) => invoiceParty(ctx, each) !== undefined,
    );

    return id === undefined ? "null" : `${alias}.${i(`${id}Id`)}::text`;
  };

  // Splits the invoice's total over the rate groups by weight; the last group
  // takes the rounding, so the groups add up to it exactly.
  const share = (total: string, weight: string): string =>
    `case when sum(g.${weight}) over () = 0
        then case when row_number() over w = count(*) over () then ${total} else 0 end
        else round(${total} * sum(g.${weight}) over w / sum(g.${weight}) over ()) - round(${total} * (sum(g.${weight}) over w - g.${weight}) / sum(g.${weight}) over ())
      end`;

  const taxLine = (side: string, amountSql: string): string =>
    `jsonb_strip_nulls(jsonb_build_object('role', ${side}, 'credit', (inv.sign * ${amountSql})::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'partyId', inv.party))`;

  return [
    {
      source: "invoice",
      journal: "sales",
      fn: "accounting_invoice_lines",
      comment:
        "The entry of an issued invoice or credit note for accounting: the receivable\nagainst revenue and tax per rate, mirrored for a credit note.",
      body: `  with inv as (
    select x.${i("id")} as id, x.${i("tenant")} as tenant, x.${i("issuedOn")} as issued_on, x.${i("currency")} as currency,
      x.${i("identifier")} as identifier, x.${i("title")} as title, x.${i("subtotal")} as subtotal, x.${i("taxTotal")} as tax_total,
      x.${i("total")} as total, ${party("x")} as party, ${inclusive} as inclusive,
      case when ${ctx.is("invoices", "kind", `x.${i("kind")}`, ["credit_note"])} then -1 else 1 end as sign
    from ${invoices} x
    where x.${i("id")}::text = source_id and ${ctx.is("invoices", "status", `x.${i("status")}`, ["draft", "void"], true)}
  ),
  groups as (
    select ${rate} as rate, ${code} as code, sum(${amount} - ${discount}) as net,
      sum((${amount} - ${discount}) * ${rate} / case when inv.inclusive then 10000.0 + ${rate} else 10000.0 end) as tax
    from ${lines} l cross join inv
    where l.${l("parent")} = inv.id and ${countedLine(ctx, "lines", "l")}
    group by 1, 2
  ),
  shares as (
    select g.rate, g.code,
      ${share("inv.subtotal", "net")} as net,
      ${share("inv.tax_total", "tax")} as tax
    from groups g cross join inv
    window w as (order by g.rate, g.code nulls first rows between unbounded preceding and current row)
  )
  select jsonb_build_object(
    'organizationId', inv.tenant,
    'entryDate', inv.issued_on,
    'currency', inv.currency,
    'reference', inv.identifier,
    'memo', inv.title,
    'lines', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', (inv.sign * inv.total)::text, 'partyId', inv.party)))
      || coalesce((select jsonb_agg(${taxLine("'revenue'", "s.net")}) from shares s where s.net <> 0), '[]'::jsonb)
      || coalesce((select jsonb_agg(${taxLine("'tax_payable'", "s.tax")}) from shares s where s.tax <> 0), '[]'::jsonb)
  )
  from inv`,
    },
    {
      source: "invoice_payment",
      journal: "bank",
      fn: "accounting_invoice_payment_lines",
      comment:
        "The entry of an invoice payment for accounting: bank against the receivable,\nthe other way round for a refund.",
      body: `  select jsonb_build_object(
    'organizationId', inv.${i("tenant")},
    'entryDate', (y.${tx("effectiveAt")} at time zone 'UTC')::date,
    'currency', inv.${i("currency")},
    'reference', coalesce(y.${tx("metadata")} ->> 'reference', inv.${i("identifier")}),
    'memo', 'Payment of ' || coalesce(inv.${i("identifier")}, inv.${i("title")}),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', ${party("inv")})))
  )
  from ${ledger.table("transactions")} y
  join ${invoices} inv on inv.${i("id")}::text = y.${tx("metadata")} ->> 'invoiceId'
  cross join lateral (
    select sum(e.${le("amount")}) as amount from ${ledger.table("entries")} e
    join ${ledger.table("accounts")} a on a.${la("id")} = e.${le("account")}
    where e.${le("transaction")} = y.${tx("id")} and a.${la("code")} = 'invoices:cash:' || inv.${i("currency")}
  ) p
  where y.${tx("id")}::text = source_id and y.${tx("referenceType")} = 'invoices' and p.amount <> 0`,
    },
  ];
}
