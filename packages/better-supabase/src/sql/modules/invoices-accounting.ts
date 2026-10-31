import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

import { countedLine, lineAmount, lineColumn } from "../line-items-sql.ts";
import { partyPaymentSource } from "./invoices-collections.ts";
import { invoiceParty } from "./invoices-functions.ts";
import { invoiceCashCode } from "./invoices-ledger.ts";

/**
 * What invoices books in accounting: an issued invoice or credit note in the
 * sales journal (the receivable against revenue and tax per rate), each payment
 * or refund in the bank journal (bank against the receivable), each charge in
 * the sales journal (the receivable against revenue) and a written off invoice
 * in the general journal (the open balance against expenses). A purchase bill
 * books in the purchase journal: the supplier's payable against expense,
 * carrying the bill's dimensions, and deductible tax. With inventory, a product
 * line on a bill of a purchase order clears the payable its receipt booked
 * instead of an expense, so received stock isn't counted twice.
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

  const purchase = ctx.has("invoices", "direction");
  const cashCode = (alias: string): string => invoiceCashCode(ctx, alias);

  const direction = (alias: string): string =>
    purchase ? `${alias}.${i("direction")} = 'purchase'` : "false";

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

  const chargeTable = ctx.hasTable("charges");
  const ch = (column: string): string => ctx.col("charges", column);

  const charged = chargeTable
    ? `coalesce((select sum(y.${ch("amount")}) from ${ctx.table("charges")} y where y.${ch("invoice")} = inv.${i("id")}), 0)`
    : "0";

  const chargeSources = (): readonly AccountingSource[] =>
    chargeTable
      ? [
          {
            source: "invoice_charge",
            journal: "sales",
            fn: "accounting_invoice_charge_lines",
            comment:
              "The entry of an invoice charge for accounting: the receivable against\nrevenue, with no tax.",
            body: `  select jsonb_build_object(
    'organizationId', inv.${i("tenant")},
    'entryDate', ${ctx.has("charges", "createdAt") ? `(c.${ch("createdAt")} at time zone 'UTC')::date` : "current_date"},
    'currency', inv.${i("currency")},
    'reference', inv.${i("identifier")},
    'memo', 'Charge on ' || coalesce(inv.${i("identifier")}, inv.${i("title")}),
    'lines', jsonb_build_array(
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', c.${ch("amount")}::text, 'partyId', ${party("inv")})),
      jsonb_strip_nulls(jsonb_build_object('role', 'revenue', 'credit', c.${ch("amount")}::text, 'description', ${ctx.has("charges", "description") ? `c.${ch("description")}` : "null"})))
  )
  from ${ctx.table("charges")} c
  join ${invoices} inv on inv.${i("id")} = c.${ch("invoice")}
  where c.${ch("id")}::text = source_id and c.${ch("amount")} <> 0 and not (${direction("inv")})`,
          },
        ]
      : [];

  const taxLine = (
    side: string,
    amountSql: string,
    entry = "credit",
    extra = "'partyId', inv.party",
  ): string =>
    `jsonb_strip_nulls(jsonb_build_object('role', ${side}, '${entry}', (inv.sign * ${amountSql})::text, 'taxCode', s.code, 'taxRateBps', s.rate, ${extra}))`;

  // Whether a line clears the payable a stock receipt booked.
  const clearing =
    purchase && ctx.installed("inventory")
      ? `(inv.purchase and inv.ordered and ${lineColumn(ctx, "lines", "l", "productId")} is not null)`
      : "false";

  const salesLines = `jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', (inv.sign * inv.total)::text, 'partyId', inv.party)))
      || coalesce((select jsonb_agg(${taxLine("'revenue'", "s.net")}) from shares s where s.net <> 0), '[]'::jsonb)
      || coalesce((select jsonb_agg(${taxLine("'tax_payable'", "s.tax")}) from shares s where s.tax <> 0), '[]'::jsonb)`;

  const purchaseLines = `jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('role', 'payable', 'credit', (inv.sign * inv.total)::text, 'partyId', inv.party)))
      || coalesce((select jsonb_agg(${taxLine("case when s.clearing then 'payable' else 'expense' end", "s.net", "debit", "'dimensions', case when not s.clearing then inv.dimensions end")}) from shares s where s.net <> 0), '[]'::jsonb)
      || coalesce((select jsonb_agg(${taxLine("'tax_receivable'", "s.tax", "debit")}) from shares s where s.tax <> 0), '[]'::jsonb)`;

  return [
    {
      source: "invoice",
      journal: "sales",
      fn: "accounting_invoice_lines",
      comment:
        "The entry of an issued invoice or credit note for accounting: the receivable\nagainst revenue and tax per rate, mirrored for a credit note. A purchase bill\ncredits the supplier's payable against expense and deductible tax.",
      body: `  with inv as (
    select x.${i("id")} as id, x.${i("tenant")} as tenant, x.${i("issuedOn")} as issued_on, x.${i("currency")} as currency,
      x.${i("identifier")} as identifier, x.${i("title")} as title, x.${i("subtotal")} as subtotal, x.${i("taxTotal")} as tax_total,
      x.${i("total")} as total, ${party("x")} as party, ${inclusive} as inclusive,
      case when ${ctx.is("invoices", "kind", `x.${i("kind")}`, ["credit_note"])} then -1 else 1 end as sign${
        purchase
          ? `,
      ${direction("x")} as purchase, ${ctx.has("invoices", "dimensions") ? `nullif(x.${i("dimensions")}, '{}'::jsonb)` : "null::jsonb"} as dimensions,
      ${ctx.installed("inventory") && ctx.has("invoices", "purchaseOrder") ? `x.${i("purchaseOrder")} is not null` : "false"} as ordered`
          : ""
      }
    from ${invoices} x
    where x.${i("id")}::text = source_id and ${ctx.is("invoices", "status", `x.${i("status")}`, ["draft", "void"], true)}
  ),
  groups as (
    select ${rate} as rate, ${code} as code, ${clearing} as clearing, sum(${amount} - ${discount}) as net,
      sum((${amount} - ${discount}) * ${rate} / case when inv.inclusive then 10000.0 + ${rate} else 10000.0 end) as tax
    from ${lines} l cross join inv
    where l.${l("parent")} = inv.id and ${countedLine(ctx, "lines", "l")}
    group by 1, 2, 3
  ),
  shares as (
    select g.rate, g.code, g.clearing,
      ${share("inv.subtotal", "net")} as net,
      ${share("inv.tax_total", "tax")} as tax
    from groups g cross join inv
    window w as (order by g.rate, g.code nulls first, g.clearing rows between unbounded preceding and current row)
  )
  select jsonb_build_object(
    'organizationId', inv.tenant,
    'entryDate', inv.issued_on,
    'currency', inv.currency,
    'reference', inv.identifier,
    'memo', inv.title,
    'lines', ${purchase ? `case when inv.purchase then ${purchaseLines} else ${salesLines} end` : salesLines}
  )${purchase ? " || case when inv.purchase then jsonb_build_object('journal', 'purchase') else '{}'::jsonb end" : ""}
  from inv`,
    },
    {
      source: "invoice_payment",
      journal: "bank",
      fn: "accounting_invoice_payment_lines",
      comment:
        "The entry of an invoice payment for accounting: bank against the receivable,\nthe other way round for a refund. Paying a purchase bill debits the payable\nand credits bank.",
      body: `  select jsonb_build_object(
    'organizationId', inv.${i("tenant")},
    'entryDate', (y.${tx("effectiveAt")} at time zone 'UTC')::date,
    'currency', inv.${i("currency")},
    'reference', coalesce(y.${tx("metadata")} ->> 'reference', inv.${i("identifier")}),
    'memo', 'Payment of ' || coalesce(inv.${i("identifier")}, inv.${i("title")}),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', ${purchase ? `case when ${direction("inv")} then 'credit' else 'debit' end` : "'debit'"}, p.amount::text),
      jsonb_strip_nulls(jsonb_build_object('role', ${purchase ? `case when ${direction("inv")} then 'payable' else 'receivable' end` : "'receivable'"}, ${purchase ? `case when ${direction("inv")} then 'debit' else 'credit' end` : "'credit'"}, p.amount::text, 'partyId', ${party("inv")})))
  )
  from ${ledger.table("transactions")} y
  join ${invoices} inv on inv.${i("id")}::text = y.${tx("metadata")} ->> 'invoiceId'
  cross join lateral (
    select sum(e.${le("amount")}) as amount from ${ledger.table("entries")} e
    join ${ledger.table("accounts")} a on a.${la("id")} = e.${le("account")}
    where e.${le("transaction")} = y.${tx("id")} and a.${la("code")} = ${cashCode("inv")}
  ) p
  where y.${tx("id")}::text = source_id and y.${tx("referenceType")} = 'invoices' and p.amount <> 0`,
    },
    ...chargeSources(),
    {
      source: "invoice_write_off",
      journal: "general",
      fn: "accounting_invoice_write_off_lines",
      comment:
        "The entry of a written-off invoice for accounting: the open balance against\nexpenses, the receivable cleared.",
      body: `  select jsonb_build_object(
    'organizationId', inv.${i("tenant")},
    'currency', inv.${i("currency")},
    'reference', inv.${i("identifier")},
    'memo', 'Write-off of ' || coalesce(inv.${i("identifier")}, inv.${i("title")}),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'expense', 'debit', b.balance::text),
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', b.balance::text, 'partyId', ${party("inv")})))
  )
  from ${invoices} inv
  cross join lateral (select inv.${i("total")} + ${charged} - inv.${i("creditedTotal")} - inv.${i("paidTotal")} as balance) b
  where inv.${i("id")}::text = source_id and b.balance > 0 and not (${direction("inv")})`,
    },
    ...partyPaymentSource(ctx),
  ];
}
