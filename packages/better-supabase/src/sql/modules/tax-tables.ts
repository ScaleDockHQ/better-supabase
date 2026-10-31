import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockModuleTable } from "./over-app.ts";
import { EPOCH, EU_SALES_KINDS, RETURN_STATUSES, taxSql } from "./tax-sql.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

const NO_ENTITY = "'00000000-0000-0000-0000-000000000000'::uuid";

/**
 * The tax tables: codes, rates, invoice tax lines, returns and EU sales list
 * lines.
 */
export function taxTables(ctx: BlockSqlContext): string {
  const q = taxSql(ctx);
  const { c, r, l, t, e } = q;
  const invoices = ctx.installed("invoices") ? ctx.of("invoices") : undefined;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const key = (logical: string, what: string): string =>
    sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}`);

  const unique = (
    logical: string,
    what: string,
    columns: string,
    where = "",
  ): string =>
    `\ncreate unique index if not exists ${ctx.owns(logical) ? name(logical, what) : key(logical, what)} on ${ctx.table(logical)} (${columns})${where};`;

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const invoiceRef = invoices?.owns("invoices")
    ? ` references ${invoices.table("invoices")} (${invoices.col("invoices", "id")}) on delete cascade`
    : "";

  const linesRead = invoices
    ? `exists (select 1 from ${invoices.table("invoices")} z where z.${invoices.col("invoices", "id")} = ${l("parent")})`
    : ctx.scope.check(l("tenant"), q.read);

  return `
-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
create table if not exists ${q.codes} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("legalEntity")} uuid,
  ${c("code")} text not null check (length(${c("code")}) between 1 and 50),
  ${c("name")} text not null check (length(${c("name")}) between 1 and 200),
  ${c("type")} text not null check (${c("type")} in (${q.typeList})),
  ${c("salesAccount")} uuid,
  ${c("purchaseAccount")} uuid,
  -- The boxes of a tax return the code's base and tax count toward.
  ${c("returnBoxes")} text[] not null default '{}',
  ${c("archivedAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now()
);${unique("codes", "code_key", `${c("tenant")}, (coalesce(${c("legalEntity")}, ${NO_ENTITY})), ${c("code")}`)}
create index if not exists ${name("codes", "tenant_idx")} on ${q.codes} (${c("tenant")}, ${c("code")});
${lockModuleTable(ctx, "codes", { read: true })}
${readPolicy("codes", ctx.scope.check(c("tenant"), q.read))}

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
create table if not exists ${q.rates} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("taxCode")} uuid not null references ${q.codes} (${c("id")}) on delete cascade,
  -- Basis points: 2100 is 21%.
  ${r("rateBps")} integer not null check (${r("rateBps")} >= 0 and ${r("rateBps")} <= 100000),
  ${r("validFrom")} date not null default date '${EPOCH}',
  ${r("validTo")} date,
  ${r("createdAt")} timestamptz not null default now(),
  check (${r("validTo")} is null or ${r("validTo")} >= ${r("validFrom")})
);${unique("rates", "from_key", `${r("taxCode")}, ${r("validFrom")}`)}
${lockModuleTable(ctx, "rates", { read: true })}
${readPolicy("rates", ctx.scope.check(r("tenant"), q.read))}

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
create table if not exists ${q.lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("parent")} uuid not null${invoiceRef},
  ${l("taxRateBps")} integer not null,
  ${l("taxCode")} text,
  ${l("taxCodeId")} uuid,
  ${l("net")} bigint not null,
  ${l("tax")} bigint not null,
  ${l("gross")} bigint not null,
  ${l("discount")} bigint not null default 0,
  ${l("customerVat")} text,
  ${l("showTax")} boolean not null default true
);
create index if not exists ${name("invoiceTaxLines", "parent_idx")} on ${q.lines} (${l("parent")});
create index if not exists ${name("invoiceTaxLines", "tenant_code_idx")} on ${q.lines} (${l("tenant")}, ${l("taxCodeId")});
${lockModuleTable(ctx, "invoiceTaxLines", { read: true })}
${readPolicy("invoiceTaxLines", linesRead)}

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
create table if not exists ${q.returns} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("legalEntity")} uuid,
  ${t("period")} text not null check (length(${t("period")}) between 1 and 50),
  ${t("periodStart")} date not null,
  ${t("periodEnd")} date not null,
  ${t("status")} text not null default 'draft' check (${t("status")} in (${list(RETURN_STATUSES)})),
  ${t("currency")} char(3) check (${t("currency")} is null or ${t("currency")} ~ '^[A-Z]{3}$'),
  ${t("boxes")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${t("boxes")}) = 'object'),
  ${t("preparedBy")} uuid,
  ${t("preparedAt")} timestamptz not null default now(),
  ${t("filedAt")} timestamptz,
  ${t("createdAt")} timestamptz not null default now(),
  ${t("updatedAt")} timestamptz not null default now(),
  check (${t("periodEnd")} >= ${t("periodStart")}),
  check ((${t("status")} = 'filed') = (${t("filedAt")} is not null))
);${unique("returns", "period_key", `${t("tenant")}, (coalesce(${t("legalEntity")}, ${NO_ENTITY})), ${t("periodStart")}, ${t("periodEnd")}`)}
${lockModuleTable(ctx, "returns", { read: true })}
${readPolicy("returns", ctx.scope.check(t("tenant"), q.read))}

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
create table if not exists ${q.euLines} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("taxReturn")} uuid not null references ${q.returns} (${t("id")}) on delete cascade,
  ${e("customerVat")} text not null check (length(${e("customerVat")}) between 4 and 20),
  ${e("country")} char(2) not null check (${e("country")} ~ '^[A-Z]{2}$'),
  ${e("kind")} text not null check (${e("kind")} in (${list(EU_SALES_KINDS)})),
  ${e("amount")} bigint not null,
  ${e("currency")} char(3) not null check (${e("currency")} ~ '^[A-Z]{3}$'),
  ${e("invoiceCount")} integer not null check (${e("invoiceCount")} > 0)
);${unique("euSalesLines", "key", `${e("taxReturn")}, ${e("customerVat")}, ${e("kind")}, ${e("currency")}`)}
${lockModuleTable(ctx, "euSalesLines", { read: true })}
${readPolicy("euSalesLines", ctx.scope.check(e("tenant"), q.read))}
`;
}
