import type { BlockSqlContext } from "../context.ts";
import type { QuoteNames } from "./quotes-functions.ts";

import { sqlString } from "../../core/template.ts";
import { lineCopyColumns } from "../line-items-sql.ts";
import { extraFieldsJson, fail, userGrant } from "../shared.ts";
import { quoteKit, quoteParty, quotePartyType } from "./quotes-kit.ts";

/** The quote columns that make a quote one of several variants. */
const VARIANT_COLUMNS: readonly string[] = [
  "variantOf",
  "variantLabel",
  "isSelected",
];

/** Whether the quotes table keeps variants. */
export function hasVariants(ctx: BlockSqlContext): boolean {
  return VARIANT_COLUMNS.every((column) => ctx.has("quotes", column));
}

/**
 * PL/pgSQL that refuses a quote (`row`, a `quotes` record) that belongs to a
 * group of variants and isn't the selected one, so only the chosen scope moves
 * on to an order or an invoice. Empty without the variant columns.
 */
export function quoteVariantGuard(
  ctx: BlockSqlContext,
  row: string,
  table: string,
): string {
  if (!hasVariants(ctx)) {
    return "";
  }

  const q = (column: string): string => ctx.col("quotes", column);

  return `
  if (${row}.${q("variantOf")} is not null or exists (select 1 from ${table} s where s.${q("variantOf")} = ${row}.${q("id")}))
    and not ${row}.${q("isSelected")} then
    ${fail("QUOTE_VARIANT_NOT_SELECTED", "this quote is one of several variants; select a variant first", "55000")}
  end if;`;
}

/**
 * `create_quote_variant`, `select_quote_variant` and `list_quote_variants`:
 * alternative scopes or prices of one quote as separate quotes that share a
 * root (`variant_of`), one of them marked selected.
 */
export function quoteVariantFunctions(
  ctx: BlockSqlContext,
  n: QuoteNames,
): string {
  if (!hasVariants(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const k = quoteKit(ctx, n);
  const { q, l, has, row, editable, st } = k;
  const orders = ctx.installed("orders") ? ctx.of("orders") : undefined;
  const invoices = ctx.installed("invoices") ? ctx.of("invoices") : undefined;
  const id = sqlString(ctx.colName("quotes", "id"));
  const company = quoteParty(ctx, "company");
  const contact = quoteParty(ctx, "contact");

  const party = (kind: "company" | "contact"): string =>
    (kind === "company" ? company : contact) === undefined
      ? "null"
      : `case when v_src.${q(`${kind}Id`)} is null then null else jsonb_build_object('type', ${quotePartyType(ctx, kind, "v_src.")}, 'id', v_src.${q(`${kind}Id`)}) end`;

  const copied = [
    "terms",
    "note",
    "pricesIncludeTax",
    "discountBps",
    "discountAmount",
    "depositBps",
    "depositAmount",
    "depositRequired",
  ]
    .filter(has)
    .map(
      (column) =>
        `, ${sqlString(column)}, v_src.${q(column)}${["discountAmount", "depositAmount"].includes(column) ? "::text" : ""}`,
    )
    .join("");

  const lineColumns = lineCopyColumns(ctx, "lines");
  const extras = n.lineExtras;

  const columnList = [
    ...lineColumns.map(l),
    ...extras.map((extra) => extra.ident),
  ].join(", ");

  const valueList = [
    ...lineColumns.map((column) =>
      column === "parent" ? "v_id" : `x.${l(column)}`,
    ),
    ...extras.map((extra) => `x.${extra.ident}`),
  ].join(", ");

  const allowed =
    [
      ...(orders === undefined ? [] : ["'order'"]),
      ...(invoices === undefined ? [] : ["'invoice'"]),
    ].join(", ") || "''";

  const readable = `(${n.service} or ${ctx.scope.can(`v_src.${q("tenant")}`, n.read)})`;

  const group = (root: string): string =>
    `(x.${q("id")} = ${root} or x.${q("variantOf")} = ${root})`;

  const listJson = (
    root: string,
  ): string => `(select coalesce(jsonb_agg(jsonb_build_object(
      'id', x.${q("id")}, 'identifier', x.${q("identifier")}, 'variantLabel', x.${q("variantLabel")},
      'isSelected', x.${q("isSelected")}, 'status', ${ctx.label("quotes", "status", `x.${q("status")}`)},
      'currency', x.${q("currency")}, 'total', x.${q("total")}::text, 'isRoot', x.${q("variantOf")} is null)
      order by (x.${q("variantOf")} is not null), x.${q("number")}), '[]'::jsonb)
    from ${t("quotes")} x where ${group(root)})`;

  const forwardOrder =
    orders === undefined
      ? ""
      : `
  if v_forward = 'order' then
    v_order := ${orders.fn("order_from_quote")}(v_row.${q("id")}, select_quote_variant.options -> 'attrs');
  end if;`;

  const forwardInvoice =
    invoices === undefined
      ? ""
      : `
  if v_forward = 'invoice' then
    v_invoice := ${invoices.fn("invoice_from_quote")}(v_row.${q("id")}, (select_quote_variant.options ->> 'depositBps')::integer);
  end if;`;

  return `
-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function ${fn("create_quote_variant")}(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src ${t("quotes")};
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  select * into v_src from ${t("quotes")} x where x.${q("id")} = create_quote_variant.quote and ${editable("x")};
  if v_src.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  if v_label is null or length(v_label) > 100 then
    ${fail("QUOTE_VARIANT_INVALID", "a variant needs a label of up to 100 characters", "22023")}
  end if;
  v_root := coalesce(v_src.${q("variantOf")}, v_src.${q("id")});
  if exists (select 1 from ${t("quotes")} x where ${group("v_root")} and lower(x.${q("variantLabel")}) = lower(v_label)) then
    ${fail("QUOTE_VARIANT_LABEL_TAKEN", "another variant of this quote has that label", "23505")}
  end if;
  v_made := ${fn("create_quote")}(v_src.${q("tenant")}, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src.${q("title")}, 'currency', v_src.${q("currency")}, 'validUntil', v_src.${q("validUntil")},
    'company', ${party("company")}, 'contact', ${party("contact")}${copied}${extraFieldsJson("v_src", n.extras)})) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> ${id})::uuid;
  insert into ${t("lines")} (${columnList})
  select ${valueList} from ${t("lines")} x where x.${l("parent")} = v_src.${q("id")};
  update ${t("quotes")} x set ${q("variantLabel")} = coalesce(x.${q("variantLabel")}, 'Original')
  where x.${q("id")} = v_root;
  update ${t("quotes")} x set ${q("variantOf")} = v_root, ${q("variantLabel")} = v_label, ${q("isSelected")} = false
  where x.${q("id")} = v_id;
  return (select ${row("x")} from ${t("quotes")} x where x.${q("id")} = v_id);
end;
$$;
${userGrant(`${fn("create_quote_variant")}(uuid, text, jsonb)`)}

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function ${fn("list_quote_variants")}(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src ${t("quotes")};
begin
  select * into v_src from ${t("quotes")} x where x.${q("id")} = list_quote_variants.quote;
  if v_src.${q("id")} is null or not ${readable} then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can read", "P0002")}
  end if;
  return ${listJson(`coalesce(v_src.${q("variantOf")}, v_src.${q("id")})`)};
end;
$$;
${userGrant(`${fn("list_quote_variants")}(uuid)`)}

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function ${fn("select_quote_variant")}(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("quotes")};
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  select * into v_row from ${t("quotes")} x where x.${q("id")} = select_quote_variant.quote and ${editable("x")} for update;
  if v_row.${q("id")} is null then
    ${fail("QUOTE_NOT_FOUND", "no such quote you can edit", "P0002")}
  end if;
  v_root := coalesce(v_row.${q("variantOf")}, v_row.${q("id")});
  if v_row.${q("variantOf")} is null and not exists (select 1 from ${t("quotes")} x where x.${q("variantOf")} = v_row.${q("id")}) then
    ${fail("QUOTE_VARIANT_INVALID", "this quote has no variants", "22023")}
  end if;
  if ${st(`v_row.${q("status")}`, ["withdrawn", "rejected", "expired"])} then
    ${fail("QUOTE_VARIANT_NOT_SELECTABLE", "a withdrawn, rejected or expired variant can't be selected", "55000")}
  end if;
  if v_forward is not null and v_forward not in (${allowed}) then
    ${fail("QUOTE_VARIANT_INVALID", "forward is order or invoice", "22023")}
  end if;
  perform 1 from ${t("quotes")} x where ${group("v_root")} for update;
  update ${t("quotes")} x set ${q("isSelected")} = (x.${q("id")} = v_row.${q("id")}), ${q("updatedAt")} = now()
  where ${group("v_root")} and x.${q("isSelected")} is distinct from (x.${q("id")} = v_row.${q("id")});${forwardOrder}${forwardInvoice}${
    orders === undefined || invoices === undefined
      ? `
  if v_forward is not null and v_order is null and v_invoice is null then
    ${fail("QUOTE_VARIANT_INVALID", "the organization has no block to copy the variant forward to", "22023")}
  end if;`
      : ""
  }
  select * into v_row from ${t("quotes")} x where x.${q("id")} = v_row.${q("id")};
  return jsonb_build_object('quote', ${row("v_row")}, 'variants', ${listJson("v_root")}, 'order', v_order, 'invoice', v_invoice);
end;
$$;
${userGrant(`${fn("select_quote_variant")}(uuid, jsonb)`)}
`;
}
