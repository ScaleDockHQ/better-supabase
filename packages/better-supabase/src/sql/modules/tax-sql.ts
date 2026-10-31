import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** What a tax code does to a document line. */
export const TAX_CODE_TYPES = [
  "sales",
  "purchase",
  "exempt",
  "zero",
  "reverse_charge",
  "intra_eu_goods",
  "intra_eu_services",
  "export",
  "margin",
] as const;

/** The types that charge a rate; the others always count 0%. */
const RATE_CODE_TYPES = ["sales", "purchase", "margin"] as const;

/** Where a tax return stands. */
export const RETURN_STATUSES = ["draft", "filed"] as const;

/** What an EU sales list line reports. */
export const EU_SALES_KINDS = ["goods", "services"] as const;

/** The day a rate without a start applies from. */
export const EPOCH = "1970-01-01";

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

/** The SQL pieces the tax files share. */
export interface TaxSql {
  readonly fn: (name: string) => string;
  /**
   * Columns of tax_codes, tax_rates, invoice_tax_lines, tax_returns and
   * eu_sales_list_lines.
   */
  readonly c: (column: string) => string;
  readonly r: (column: string) => string;
  readonly l: (column: string) => string;
  readonly t: (column: string) => string;
  readonly e: (column: string) => string;
  readonly codes: string;
  readonly rates: string;
  readonly lines: string;
  readonly returns: string;
  readonly euLines: string;
  readonly read: string;
  readonly manage: string;
  /** The service role, or a member of `tenant` with `permission`. */
  readonly allowed: (tenant: string, permission: string) => string;
  /** SQL that is true for a code type that charges a rate. */
  readonly ratedType: (type: string) => string;
  readonly forbidden: (message: string) => string;
  readonly codeInvalid: (message: string) => string;
  readonly rateInvalid: (message: string) => string;
  readonly computeInvalid: (message: string) => string;
  readonly returnInvalid: (message: string) => string;
  readonly codeMissing: string;
  readonly returnMissing: string;
  readonly typeList: string;
  readonly rateTypeList: string;
  readonly codeJson: (row: string) => string;
  readonly rateJson: (row: string) => string;
  readonly returnJson: (row: string) => string;
  /** Records a `tax_code.*` event of a tax_codes row. */
  readonly recordCode: (
    type: "tax_code.created" | "tax_code.updated",
    row: string,
    summary: string,
  ) => string;
}

export function taxSql(ctx: BlockSqlContext): TaxSql {
  const col =
    (table: string) =>
    (column: string): string =>
      ctx.col(table, column);

  const c = col("codes");
  const r = col("rates");
  const l = col("invoiceTaxLines");
  const t = col("returns");
  const e = col("euSalesLines");
  const rates = ctx.table("rates");
  const euLines = ctx.table("euSalesLines");

  const rateJsonOf = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'taxCodeId', ${row}.${r("taxCode")}, 'rateBps', ${row}.${r("rateBps")}, 'validFrom', ${row}.${r("validFrom")}, 'validTo', ${row}.${r("validTo")}, 'createdAt', ${row}.${r("createdAt")})`;

  const ratesOf = (row: string): string =>
    `coalesce((select jsonb_agg(${rateJsonOf("y")} order by y.${r("validFrom")}) from ${rates} y where y.${r("taxCode")} = ${row}.${c("id")}), '[]'::jsonb)`;

  return {
    fn: (name) => ctx.fn(name),
    c,
    r,
    l,
    t,
    e,
    codes: ctx.table("codes"),
    rates,
    lines: ctx.table("invoiceTaxLines"),
    returns: ctx.table("returns"),
    euLines,
    read: ctx.permission("read", OPERATIONS["tax.read"]),
    manage: ctx.permission("manage", OPERATIONS["tax.manage"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    ratedType: (type) => `${type} in (${list(RATE_CODE_TYPES)})`,
    forbidden: (message) => fail("TAX_FORBIDDEN", message),
    codeInvalid: (message) => fail("TAX_CODE_INVALID", message, "22023"),
    rateInvalid: (message) => fail("TAX_RATE_INVALID", message, "22023"),
    computeInvalid: (message) => fail("TAX_COMPUTE_INVALID", message, "22023"),
    returnInvalid: (message) => fail("TAX_RETURN_INVALID", message, "22023"),
    codeMissing: fail("TAX_CODE_NOT_FOUND", "no such tax code", "P0002"),
    returnMissing: fail("TAX_RETURN_NOT_FOUND", "no such tax return", "P0002"),
    typeList: list(TAX_CODE_TYPES),
    rateTypeList: list(RATE_CODE_TYPES),
    codeJson: (row) =>
      `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'legalEntityId', ${row}.${c("legalEntity")}, 'code', ${row}.${c("code")}, 'name', ${row}.${c("name")}, 'type', ${row}.${c("type")}, 'salesAccountId', ${row}.${c("salesAccount")}, 'purchaseAccountId', ${row}.${c("purchaseAccount")}, 'returnBoxes', to_jsonb(${row}.${c("returnBoxes")}), 'archivedAt', ${row}.${c("archivedAt")}, 'createdAt', ${row}.${c("createdAt")}, 'updatedAt', ${row}.${c("updatedAt")}, 'rates', ${ratesOf(row)})`,
    rateJson: rateJsonOf,
    returnJson: (row) =>
      `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'legalEntityId', ${row}.${t("legalEntity")}, 'period', ${row}.${t("period")}, 'periodStart', ${row}.${t("periodStart")}, 'periodEnd', ${row}.${t("periodEnd")}, 'status', ${row}.${t("status")}, 'currency', ${row}.${t("currency")}, 'boxes', ${row}.${t("boxes")}, 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z.${e("customerVat")}, 'country', z.${e("country")}, 'kind', z.${e("kind")}, 'amount', z.${e("amount")}::text, 'currency', z.${e("currency")}, 'invoiceCount', z.${e("invoiceCount")}) order by z.${e("customerVat")}, z.${e("kind")}, z.${e("currency")}) from ${euLines} z where z.${e("taxReturn")} = ${row}.${t("id")}), '[]'::jsonb), 'preparedBy', ${row}.${t("preparedBy")}, 'preparedAt', ${row}.${t("preparedAt")}, 'filedAt', ${row}.${t("filedAt")}, 'createdAt', ${row}.${t("createdAt")}, 'updatedAt', ${row}.${t("updatedAt")})`,
    recordCode: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}, 'id', ${row}.${c("id")}, 'code', ${row}.${c("code")}, 'type', ${row}.${c("type")}, 'legalEntityId', ${row}.${c("legalEntity")})`,
        subject: `'tax-codes/' || ${row}.${c("id")}::text`,
        tenant: `${row}.${c("tenant")}`,
        audit: {
          category: "billing",
          targetType: "tax_code",
          recordId: `${row}.${c("id")}::text`,
          targetLabel: `${row}.${c("code")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
