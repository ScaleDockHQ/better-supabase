import type { BlockSqlContext } from "../context.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlString } from "../../core/template.ts";
import { tryColumnType } from "../column-type.ts";
import {
  countedLine,
  declared,
  lineAmount,
  lineColumn,
  lineDiscount,
  lineExtraColumns,
} from "../line-items-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { quoteParty, quotePartyType } from "./quotes-kit.ts";
import { quoteVariantGuard } from "./quotes-variants.ts";

/** The sales line columns a quote's lines hand to the invoice. */
const SALES_KEYS: readonly string[] = [
  "discountAmount",
  "taxCodeId",
  "unitCost",
  "costSource",
  "locationId",
  "binId",
  "billingParty",
  "billingPartyId",
  "billingAccountId",
];

/** The invoice helpers `invoice_from_quote` shares with the other functions. */
export interface InvoiceKit {
  readonly has: (logical: string) => boolean;
  readonly row: (alias: string) => string;
  readonly refuse: (
    supported: boolean,
    given: string,
    thing: string,
    what: string,
  ) => string;
  readonly st: (
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
  readonly kd: (
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
  readonly origin: "pair" | "fixed" | undefined;
  readonly company: boolean;
  readonly contact: boolean;
}

/**
 * `invoice_from_quote`: a deposit invoice for a share or an amount of an
 * accepted quote, or the final invoice less the deposits issued. Empty without
 * the quotes module.
 */
export function invoiceFromQuote(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  k: InvoiceKit,
): string {
  const quotes = ctx.installed("quotes") ? ctx.of("quotes") : undefined;

  if (quotes === undefined) {
    return "";
  }

  const { fn, t } = n;
  const i = (column: string): string => n.c("invoices", column);
  const { has, row, refuse, st, kd, origin, company, contact } = k;
  const q = (column: string): string => quotes.col("quotes", column);
  const ql = (column: string): string => quotes.col("lines", column);
  const kind = n.depositKind;
  const bpsDeposits = kind !== undefined || has("depositBps");
  const amountDeposits = kind !== undefined || has("depositAmount");

  // How a deposit invoice is told from the final one: its kind
  // (options.depositKind), else its deposit columns.
  const markers = ["depositBps", "depositAmount"].filter(has);

  const deposits = kind !== undefined || markers.length > 0;

  const isDeposit = (alias: string): string =>
    kind === undefined
      ? markers
          .map((column) => `${alias}.${i(column)} is not null`)
          .join(" or ")
      : `${alias}.${i("kind")}::text = ${sqlString(kind)}`;

  const notDeposit = (alias: string): string =>
    kind === undefined
      ? markers.map((column) => `${alias}.${i(column)} is null and `).join("")
      : `${alias}.${i("kind")}::text <> ${sqlString(kind)} and `;

  const originIs = (alias: string): string =>
    `${origin === "pair" ? `${alias}.${i("originType")} = 'quote' and ` : ""}${alias}.${i("originId")}::text = v_quote.${q("id")}::text`;

  const inclusive =
    has("pricesIncludeTax") && quotes.has("quotes", "pricesIncludeTax")
      ? `v_quote.${q("pricesIncludeTax")}`
      : "false";

  // What a deposit is a share of: the amount the prices are given in.
  const base = (alias: string): string =>
    `case when ${inclusive} then ${alias}.${q("total")} else ${alias}.${q("subtotal")} end`;

  const blendedRate = `case when v_quote.${q("subtotal")} = 0 then 0 else round(v_quote.${q("taxTotal")} * 10000.0 / v_quote.${q("subtotal")})::integer end`;

  const taxLines = quotes.hasTable("taxLines")
    ? (column: string): string => quotes.col("taxLines", column)
    : undefined;

  // The line and header extra columns both tables have, by name.
  const invoiceLineExtras = new Set(n.lineExtras.map((extra) => extra.name));

  const lineFields = lineExtraColumns(quotes).filter((extra) =>
    invoiceLineExtras.has(extra.name),
  );

  const copiedField = (name: string, ident: string): string => {
    const map = Object.entries(n.quoteLineValues[name] ?? {});

    const text =
      map.length === 0
        ? `x.${ident}::text`
        : `case x.${ident}::text ${map.map(([from, to]) => `when ${sqlString(from)} then ${sqlString(to)}`).join(" ")} else x.${ident}::text end`;

    const value = map.length === 0 ? `x.${ident}` : text;

    return `case when x.${ident} is null or ${tryColumnType(t("lines"), name, text)} is not null then jsonb_build_object(${sqlString(name)}, ${value}) else '{}'::jsonb end`;
  };

  const lineFieldsSql =
    lineFields.length === 0
      ? ""
      : `, 'fields', ${lineFields.map((extra) => copiedField(extra.name, extra.ident)).join(" || ")}`;

  const depositFields =
    Object.keys(n.depositLine.fields).length === 0
      ? ""
      : `, 'fields', ${sqlString(JSON.stringify(n.depositLine.fields))}::jsonb`;

  const depositDescription = `coalesce(nullif(trim(invoice_from_quote.deposit_description), ''), ${sqlString(n.depositLine.description)})`;

  const product = declared(quotes, "lines", "productType")
    ? `case when ${lineColumn(quotes, "lines", "x", "productType")} is null then null else jsonb_build_object('type', ${lineColumn(quotes, "lines", "x", "productType")}, 'id', ${lineColumn(quotes, "lines", "x", "productId")}) end`
    : declared(quotes, "lines", "productId") &&
        !declared(ctx, "lines", "productType")
      ? `case when x.${ql("productId")} is null then null else jsonb_build_object('type', null, 'id', x.${ql("productId")}::text) end`
      : "null";

  const dl = (column: string): string => n.c("lines", column);
  const depositList = lineAmount(ctx, "lines", "dl");

  const depositNet = `${depositList} - ${lineDiscount(
    ctx,
    "lines",
    "dl",
    depositList,
    ctx.has("lines", "discountBps")
      ? lineColumn(ctx, "lines", "dl", "discountBps")
      : null,
  )}`;

  const invoiceExtras = new Set(n.extras.map((extra) => extra.name));

  const headerFields = quotes
    .extraColumns("quotes", ["lines", "token", "fields"])
    .filter((extra) => invoiceExtras.has(extra.name));

  const headerFieldsSql =
    headerFields.length === 0
      ? ""
      : ` || jsonb_build_object(${headerFields.map((extra) => `${sqlString(extra.name)}, v_quote.${extra.ident}`).join(", ")})`;

  // The document discount as one line per tax rate, its share of
  // each, so the invoice counts the tax the quote counted.
  const discountLines =
    taxLines !== undefined && quotes.has("taxLines", "discount")
      ? `
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', 'Discount', 'quantity', 1, 'unitAmount', (-x.${taxLines("discount")})::text,
        'taxRateBps', x.${taxLines("taxRateBps")}, 'taxCode', ${quotes.has("taxLines", "taxCode") ? `x.${taxLines("taxCode")}` : "null"}) order by x.${taxLines("taxRateBps")}), '[]'::jsonb)
      into v_lines
    from ${quotes.table("taxLines")} x where x.${taxLines("parent")} = v_quote.${q("id")} and x.${taxLines("discount")} <> 0;`
      : "";

  // The quote's document discount kept on the invoice's header, when
  // the invoices table has a column for each part the quote has.
  const quoteDiscounts = ["discountBps", "discountAmount"].filter((column) =>
    quotes.has("quotes", column),
  );

  const headerDiscount = quoteDiscounts.length > 0 && quoteDiscounts.every(has);

  const live = (alias: string): string =>
    `${has("archivedAt") ? `${alias}.${i("archivedAt")} is null and ` : ""}not (${alias}.${i("total")} > 0 and ${alias}.${i("creditedTotal")} >= ${alias}.${i("total")})`;

  const issuedDeposits = (alias: string): string =>
    `${originIs(alias)} and ${isDeposit(alias) === "" ? "false" : `(${isDeposit(alias)})`} and ${st(`${alias}.${i("status")}`, ["draft", "void"], true)} and ${live(alias)}`;

  const depositInclusive = has("pricesIncludeTax")
    ? `d.${i("pricesIncludeTax")}`
    : "false";

  const deducted = has("pricesIncludeTax")
    ? `case when ${depositInclusive} = ${inclusive} then y.amount when ${depositInclusive} then round(y.amount * 10000.0 / (10000 + y.rate))::bigint else round(y.amount * (10000 + y.rate) / 10000.0)::bigint end`
    : "y.amount";

  // With the block's totals and deposits to deduct, a header discount
  // would also take its share off the deductions, so the discount
  // stays as lines then.
  const discount = headerDiscount
    ? `
    if ${n.appTotals || !deposits ? "true" : `not exists (select 1 from ${t("invoices")} d where ${issuedDeposits("d")})`} then
      v_header := jsonb_build_object(${quoteDiscounts.map((column) => `${sqlString(column)}, v_quote.${q(column)}${column === "discountAmount" ? "::text" : ""}`).join(", ")});
    else${discountLines === "" ? "\n      null;" : discountLines.replaceAll("\n", "\n  ")}
    end if;`
    : discountLines;

  const party = (kind: "company" | "contact"): string =>
    (kind === "company" ? company : contact) &&
    quoteParty(quotes, kind) !== undefined
      ? `case when v_quote.${q(`${kind}Id`)} is null then null else jsonb_build_object('type', ${quotePartyType(quotes, kind, "v_quote.")}, 'id', v_quote.${q(`${kind}Id`)}) end`
      : "null";

  const create = `${fn("create_invoice")}(v_quote.${q("tenant")}, jsonb_build_object(
    'title', v_quote.${q("title")}, 'currency', v_quote.${q("currency")}, 'depositBps', ${has("depositBps") ? "invoice_from_quote.deposit_bps" : "null"},${has("depositAmount") ? " 'depositAmount', invoice_from_quote.deposit_amount::text," : ""}${has("pricesIncludeTax") ? ` 'pricesIncludeTax', ${inclusive},` : ""}
    'company', ${party("company")},
    'contact', ${party("contact")},
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote.${q("id")}::text))${headerDiscount ? " || v_header" : ""}${headerFieldsSql}, v_lines)`;

  const amountLine = amountDeposits
    ? `
  elsif invoice_from_quote.deposit_amount is not null then
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit of ' || v_quote.${q("identifier")},
      'quantity', 1,
      'unitAmount', (case when ${inclusive} or v_quote.${q("total")} = 0 then invoice_from_quote.deposit_amount
        else round(invoice_from_quote.deposit_amount::numeric * v_quote.${q("subtotal")} / v_quote.${q("total")})::bigint end)::text,
      'taxRateBps', ${blendedRate}${depositFields}));`
    : "";

  const body = (): string => `
  if invoice_from_quote.deposit_bps is null${amountDeposits ? " and invoice_from_quote.deposit_amount is null" : ""} then
    select * into v_row from ${t("invoices")} x
    where ${originIs("x")}
      and ${notDeposit("x")}${st(`x.${i("status")}`, ["void"], true)} and ${kd(`x.${i("kind")}`, ["invoice"])} and ${live("x")}
    limit 1;
    if v_row.${i("id")} is not null then
      return ${row("v_row")};
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('description', x.${ql("description")}, 'quantity', x.${ql("quantity")}${declared(quotes, "lines", "periods") ? ` * coalesce(x.${ql("periods")}, 1)` : ""}, 'unitAmount', x.${ql("unitAmount")}::text,
        'discountBps', ${lineColumn(quotes, "lines", "x", "discountBps")}, 'taxRateBps', ${lineColumn(quotes, "lines", "x", "taxRateBps")}, 'taxCode', ${lineColumn(quotes, "lines", "x", "taxCode")},
        ${SALES_KEYS.map((key) => `${sqlString(key)}, ${lineColumn(quotes, "lines", "x", key)}`).join(", ")},
        'product', ${product}${lineFieldsSql}
      ) order by x.${ql("position")}), '[]'::jsonb) into v_lines
    from ${quotes.table("lines")} x where x.${ql("parent")} = v_quote.${q("id")} and ${countedLine(quotes, "lines", "x")};${discount}${
      deposits
        ? `
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', replace(${depositDescription}, '{identifier}', d.${i("identifier")}), 'quantity', 1, 'unitAmount', (-(${deducted}))::text,
        'taxRateBps', y.rate${depositFields}) order by d.${i("identifier")}, y.rate), '[]'::jsonb)
      into v_lines
    from ${t("invoices")} d
    cross join lateral (
      select ${lineColumn(ctx, "lines", "dl", "taxRateBps")} as rate, sum(${depositNet})::bigint as amount
      from ${t("lines")} dl where dl.${dl("parent")} = d.${i("id")} and ${countedLine(ctx, "lines", "dl")}
      group by 1
    ) y
    where ${issuedDeposits("d")} and y.amount <> 0;`
        : ""
    }${amountLine}
  else
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit ' || (invoice_from_quote.deposit_bps / 100.0)::text || '% of ' || v_quote.${q("identifier")},
      'quantity', 1,
      'unitAmount', round(${base("v_quote")}::numeric * invoice_from_quote.deposit_bps / 10000)::bigint::text,
      'taxRateBps', ${blendedRate}${depositFields}));
  end if;
  v_row := null;${
    kind === undefined
      ? `
  return ${create};`
      : `
  v_made := ${create};
  if invoice_from_quote.deposit_bps is not null or invoice_from_quote.deposit_amount is not null then
    update ${t("invoices")} x set ${i("kind")} = ${ctx.cast("invoices", "kind", sqlString(kind))} where x.${i("id")} = (v_made ->> 'id')::uuid;
    return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = (v_made ->> 'id')::uuid);
  end if;
  return v_made;`
  }`;

  return `
-- An invoice from an accepted quote. With deposit_bps (2000 for 20%) it is
-- a deposit invoice for that share of the quote${amountDeposits ? ", and with deposit_amount\n-- one for that amount, tax included" : ""}; without, the full invoice,
-- which subtracts the deposits already issued, one line per deposit and tax
-- rate described by deposit_description ({identifier} is the deposit's), and
-- is made once per quote.${headerDiscount ? "\n-- The quote's document discount stays on the invoice's header." : ""}
drop function if exists ${fn("invoice_from_quote")}(uuid, integer);
drop function if exists ${fn("invoice_from_quote")}(uuid, integer, bigint);
create or replace function ${fn("invoice_from_quote")}(quote uuid, deposit_bps integer, deposit_amount bigint default null, deposit_description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote ${quotes.table("quotes")};
  v_row ${t("invoices")};
  v_lines jsonb;${headerDiscount ? "\n  v_header jsonb := '{}'::jsonb;" : ""}${kind === undefined ? "" : "\n  v_made jsonb;"}
begin
  select * into v_quote from ${quotes.table("quotes")} x where x.${q("id")} = invoice_from_quote.quote;
  if v_quote.${q("id")} is null or not (${n.service} or ${ctx.scope.can(`v_quote.${q("tenant")}`, n.create)}) then
    ${fail("INVOICE_ORIGIN_NOT_FOUND", "no such quote you can invoice", "P0002")}
  end if;
  if ${quotes.is("quotes", "status", `v_quote.${q("status")}`, ["accepted"], true)} then
    ${fail("INVOICE_QUOTE_NOT_ACCEPTED", "only an accepted quote is invoiced", "55000")}
  end if;${quoteVariantGuard(quotes, "v_quote", quotes.table("quotes"))}
  if invoice_from_quote.deposit_bps is not null and (invoice_from_quote.deposit_bps <= 0 or invoice_from_quote.deposit_bps >= 10000) then
    ${fail("INVOICE_DEPOSIT_INVALID", "a deposit is between 0 and 100 percent", "22023")}
  end if;
  if invoice_from_quote.deposit_bps is not null and invoice_from_quote.deposit_amount is not null then
    ${fail("INVOICE_DEPOSIT_INVALID", "a deposit is a share (deposit_bps) or an amount (deposit_amount), not both", "22023")}
  end if;
  if invoice_from_quote.deposit_amount is not null and (invoice_from_quote.deposit_amount <= 0 or invoice_from_quote.deposit_amount > v_quote.${q("total")}) then
    ${fail("INVOICE_DEPOSIT_INVALID", "a deposit amount is positive and at most the quote's total", "22023")}
  end if;${refuse(bpsDeposits, "invoice_from_quote.deposit_bps", "DEPOSIT", "deposit column")}${refuse(amountDeposits, "invoice_from_quote.deposit_amount", "DEPOSIT", "deposit amount column")}${
    origin === undefined
      ? `
  ${fail("INVOICE_ORIGIN_UNSUPPORTED", "this invoices table has no origin columns, so a quote can't be invoiced once", "22023")}`
      : body()
  }
end;
$$;
${userGrant(`${fn("invoice_from_quote")}(uuid, integer, bigint, text)`)}
`;
}
