import type { BlockSqlContext, ExtraColumn } from "../context.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  bookSource,
  booksAccounting,
  unbookSource,
} from "../accounting-sources-sql.ts";
import { asColumnType } from "../column-type.ts";
import {
  lineColumn,
  lineCopyColumns,
  lineFieldsJson,
  lineItemsSql,
  TOTAL_COLUMNS,
} from "../line-items-sql.ts";
import { createdFromLink } from "../links.ts";
import { int8Text } from "../money-sql.ts";
import {
  assignNumberSql,
  hasLegalEntityColumn,
  scopeSql,
} from "../numbering-sql.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  transitionActorSql,
  transitionReasonSql,
  updateExtraColumns,
  userGrant,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { linked } from "./banking-sql.ts";
import { invoiceFromQuote } from "./invoices-from-quote.ts";
import { invoiceLedger, paymentKey } from "./invoices-ledger.ts";
import { invoiceCollectionsAndOpenItems } from "./invoices-open-items.ts";
import { invoicePurchase, PURCHASE_VALUES } from "./invoices-purchase.ts";
import { createTerms, discountIssue, lineMatrix } from "./invoices-terms.ts";
import { sequenceEntry } from "./numbering-entities.ts";

/**
 * Invoice columns a config opts into by naming them in
 * `blocks.invoices.columns.invoices`, so app tables made before them keep
 * working: an archive mark, a fixed deposit and a header discount.
 */
export const OPT_IN: readonly string[] = [
  "archivedAt",
  "depositAmount",
  "discountBps",
  "discountAmount",
];

/** Whether the invoices table has the opt-in column `logical`. */
/**
 * The call that gives an invoice's lines their tax codes and writes its
 * `invoice_tax_lines` for the issue date, when the tax block is installed.
 */
function taxIssue(ctx: BlockSqlContext, row: string, date: string): string {
  const tax = linked(ctx, "tax");

  return tax === undefined
    ? ""
    : `\n  perform ${tax.fn("issue_invoice_tax")}(${row}.${ctx.col("invoices", "id")}, ${date});`;
}

export function invoiceOptIn(ctx: BlockSqlContext, logical: string): boolean {
  return (
    typeof ctx.config.columns["invoices"]?.[logical] === "string" &&
    ctx.has("invoices", logical)
  );
}

type Party = "company" | "contact" | "origin";

/** `options.chargeExtraColumns`: app columns of the charges table. */
export const chargeExtraColumns = (
  ctx: BlockSqlContext,
): readonly ExtraColumn[] =>
  ctx.hasTable("charges")
    ? ctx.extraColumns("charges", ["fields"], "chargeExtraColumns")
    : [];

/**
 * How the invoices table holds a company, contact or origin: a type and an id
 * column (`pair`), only an id column of one fixed type, such as a foreign key
 * to the app's customers (`fixed`), or not at all.
 */
export function invoiceParty(
  ctx: BlockSqlContext,
  party: Party,
): "pair" | "fixed" | undefined {
  if (!ctx.has("invoices", `${party}Id`)) {
    return undefined;
  }

  return ctx.has("invoices", `${party}Type`) ? "pair" : "fixed";
}

/** The type a fixed party column holds: `options.company`, `contact` or a quote. */
function fixedType(n: InvoiceNames, party: Party): string {
  if (party === "origin") {
    return "quote";
  }

  return party === "company" ? n.company : n.contact;
}

/**
 * SQL for the type of a row's company, contact or origin (`alias` "" for the
 * bare column): its type column, or the fixed type when the id is set.
 */
export function partyTypeSql(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  party: Party,
  alias: string,
): string {
  const at = (logical: string): string =>
    `${alias === "" ? "" : `${alias}.`}${ctx.col("invoices", logical)}`;

  return invoiceParty(ctx, party) === "pair"
    ? at(`${party}Type`)
    : `(case when ${at(`${party}Id`)} is null then null else ${sqlString(fixedType(n, party))} end)`;
}

export function invoiceFunctions(
  ctx: BlockSqlContext,
  n: InvoiceNames,
): string {
  const { fn, t, c } = n;
  const i = (column: string): string => c("invoices", column);
  const l = (column: string): string => c("lines", column);
  const ledger = invoiceLedger(ctx);
  const company = invoiceParty(ctx, "company");
  const contact = invoiceParty(ctx, "contact");
  const origin = invoiceParty(ctx, "origin");

  const has = (logical: string): boolean =>
    OPT_IN.includes(logical)
      ? invoiceOptIn(ctx, logical)
      : ctx.has("invoices", logical);

  const charges = ctx.hasTable("charges");
  const ch = (column: string): string => c("charges", column);

  const physical = (logical: string): string =>
    ctx.colName("invoices", logical);

  const quoted = `${sqlIdent(ctx.tableName("invoices").schema)}.${sqlIdent(ctx.tableName("invoices").name)}`;

  // A party's id for an insert: text in a pair, the fixed column's own type
  // otherwise.
  const partyId = (party: Party, value: string): string =>
    invoiceParty(ctx, party) === "fixed"
      ? asColumnType(quoted, physical(`${party}Id`), value)
      : value;

  // ", <column>" for an insert's column list, when the column exists.
  const also = (logical: string): string =>
    has(logical) ? `, ${i(logical)}` : "";

  const early = discountIssue(ctx, "v_row", "v_issued_on");
  const terms = createTerms(ctx);

  // value when the column exists, for valueLines().
  const present = (logical: string, value: string): string | undefined =>
    has(logical) ? value : undefined;

  // The column's name, or "" when the app maps it to null, so present() can
  // take it without throwing.
  const copy = (logical: string): string => (has(logical) ? i(logical) : "");

  // The values of an insert, the present ones of each group on a line.
  const valueLines = (
    indent: string,
    ...groups: readonly (string | undefined)[][]
  ): string =>
    groups
      .map((group) => group.filter((value) => value !== undefined).join(", "))
      .filter((line) => line !== "")
      .join(`,\n${indent}`);

  // Refuses a value the app's invoices table has no column for.
  const refuse = (
    supported: boolean,
    given: string,
    thing: string,
    what: string,
  ): string =>
    supported
      ? ""
      : `
  if ${given} is not null then
    ${fail(`INVOICE_${thing}_UNSUPPORTED`, `this invoices table has no ${what}`, "22023")}
  end if;`;

  const can = (alias: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${i("tenant")}`, p.routed(alias, permission))})`;

  const st = (value: string, labels: readonly string[], negate = false) =>
    ctx.is("invoices", "status", value, labels, negate);

  const kd = (value: string, labels: readonly string[], negate = false) =>
    ctx.is("invoices", "kind", value, labels, negate);

  const charged = (alias: string): string =>
    charges
      ? `coalesce((select sum(y.${ch("amount")}) from ${t("charges")} y where y.${ch("invoice")} = ${alias}.${i("id")}), 0)`
      : "0";

  const balance = (alias: string): string =>
    `(${alias}.${i("total")}${charges ? ` + ${charged(alias)}` : ""} - ${alias}.${i("creditedTotal")} - ${alias}.${i("paidTotal")})`;

  const amounts = [
    "number",
    "paidTotal",
    "creditedTotal",
    ...Object.keys(TOTAL_COLUMNS),
    "depositAmount",
    "discountAmount",
    "discountAmountEarly",
  ].filter(has);

  const int8 = amounts.map(i);

  const int8Text8 = Object.fromEntries(
    amounts.map((logical) => [logical, (value: string) => `${value}::text`]),
  );

  // The keys a row reads back that the app's table has no column for.
  const missingKeys = (alias: string): string =>
    `${(["company", "contact", "origin"] as const)
      .filter((party) => invoiceParty(ctx, party) === "fixed")
      .map(
        (party) =>
          `, ${sqlString(`${party}_type`)}, ${partyTypeSql(ctx, n, party, alias)}`,
      )
      .join(
        "",
      )}${has("listTotal") ? "" : `, 'list_total', ${alias}.${i("subtotal")}::text`}${has("discountTotal") ? "" : ", 'discount_total', '0'"}`;

  const chargesJson = (alias: string): string =>
    charges
      ? `,
      'charged_total', ${charged(alias)}::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y.${ch("id")}, 'amount', y.${ch("amount")}::text, 'description', ${ctx.has("charges", "description") ? `y.${ch("description")}` : "null"}${ctx.has("charges", "createdAt") ? `, 'createdAt', y.${ch("createdAt")}` : ""}${extraFieldsJson("y", n.chargeExtras)})${ctx.has("charges", "createdAt") ? ` order by y.${ch("createdAt")}` : ""}) from ${t("charges")} y where y.${ch("invoice")} = ${alias}.${i("id")}), '[]'::jsonb)`
      : "";

  const row = (alias: string): string =>
    `${ctx.rowJson("invoices", alias, { as: int8Text8 })} || ${int8Text(alias, int8)} || jsonb_build_object(
      'balance', ${balance(alias)}::text${missingKeys(alias)}${chargesJson(alias)},
      'overdue', ${st(`${alias}.${i("status")}`, ["issued", "partially_paid"])} and ${alias}.${i("dueOn")} < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il.${l("description")}, 'quantity', il.${l("quantity")}, 'unitAmount', il.${l("unitAmount")}::text, 'discountBps', ${lineColumn(ctx, "lines", "il", "discountBps")}, 'taxRateBps', ${lineColumn(ctx, "lines", "il", "taxRateBps")}, 'taxCode', ${lineColumn(ctx, "lines", "il", "taxCode")}, 'taxCodeId', ${lineColumn(ctx, "lines", "il", "taxCodeId")}, 'unitCost', ${lineColumn(ctx, "lines", "il", "unitCost")}::text${ctx.has("lines", "dimensions") ? `, 'dimensions', il.${l("dimensions")}` : ""}${lineFieldsJson("il", n.lineExtras)}) order by il.${l("position")}) from ${t("lines")} il where il.${l("parent")} = ${alias}.${i("id")}), '[]'::jsonb),
      'payments', ${ledger.payments(alias)})`;

  const record = (
    type: string,
    alias: string,
    extra = "",
    audit = false,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${alias}.${i("tenant")}, 'invoiceId', ${alias}.${i("id")}, 'subjectType', 'invoice', 'subjectId', ${alias}.${i("id")}::text, 'identifier', ${alias}.${i("identifier")}${extra})`,
      subject: `'invoices/' || ${alias}.${i("id")}::text`,
      tenant: `${alias}.${i("tenant")}::text`,
      audit: audit
        ? {
            category: "billing",
            targetType: "invoice",
            recordId: `${alias}.${i("id")}::text`,
            targetLabel: `${alias}.${i("identifier")}`,
            summary: sqlString(type.replace("invoice.", "invoice ")),
          }
        : false,
    });

  const p = invoicePurchase(ctx, n, { i, balance, st, kd, record });

  const checkParty = (
    kind: "COMPANY" | "CONTACT",
    type: string,
    id: string,
    tenant: string,
  ): string => {
    const party = kind === "COMPANY" ? "company" : "contact";
    const mode = kind === "COMPANY" ? company : contact;

    if (mode === undefined) {
      return refuse(false, id, kind, `${party} columns`);
    }

    return `${
      mode === "fixed"
        ? `
  if ${id} is not null and ${type} is distinct from ${sqlString(fixedType(n, party))} then
    ${fail(`INVOICE_${kind}_UNSUPPORTED`, `this invoices table takes only a ${fixedType(n, party)} as the ${party}`, "22023")}
  end if;`
        : ""
    }
  if ${id} is not null and not ${subjectInTenant(ctx, type, id, tenant)} then
    ${fail(`INVOICE_${kind}_FORBIDDEN`, `the ${party} is unknown or not readable in this organization`, "42501")}
  end if;`;
  };

  const afterWriteOff = ctx.flag("paymentsAfterWriteOff", false);

  const settle = (alias: string, writtenOff = false): string => `
  update ${t("invoices")} x set
    ${i("paidTotal")} = ${ledger.paidTotal("x")},
    ${i("updatedAt")} = now()
  where x.${i("id")} = ${alias}.${i("id")}
  returning * into ${alias};
  update ${t("invoices")} x set
    ${i("status")} = ${ctx.cast(
      "invoices",
      "status",
      `case
      when ${balance("x")} <= 0 then 'paid'${writtenOff ? `\n      when ${st(`x.${i("status")}`, ["uncollectible"])} then 'uncollectible'` : ""}
      when x.${i("paidTotal")} > 0 or x.${i("creditedTotal")} > 0 then 'partially_paid'
      else 'issued' end`,
    )},
    ${i("paidAt")} = case when ${balance("x")} <= 0 then coalesce(x.${i("paidAt")}, now()) end
  where x.${i("id")} = ${alias}.${i("id")} and ${st(`x.${i("status")}`, writtenOff ? ["issued", "partially_paid", "paid", "uncollectible"] : ["issued", "partially_paid", "paid"])}
  returning * into ${alias};`;

  const keep = (logical: string, value: string, key: string): string =>
    has(logical)
      ? `,\n      ${i(logical)} = case when update_invoice.attrs ? ${sqlString(key)} then ${value} else x.${i(logical)} end`
      : "";

  const relations = ctx.installed("relations")
    ? ctx.of("relations")
    : undefined;

  const discounts = has("discountBps") || has("discountAmount");

  // The header keys whose change recounts the totals.
  const recountKeys = [
    "pricesIncludeTax",
    "discountBps",
    "discountAmount",
  ].filter(has);

  // Refuses a fixed deposit or a header discount the table has no column for.
  const headerRefusals = (attrs: string): string =>
    [
      refuse(
        has("depositAmount"),
        `${attrs} ->> 'depositAmount'`,
        "DEPOSIT",
        "deposit amount column",
      ),
      refuse(
        has("discountBps"),
        `nullif(${attrs} ->> 'discountBps', '0')`,
        "DISCOUNT",
        "discount column",
      ),
      refuse(
        has("discountAmount"),
        `nullif(${attrs} ->> 'discountAmount', '0')`,
        "DISCOUNT",
        "discount amount column",
      ),
    ].join("");

  const updateInvoiceSql = (): string => `
-- Changes a draft's header. attrs: title, company and contact ({ type, id },
-- null clears), termsDays, note, depositBps, pricesIncludeTax and the extra
-- columns by name${discounts ? ", and the header discount (discountBps, discountAmount)" : ""}. A key left out keeps its value.
create or replace function ${fn("update_invoice")}(invoice uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_company_type text := coalesce(update_invoice.attrs -> 'company' ->> 'type', ${sqlString(n.company)});
  v_company_id text := update_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(update_invoice.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)});
  v_contact_id text := update_invoice.attrs -> 'contact' ->> 'id';
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = update_invoice.invoice and ${can("x", n.update)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if ${st(`v_row.${i("status")}`, ["draft"], true)} then
    ${fail("INVOICE_NOT_DRAFT", "only a draft changes", "55000")}
  end if;
  if jsonb_typeof(update_invoice.attrs) is distinct from 'object'
    or (update_invoice.attrs ? 'title' and nullif(trim(update_invoice.attrs ->> 'title'), '') is null) then
    ${fail("INVOICE_ATTRS_INVALID", "attrs is an object, and a title isn't empty", "22023")}
  end if;${p.check("update_invoice.attrs", `v_row.${i("tenant")}`, has("direction") ? `v_row.${i("direction")}` : "'sales'")}${checkParty("COMPANY", "v_company_type", "v_company_id", `v_row.${i("tenant")}`)}${checkParty("CONTACT", "v_contact_type", "v_contact_id", `v_row.${i("tenant")}`)}${refuse(has("note"), "update_invoice.attrs ->> 'note'", "NOTE", "note column")}${refuse(has("depositBps"), "update_invoice.attrs ->> 'depositBps'", "DEPOSIT", "deposit column")}${refuse(has("pricesIncludeTax"), "nullif(update_invoice.attrs ->> 'pricesIncludeTax', 'false')", "PRICING", "prices_include_tax column")}${headerRefusals("update_invoice.attrs")}
  begin
    update ${t("invoices")} x set
      ${i("title")} = case when update_invoice.attrs ? 'title' then trim(update_invoice.attrs ->> 'title') else x.${i("title")} end${keep("companyType", "case when v_company_id is null then null else v_company_type end", "company")}${company === undefined ? "" : keep("companyId", partyId("company", "v_company_id"), "company")}${keep("contactType", "case when v_contact_id is null then null else v_contact_type end", "contact")}${contact === undefined ? "" : keep("contactId", partyId("contact", "v_contact_id"), "contact")}${keep("termsDays", "(update_invoice.attrs ->> 'termsDays')::integer", "termsDays")}${keep("note", "update_invoice.attrs ->> 'note'", "note")}${keep("depositBps", "(update_invoice.attrs ->> 'depositBps')::integer", "depositBps")}${keep("pricesIncludeTax", "coalesce((update_invoice.attrs ->> 'pricesIncludeTax')::boolean, false)", "pricesIncludeTax")}${keep("depositAmount", "(update_invoice.attrs ->> 'depositAmount')::bigint", "depositAmount")}${keep("discountBps", "coalesce((update_invoice.attrs ->> 'discountBps')::integer, 0)", "discountBps")}${keep("discountAmount", "coalesce((update_invoice.attrs ->> 'discountAmount')::bigint, 0)", "discountAmount")}${keep("supplierReference", "nullif(trim(update_invoice.attrs ->> 'supplierReference'), '')", "supplierReference")}${keep("purchaseOrder", "(update_invoice.attrs ->> 'purchaseOrderId')::uuid", "purchaseOrderId")}${keep("dimensions", "coalesce(nullif(update_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb)", "dimensions")},
      ${i("updatedAt")} = now()${updateExtraColumns(t("invoices"), n.extras, "update_invoice.attrs")}
    where x.${i("id")} = v_row.${i("id")}
    returning * into v_row;
  exception when check_violation or invalid_text_representation or not_null_violation${discounts || has("depositAmount") ? " or numeric_value_out_of_range" : ""} then
    ${fail("INVOICE_ATTRS_INVALID", "an invoice field has an invalid value", "22023")}
  end;${
    n.appTotals || recountKeys.length === 0
      ? ""
      : `
  if ${recountKeys.map((key) => `update_invoice.attrs ? ${sqlString(key)}`).join(" or ")} then
    perform ${fn("set_invoice_lines_recount")}(v_row.${i("id")});
  end if;`
  }
  ${record("invoice.updated", "v_row")}
  return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")});
end;
$$;
${userGrant(`${fn("update_invoice")}(uuid, jsonb)`)}

-- Deletes a draft with its lines${charges ? " and charges" : ""}. An issued invoice is voided instead.
create or replace function ${fn("delete_invoice")}(invoice uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = delete_invoice.invoice and ${can("x", n.remove)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can delete", "P0002")}
  end if;
  if ${st(`v_row.${i("status")}`, ["draft"], true)} then
    ${fail("INVOICE_NOT_DRAFT", "only a draft is deleted; void an issued invoice", "55000")}
  end if;${
    charges
      ? `
  delete from ${t("charges")} y where y.${ch("invoice")} = v_row.${i("id")};`
      : ""
  }
  delete from ${t("lines")} y where y.${l("parent")} = v_row.${i("id")};${
    relations === undefined
      ? ""
      : `
  delete from ${relations.table("relations")} y
  where y.${relations.col("relations", "kind")} = 'created_from' and y.${relations.col("relations", "sourceType")} = 'invoice' and y.${relations.col("relations", "sourceId")} = v_row.${i("id")}::text;`
  }
  delete from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")};
  ${record("invoice.deleted", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("delete_invoice")}(uuid)`)}
`;

  const fromQuote = invoiceFromQuote(ctx, n, {
    has,
    row,
    refuse,
    st,
    kd,
    origin,
    company: company !== undefined,
    contact: contact !== undefined,
  });

  const chargeColumns = [
    ch("tenant"),
    ch("invoice"),
    ch("amount"),
    ...(ctx.has("charges", "currency") ? [ch("currency")] : []),
    ...(ctx.has("charges", "description") ? [ch("description")] : []),
    ...(ctx.has("charges", "createdBy") ? [ch("createdBy")] : []),
  ];

  const chargeValues = [
    `v_row.${i("tenant")}`,
    `v_row.${i("id")}`,
    "add_invoice_charge.amount",
    ...(ctx.has("charges", "currency") ? [`v_row.${i("currency")}`] : []),
    ...(ctx.has("charges", "description")
      ? ["nullif(trim(add_invoice_charge.description), '')"]
      : []),
    ...(ctx.has("charges", "createdBy") ? ["auth.uid()"] : []),
  ];

  const chargeFields = extraFieldsArg(n.chargeExtras);

  const chargeExtras = insertExtraColumns(
    t("charges"),
    n.chargeExtras,
    "coalesce(add_invoice_charge.fields, '{}'::jsonb)",
  );

  const writeOffReason =
    typeof ctx.config.columns["invoices"]?.["writeOffReason"] === "string" &&
    ctx.has("invoices", "writeOffReason");

  // Voiding an issued invoice also takes back the entries of its charges.
  const voidCharges =
    charges && booksAccounting(ctx)
      ? `
  perform ${ctx.of("accounting").fn("accounting_reverse_source")}(v_row.${i("tenant")}, 'invoice_charge', c.${ch("id")}::text)
  from ${t("charges")} c where c.${ch("invoice")} = v_row.${i("id")};`
      : "";

  const addCharge = charges
    ? `
${chargeFields.drop(fn("add_invoice_charge"), "uuid, bigint, text, text")}
drop function if exists ${fn("add_invoice_charge")}(uuid, bigint, text, text${chargeFields.type});
-- Adds a charge on top of an issued invoice's total, such as collection
-- costs or a late fee, in the invoice's currency. It raises the balance, so
-- a paid invoice is open again until the charge is paid too. fields: the
-- charge's extra columns (options.chargeExtraColumns). actor: who added it,
-- for the state machine's history.
create or replace function ${fn("add_invoice_charge")}(invoice uuid, amount bigint, currency text, description text${chargeFields.param}, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_charge uuid;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = add_invoice_charge.invoice and ${can("x", n.charge)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if ${kd(`v_row.${i("kind")}`, ["invoice"], true)} or ${st(`v_row.${i("status")}`, ["issued", "partially_paid", "paid"], true)} then
    ${fail("INVOICE_NOT_CHARGEABLE", "only an issued invoice takes charges", "55000")}
  end if;
  if coalesce(add_invoice_charge.amount, 0) <= 0 then
    ${fail("INVOICE_CHARGE_INVALID", "a charge has a positive amount", "22023")}
  end if;
  if upper(add_invoice_charge.currency) is distinct from v_row.${i("currency")} then
    ${fail("INVOICE_CURRENCY_MISMATCH", "a charge must be in the invoice's currency", "22023")}
  end if;
  ${transitionActorSql("add_invoice_charge.actor", "INVOICE_ACTOR_INVALID")}
  insert into ${t("charges")} (${chargeColumns.join(", ")}${chargeExtras.columns})
  values (${chargeValues.join(", ")}${chargeExtras.values})
  returning ${ch("id")} into v_charge;${settle("v_row")}
  ${bookSource(ctx, "invoice_charge", "v_charge")}
  ${record("invoice.charged", "v_row", `, 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', ${balance("v_row")}::text`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("add_invoice_charge")}(uuid, bigint, text, text${chargeFields.type}, jsonb)`)}

drop function if exists ${fn("remove_invoice_charge")}(uuid);
create or replace function ${fn("remove_invoice_charge")}(charge uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_amount bigint;
begin
  select x.* into v_row from ${t("invoices")} x join ${t("charges")} c on c.${ch("invoice")} = x.${i("id")}
  where c.${ch("id")} = remove_invoice_charge.charge and ${can("x", n.charge)}
  for update of x;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_CHARGE_NOT_FOUND", "no such charge on an invoice you can edit", "P0002")}
  end if;
  if ${st(`v_row.${i("status")}`, ["issued", "partially_paid", "paid"], true)} then
    ${fail("INVOICE_NOT_CHARGEABLE", "only an issued invoice changes its charges", "55000")}
  end if;
  ${transitionActorSql("remove_invoice_charge.actor", "INVOICE_ACTOR_INVALID")}
  delete from ${t("charges")} c where c.${ch("id")} = remove_invoice_charge.charge
  returning c.${ch("amount")} into v_amount;${settle("v_row")}
  ${unbookSource(ctx, "invoice_charge", `v_row.${i("tenant")}`, "remove_invoice_charge.charge")}
  ${record("invoice.charge_removed", "v_row", `, 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', ${balance("v_row")}::text`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("remove_invoice_charge")}(uuid, jsonb)`)}
`
    : "";

  const kindTable = (kind: string, direction = "sales"): string =>
    `(select * from ${t("invoices")} k where ${has("direction") ? `k.${i("direction")} = '${direction}' and ` : ""}${kd(`k.${i("kind")}`, [kind])})`;

  const assign = (
    entity: string,
    kind: string,
    prefix: string,
    direction = "sales",
  ): string =>
    assignNumberSql(
      ctx,
      entity,
      `v_row.${i("tenant")}`,
      { seq: "v_seq", identifier: "v_identifier" },
      {
        table: kindTable(kind, direction),
        seq: i("number"),
        tenant: i("tenant"),
        prefix,
      },
      "v_issued_on::timestamptz",
      {
        scope: scopeSql(ctx, "invoices", `v_row.${i("tenant")}`, "v_row"),
        fixed: `issue_invoice.fixed_number`,
      },
    );

  // series "none" on the invoice entity: credit notes take its numbers.
  const credited = (own: string, shared: string): string =>
    ctx.installed("numbering") &&
    sequenceEntry(ctx.of("numbering"), shared)?.["series"] === "none"
      ? shared
      : own;

  return `
-- Creates a draft invoice. attrs: title (required), currency, company and
-- contact ({ type, id }), termsDays, note, origin ({ type, id }) and the
-- extra columns by name${discounts || has("depositAmount") ? ", with depositAmount and the header discount (discountBps,\n-- discountAmount) when the table has them" : ""}.
create or replace function ${fn("create_invoice")}(tenant ${ctx.idType}, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_company_type text := coalesce(create_invoice.attrs -> 'company' ->> 'type', ${sqlString(n.company)});
  v_company_id text := create_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_invoice.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)});
  v_contact_id text := create_invoice.attrs -> 'contact' ->> 'id';${terms.declare}
begin
  if not (${n.service} or ${ctx.scope.can("create_invoice.tenant", p.create("create_invoice.attrs"))}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to change invoices")}
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    ${fail("INVOICE_ATTRS_INVALID", "an invoice needs a title", "23502")}
  end if;${p.check("create_invoice.attrs", "create_invoice.tenant", "create_invoice.attrs ->> 'direction'")}${checkParty("COMPANY", "v_company_type", "v_company_id", "create_invoice.tenant")}${checkParty("CONTACT", "v_contact_type", "v_contact_id", "create_invoice.tenant")}${refuse(has("note"), "create_invoice.attrs ->> 'note'", "NOTE", "note column")}${refuse(origin !== undefined, "(create_invoice.attrs -> 'origin' ->> 'id')", "ORIGIN", "origin columns")}${
    origin === "fixed"
      ? `
  if create_invoice.attrs -> 'origin' ->> 'id' is not null and (create_invoice.attrs -> 'origin' ->> 'type') is distinct from 'quote' then
    ${fail("INVOICE_ORIGIN_UNSUPPORTED", "this invoices table takes only a quote as the origin", "22023")}
  end if;`
      : ""
  }${refuse(has("depositBps"), "create_invoice.attrs ->> 'depositBps'", "DEPOSIT", "deposit column")}${refuse(has("pricesIncludeTax"), "nullif(create_invoice.attrs ->> 'pricesIncludeTax', 'false')", "PRICING", "prices_include_tax column")}${headerRefusals("create_invoice.attrs")}${terms.lookup}
  begin
    insert into ${t("invoices")} (${i("tenant")}, ${i("title")}${also("companyType")}${also("companyId")}${also("contactType")}${also("contactId")}, ${i("currency")},
      ${i("termsDays")}${also("note")}${also("originType")}${also("originId")}${also("depositBps")}${also("depositAmount")}${also("discountBps")}${also("discountAmount")}${also("pricesIncludeTax")}${also("direction")}${also("supplierReference")}${also("purchaseOrder")}${also("dimensions")}${terms.column}${also("createdBy")}${insertExtraColumns(t("invoices"), n.extras, "create_invoice.attrs").columns})
    values (${valueLines(
      "      ",
      ["create_invoice.tenant", "trim(create_invoice.attrs ->> 'title')"],
      [
        present(
          "companyType",
          "case when v_company_id is null then null else v_company_type end",
        ),
        company === undefined ? undefined : partyId("company", "v_company_id"),
      ],
      [
        present(
          "contactType",
          "case when v_contact_id is null then null else v_contact_type end",
        ),
        contact === undefined ? undefined : partyId("contact", "v_contact_id"),
      ],
      [
        "upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR'))",
        `case when create_invoice.attrs ? 'termsDays' then (create_invoice.attrs ->> 'termsDays')::integer else ${terms.days(String(n.termsDays))} end`,
      ],
      [
        present("note", "create_invoice.attrs ->> 'note'"),
        present("originType", "create_invoice.attrs -> 'origin' ->> 'type'"),
        present(
          "originId",
          partyId("origin", "create_invoice.attrs -> 'origin' ->> 'id'"),
        ),
      ],
      [
        present(
          "depositBps",
          "(create_invoice.attrs ->> 'depositBps')::integer",
        ),
        present(
          "depositAmount",
          "(create_invoice.attrs ->> 'depositAmount')::bigint",
        ),
        present(
          "discountBps",
          "coalesce((create_invoice.attrs ->> 'discountBps')::integer, 0)",
        ),
        present(
          "discountAmount",
          "coalesce((create_invoice.attrs ->> 'discountAmount')::bigint, 0)",
        ),
        present(
          "pricesIncludeTax",
          "coalesce((create_invoice.attrs ->> 'pricesIncludeTax')::boolean, false)",
        ),
        ...PURCHASE_VALUES.map(([key, value]) => present(key, value)),
        terms.value,
        present("createdBy", "auth.uid()"),
      ],
    )}${insertExtraColumns(t("invoices"), n.extras, "create_invoice.attrs").values})
    returning * into v_row;
  exception when check_violation or invalid_text_representation${discounts || has("depositAmount") ? " or numeric_value_out_of_range" : ""} then
    ${fail("INVOICE_ATTRS_INVALID", "an invoice field has an invalid value", "22023")}
  end;
  if create_invoice.lines is not null then
    perform ${fn("set_invoice_lines")}(v_row.${i("id")}, create_invoice.lines);
  end if;${
    origin === undefined
      ? ""
      : `
  if v_row.${i("originId")} is not null then
    ${createdFromLink(ctx, { tenant: `v_row.${i("tenant")}`, sourceType: "'invoice'", sourceId: `v_row.${i("id")}::text`, originType: partyTypeSql(ctx, n, "origin", "v_row"), originId: `v_row.${i("originId")}::text` })}
  end if;`
  }
  ${record("invoice.created", "v_row")}
  return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")});
end;
$$;
${userGrant(`${fn("create_invoice")}(${ctx.idType}, jsonb, jsonb)`)}
${updateInvoiceSql()}${lineItemsSql(
    ctx,
    {
      lines: "lines",
      parent: "invoices",
      frozen: st(`p.${i("status")}`, ["draft"], true),
      extras: n.lineExtras,
      totals: !n.appTotals,
      parentHas: has,
      positionKey: ctx.flag("linePositionKey", true),
    },
    {
      setter: "set_invoice_lines",
      guard: `if not exists (select 1 from ${t("invoices")} x where x.${i("id")} = v_parent and ${can("x", n.update)}) then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;`,
      ...lineMatrix(ctx, t, i, has),
    },
  )}
-- Issues a draft: it gets the next number of its kind (gapless, so a
-- number is only taken when the invoice is final), its issue and due date,
-- and its lines freeze. A credit note reduces the balance of its original.
-- actor: who issued it, for the state machine's history.
drop function if exists ${fn("issue_invoice")}(uuid, date);
drop function if exists ${fn("issue_invoice")}(uuid, date, date);
drop function if exists ${fn("issue_invoice")}(uuid, date, date, jsonb);
-- fixed_number: a historical number to keep as is, only while an import runs
-- (better_supabase.import_run()); NUMBER_FIXED_FORBIDDEN otherwise. The counter
-- of its series (kind, direction, legal entity, period) rises to it.
create or replace function ${fn("issue_invoice")}(invoice uuid, issued_on date, due_on date default null, actor jsonb default null, fixed_number text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_original ${t("invoices")};
  v_seq bigint;
  v_identifier text;
  v_issued_on date := coalesce(issue_invoice.issued_on, current_date);
  v_warnings jsonb;${early.declare}
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = issue_invoice.invoice and ${can("x", n.issue)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if ${st(`v_row.${i("status")}`, ["draft"], true)} then
    ${fail("INVOICE_NOT_DRAFT", "the invoice was already issued", "55000")}
  end if;
  if not exists (select 1 from ${t("lines")} x where x.${l("parent")} = v_row.${i("id")}) then
    ${fail("INVOICE_EMPTY", "an invoice needs a line before it is issued", "23514")}
  end if;
  if issue_invoice.due_on < v_issued_on then
    ${fail("INVOICE_DUE_INVALID", "an invoice falls due on or after its issue date", "22023")}
  end if;
  ${transitionActorSql("issue_invoice.actor", "INVOICE_ACTOR_INVALID")}
  ${ctx.hook("before_invoice_issue", [["uuid", `v_row.${i("id")}`]])}${taxIssue(ctx, "v_row", "v_issued_on")}${early.load}
  if ${kd(`v_row.${i("kind")}`, ["credit_note"])} then
    select * into v_original from ${t("invoices")} x where x.${i("id")} = v_row.${i("original")} for update;
    if v_row.${i("total")} > v_original.${i("total")}${charges ? ` + ${charged("v_original")}` : ""} - v_original.${i("creditedTotal")} then
      ${fail("INVOICE_CREDIT_TOO_LARGE", "a credit note can't exceed the invoice's total less its earlier credits", "23514")}
    end if;
    ${p.byDirection("v_row", assign(credited("credit_note", "invoice"), "credit_note", n.creditPrefix), assign(credited("purchase_credit_note", "purchase_bill"), "credit_note", n.purchaseCreditPrefix, "purchase"))}
  else
    ${p.byDirection("v_row", assign("invoice", "invoice", n.prefix), assign("purchase_bill", "invoice", n.purchasePrefix, "purchase"))}
  end if;${p.issue("v_row")}
  update ${t("invoices")} x set ${i("status")} = ${ctx.value("invoices", "status", "issued")}, ${i("number")} = v_seq, ${i("identifier")} = v_identifier,
    ${i("issuedOn")} = v_issued_on,
    ${i("dueOn")} = coalesce(issue_invoice.due_on, v_issued_on + x.${i("termsDays")}),${early.set}
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${record("invoice.issued", "v_row", `, 'total', v_row.${i("total")}::text, 'currency', v_row.${i("currency")}, 'dueOn', v_row.${i("dueOn")}`)}
  if ${kd(`v_row.${i("kind")}`, ["credit_note"])} then
    update ${t("invoices")} x set ${i("creditedTotal")} = x.${i("creditedTotal")} + v_row.${i("total")}, ${i("updatedAt")} = now()
    where x.${i("id")} = v_original.${i("id")}
    returning * into v_original;${settle("v_original")}
    ${record("invoice.credited", "v_original", `, 'creditNoteId', v_row.${i("id")}, 'amount', v_row.${i("total")}::text`)}
    if ${st(`v_original.${i("status")}`, ["paid"])} then
      ${record("invoice.paid", "v_original", `, 'total', v_original.${i("total")}::text`)}
    end if;
  end if;
  ${bookSource(ctx, "invoice", `v_row.${i("id")}`)}
  ${ctx.hook("after_invoice_issue", [["uuid", `v_row.${i("id")}`]])}
  return ${row("v_row")}|| case when v_warnings is null then '{}'::jsonb else jsonb_build_object('warnings', v_warnings) end;
end;
$$;
${userGrant(`${fn("issue_invoice")}(uuid, date, date, jsonb, text)`)}

-- Records a payment (a negative amount is a refund) in the invoice's
-- currency as a ledger transaction from the invoice's receivable account to
-- cash. A reference, such as a bank or payment provider id, is unique per
-- organization, so recording the same payment twice adds it once. actor:
-- who recorded it, and reason: why the status changes, for the state
-- machine's history.
drop function if exists ${fn("record_invoice_payment")}(uuid, bigint, timestamptz, text, text);
drop function if exists ${fn("record_invoice_payment")}(uuid, bigint, text, timestamptz, text, text);
drop function if exists ${fn("record_invoice_payment")}(uuid, bigint, text, timestamptz, text, text, text);
drop function if exists ${fn("record_invoice_payment")}(uuid, bigint, text, timestamptz, text, text, text, jsonb);
create or replace function ${fn("record_invoice_payment")}(invoice uuid, amount bigint, currency text, paid_at timestamptz, method text, reference text, note text default null, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_payment uuid;
  v_reference text;
  v_was text;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = record_invoice_payment.invoice and ${can("x", n.payment)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if ${kd(`v_row.${i("kind")}`, ["invoice"], true)} or ${st(`v_row.${i("status")}`, afterWriteOff ? ["issued", "partially_paid", "paid", "uncollectible"] : ["issued", "partially_paid", "paid"], true)} then
    ${fail("INVOICE_NOT_PAYABLE", "only an issued invoice takes payments", "55000")}
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    ${fail("INVOICE_PAYMENT_INVALID", "a payment has an amount", "22023")}
  end if;
  if upper(record_invoice_payment.currency) is distinct from v_row.${i("currency")} then
    ${fail("INVOICE_CURRENCY_MISMATCH", "a payment must be in the invoice's currency", "22023")}
  end if;${p.payment("v_row", "record_invoice_payment.amount")}
  ${transitionActorSql("record_invoice_payment.actor", "INVOICE_ACTOR_INVALID")}
  -- A recorded reference is a replay that adds nothing, so it skips the check.
  v_reference := nullif(trim(record_invoice_payment.reference), '');
  if v_reference is not null and exists (
    select 1 from ${ledger.transactions} y
    where y.${ledger.tx("tenant")} = v_row.${i("tenant")} and y.${ledger.tx("key")} = ${paymentKey("v_reference")}
  ) then
    return ${row("v_row")};
  end if;
  if record_invoice_payment.amount < 0 and v_row.${i("paidTotal")} + record_invoice_payment.amount < 0 then
    ${fail("INVOICE_REFUND_TOO_LARGE", "a refund can't exceed what was paid", "23514")}
  end if;
  ${ctx.hook("before_invoice_payment", [
    ["uuid", `v_row.${i("id")}`],
    ["bigint", "record_invoice_payment.amount"],
  ])}
  v_was := v_row.${i("status")};
  ${transitionReasonSql("record_invoice_payment.reason")}
  v_payment := ${ledger.post("v_row", "record_invoice_payment.amount", "coalesce(record_invoice_payment.paid_at, now())", "record_invoice_payment.method", "v_reference", "nullif(trim(record_invoice_payment.note), '')")};${settle("v_row", afterWriteOff)}
  ${bookSource(ctx, "invoice_payment", "v_payment")}
  ${transitionReasonSql()}
  ${record("invoice.payment_recorded", "v_row", `, 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', ${balance("v_row")}::text`)}
  if ${st(`v_row.${i("status")}`, ["paid"])} and ${st("v_was", ["paid"], true)} then
    ${record("invoice.paid", "v_row", `, 'total', v_row.${i("total")}::text`)}
  end if;
  ${ctx.hook("after_invoice_payment", [
    ["uuid", `v_row.${i("id")}`],
    ["uuid", "v_payment"],
  ])}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("record_invoice_payment")}(uuid, bigint, text, timestamptz, text, text, text, jsonb, text)`)}

create or replace function ${fn("list_invoice_payments")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = list_invoice_payments.invoice and ${can("x", n.read)};
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  return jsonb_build_object('currency', v_row.${i("currency")}, 'payments', ${ledger.payments("v_row")});
end;
$$;
${userGrant(`${fn("list_invoice_payments")}(uuid)`)}

-- A draft credit note against an issued invoice: its lines, or the given
-- lines for a partial credit. Issue it to apply it. fixed_number: during an
-- import (better_supabase.import_run()), a historical credit note number; the
-- credit note is then issued at once on issued_on (today by default) with that
-- number. NUMBER_FIXED_FORBIDDEN outside an import.
drop function if exists ${fn("credit_invoice")}(uuid, jsonb, text);
create or replace function ${fn("credit_invoice")}(invoice uuid, lines jsonb, note text, fixed_number text default null, issued_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_original ${t("invoices")};
  v_row ${t("invoices")};
begin
  if credit_invoice.fixed_number is not null and better_supabase.import_run() is null then
    ${fail("NUMBER_FIXED_FORBIDDEN", "a fixed number is only accepted during an import", "42501")}
  end if;
  select * into v_original from ${t("invoices")} x where x.${i("id")} = credit_invoice.invoice and ${can("x", n.credit)};
  if v_original.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if ${kd(`v_original.${i("kind")}`, ["invoice"], true)} or ${st(`v_original.${i("status")}`, ["issued", "partially_paid", "paid"], true)} then
    ${fail("INVOICE_NOT_CREDITABLE", "only an issued invoice is credited", "55000")}
  end if;
  insert into ${t("invoices")} (${valueLines(
    "    ",
    [
      i("tenant"),
      i("kind"),
      i("original"),
      i("title"),
      present("companyType", copy("companyType")),
      present("companyId", copy("companyId")),
      present("contactType", copy("contactType")),
      present("contactId", copy("contactId")),
      ...(hasLegalEntityColumn(ctx, "invoices") ? ["legal_entity_id"] : []),
    ],
    [
      i("currency"),
      i("termsDays"),
      present("note", copy("note")),
      present("pricesIncludeTax", copy("pricesIncludeTax")),
      ...PURCHASE_VALUES.map(([key]) => present(key, copy(key))),
      present("createdBy", copy("createdBy")),
    ],
  )})
  values (${valueLines(
    "    ",
    [
      `v_original.${i("tenant")}`,
      ctx.value("invoices", "kind", "credit_note"),
      `v_original.${i("id")}`,
      `'Credit for ' || coalesce(v_original.${i("identifier")}, v_original.${i("title")})`,
    ],
    [
      present("companyType", `v_original.${copy("companyType")}`),
      present("companyId", `v_original.${copy("companyId")}`),
      present("contactType", `v_original.${copy("contactType")}`),
      present("contactId", `v_original.${copy("contactId")}`),
      ...(hasLegalEntityColumn(ctx, "invoices")
        ? ["v_original.legal_entity_id"]
        : []),
    ],
    [
      `v_original.${i("currency")}`,
      "0",
      present("note", "nullif(trim(credit_invoice.note), '')"),
      present("pricesIncludeTax", `v_original.${copy("pricesIncludeTax")}`),
      ...PURCHASE_VALUES.map(([key]) =>
        present(key, `v_original.${copy(key)}`),
      ),
      present("createdBy", "auth.uid()"),
    ],
  )})
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into ${t("lines")} (${lineCopyColumns(ctx, "lines").map(l).join(", ")})
    select ${lineCopyColumns(ctx, "lines")
      .map((column) =>
        column === "parent" ? `v_row.${i("id")}` : `x.${l(column)}`,
      )
      .join(", ")}
    from ${t("lines")} x where x.${l("parent")} = v_original.${i("id")};
  else
    perform ${fn("set_invoice_lines")}(v_row.${i("id")}, credit_invoice.lines);
  end if;
  ${record("invoice.created", "v_row")}
  if credit_invoice.fixed_number is not null then
    perform ${fn("issue_invoice")}(v_row.${i("id")}, coalesce(credit_invoice.issued_on, current_date), null, null, credit_invoice.fixed_number);
  end if;
  return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")});
end;
$$;
${userGrant(`${fn("credit_invoice")}(uuid, jsonb, text, text, date)`)}

-- Voids an invoice without payments: a draft, or an issued one sent in
-- error. Its number stays taken. Needs invoices.manage. The reason and actor
-- go to the state machine's history.
drop function if exists ${fn("void_invoice")}(uuid, text);
create or replace function ${fn("void_invoice")}(invoice uuid, reason text, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = void_invoice.invoice and ${can("x", n.void)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can manage", "P0002")}
  end if;
  if ${st(`v_row.${i("status")}`, ["draft", "issued"], true)} or v_row.${i("paidTotal")} <> 0 or v_row.${i("creditedTotal")} <> 0 then
    ${fail("INVOICE_NOT_VOIDABLE", "an invoice with payments or credits is credited, not voided", "55000")}
  end if;
  ${transitionActorSql("void_invoice.actor", "INVOICE_ACTOR_INVALID")}
  ${transitionReasonSql("void_invoice.reason")}
  update ${t("invoices")} x set ${i("status")} = ${ctx.value("invoices", "status", "void")}, ${i("voidedAt")} = now(),
    ${has("voidReason") ? `${i("voidReason")} = nullif(trim(void_invoice.reason), ''), ` : ""}${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${unbookSource(ctx, "invoice", `v_row.${i("tenant")}`, `v_row.${i("id")}`)}${voidCharges}
  ${transitionReasonSql()}
  ${record("invoice.voided", "v_row", `, 'reason', ${has("voidReason") ? `v_row.${i("voidReason")}` : "nullif(trim(void_invoice.reason), '')"}`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("void_invoice")}(uuid, text, jsonb)`)}

-- Writes an open invoice off as uncollectible. Needs invoices.manage. The
-- reason and actor go to the state machine's history.
drop function if exists ${fn("write_off_invoice")}(uuid);
drop function if exists ${fn("write_off_invoice")}(uuid, text);
create or replace function ${fn("write_off_invoice")}(invoice uuid, reason text default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  ${transitionActorSql("write_off_invoice.actor", "INVOICE_ACTOR_INVALID")}
  ${transitionReasonSql("write_off_invoice.reason")}
  update ${t("invoices")} x set ${i("status")} = ${ctx.value("invoices", "status", "uncollectible")}, ${writeOffReason ? `${i("writeOffReason")} = nullif(trim(write_off_invoice.reason), ''), ` : ""}${i("updatedAt")} = now()
  where x.${i("id")} = write_off_invoice.invoice and ${can("x", n.writeOff)} and ${st(`x.${i("status")}`, ["issued", "partially_paid"])}
  returning * into v_row;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_OPEN", "only an open invoice you can manage is written off", "55000")}
  end if;
  ${bookSource(ctx, "invoice_write_off", `v_row.${i("id")}`)}
  ${transitionReasonSql()}
  ${record("invoice.uncollected", "v_row", `, 'balance', ${balance("v_row")}::text, 'reason', nullif(trim(write_off_invoice.reason), '')`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("write_off_invoice")}(uuid, text, jsonb)`)}

-- Reverses a recorded payment. The reason and actor go to the state machine's
-- history.
drop function if exists ${fn("reverse_invoice_payment")}(uuid, text);
create or replace function ${fn("reverse_invoice_payment")}(payment uuid, reason text default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_meta jsonb;
  v_amount bigint;
  v_reversal uuid;
begin
  select y.${ledger.tx("metadata")} into v_meta from ${ledger.transactions} y
  where y.${ledger.tx("id")} = reverse_invoice_payment.payment and y.${ledger.tx("referenceType")} = 'invoices';
  select * into v_row from ${t("invoices")} x where x.${i("id")} = (v_meta ->> 'invoiceId')::uuid and ${can("x", n.reverse)} for update;
  if v_meta is null or v_row.${i("id")} is null then
    ${fail("INVOICE_PAYMENT_NOT_FOUND", "no such payment on an invoice you can manage", "P0002")}
  end if;
  if coalesce(v_meta ->> 'method', '') = any (${sqlString(`{${n.providerMethods.join(",")}}`)}::text[]) then
    ${fail("INVOICE_PAYMENT_PROVIDER", "a payment provider's payment is refunded through the provider, not reversed", "55000")}
  end if;
  if (v_meta ->> 'reversal')::boolean is true
    or exists (select 1 from ${ledger.transactions} y where y.${ledger.tx("reverses")} = reverse_invoice_payment.payment) then
    ${fail("INVOICE_PAYMENT_REVERSED", "this payment is a reversal or is already reversed", "55000")}
  end if;
  ${transitionActorSql("reverse_invoice_payment.actor", "INVOICE_ACTOR_INVALID")}
  ${transitionReasonSql("reverse_invoice_payment.reason")}
  v_amount := ${ledger.paidTotal("v_row")};
  v_reversal := ${ledger.reverse("v_row", "reverse_invoice_payment.payment", "nullif(trim(reverse_invoice_payment.reason), '')")};
  v_amount := v_amount - ${ledger.paidTotal("v_row")};${settle("v_row")}
  ${unbookSource(ctx, "invoice_payment", `v_row.${i("tenant")}`, "reverse_invoice_payment.payment")}
  ${transitionReasonSql()}
  ${record("invoice.payment_reversed", "v_row", `, 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', ${balance("v_row")}::text, 'reason', nullif(trim(reverse_invoice_payment.reason), '')`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("reverse_invoice_payment")}(uuid, text, jsonb)`)}
${addCharge}${p.aging}${fromQuote}${p.functions}${invoiceCollectionsAndOpenItems(ctx, n, { i, can, st, kd, balance, row, record, settle, ledger, charges })}`;
}
