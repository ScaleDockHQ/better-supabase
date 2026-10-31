import type { BlockSqlContext } from "../context.ts";

import { fail } from "../shared.ts";
import { linked } from "./manufacturing-sql.ts";

/**
 * The invoice columns payment terms add: the terms an invoice copied from its
 * party, when the early-payment discount ends and how much it is.
 */
export const TERMS_COLUMNS: readonly string[] = [
  "paymentTermsId",
  "discountDueOn",
  "discountAmountEarly",
];

/** The invoice columns a hand-over to a collection agency sets. */
export const HANDOVER_COLUMNS: readonly string[] = [
  "collectionStatus",
  "collectionAgencyId",
  "collectionHandedAt",
];

/** The `create table` lines of the terms columns; `column` skips unmapped ones. */
export function termsColumnsSql(
  column: (
    logical: string,
    definition: string | ((name: string) => string),
  ) => string,
): string {
  return `${column("paymentTermsId", "uuid")}${column("discountDueOn", "date")}${column("discountAmountEarly", (name) => `bigint check (${name} >= 0)`)}${column("collectionStatus", (name) => `text check (${name} in ('handed_over'))`)}${column("collectionAgencyId", "text")}${column("collectionHandedAt", "timestamptz")}`;
}

/** The linked contacts block when it keeps payment terms. */
function termsOwner(ctx: BlockSqlContext): BlockSqlContext | undefined {
  const contacts = linked(ctx, "contacts");

  return contacts?.hasTable("terms") ? contacts : undefined;
}

/** Whether invoices keep the terms they copied. */
function hasTerms(ctx: BlockSqlContext): boolean {
  return termsOwner(ctx) !== undefined && ctx.has("invoices", "paymentTermsId");
}

/**
 * PL/pgSQL for `create_invoice`: loads `v_terms` (a `resolve_payment_terms`
 * result) from the attrs' `paymentTermsId` or from the invoice's company, and
 * refuses a terms id that doesn't exist.
 */
function termsLookupSql(ctx: BlockSqlContext): string {
  const contacts = termsOwner(ctx);

  if (contacts === undefined || !hasTerms(ctx)) {
    return "";
  }

  const failed = fail(
    "INVOICE_PAYMENT_TERMS_NOT_FOUND",
    "no such payment terms in this organization",
    "P0002",
  );

  return `
  v_terms := ${contacts.fn("resolve_payment_terms")}(create_invoice.tenant, nullif(create_invoice.attrs ->> 'paymentTermsId', '')::uuid, v_company_id, coalesce(create_invoice.attrs ->> 'direction', 'sales'));
  if create_invoice.attrs ->> 'paymentTermsId' is not null and v_terms is null then
    ${failed}
  end if;`;
}

/** The due days a draft takes: the copied terms, else `fallback`. */
function termsDays(ctx: BlockSqlContext, fallback: string): string {
  return hasTerms(ctx)
    ? `coalesce((v_terms ->> 'days')::integer, ${fallback})`
    : fallback;
}

/** What `issue_invoice` adds for the early-payment discount. */
export interface DiscountIssue {
  /** Variables to declare. */
  readonly declare: string;
  /** Statements that load the invoice's terms. */
  readonly load: string;
  /** `set` assignments, each ending in a comma. */
  readonly set: string;
}

/**
 * The date until the early-payment discount applies and its amount, from the
 * terms the invoice copied: `total * discount_bps / 10000`, rounded half up.
 */
export function discountIssue(
  ctx: BlockSqlContext,
  row: string,
  issuedOn: string,
): DiscountIssue {
  const contacts = termsOwner(ctx);

  if (
    contacts === undefined ||
    !hasTerms(ctx) ||
    !ctx.has("invoices", "discountDueOn") ||
    !ctx.has("invoices", "discountAmountEarly")
  ) {
    return { declare: "", load: "", set: "" };
  }

  const i = (column: string): string => ctx.col("invoices", column);
  const x = (column: string): string => contacts.col("terms", column);

  return {
    declare: "\n  v_early_bps integer;\n  v_early_days integer;",
    load: `
  select z.${x("discountBps")}, z.${x("discountDays")} into v_early_bps, v_early_days
  from ${contacts.table("terms")} z where z.${x("id")} = ${row}.${i("paymentTermsId")};`,
    set: `
    ${i("discountDueOn")} = case when coalesce(v_early_bps, 0) > 0 and x.${i("kind")} = 'invoice' then ${issuedOn} + v_early_days end,
    ${i("discountAmountEarly")} = case when coalesce(v_early_bps, 0) > 0 and x.${i("kind")} = 'invoice'
      then ((x.${i("total")}::numeric * v_early_bps + 5000) / 10000)::bigint end,`,
  };
}

/** The credit restriction of the terms an invoice copied, in basis points. */
export function creditRestrictionSql(
  ctx: BlockSqlContext,
  row: string,
): string {
  const contacts = termsOwner(ctx);

  if (contacts === undefined || !ctx.has("invoices", "paymentTermsId")) {
    return "0";
  }

  const x = (column: string): string => contacts.col("terms", column);

  return `coalesce((select z.${x("creditRestrictionBps")} from ${contacts.table("terms")} z where z.${x("id")} = ${row}.${ctx.col("invoices", "paymentTermsId")}), 0)`;
}

/** What `create_invoice` adds for the copied payment terms. */
export interface CreateTerms {
  /** The `v_terms` declaration, with its leading newline. */
  readonly declare: string;
  /** The lookup that fills `v_terms`. */
  readonly lookup: string;
  /** The insert column list entry, with its leading comma. */
  readonly column: string;
  /** The insert value, or `undefined` without the column. */
  readonly value: string | undefined;
  /** The due days of a draft: the copied terms, else `fallback`. */
  readonly days: (fallback: string) => string;
}

export function createTerms(ctx: BlockSqlContext): CreateTerms {
  const on = hasTerms(ctx);

  return {
    declare: on ? "\n  v_terms jsonb;" : "",
    lookup: termsLookupSql(ctx),
    column: on ? `, ${ctx.col("invoices", "paymentTermsId")}` : "",
    value: on ? "(v_terms ->> 'id')::uuid" : undefined,
    days: (fallback) => termsDays(ctx, fallback),
  };
}

/**
 * The `discountMatrix` option of the invoice line setter: it prices catalog
 * lines for the invoice's company, else its contact, on the day the lines are
 * set. Empty while the block option is off.
 */
export function lineMatrix(
  ctx: BlockSqlContext,
  t: (table: string) => string,
  i: (column: string) => string,
  has: (column: string) => boolean,
): {
  readonly discountMatrix?: { readonly party: string; readonly on: string };
} {
  if (!ctx.flag("discountMatrix", false)) {
    return {};
  }

  const parties =
    ["companyId", "contactId"]
      .filter((column) => has(column))
      .map((column) => `x.${i(column)}`)
      .join(", ") || "null";

  return {
    discountMatrix: {
      party: `(select coalesce(${parties}) from ${t("invoices")} x where x.${i("id")} = v_parent)`,
      on: "current_date",
    },
  };
}
